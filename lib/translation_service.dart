import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

class TranslationService {
  bool _isInitialized = false;
  InferenceModel? _model;

  @visibleForTesting
  set model(InferenceModel? value) {
    _model = value;
    _isInitialized = value != null;
  }

  Future<void> init(String modelPath) async {
    if (_isInitialized) {
      debugPrint("[TranslationService] init() called but already initialized — skipping.");
      return;
    }
    debugPrint("[TranslationService] init() start — modelPath: $modelPath");
    
    // 1. Initialize SDK with LiteRT-LM engine
    debugPrint("[TranslationService] Step 1: FlutterGemma.initialize()...");
    await FlutterGemma.initialize(
      inferenceEngines: [const LiteRtLmEngine()],
    );
    debugPrint("[TranslationService] Step 1: done.");

    // 2. Set the local model file as the active model
    debugPrint("[TranslationService] Step 2: installModel().fromFile().install()...");
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(modelPath).install();
    debugPrint("[TranslationService] Step 2: done.");

    // 3. Load active model
    debugPrint("[TranslationService] Step 3: getActiveModel(maxTokens=1024)...");
    _model = await FlutterGemma.getActiveModel(maxTokens: 1024);
    debugPrint("[TranslationService] Step 3: done. model=$_model");

    _isInitialized = true;
    debugPrint("[TranslationService] init() complete.");
  }

  Future<String> translate(String japaneseText) async {
    if (!_isInitialized || _model == null) {
      throw StateError("TranslationService is not initialized. Call init() first.");
    }
    debugPrint("[TranslationService] translate() start. text=${japaneseText.length > 40 ? japaneseText.substring(0, 40) : japaneseText}");
    // Create a fresh session for this block to avoid chat history bloat and memory leaks
    debugPrint("[TranslationService] Creating session...");
    final session = await _model!.createSession();
    debugPrint("[TranslationService] Session created.");
    try {
      final prompt = "Translate the following Japanese text to English. Return only the English translation. Text: $japaneseText";
      debugPrint("[TranslationService] addQueryChunk...");
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      debugPrint("[TranslationService] getResponse()...");
      final response = await session.getResponse();
      debugPrint("[TranslationService] getResponse() returned ${response.length} chars.");
      return response;
    } finally {
      await session.close();
      debugPrint("[TranslationService] Session closed.");
    }
  }

  Future<List<String>> translateBatch(List<({String text, int x, int y})> blocks) async {
    if (blocks.isEmpty) return [];
    if (!_isInitialized || _model == null) {
      throw StateError("TranslationService is not initialized. Call init() first.");
    }

    if (blocks.length == 1) {
      final single = await translate(blocks.first.text);
      return [single];
    }

    // Batch translation: single inference with structured XML prompt containing layout coordinates
    final session = await _model!.createSession();
    try {
      final prompt = TranslationService.buildStructuredPrompt(blocks);
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final response = await session.getResponse();
      
      final parsed = TranslationService.parseStructuredResponse(response, blocks.length);
      if (parsed != null) {
        return parsed;
      }
      
      // Fall back to sequential if XML parsing fails
      debugPrint("Structured batch translation parsing failed. Falling back to sequential translation.");
      return await _fallbackToSequential(blocks);
    } catch (e) {
      debugPrint("Structured batch translation failed: $e. Falling back to sequential.");
      return await _fallbackToSequential(blocks);
    } finally {
      await session.close();
    }
  }

  Future<List<String>> _fallbackToSequential(List<({String text, int x, int y})> blocks) async {
    final List<String> results = [];
    for (final block in blocks) {
      try {
        results.add(await translate(block.text));
      } catch (e) {
        debugPrint("Failed to translate block: ${block.text}, error: $e");
        results.add(block.text); // Original text as last resort
      }
    }
    return results;
  }


  /// Builds a structured XML prompt for batch translation.
  /// [blocks] is a list of records with text and top-left pixel coordinates.
  static String buildStructuredPrompt(List<({String text, int x, int y})> blocks) {
    final buffer = StringBuffer();
    buffer.writeln("Translate the following Japanese text blocks captured from an Android screen to English.");
    buffer.writeln("The coordinates (x, y) represent their top-left pixel locations on the screen.");
    buffer.writeln("Use these locations to understand the layout context (e.g., adjacent blocks, title vs. body).");
    buffer.writeln("");
    buffer.writeln('Output ONLY the translated blocks wrapped in matching XML tags like: <t id="1">translated text</t>.');
    buffer.writeln("Do not include coordinates in the output. Do not write any other explanations.");
    buffer.writeln("");
    buffer.writeln("Input:");
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      buffer.writeln('<t id="${i + 1}" x="${block.x}" y="${block.y}">${block.text}</t>');
    }
    return buffer.toString();
  }

  /// Parses the structured XML response from the LLM.
  /// Returns a list of translations in the same order as the input blocks,
  /// or null if the response is malformed or incomplete.
  static List<String>? parseStructuredResponse(String response, int expectedCount) {
    final List<String> results = List.filled(expectedCount, "");
    // Match <t id="N"> ... </t> — double-quoted IDs only, matching our prompt format.
    // Allows optional whitespace around the id value and inside tags.
    final pattern = RegExp(r'<t\s+id\s*=\s*"(\d+)"\s*>\s*([\s\S]*?)\s*<\/t>');
    final matches = pattern.allMatches(response);
    
    int foundCount = 0;
    final Set<int> seenIndices = {};
    
    for (final match in matches) {
      final idStr = match.group(1);
      final text = match.group(2);
      if (idStr == null || text == null) continue;
      
      final id = int.tryParse(idStr);
      if (id == null || id < 1 || id > expectedCount) continue;
      
      if (seenIndices.contains(id)) continue;
      seenIndices.add(id);
      
      results[id - 1] = text.trim();
      foundCount++;
    }
    
    if (foundCount == expectedCount && results.every((r) => r.isNotEmpty)) {
      return results;
    }
    return null;
  }

  Future<void> dispose() async {
    if (_model != null) {
      await _model!.close();
    }
    _isInitialized = false;
  }
}
