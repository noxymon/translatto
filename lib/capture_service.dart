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

  Future<void> minimizeApp() async {
    try {
      await _channel.invokeMethod('minimizeApp');
    } on PlatformException catch (e) {
      debugPrint("Failed to minimize app: ${e.message}");
    }
  }

  Future<void> sendFeedback(String version) async {
    try {
      await _channel.invokeMethod('sendFeedback', {'version': version});
    } on PlatformException catch (e) {
      debugPrint("Failed to send feedback: ${e.message}");
    }
  }

  Future<void> shareApp() async {
    try {
      await _channel.invokeMethod('shareApp');
    } on PlatformException catch (e) {
      debugPrint("Failed to share app: ${e.message}");
    }
  }

  Future<void> rateApp() async {
    try {
      await _channel.invokeMethod('rateApp');
    } on PlatformException catch (e) {
      debugPrint("Failed to rate app: ${e.message}");
    }
  }

  Future<void> openPrivacyPolicy() async {
    try {
      await _channel.invokeMethod('openPrivacyPolicy');
    } on PlatformException catch (e) {
      debugPrint("Failed to open privacy policy: ${e.message}");
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final bool? res = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to check battery optimization ignore status: ${e.message}");
      return false;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } on PlatformException catch (e) {
      debugPrint("Failed to request ignoring battery optimization: ${e.message}");
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
