import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

class TranslationService {
  bool _isInitialized = false;
  InferenceModel? _model;
  InferenceModelSession? _session;

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

    // 3. Load active model and open session
    _model = await FlutterGemma.getActiveModel(maxTokens: 1024);
    _session = await _model!.createSession();

    _isInitialized = true;
  }

  Future<String> translate(String japaneseText) async {
    if (!_isInitialized) {
      throw StateError("TranslationService is not initialized. Call init() first.");
    }
    
    final prompt = "Translate the following Japanese text to English. Return only the English translation. Text: $japaneseText";
    
    await _session!.addQueryChunk(Message(text: prompt, isUser: true));
    final response = await _session!.getResponse();
    return response;
  }

  Future<void> dispose() async {
    if (_session != null) {
      await _session!.close();
    }
    if (_model != null) {
      await _model!.close();
    }
    _isInitialized = false;
  }
}
