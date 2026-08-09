import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'NetworkManager.dart';
import 'VisionManager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final NetworkManager _networkManager = NetworkManager();
  bool _isPipelineActive = false;
  bool _isConnected = false;
  String _statusMessage = "Ready to pair with Windows 11 PC";
  String _activeGesture = "None";
  String _clipboardPayload = "";

  late StreamSubscription _gestureSubscription;
  late StreamSubscription _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _networkManager.startAutoPairing();
    VisionManager.init();

    _connectionSubscription = _networkManager.connectionStateStream.listen((connected) {
      setState(() {
        _isConnected = connected;
        _statusMessage = connected
            ? "Paired & Connected to Windows Service"
            : "Scanning network for Windows Service...";
      });
    });

    _gestureSubscription = VisionManager.gestureStream.listen((gesture) {
      setState(() {
        _activeGesture = gesture == 'TRIGGER_GRAB' ? "Fist / closed pinch (GRAB)" : "Open palm push (DROP)";
      });
      _handleGestureAction(gesture);
    });
  }

  void _handleGestureAction(String gesture) {
    if (gesture == 'TRIGGER_GRAB') {
      // Simulate grabbing a clipboard payload
      setState(() {
        _clipboardPayload = "Gesture Grab Payload @ ${DateTime.now().toLocal()}";
        _statusMessage = "Payload Grabbed! Ready to Drop.";
      });
    } else if (gesture == 'TRIGGER_DROP') {
      if (_clipboardPayload.isNotEmpty) {
        _networkManager.sendPayload("text", _clipboardPayload);
        setState(() {
          _statusMessage = "Payload Dropped to Windows PC!";
          _clipboardPayload = "";
        });
      } else {
        setState(() {
          _statusMessage = "Nothing grabbed yet. Pinch/Grab first.";
        });
      }
    }
  }

  void _toggleVisionPipeline() {
    if (_isPipelineActive) {
      VisionManager.stopVisionPipeline();
      setState(() {
        _isPipelineActive = false;
        _activeGesture = "None";
      });
    } else {
      VisionManager.startVisionPipeline();
      setState(() {
        _isPipelineActive = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("AirDrop Gesture Control"),
        backgroundColor: scheme.surfaceContainerLow,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Badge(
              backgroundColor: _isConnected ? Colors.green : Colors.red,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: Text(
                  _isConnected ? "PC Online" : "PC Offline",
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Info Card
            M3ECard(
              variant: M3ECardVariant.filled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Network Sync Status",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Gestural Status Card
            Expanded(
              child: M3ECard(
                variant: M3ECardVariant.elevated,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isPipelineActive ? Icons.videocam : Icons.videocam_off,
                      size: 64,
                      color: _isPipelineActive ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Local Hand Tracking Engine",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPipelineActive ? "Status: ACTIVE (GPU Accelerated)" : "Status: SLEEPING (Power Saved)",
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Detected Gesture: $_activeGesture",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: scheme.primary,
                      ),
                    ),
                    if (_clipboardPayload.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "Grabbed: $_clipboardPayload",
                          style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
                        ),
                      )
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: _toggleVisionPipeline,
              child: Text(_isPipelineActive ? "Stop Hand Camera" : "Arm Hand Camera"),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isConnected
                  ? () => _networkManager.sendPayload("text", "Manual clip: Hello from Android Flutter UI!")
                  : null,
              child: const Text("Send Manual Clipboard Ping"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _gestureSubscription.cancel();
    _connectionSubscription.cancel();
    _networkManager.dispose();
    super.dispose();
  }
}
