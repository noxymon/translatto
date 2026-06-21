import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CaptureService {
  static const _channel = MethodChannel('id.web.noxymon.translatto/capture');

  Future<bool> startCaptureSession() async {
    try {
      final bool? success = await _channel.invokeMethod<bool>('startCaptureSession');
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to start capture session: ${e.message}");
      return false;
    }
  }

  Future<Map<String, dynamic>?> captureScreen() async {
    try {
      final Map? data = await _channel.invokeMethod<Map>('captureScreen');
      if (data != null) {
        return Map<String, dynamic>.from(data);
      }
      return null;
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

  Future<String?> getDeviceBoard() async {
    try {
      return await _channel.invokeMethod<String>('getDeviceBoard');
    } on PlatformException catch (e) {
      debugPrint("Failed to get device board: ${e.message}");
      return null;
    }
  }
}
