import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

class TranslationService {
  bool _isInitialized = false;
  InferenceModel? _model;

  Future<void> init(String modelPath) async {
    if (_isInitialized) return;
    
    // 1. Initialize SDK with LiteRT-LM engine
    await FlutterGemma.initialize(
      inferenceEngines: [const LiteRtLmEngine()],
    );

    // 2. Set the local model file as the active model
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
    ).fromFile(modelPath).install();

    // 3. Load active model
    _model = await FlutterGemma.getActiveModel(maxTokens: 1024);

    _isInitialized = true;
  }

  Future<String> translate(String japaneseText) async {
    if (!_isInitialized || _model == null) {
      throw StateError("TranslationService is not initialized. Call init() first.");
    }
    
    // Create a fresh session for this block to avoid chat history bloat and memory leaks
    final session = await _model!.createSession();
    try {
      final prompt = "Translate the following Japanese text to English. Return only the English translation. Text: $japaneseText";
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final response = await session.getResponse();
      return response;
    } finally {
      await session.close();
    }
  }

  Future<List<String>> translateBatch(List<String> texts) async {
    if (texts.isEmpty) return [];
    if (!_isInitialized || _model == null) {
      throw StateError("TranslationService is not initialized. Call init() first.");
    }

    if (texts.length == 1) {
      final single = await translate(texts.first);
      return [single];
    }

    // Try batch translation to reduce context and token generation overhead (N runs -> 1 run)
    final session = await _model!.createSession();
    try {
      final buffer = StringBuffer();
      buffer.writeln("Translate these Japanese text blocks to English. Return them as a numbered list with the same indices. Format each item as: '<index>. <translation>'. Return ONLY the translated list. Do not write any other explanations.");
      for (int i = 0; i < texts.length; i++) {
        buffer.writeln("${i + 1}. ${texts[i]}");
      }

      await session.addQueryChunk(Message(text: buffer.toString(), isUser: true));
      final response = await session.getResponse();
      
      final parsed = _parseBatchResponse(response, texts.length);
      if (parsed != null) {
        return parsed;
      }
      
      // If parsing fails, fall back to sequential translation (safe double-barrier strategy)
      debugPrint("Batch translation parsing failed. Falling back to sequential translation.");
      final List<String> results = [];
      for (final text in texts) {
        results.add(await translate(text));
      }
      return results;
    } catch (e) {
      debugPrint("Batch translation failed: $e. Falling back to sequential.");
      final List<String> results = [];
      for (final text in texts) {
        results.add(await translate(text));
      }
      return results;
    } finally {
      await session.close();
    }
  }

  List<String>? _parseBatchResponse(String response, int expectedCount) {
    final lines = response.split('\n');
    final List<String> results = List.filled(expectedCount, "");
    int foundCount = 0;
    
    final pattern = RegExp(r'^(\d+)\.\s*(.*)$');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      final match = pattern.firstMatch(trimmed);
      if (match != null) {
        final index = int.tryParse(match.group(1)!) ?? 0;
        final translation = match.group(2)!.trim();
        
        if (index >= 1 && index <= expectedCount) {
          String clean = translation;
          if (clean.startsWith('"') && clean.endsWith('"') && clean.length > 1) {
            clean = clean.substring(1, clean.length - 1);
          } else if (clean.startsWith("'") && clean.endsWith("'") && clean.length > 1) {
            clean = clean.substring(1, clean.length - 1);
          }
          results[index - 1] = clean;
          foundCount++;
        }
      }
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
