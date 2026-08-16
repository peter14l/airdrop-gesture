# Project Specification & Progress Tracker: AirDrop Gesture Suite (Huawei Air-Grab & Drop Parity)

## 1. Vision & Architectural Objective
To build an open-source, zero-config, cross-device file & clipboard sharing suite between Android and Windows 11 matching the user experience of **Huawei Super Device Air-Grab & Air-Drop**:
- **Air-Grab (Android)**: Closed fist / pinch in front of the front camera captures real clipboard text, screenshots, or selected files/photos into an active transfer holding state.
- **Air-Push / Drop (Android $\rightarrow$ Windows)**: Open palm push gesture sends the payload over a high-speed local WebSocket / mDNS network tunnel.
- **Air-Receive / Paste (Windows 11)**: Receives payload, automatically writes to system clipboard, stores incoming files to `Downloads/AirDrop`, and supports webcam gesture-triggered paste or instant sync.

---

## 2. Technical Architecture & Protocols

### A. Network & Protocol Layer
- **Discovery**: Zero-configuration mDNS beaconing `_airdropgesture._tcp` on local WiFi.
- **Transport**: WebSockets (`ws://<IP>:8080`).
- **Payload Schema (JSON Envelope + Binary Streaming)**:
  ```json
  {
    "type": "text" | "image" | "file",
    "name": "filename.ext",
    "mime": "image/png",
    "size": 1048576,
    "content": "<base64 string or plain text>",
    "timestamp": 1723820000000
  }
  ```

### B. Android Subsystem (`android_app/`)
- **UI**: Flutter with Material 3 Expressive UI, live gesture feedback badge, and payload preview card.
- **Sensors**: Accelerometer + Proximity hardware gating (wake camera on lift/proximity, auto-sleep after 30s idle).
- **Vision Pipeline**: CameraX `LIVE_STREAM` output feeding Google MediaPipe `GestureRecognizer` (`gesture_recognizer.task` with GPU delegate).
- **Triggers**:
  - `Closed_Fist` $\rightarrow$ `TRIGGER_GRAB` (Reads real Android clipboard or grabs queued image/file).
  - `Open_Palm` $\rightarrow$ `TRIGGER_DROP` (Transmits payload across WebSocket).

### C. Windows Subsystem (`windows_app/`)
- **UI**: WinUI 3 desktop client targeting `.NET 10`, Windows App SDK 2.3, Mica Alt backdrop, System Tray minimization.
- **Receiver Service**: Background WebSocket listener on port 8080 + mDNS advertiser (`Makaretu.Dns`).
- **File System / Clipboard Sink**:
  - Automatically saves dropped media to `%USERPROFILE%\Downloads\AirDrop\`.
  - Injects received text and images into `Windows.ApplicationModel.DataTransfer.Clipboard`.
  - Dispatches Windows Toast Notification via `Microsoft.Windows.AppNotifications`.
  - Supports webcam motion/occlusion detector to trigger paste action.

---

## 3. Implementation Progress Checklist

| Component | Task | Status | Notes |
|---|---|:---:|---|
| **Android** | Project structure & Flutter UI | ✅ Completed | Using Material 3 Expressive components |
| **Android** | Hardware Sensor Wake / Idle Sleep | ✅ Completed | Accelerometer & proximity listeners in `MainActivity.kt` |
| **Android** | System Floating Overlay Mode | ✅ Completed | `SYSTEM_ALERT_WINDOW` permission + background gesture persistence |
| **Android** | CameraX & MediaPipe Pipeline Setup | ✅ Completed | Running `LIVE_STREAM` with GPU Delegate in `GestureRecognizerHelper.kt` |
| **Android** | MediaPipe Task Model Asset | ✅ Completed | `gesture_recognizer.task` (8.37 MB) bundled in `assets/` |
| **Android** | Real OS Clipboard & Grab Trigger | ✅ Completed | Hooked Flutter `Clipboard.getData` on `Closed_Fist` |
| **Android** | File & Photo Picker Integration | ✅ Completed | `file_picker` integration for queuing photos/files for Air-Drop |
| **Android** | System-Wide Share Sheet Integration | ✅ Completed | `receive_sharing_intent` + AndroidManifest `ACTION_SEND` filters |
| **Networking** | mDNS Discovery & WebSocket Client | ✅ Completed | Auto-discovers and connects without manual IP |
| **Networking** | Multi-type Payload Protocol (Text/Image/File) | ✅ Completed | JSON schema with base64 payload & metadata support |
| **Windows** | WinUI 3 App Shell & Mica Backdrop | ✅ Completed | Packaged MSIX with tray icon |
| **Windows** | WebSocket Listener & mDNS Advertiser | ✅ Completed | HttpListener with fallback to localhost |
| **Windows** | Real Clipboard Auto-Sync & Notifications | ✅ Completed | Direct `Clipboard.SetContent` + Windows 11 Toast notifications |
| **Windows** | Auto-save Dropped Files to Storage | ✅ Completed | Writes incoming files/images to `%USERPROFILE%\Downloads\AirDrop` with UI direct open |
| **Windows** | Webcam Drop Sensor | ✅ Completed | Unsafe luminance detector with custom drop gesture |
| **CI/CD** | GitHub Actions Workflow for Release | ✅ Completed | Builds APK & MSIX, publishes signed release |

---

## 4. LLM Handover & Continuity Instructions
*For any AI assistant / developer continuing this work:*
1. **Source Code Structure**:
   - `android_app/lib/`: Flutter code (`HomeScreen.dart`, `NetworkManager.dart`, `VisionManager.dart`).
   - `android_app/android/app/src/main/kotlin/com/airdrop/gesture/android_app/`: Native CameraX and MediaPipe implementation (`MainActivity.kt`, `GestureRecognizerHelper.kt`).
   - `windows_app/`: WinUI 3 project (`WebSocketListenerService.cs`, `MainPage.xaml.cs`, `MainWindow.xaml.cs`).
2. **Build Commands**:
   - Android: `cd android_app && flutter build apk --release`
   - Windows: `dotnet build windows_app/windows_app.csproj -c Release -p:Platform=x64`
3. **Core Dependencies**:
   - Android MediaPipe: `com.google.mediapipe:tasks-vision:0.10.29`
   - Windows App SDK: `Microsoft.WindowsAppSDK 2.3.1` on `.NET 10.0`
