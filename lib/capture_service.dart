import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CaptureService {
  static const _channel = MethodChannel('com.example.screentranslate/capture');

  Future<bool> startCaptureSession() async {
    try {
      final bool? success = await _channel.invokeMethod<bool>('startCaptureSession');
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to start capture session: ${e.message}");
      return false;
    }
  }

  Future<String?> captureScreen() async {
    try {
      final String? path = await _channel.invokeMethod<String>('captureScreen');
      return path;
    } on PlatformException catch (e) {
      debugPrint("Failed to capture screen: ${e.message}");
      return null;
    }
  }

  Future<void> stopCaptureSession() async {
    try {
      await _channel.invokeMethod('stopCaptureSession');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop capture session: ${e.message}");
    }
  }
}
