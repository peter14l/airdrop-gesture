import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
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
  
  // Holding payload state
  String _payloadType = "text"; // "text", "image", "file"
  String _clipboardPayload = "";
  String? _selectedFileName;
  int? _selectedFileSize;
  String? _base64FileContent;

  List<Offset> _handLandmarks = [];
  late StreamSubscription _landmarksSubscription;
  late StreamSubscription _gestureSubscription;
  late StreamSubscription _rawGestureSubscription;
  late StreamSubscription _connectionSubscription;
  StreamSubscription? _sharedFileSub;

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

    _landmarksSubscription = VisionManager.landmarksStream.listen((landmarks) {
      setState(() {
        _handLandmarks = landmarks;
      });
    });

    _rawGestureSubscription = VisionManager.rawGestureStream.listen((rawGesture) {
      setState(() {
        _activeGesture = rawGesture;
      });
    });

    _gestureSubscription = VisionManager.gestureStream.listen((gesture) {
      setState(() {
        _activeGesture = gesture == 'TRIGGER_GRAB' ? "Closed_Fist (GRAB)" : "Open_Palm (DROP)";
      });
      _handleGestureAction(gesture);
    });

    // Listen for incoming shared files/text from Android Share Sheet via native Kotlin channel
    _sharedFileSub = VisionManager.sharedFileStream.listen((filePath) {
      _processSharedFile(filePath);
    });

    VisionManager.getInitialSharedFile().then((filePath) {
      if (filePath != null) {
        _processSharedFile(filePath);
      }
    });
  }

  Future<void> _processSharedFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final name = filePath.split(Platform.pathSeparator).last;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final isImg = ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext);

        setState(() {
          _payloadType = isImg ? "image" : "file";
          _selectedFileName = name;
          _selectedFileSize = bytes.length;
          _base64FileContent = base64Encode(bytes);
          _clipboardPayload = "$name (${(bytes.length / 1024).toStringAsFixed(1)} KB)";
          _statusMessage = "Shared file queued! Make a fist (Grab) or push palm (Drop).";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to load shared file: $e";
      });
    }
  }

  Future<void> _pickFileForGrab() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);

        if (bytes != null) {
          final isImg = ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(file.extension?.toLowerCase());
          setState(() {
            _payloadType = isImg ? "image" : "file";
            _selectedFileName = file.name;
            _selectedFileSize = file.size;
            _base64FileContent = base64Encode(bytes);
            _clipboardPayload = "${file.name} (${(file.size / 1024).toStringAsFixed(1)} KB)";
            _statusMessage = "File loaded into hand queue! Make a fist (Grab) or Push (Drop).";
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = "File selection error: $e";
      });
    }
  }

  // Transfer Progress & Animation State
  bool _isTransferring = false;
  double _transferProgress = 0.0;
  String _transferStatusText = "";

  Future<void> _handleGestureAction(String gesture) async {
    if (gesture == 'TRIGGER_GRAB') {
      // If a file is already queued by user, keep it; otherwise grab real OS clipboard
      if (_base64FileContent == null) {
        try {
          final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
          final realText = clipboardData?.text;

          setState(() {
            _payloadType = "text";
            if (realText != null && realText.trim().isNotEmpty) {
              _clipboardPayload = realText;
              _statusMessage = "Clipboard text grabbed! Push palm to drop to PC.";
            } else {
              _clipboardPayload = "Gesture Grab @ ${DateTime.now().toLocal()}";
              _statusMessage = "Grabbed snapshot! Push palm to drop.";
            }
          });
        } catch (e) {
          setState(() {
            _payloadType = "text";
            _clipboardPayload = "Captured Payload @ ${DateTime.now().toLocal()}";
            _statusMessage = "Grabbed! Ready to Drop.";
          });
        }
      } else {
        setState(() {
          _statusMessage = "File/Photo firmly grabbed in hand! Push palm to drop.";
        });
      }
    } else if (gesture == 'TRIGGER_DROP') {
      if (_isTransferring) return;

      if (_payloadType == "text" && _clipboardPayload.isNotEmpty) {
        setState(() {
          _isTransferring = true;
          _transferProgress = 0.3;
          _transferStatusText = "Beaming text...";
        });

        await _networkManager.sendPayload(
          "text",
          _clipboardPayload,
          onProgress: (p, msg) {
            setState(() {
              _transferProgress = p;
              _transferStatusText = msg;
            });
          },
        );

        setState(() {
          _isTransferring = false;
          _statusMessage = "Text dropped & synced to Windows clipboard!";
          _clipboardPayload = "";
        });
      } else if ((_payloadType == "file" || _payloadType == "image") && _base64FileContent != null) {
        setState(() {
          _isTransferring = true;
          _transferProgress = 0.05;
          _transferStatusText = "Initiating High-Speed Transfer...";
        });

        await _networkManager.sendPayload(
          _payloadType,
          _base64FileContent!,
          fileName: _selectedFileName,
          fileSize: _selectedFileSize,
          onProgress: (p, msg) {
            setState(() {
              _transferProgress = p;
              _transferStatusText = msg;
            });
          },
        );

        setState(() {
          _isTransferring = false;
          _statusMessage = "Dropped $_selectedFileName to Windows Downloads/AirDrop!";
          _clipboardPayload = "";
          _base64FileContent = null;
          _selectedFileName = null;
          _payloadType = "text";
        });
      } else {
        setState(() {
          _statusMessage = "Nothing grabbed yet. Make a fist or select a file first.";
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

            // Gestural Status & Live Skeleton Preview Card
            Expanded(
              child: M3ECard(
                variant: M3ECardVariant.elevated,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Viewport Background
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black.withOpacity(0.92),
                        child: _isPipelineActive
                            ? CustomPaint(
                                painter: HandSkeletonPainter(
                                  landmarks: _handLandmarks,
                                  gesture: _activeGesture,
                                  primaryColor: scheme.primary,
                                  secondaryColor: scheme.secondary,
                                ),
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam_off, size: 64, color: scheme.outline),
                                    const SizedBox(height: 12),
                                    Text(
                                      "Sensor Sleeping (Power Saved)",
                                      style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Tap 'Arm Camera' or hover over sensor to wake",
                                      style: TextStyle(color: scheme.outline, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                      ),

                      // Overlay HUD Badges
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isPipelineActive ? Colors.greenAccent : Colors.grey,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isPipelineActive ? Colors.greenAccent : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isPipelineActive ? "TRACKING ACTIVE" : "STANDBY",
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: scheme.primary.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "Gesture: $_activeGesture",
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bottom Holding & Transfer Card
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Column(
                          children: [
                            if (_clipboardPayload.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _payloadType == 'image' ? Icons.image : (_payloadType == 'file' ? Icons.insert_drive_file : Icons.content_paste),
                                      color: scheme.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Holding: $_clipboardPayload",
                                        style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Live Transfer Progress
                            if (_isTransferring)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: scheme.secondary, width: 1.5),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_transferStatusText, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text("${(_transferProgress * 100).toStringAsFixed(0)}%", style: TextStyle(color: scheme.secondary, fontWeight: FontWeight.w900)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: _transferProgress,
                                      backgroundColor: Colors.white24,
                                      valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                                    ),
                                  ],
                                ),
                              )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _toggleVisionPipeline,
                    icon: Icon(_isPipelineActive ? Icons.stop : Icons.play_arrow),
                    label: Text(_isPipelineActive ? "Stop Camera" : "Arm Camera"),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: "Select File / Photo to Drop",
                  onPressed: _pickFileForGrab,
                  icon: const Icon(Icons.attach_file),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: "Request Floating Overlay Permission (Huawei-style background mode)",
                  onPressed: () async {
                    final hasPerm = await VisionManager.checkOverlayPermission();
                    if (!hasPerm) {
                      await VisionManager.requestOverlayPermission();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Overlay Permission Active! Gesture tracker ready across apps.")),
                      );
                    }
                  },
                  icon: const Icon(Icons.layers),
                )
              ],
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
    _landmarksSubscription.cancel();
    _gestureSubscription.cancel();
    _rawGestureSubscription.cancel();
    _connectionSubscription.cancel();
    _sharedFileSub?.cancel();
    _networkManager.dispose();
    super.dispose();
  }
}

// MediaPipe 21 Hand Landmarks Skeleton Painter with glowing cyber lines & joints
class HandSkeletonPainter extends CustomPainter {
  final List<Offset> landmarks;
  final String gesture;
  final Color primaryColor;
  final Color secondaryColor;

  HandSkeletonPainter({
    required this.landmarks,
    required this.gesture,
    required this.primaryColor,
    required this.secondaryColor,
  });

  // 21 standard MediaPipe hand landmark connections
  static const List<List<int>> connections = [
    // Palm base
    [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // Index
    [5, 9], [9, 10], [10, 11], [11, 12], // Middle
    [9, 13], [13, 14], [14, 15], [15, 16], // Ring
    [13, 17], [17, 18], [18, 19], [19, 20], // Pinky
    [0, 17], // Wrist to Pinky root
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Draw radar grid
    final gridPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.35, gridPaint);
    canvas.drawCircle(center, size.width * 0.20, gridPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);

    if (landmarks.isEmpty) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: "Show your hand to camera\n(Fist to Grab • Palm to Drop)",
          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 40);
      textPainter.paint(canvas, Offset((size.width - textPainter.width) / 2, center.dy - 20));
      return;
    }

    final isGrab = gesture.contains("Closed_Fist") || gesture.contains("GRAB");
    final isDrop = gesture.contains("Open_Palm") || gesture.contains("DROP");
    final activeBoneColor = isGrab ? Colors.amberAccent : (isDrop ? Colors.cyanAccent : Colors.greenAccent);

    // Glowing bone stroke
    final boneGlowPaint = Paint()
      ..color = activeBoneColor.withOpacity(0.4)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final bonePaint = Paint()
      ..color = activeBoneColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final jointGlowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final jointRingPaint = Paint()
      ..color = activeBoneColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw connecting bones
    for (final conn in connections) {
      if (conn[0] < landmarks.length && conn[1] < landmarks.length) {
        final p1 = Offset(landmarks[conn[0]].dx * size.width, landmarks[conn[0]].dy * size.height);
        final p2 = Offset(landmarks[conn[1]].dx * size.width, landmarks[conn[1]].dy * size.height);

        canvas.drawLine(p1, p2, boneGlowPaint);
        canvas.drawLine(p1, p2, bonePaint);
      }
    }

    // Draw joints
    for (int i = 0; i < landmarks.length; i++) {
      final p = Offset(landmarks[i].dx * size.width, landmarks[i].dy * size.height);
      // Fingertips (4, 8, 12, 16, 20) are slightly larger
      final isTip = [4, 8, 12, 16, 20].contains(i);
      final radius = isTip ? 6.0 : 4.0;

      canvas.drawCircle(p, radius, jointGlowPaint);
      canvas.drawCircle(p, radius + 2, jointRingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HandSkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks || oldDelegate.gesture != gesture;
  }
}
