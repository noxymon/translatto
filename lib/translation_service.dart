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

  Future<void> dispose() async {
    if (_model != null) {
      await _model!.close();
    }
    _isInitialized = false;
  }
}
