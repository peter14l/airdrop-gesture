import 'dart:async';
import 'package:flutter/services.dart';

class VisionManager {
  static const MethodChannel _channel = MethodChannel('com.airdrop.gesture/vision');

  // Broadcast stream for real-time detected hand landmarks [(x, y, z)]
  static final StreamController<List<Offset>> _landmarksStreamController = StreamController<List<Offset>>.broadcast();
  static Stream<List<Offset>> get landmarksStream => _landmarksStreamController.stream;

  // Broadcast stream for real-time detected gesture labels
  static final StreamController<String> _rawGestureStreamController = StreamController<String>.broadcast();
  static Stream<String> get rawGestureStream => _rawGestureStreamController.stream;

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
        case 'onLandmarksDetected':
          if (call.arguments is List) {
            final list = call.arguments as List;
            final points = list.map<Offset>((pt) {
              if (pt is Map) {
                final x = (pt['x'] as num?)?.toDouble() ?? 0.0;
                final y = (pt['y'] as num?)?.toDouble() ?? 0.0;
                return Offset(x, y);
              }
              return Offset.zero;
            }).toList();
            _landmarksStreamController.add(points);
          }
          break;
        case 'onGestureDetected':
          if (call.arguments is String) {
            _rawGestureStreamController.add(call.arguments as String);
          }
          break;
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
