import 'dart:async';
import 'package:flutter/services.dart';

class VisionManager {
  static const MethodChannel _channel = MethodChannel('com.airdrop.gesture/vision');

  // Broadcast stream for incoming gesture triggers
  static final StreamController<String> _gestureStreamController = StreamController<String>.broadcast();
  static Stream<String> get gestureStream => _gestureStreamController.stream;

  static bool _initialized = false;
  static bool _isActive = false;
  static bool get isActive => _isActive;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'TRIGGER_GRAB':
          _gestureStreamController.add('TRIGGER_GRAB');
          break;
        case 'TRIGGER_DROP':
          _gestureStreamController.add('TRIGGER_DROP');
          break;
        default:
          break;
      }
    });
  }

  static Future<void> startVisionPipeline() async {
    init();
    try {
      await _channel.invokeMethod('startVisionPipeline');
      _isActive = true;
    } on PlatformException catch (e) {
      print("Failed to start vision pipeline: ${e.message}");
    }
  }

  static Future<void> stopVisionPipeline() async {
    try {
      await _channel.invokeMethod('stopVisionPipeline');
      _isActive = false;
    } on PlatformException catch (e) {
      print("Failed to stop vision pipeline: ${e.message}");
    }
  }

  static Future<void> sendFrame(Uint8List bytes, int width, int height) async {
    if (!_isActive) return;
    try {
      await _channel.invokeMethod('processFrame', {
        'bytes': bytes,
        'width': width,
        'height': height,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } on PlatformException catch (e) {
      print("Error sending frame: ${e.message}");
    }
  }
}
