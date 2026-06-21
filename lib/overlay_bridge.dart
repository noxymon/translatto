import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class OverlayBridge {
  static const MethodChannel _channel = MethodChannel("id.web.noxymon.translatto/overlay_bridge");
  static final StreamController<dynamic> _controller = StreamController<dynamic>.broadcast();

  static Stream<dynamic> get messages => _controller.stream;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == "onMessage") {
        _controller.add(call.arguments);
      }
    });
  }

  static Future<void> send(dynamic message) async {
    try {
      await _channel.invokeMethod("send", message);
    } catch (e) {
      // Print locally in console
      debugPrint("[OverlayBridge] Error sending message: $e");
    }
  }
}
