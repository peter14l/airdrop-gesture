# AirDrop Gesture Suite

A low-power, cross-device clipboard sharing suite between Android and Windows 11 using real-time hand gesture recognition (MediaPipe via CameraX) and a zero-config mDNS / WebSocket local network pipeline.

---

## Project Structure

```
airdrop/
├── android_app/          # Flutter Android app — gesture capture & payload sender
│   └── android/          # Native Kotlin — CameraX + MediaPipe pipeline
├── windows_app/          # WinUI 3 Windows desktop service — WebSocket receiver
└── .github/workflows/    # GitHub Actions CI/CD — builds APK + MSIX, creates releases
```

---

## How It Works

1. **Windows app** starts a WebSocket server on port 8080 (bound to all network interfaces) and advertises itself over mDNS as `_airdropgesture._tcp`.
2. **Android app** performs mDNS discovery on the local WiFi network, finds the Windows PC automatically, and connects via WebSocket — no IP address entry needed.
3. Once connected, tapping **Arm Hand Camera** opens the front camera and runs MediaPipe hand gesture recognition in real time.
4. A **closed fist / pinch** gesture grabs a clipboard payload; an **open palm push** drops it to the Windows PC, which writes it directly to the system clipboard.

---

## Core Features

| Feature | Detail |
|---|---|
| **Real-Time Hand Tracking** | MediaPipe `GestureRecognizer` running in `LIVE_STREAM` mode via CameraX on the front camera |
| **Gesture Actions** | Closed Fist → **Grab** payload · Open Palm → **Drop** to Windows clipboard |
| **Zero-Config Pairing** | mDNS auto-discovery (`_airdropgesture._tcp`) — no manual IP entry |
| **Sensor-Gated Wake** | Accelerometer + proximity sensor auto-arm the camera; 30 s idle auto-sleep |
| **System Clipboard Sync** | Received payloads written directly to the Windows system clipboard |
| **Fluent / Mica UI** | WinUI 3 desktop client with Mica Alt backdrop and system tray minimize |
| **CI/CD Releases** | GitHub Actions builds and publishes signed APK + MSIX on every push to `main` |

---

## Requirements

### Android
- Android device with a front camera
- Same WiFi network as the Windows PC
- Android 8.0+ (API 26+)

### Windows
- Windows 11 (or Windows 10 1903+)
- Same WiFi network as the Android device
- .NET 10 Runtime (bundled in the MSIX via Windows App Runtime 2.3)
- Port 8080 open on the local firewall

---

## Building & Installing

### Android APK

```bash
cd android_app
flutter pub get
flutter build apk --release
# Output: android_app/build/app/outputs/flutter-apk/app-release.apk
```

### Windows MSIX (local sideload)

```powershell
# 1. Build the unsigned package
dotnet build windows_app/windows_app.csproj `
  -c Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 `
  -p:GenerateAppxPackageOnBuild=true `
  -p:AppxPackageSigningEnabled=false `
  -p:UapAppxPackageBuildMode=Sideloading

# 2. Sign with your local certificate
signtool.exe sign /fd SHA256 /sha1 <CERT_THUMBPRINT> `
  windows_app\AppPackages\windows_app_1.0.0.0_x64_Test\windows_app_1.0.0.0_x64.msix

# 3. Register the HTTP URL ACL (one-time, run as admin)
netsh http add urlacl url=http://+:8080/ user=Everyone

# 4. Install
Add-AppxPackage -Path windows_app\AppPackages\windows_app_1.0.0.0_x64_Test\windows_app_1.0.0.0_x64.msix
```

### CI/CD (GitHub Actions)

Push to `main` triggers `.github/workflows/release.yml`, which:
- Builds and signs the Android APK
- Builds and signs the Windows MSIX
- Creates a GitHub Release with both artifacts attached

Releases are created even if one platform's build fails — only the successfully built artifact is attached.

Required repository secrets:

| Secret | Description |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded `.jks` keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |
| `WINDOWS_PFX_BASE64` | Base64-encoded `.pfx` signing certificate |
| `WINDOWS_PFX_PASSWORD` | PFX password |

---

## Usage

1. Launch the **Windows app** — it starts listening and advertising on the network immediately.
2. Launch the **Android app** — the status badge turns **green** once it auto-discovers and connects to the PC.
3. Tap **Arm Hand Camera** → grant camera permission when prompted.
4. Hold your hand in front of the front camera:
   - **Closed fist / pinch** → grabs a payload
   - **Open palm (push outward)** → sends the payload to the Windows clipboard
5. The Windows app log panel shows each received payload in real time.
