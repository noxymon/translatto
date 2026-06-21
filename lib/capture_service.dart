import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CaptureService {
  static const _channel = MethodChannel('com.example.screentranslate/capture');

  Future<String?> captureScreen() async {
    try {
      final String? path = await _channel.invokeMethod('captureScreen');
      return path;
    } on PlatformException catch (e) {
      debugPrint("Failed to capture screen: ${e.message}");
      return null;
    }
  }
}

