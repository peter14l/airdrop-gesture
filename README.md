# AirDrop Gesture Suite

A low-power, cross-device file & clipboard sharing suite between Android and Windows 11 using local computer vision (MediaPipe) and secure mDNS / WebSocket network pipelines.

## Project Structure
- `/android_app`: Flutter-based Android App with Material 3 Expressive UI and native MediaPipe tracking.
- `/windows_app`: WinUI 3 desktop client using Fluent Design (Mica Alt) and native system tray listener.
- `/material_3_expressive`: Localized layout foundations.

## Core Features
- **Low-Power Sensor-Gated Vision**: Hands-free gestural triggers (Pinch to Grab, Palm to Drop) utilizing GPU/NNAPI (NPU). Auto-sleeps camera pipeline after 8s of inactivity.
- **Zero-Config Pairing**: Auto-discovers companion IP address on local network using mDNS (Network Service Discovery).
- **Mica Alt & Fluent UI**: Windows desktop helper client matches native Windows 11 styling and hides cleanly in System Tray.
