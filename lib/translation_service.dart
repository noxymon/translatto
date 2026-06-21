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
    // maxTokens=256: the compiled LiteRT-LM .task file has a hard max_seq_len
    // baked in at model compile time. CJK text tokenizes at ~1.5 tokens/char,
    // so 332 chars of formatted prompt ≈ 300-400 tokens which overflows a
    // 512-slot KV-cache causing DYNAMIC_UPDATE_SLICE to fail at prepare.
    // 256 gives us ~144 input tokens + headroom for output tokens.
    debugPrint('[TranslationService] Step 3: getActiveModel(maxTokens=256, preferredBackend: cpu)...');
    _model = await FlutterGemma.getActiveModel(
      maxTokens: 256,
      preferredBackend: PreferredBackend.cpu,
    );
    debugPrint('[TranslationService] Step 3: done. model=$_model');

    _isInitialized = true;
    debugPrint("[TranslationService] init() complete.");
  }

  /// Max input characters before sending to model.
  /// CJK tokenizes at ~1.5 tokens/char. Formula:
  ///   60 chars × 1.5 = 90 input tokens
  ///   + ~50 tokens prompt boilerplate + chat template
  ///   = ~140 total input tokens → fits in maxTokens=256 KV-cache.
  static const int _maxInputChars = 60;

  /// Truncates [text] to [_maxInputChars] on a natural Japanese sentence
  /// boundary (※ bullet or 。) when possible, to avoid mid-sentence cuts.
  static String _truncateInput(String text) {
    if (text.length <= _maxInputChars) return text;
    // Try to cut at a bullet or sentence end within the allowed range.
    final window = text.substring(0, _maxInputChars);
    final sentenceEnd = window.lastIndexOf('。');
    final bulletStart = window.lastIndexOf('※');
    final cutPoint = [sentenceEnd, bulletStart]
        .where((i) => i > 10)
        .fold(-1, (best, i) => i > best ? i : best);
    return cutPoint > 0 ? window.substring(0, cutPoint + 1) : window;
  }

  Future<String> translate(String japaneseText) async {
    if (!_isInitialized || _model == null) {
      throw StateError('TranslationService is not initialized. Call init() first.');
    }
    // Guard: truncate oversized input to stay within context window.
    final safeText = _truncateInput(japaneseText);
    debugPrint('[TranslationService] translate() chars=${japaneseText.length}→${safeText.length}');
    final session = await _model!.createSession();
    try {
      // Prompt tuned for natural, idiomatic English — not word-for-word.
      final prompt =
          'Translate this Japanese text into natural, fluent English. '
          'Output only the English translation, no explanations.\n'
          'Japanese: $safeText\nEnglish:';
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final response = await session.getResponse();
      debugPrint('[TranslationService] response ${response.length} chars.');
      return response.trim();
    } finally {
      await session.close();
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
    buffer.writeln('Translate these Japanese UI text blocks into natural, fluent English.');
    buffer.writeln('The (x, y) coordinates show where each block appears on screen — use them for layout context.');
    buffer.writeln('Output ONLY the translations inside matching XML tags: <t id="N">translation</t>');
    buffer.writeln('No explanations. No notes. No extra text.');
    buffer.writeln('');
    buffer.writeln('Input:');
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      // Truncate each block to stay within context budget
      final safeText = _truncateInput(block.text);
      buffer.writeln('<t id="${i + 1}" x="${block.x}" y="${block.y}">$safeText</t>');
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
