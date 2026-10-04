# LocalChat project context

Updated: 2026-10-04. The workspace is authoritative; read README.md,
docs/SECURITY.md, docs/VALIDATION.md and the relevant code before making changes.

## Goal and scope

LocalChat was created in ChatGPT and continued in this Flutter workspace.
It enables nearby offline messaging without a router, mobile data, accounts,
backend, Firebase or cloud database. Version 0.1 is Android-first and text only.
Images and videos are planned later. Bluetooth, group chat, relaying, iOS,
background delivery and notifications are also future work.

## Android implementation

- Kotlin WifiP2pManager DNS-SD discovery and framed TCP transport, bridged to
  Flutter through MethodChannel/EventChannel (`MainActivity.kt`, `transport.dart`).
- Ed25519 identity signatures, fresh X25519 session keys, HKDF-SHA256 and
  XChaCha20-Poly1305 (`secure_session.dart`). Both phones must compare and
  explicitly confirm the complete security code on each connection.
- Encrypted message bodies in SQLite, identity/history keys in
  flutter_secure_storage (`local_store.dart`). Metadata remains unencrypted.
- Material 3 nearby devices, chat, settings, acknowledgements and saved history,
  coordinated by a serialized ChangeNotifier controller (`chat_controller.dart`).
- Both apps must remain open. No automatic retransmission or offline outbox.
- The protocol is experimental and has not had an independent security audit.

## Browser preview

Run `flutter pub get`, then `flutter run -d chrome` from this directory.
`createController()` in `lib/main.dart` selects the demo only when `kIsWeb`.
Android keeps `WifiDirectTransport()` and `LocalStore()`.

`lib/demo/demo_transport.dart` supplies Ava and Noah as simulated nearby peers,
answers the shared controller's protocol frames, simulates peer confirmation,
acknowledgements and replies. `lib/demo/demo_store.dart` uses memory only and
never invokes SQLite or platform secure storage. A persistent Browser Demo
notice stays visible on all routes; verification and Settings explain the
simulation. No sockets, radio discovery or real Wi-Fi Direct communication
occur in browser mode. Everything resets when the tab reloads. Demo protocol
encryption is not a claim of communicating securely with another device.

## Validation and outstanding work

The original validation recorded 19 passing tests, clean analysis, a successful
Android debug APK build and verified APK signature with Flutter 3.35.7 /
Dart 3.9.2, Java 17, Android SDK 36 (minimum API 24). This Windows environment
currently has Flutter 3.38.7 / Dart 3.10.7.

Browser demo checks cover discovery, mandatory confirmation before send,
simulated replies/delivery, fresh verification on reconnect, per-peer history,
live history deletion, rename/reset behavior and persistent demo labelling on
small screens. This change passed `flutter analyze`, all 23 tests, and the
JavaScript web build. A headless Chrome smoke check exercised discovery,
verification, sending, simulated delivery and replies. The separate Chrome
test runner has a CanvasKit asset-serving issue in this installed Windows SDK.
Android rebuild is blocked here by the missing Android SDK. See
docs/VALIDATION.md for full results and limitations.

Still outstanding: physical two-phone discovery, pairing and messaging,
vendor/API compatibility, Android permission/lifecycle behavior, platform key
storage on hardware, and independent protocol/code security review. Browser
preview and automated tests do not validate these.

## Source control

Local Git history and LocalChat-history.bundle are included. GitHub account:
`yolomon9994`; intended repository: `LocalChat`. The user reports this project
has not been pushed yet. Do not publish or push without a user request.
No open-source license has been selected. Existing workspace changes in
`android/gradlew` and `pubspec.lock` predate the browser-preview work.
