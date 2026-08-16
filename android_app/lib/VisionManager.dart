import 'dart:async';
import 'package:flutter/services.dart';

class VisionManager {
  static const MethodChannel _channel = MethodChannel('com.airdrop.gesture/vision');

  // Broadcast stream for incoming gesture triggers
  static final StreamController<String> _gestureStreamController = StreamController<String>.broadcast();
  static Stream<String> get gestureStream => _gestureStreamController.stream;

  // Broadcast stream for incoming native shared files
  static final StreamController<String> _sharedFileStreamController = StreamController<String>.broadcast();
  static Stream<String> get sharedFileStream => _sharedFileStreamController.stream;

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
        case 'onSharedFileReceived':
          if (call.arguments is String) {
            _sharedFileStreamController.add(call.arguments as String);
          }
          break;
        default:
          break;
      }
    });
  }

  static Future<String?> getInitialSharedFile() async {
    try {
      final String? path = await _channel.invokeMethod('getSharedFile');
      return path;
    } catch (e) {
      return null;
    }
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

  static Future<bool> checkOverlayPermission() async {
    try {
      final bool hasPerm = await _channel.invokeMethod('checkOverlayPermission');
      return hasPerm;
    } catch (e) {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      print("Failed to request overlay permission: $e");
    }
  }
}
