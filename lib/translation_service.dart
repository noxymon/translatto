import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:http/http.dart' as http;

class TranslationService {
  bool _isInitialized = false;
  InferenceModel? _model;
  bool _useCloudApi = false;
  String _apiKey = '';

  // Cache to store translated strings mapping Japanese input -> English output
  static final Map<String, String> _translationCache = {};

  // ponytail: minimal fixed system message — shorter prefix = faster KV cache warm
  static const String _deepSeekSystemPrompt =
      'Translate accurately. Output only the translation.';

  /// Configure cloud API mode. Call before [init] when using cloud.
  void configureCloud({required String apiKey}) {
    _useCloudApi = true;
    _apiKey = apiKey;
    _isInitialized = true; // Cloud mode doesn't need local model loading
  }

  /// Switch to local model mode.
  void configureLocal() {
    _useCloudApi = false;
    _isInitialized = false;
  }

  bool get isCloudMode => _useCloudApi;

  static void clearCache() {
    _translationCache.clear();
  }

  @visibleForTesting
  set model(InferenceModel? value) {
    _model = value;
    _isInitialized = value != null;
  }

  Future<void> init(String modelPath, {String? deviceBoard}) async {
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
    debugPrint('[TranslationService] Step 3: getActiveModel(maxTokens=256)...');
    final isKona = deviceBoard?.toLowerCase() == 'kona';
    try {
      if (isKona) {
        throw UnsupportedError("Vulkan GPU backend disabled on Snapdragon 870 / Kona to prevent driver assertion crash.");
      }
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 256,
        preferredBackend: PreferredBackend.gpu,
      );
      debugPrint('[TranslationService] GPU model initialized successfully.');
    } catch (e) {
      debugPrint('[TranslationService] GPU initialization failed or skipped: $e. Falling back to CPU.');
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 256,
        preferredBackend: PreferredBackend.cpu,
      );
    }
    debugPrint('[TranslationService] Step 3: done. model=$_model');

    _isInitialized = true;
    debugPrint("[TranslationService] init() complete.");
  }

  static bool hasJapaneseText(String text) {
    for (int i = 0; i < text.length; i++) {
      final cp = text.codeUnitAt(i);
      if ((cp >= 0x3040 && cp <= 0x309F) || // Hiragana
          (cp >= 0x30A0 && cp <= 0x30FF) || // Katakana
          (cp >= 0x4E00 && cp <= 0x9FFF)) { // CJK Kanji
        return true;
      }
    }
    return false;
  }


  static bool _isCjkCodePoint(int codePoint) {
    return (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
           (codePoint >= 0x3040 && codePoint <= 0x309F) ||
           (codePoint >= 0x30A0 && codePoint <= 0x30FF) ||
           (codePoint >= 0x3000 && codePoint <= 0x303F) ||
           (codePoint >= 0xFF00 && codePoint <= 0xFFEF);
  }

  static List<String> _splitIntoParagraphs(String text) {
    final lines = text.split('\n');
    final paragraphs = <String>[];
    
    final listMarkerRegex = RegExp(r'^([※•・●■▲\-*\s\d①-⑨\(\[\]])');
    final sentenceEndRegex = RegExp(r'[。\.!\?？]$');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (paragraphs.isEmpty) {
        paragraphs.add(trimmed);
        continue;
      }

      final last = paragraphs.last;
      if (listMarkerRegex.hasMatch(trimmed) || sentenceEndRegex.hasMatch(last)) {
        paragraphs.add(trimmed);
      } else {
        final lastChar = last.isNotEmpty ? last.codeUnitAt(last.length - 1) : 0;
        final firstChar = trimmed.codeUnitAt(0);
        final isLastCjk = _isCjkCodePoint(lastChar);
        final isFirstCjk = _isCjkCodePoint(firstChar);
        if (isLastCjk || isFirstCjk) {
          paragraphs[paragraphs.length - 1] = last + trimmed;
        } else {
          paragraphs[paragraphs.length - 1] = '$last $trimmed';
        }
      }
    }
    return paragraphs;
  }

  @visibleForTesting
  static List<String> chunkTextForTesting(String text) => _chunkText(text);

  /// Splits [text] into chunks dynamically grouped by sentence boundaries
  /// keeping complete sentences intact and using script-adaptive character limits.
  static List<String> _chunkText(String text) {
    if (text.isEmpty) return [];

    // Adaptive limits based on script type
    final isCjk = hasJapaneseText(text);
    final maxChars = isCjk ? 100 : 400;

    if (text.length <= maxChars) return [text];

    // Regex to split on sentence endings (. ! ? 。 ！ ？) followed by whitespace, keeping delimiters
    final sentenceRegex = RegExp(r'[^.!?。！？]+[.!?。！？]?\s*');
    final matches = sentenceRegex.allMatches(text).map((m) => m.group(0)!).toList();

    // If split yields nothing, return text as fallback
    if (matches.isEmpty) return [text];

    final chunks = <String>[];
    var currentChunk = StringBuffer();

    for (final sentence in matches) {
      final currentLen = currentChunk.length;
      final sentenceLen = sentence.length;

      if (currentLen == 0) {
        currentChunk.write(sentence);
      } else if (currentLen + sentenceLen <= maxChars) {
        currentChunk.write(sentence);
      } else {
        chunks.add(currentChunk.toString().trim());
        currentChunk = StringBuffer()..write(sentence);
      }

      // If a single sentence exceeds maxChars, split it by characters/sub-clauses
      if (currentChunk.length > maxChars) {
        final longSentence = currentChunk.toString();
        int start = 0;
        while (start < longSentence.length) {
          final end = (start + maxChars).clamp(0, longSentence.length);
          chunks.add(longSentence.substring(start, end).trim());
          start = end;
        }
        currentChunk = StringBuffer();
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
    }

    return chunks.where((c) => c.isNotEmpty).toList();
  }

  /// Translates a single chunk (≤ [_maxChunkChars] chars) in one inference call.
  Future<String> _translateChunk(
    String chunk, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final cacheKey = "$sourceLanguage:$targetLanguage:$chunk";
    final cached = _translationCache[cacheKey];
    if (cached != null) {
      debugPrint("[TranslationService] Chunk cache HIT: $chunk -> $cached");
      return cached;
    }

    final session = await _model!.createSession();
    try {
      final prompt =
          'Translate the input text to $targetLanguage. Output only the $targetLanguage translation, no notes.\n'
          'Input: $chunk\n$targetLanguage:';
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final response = await session.getResponse();
      final translated = response.trim();
      
      // Cache the result (bound cache size to prevent leak)
      if (_translationCache.length >= 500) {
        _translationCache.clear();
      }
      _translationCache[cacheKey] = translated;
      
      return translated;
    } finally {
      await session.close();
    }
  }

  Future<String> translate(
    String text, {
    String sourceLanguage = "auto",
    String targetLanguage = "English",
  }) async {
    if (!_isInitialized) {
      throw StateError('TranslationService is not initialized. Call init() or configureCloud() first.');
    }
    if (_useCloudApi) {
      return _translateViaDeepSeek(text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage);
    }
    if (_model == null) {
      throw StateError('Local model not loaded. Call init() first.');
    }
    
    // Check main text cache hit
    final cacheKey = "$sourceLanguage:$targetLanguage:$text";
    final cachedText = _translationCache[cacheKey];
    if (cachedText != null) {
      debugPrint("[TranslationService] Text cache HIT: $text -> $cachedText");
      return cachedText;
    }

    final paragraphs = _splitIntoParagraphs(text);
    debugPrint('[TranslationService] translate() ${text.length} chars → ${paragraphs.length} paragraph(s)');
    
    final translatedParagraphs = <String>[];
    for (final paragraph in paragraphs) {
      final chunks = _chunkText(paragraph);
      final translatedChunks = <String>[];
      for (final chunk in chunks) {
        translatedChunks.add(await _translateChunk(
          chunk,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        ));
      }
      translatedParagraphs.add(translatedChunks.join(' '));
    }
    final hasNewlines = text.contains('\n');
    final result = translatedParagraphs.join('\n');
    final finalResult = hasNewlines ? result : result.replaceAll('\n', ' ').replaceAll('\r', ' ');
    
    if (_translationCache.length >= 500) {
      _translationCache.clear();
    }
    _translationCache[cacheKey] = finalResult;

    return finalResult;
  }

  Future<List<String>> translateBatch(
    List<({String text, int x, int y, String sourceLanguage})> blocks, {
    String targetLanguage = "English",
    bool Function()? isCancelled,
  }) async {
    if (blocks.isEmpty) return [];
    if (isCancelled != null && isCancelled()) return [];
    if (!_isInitialized) {
      throw StateError('TranslationService is not initialized. Call init() or configureCloud() first.');
    }
    if (_useCloudApi) {
      return _translateBatchViaDeepSeek(blocks, targetLanguage: targetLanguage);
    }
    if (_model == null) {
      throw StateError('Local model not loaded. Call init() first.');
    }

    // Try resolving all blocks from cache first to avoid LLM session overhead
    final List<String?> cachedResults = List.filled(blocks.length, null);
    bool allCached = true;
    for (int i = 0; i < blocks.length; i++) {
      final cacheKey = "${blocks[i].sourceLanguage}:$targetLanguage:${blocks[i].text}";
      final cachedVal = _translationCache[cacheKey];
      if (cachedVal != null) {
        cachedResults[i] = cachedVal;
      } else {
        allCached = false;
      }
    }

    if (allCached) {
      debugPrint("[TranslationService] translateBatch() ALL cached. Bypassing LLM completely.");
      return cachedResults.cast<String>();
    }

    if (blocks.length == 1) {
      final single = await translate(
        blocks.first.text,
        sourceLanguage: blocks.first.sourceLanguage,
        targetLanguage: targetLanguage,
      );
      return [single];
    }

    // Batch translation: single inference with structured XML prompt containing layout coordinates
    final session = await _model!.createSession();
    try {
      if (isCancelled != null && isCancelled()) return [];
      final prompt = TranslationService.buildStructuredPrompt(blocks, targetLanguage);
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      if (isCancelled != null && isCancelled()) return [];
      final response = await session.getResponse();
      if (isCancelled != null && isCancelled()) return [];
      
      final parsed = TranslationService.parseStructuredResponse(response, blocks.length);
      if (parsed != null) {
        // Cache successfully parsed values
        if (_translationCache.length + blocks.length >= 500) {
          _translationCache.clear();
        }
        for (int i = 0; i < blocks.length; i++) {
          final cacheKey = "${blocks[i].sourceLanguage}:$targetLanguage:${blocks[i].text}";
          _translationCache[cacheKey] = parsed[i];
        }
        return parsed;
      }
      
      // Fall back to sequential if XML parsing fails
      debugPrint("Structured batch translation parsing failed. Falling back to sequential translation.");
      return await _fallbackToSequential(blocks, targetLanguage: targetLanguage, isCancelled: isCancelled);
    } catch (e) {
      if (isCancelled != null && isCancelled()) return [];
      debugPrint("Structured batch translation failed: $e. Falling back to sequential.");
      return await _fallbackToSequential(blocks, targetLanguage: targetLanguage, isCancelled: isCancelled);
    } finally {
      await session.close();
    }
  }

  Future<List<String>> _fallbackToSequential(
    List<({String text, int x, int y, String sourceLanguage})> blocks, {
    required String targetLanguage,
    bool Function()? isCancelled,
  }) async {
    final List<String> results = [];
    for (final block in blocks) {
      if (isCancelled != null && isCancelled()) break;
      try {
        results.add(await translate(
          block.text,
          sourceLanguage: block.sourceLanguage,
          targetLanguage: targetLanguage,
        ));
      } catch (e) {
        debugPrint("Failed to translate block: ${block.text}, error: $e");
        results.add(block.text); // Original text as last resort
      }
    }
    return results;
  }


  /// Builds a structured XML prompt for batch translation.
  /// [blocks] is a list of records with text and top-left pixel coordinates.
  static String buildStructuredPrompt(List<({String text, int x, int y, String sourceLanguage})> blocks, [String targetLanguage = "English"]) {
    final buffer = StringBuffer();
    buffer.writeln('Translate the input UI text blocks to $targetLanguage.');
    buffer.writeln('Format: <t id="N">translation</t>');
    buffer.writeln('Output only XML tags. No notes.');
    buffer.writeln('');
    buffer.writeln('Input:');
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      // ponytail: strip x,y from prompt — pixel coords change every frame, break KV cache
      final safeText = _chunkText(block.text.replaceAll('\n', ' ')).first;
      buffer.writeln('<t id="${i + 1}">$safeText</t>');
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

  /// Calls DeepSeek API with streaming, optimized for KV cache prefix hits.
  Future<String> _translateViaDeepSeek(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final cacheKey = "$sourceLanguage:$targetLanguage:$text";
    final cached = _translationCache[cacheKey];
    if (cached != null) return cached;

    // ponytail: constant-system-message prefix for KV cache reuse across requests
    final messages = [
      {'role': 'system', 'content': _deepSeekSystemPrompt},
      {
        'role': 'user',
        'content': 'Translate from $sourceLanguage to $targetLanguage:\n$text',
      },
    ];

    final body = jsonEncode({
      'model': 'deepseek-v4-flash',
      'messages': messages,
      'thinking': {'type': 'disabled'},
      'stream': true,
      'temperature': 0,
      'max_tokens': 1024,
    });

    try {
      final request = http.StreamedRequest(
        'POST',
        Uri.parse('https://api.deepseek.com/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      });
      request.sink.add(utf8.encode(body));
      request.sink.close();
      final response = await request.send();

      final result = await _parseDeepSeekStream(response.stream);

      if (_translationCache.length >= 500) _translationCache.clear();
      _translationCache[cacheKey] = result;
      return result;
    } catch (e) {
      debugPrint('[DeepSeek] translate error: $e');
      rethrow;
    }
  }

  /// Parses DeepSeek SSE streaming response, accumulating content deltas.
  Future<String> _parseDeepSeekStream(http.ByteStream stream) async {
    final buffer = StringBuffer();
    final completer = Completer<String>();

    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.isEmpty || !line.startsWith('data: ')) return;
        final data = line.substring(6);
        if (data == '[DONE]') {
          if (!completer.isCompleted) completer.complete(buffer.toString().trim());
          return;
        }
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null) buffer.write(content);
          }
        } catch (_) {
          // Skip malformed JSON chunks
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(buffer.toString().trim());
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Batch translation via DeepSeek with XML structured output.
  Future<List<String>> _translateBatchViaDeepSeek(
    List<({String text, int x, int y, String sourceLanguage})> blocks, {
    String targetLanguage = "English",
  }) async {
    // Check cache first
    final List<String?> cachedResults = List.filled(blocks.length, null);
    bool allCached = true;
    for (int i = 0; i < blocks.length; i++) {
      final cacheKey = "${blocks[i].sourceLanguage}:$targetLanguage:${blocks[i].text}";
      final cachedVal = _translationCache[cacheKey];
      if (cachedVal != null) {
        cachedResults[i] = cachedVal;
      } else {
        allCached = false;
      }
    }
    if (allCached) return cachedResults.cast<String>();

    // Build structured prompt — same format as local path for cache compatibility
    final prompt = buildStructuredPrompt(blocks, targetLanguage);

    final messages = [
      {'role': 'system', 'content': _deepSeekSystemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final body = jsonEncode({
      'model': 'deepseek-v4-flash',
      'messages': messages,
      'thinking': {'type': 'disabled'},
      'stream': true,
      'temperature': 0,
      'max_tokens': 2048,
    });

    try {
      final request = http.StreamedRequest(
        'POST',
        Uri.parse('https://api.deepseek.com/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      });
      request.sink.add(utf8.encode(body));
      request.sink.close();
      final response = await request.send();

      final rawResponse = await _parseDeepSeekStream(response.stream);

      final parsed = parseStructuredResponse(rawResponse, blocks.length);
      if (parsed != null) {
        if (_translationCache.length + blocks.length >= 500) _translationCache.clear();
        for (int i = 0; i < blocks.length; i++) {
          _translationCache["${blocks[i].sourceLanguage}:$targetLanguage:${blocks[i].text}"] = parsed[i];
        }
        return parsed;
      }

      // Fallback: sequential single translations for unmatched parse
      debugPrint('[DeepSeek] Batch XML parse failed, falling back to sequential.');
      return await _fallbackToSequentialViaDeepSeek(blocks, targetLanguage: targetLanguage);
    } catch (e) {
      debugPrint('[DeepSeek] Batch translate error: $e');
      rethrow;
    }
  }

  Future<List<String>> _fallbackToSequentialViaDeepSeek(
    List<({String text, int x, int y, String sourceLanguage})> blocks, {
    required String targetLanguage,
  }) async {
    final results = <String>[];
    for (final block in blocks) {
      try {
        results.add(await _translateViaDeepSeek(
          block.text,
          sourceLanguage: block.sourceLanguage,
          targetLanguage: targetLanguage,
        ));
      } catch (e) {
        debugPrint('[DeepSeek] Sequential fallback error: $e');
        results.add(block.text);
      }
    }
    return results;
  }

  Future<void> dispose() async {
    if (_model != null) {
      await _model!.close();
    }
    _isInitialized = false;
  }
}
