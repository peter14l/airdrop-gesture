import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nsd/nsd.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NetworkManager {
  static const String _serviceType = '_airdropgesture._tcp';
  
  Discovery? _discovery;
  WebSocketChannel? _channel;
  final StreamController<String> _payloadController = StreamController<String>.broadcast();
  
  Stream<String> get payloadStream => _payloadController.stream;
  
  String? _targetIp;
  int? _targetPort;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  Future<void> startAutoPairing() async {
    try {
      _discovery = await startDiscovery(_serviceType);
      _discovery?.addListener(() {
        if (_discovery?.services.isNotEmpty == true) {
          final service = _discovery!.services.first;
          _targetIp = service.addresses?.first.address ?? service.host;
          _targetPort = service.port;
          
          if (_targetIp != null && _targetPort != null) {
            print("Auto-discovered desktop client: $_targetIp:$_targetPort");
            _connectToWebSocket();
          }
        }
      });
    } catch (e) {
      print("Discovery error: $e");
    }
  }

  void _connectToWebSocket() {
    if (_isConnected) return;
    
    final uri = Uri.parse('ws://$_targetIp:$_targetPort');
    print("Connecting to ws://$_targetIp:$_targetPort");
    
    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _connectionStateController.add(true);
      
      _channel?.stream.listen((message) {
        _payloadController.add(message.toString());
      }, onDone: () {
        _isConnected = false;
        _connectionStateController.add(false);
        print("Connection closed");
      }, onError: (e) {
        _isConnected = false;
        _connectionStateController.add(false);
        print("WebSocket error: $e");
      });
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      print("WebSocket connection failed: $e");
    }
  }

  Future<void> sendPayload(
    String type,
    String content, {
    String? fileName,
    String? mimeType,
    int? fileSize,
    void Function(double progress, String status)? onProgress,
  }) async {
    if (!_isConnected || _channel == null) {
      print("WebSocket not connected");
      return;
    }

    // For large files (> 64 KB), stream in chunks for high throughput & smooth progress animation
    if ((type == "file" || type == "image") && content.length > 65536) {
      final chunkSize = 65536; // 64 KB chunk size for fast socket dispatch
      final totalChunks = (content.length / chunkSize).ceil();
      final transferId = "xfer_${DateTime.now().millisecondsSinceEpoch}";

      // Send start header
      final initPayload = {
        'type': 'transfer_start',
        'transferId': transferId,
        'payloadType': type,
        'fileName': fileName,
        'mimeType': mimeType,
        'totalSize': content.length,
        'totalChunks': totalChunks,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _channel?.sink.add(jsonEncode(initPayload));

      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize < content.length) ? start + chunkSize : content.length;
        final chunkData = content.substring(start, end);

        final chunkPayload = {
          'type': 'transfer_chunk',
          'transferId': transferId,
          'chunkIndex': i,
          'data': chunkData,
        };
        _channel?.sink.add(jsonEncode(chunkPayload));

        final progress = (i + 1) / totalChunks;
        onProgress?.call(progress, "Streaming: ${(progress * 100).toStringAsFixed(0)}%");
        // Small yield so UI event loop stays butter smooth
        if (i % 4 == 0) await Future.delayed(const Duration(milliseconds: 1));
      }

      // Send complete header
      final completePayload = {
        'type': 'transfer_complete',
        'transferId': transferId,
      };
      _channel?.sink.add(jsonEncode(completePayload));
      onProgress?.call(1.0, "Transferred successfully!");
    } else {
      // Small payload or direct text
      onProgress?.call(0.5, "Sending...");
      final payload = {
        'type': type,
        'content': content,
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSize': fileSize,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      _channel?.sink.add(jsonEncode(payload));
      onProgress?.call(1.0, "Dropped to Windows PC!");
    }
    
    print("Payload sent: $type ${fileName != null ? '($fileName)' : ''}");
  }

  void dispose() {
    if (_discovery != null) {
      stopDiscovery(_discovery!);
    }
    _channel?.sink.close();
    _payloadController.close();
    _connectionStateController.close();
  }
}
