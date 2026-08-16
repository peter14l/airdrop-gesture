import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
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

  late StreamSubscription _gestureSubscription;
  late StreamSubscription _connectionSubscription;
  StreamSubscription? _intentSub;

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

    // Listen for incoming shared files/text from Android Share Sheet
    _listenForSharedIntents();
  }

  void _listenForSharedIntents() {
    try {
      ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _processSharedFile(value.first.path);
        }
      });

      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _processSharedFile(value.first.path);
        }
      });
    } catch (e) {
      print("Error listening to share intent: $e");
    }
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
      if (_payloadType == "text" && _clipboardPayload.isNotEmpty) {
        await _networkManager.sendPayload("text", _clipboardPayload);
        setState(() {
          _statusMessage = "Text dropped & synced to Windows clipboard!";
          _clipboardPayload = "";
        });
      } else if ((_payloadType == "file" || _payloadType == "image") && _base64FileContent != null) {
        await _networkManager.sendPayload(
          _payloadType,
          _base64FileContent!,
          fileName: _selectedFileName,
          fileSize: _selectedFileSize,
        );
        setState(() {
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

            // Gestural Status Card
            Expanded(
              child: M3ECard(
                variant: M3ECardVariant.elevated,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
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
                        const SizedBox(height: 20),
                        Text(
                          "Detected Gesture: $_activeGesture",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                        ),
                        if (_clipboardPayload.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
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
                                    style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13, fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )
                        ]
                      ],
                    ),
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
    _gestureSubscription.cancel();
    _connectionSubscription.cancel();
    _networkManager.dispose();
    super.dispose();
  }
}
