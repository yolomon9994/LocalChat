# Validation for v0.1.0

## App lock milestone — 2026-10-10

Checked on Windows with Flutter 3.38.7 / Dart 3.10.7, Java 21 and the installed
Android SDK. `local_auth` 3.0.2 requires Flutter >=3.38.0 / Dart >=3.10.0; the
project's declared minimums and README now reflect that dependency.

- `flutter analyze`: no issues.
- `flutter test`: 33 tests passed (23 existing + 10 app-lock checks).
- `flutter build web --no-wasm-dry-run`: successful JavaScript browser build.
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful testing APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
  Rebuilt successfully after the lock-screen navigation fix.

App-lock tests cover the actual production PIN KDF, configuration persistence,
current-PIN authorization for security changes, persistent wrong-PIN cooldowns,
storage/configuration failure behavior, biometric cancellation/failure/fallback,
pending authentication invalidation on backgrounding, startup withholding chat
storage, pushed-route removal, system Back behavior, PIN confirmation, manual
locking and the persistent browser-demo notice on a 320 × 568 screen.

Controller/UI tests use memory storage and biometric test doubles. They do not
validate a real Android sensor, Android secure-storage persistence, Recents
privacy or vendor-specific lifecycle behavior. Complete `APP_LOCK.md`'s phone
checklist before the user commits this milestone. No physical phone validation
or fresh APK signature verification has been performed for this milestone.

The first Android build emitted Kotlin incremental-cache warnings because the
Pub cache is on C: and the project is on I:. Gradle's fallback compilation
completed successfully; the final rebuild succeeded without changing build
configuration. The web build also emitted an optional Cupertino icon-font
warning; this app's interface uses the bundled Material icons.

## Original validation

Validated with Flutter 3.35.7 / Dart 3.9.2, Java 17, Android compile/target SDK 36 and minimum SDK 24.

- `flutter analyze`: no issues.
- `flutter test`: 19 tests passed.
- Android debug APK: successfully compiled Flutter and native Kotlin implementation.
- APK signature: verified with Android `apksigner`.

The automated suite covers signed handshake tampering, encrypted Unicode exchange, fresh session keys/codes, self-reflection, replay/sequence/session rejection, ciphertext authentication, mandatory verification on both peers, encrypted delivery acknowledgements, socket failure/disconnect state, reconnect/history restoration, UTF-8 size limits, corrected-send retries, live history deletion, encrypted SQLite persistence, stored ciphertext tampering, peer/direction ID scoping, and small-screen layout.

The controller integration tests use an in-memory transport, not simulated Wi-Fi Direct hardware. Database tests use real SQLite with secure-storage test doubles; this validates persistence and encryption logic, not Android Keystore behavior.

**Not yet validated:** installing/launching on physical phones, Wi-Fi Direct discovery/pairing across device vendors, over-the-air messaging/range, Android permission UI and lifecycle behavior, platform-backed key storage on hardware. Follow `DEVICE_TESTING.md` before considering this ready for a public release. The custom protocol has not had an independent security audit.

## Browser preview on Windows — 2026-10-04

Checked using Flutter 3.38.7 / Dart 3.10.7 and Chrome 154:

- `flutter pub get`: succeeded; no new package dependencies.
- `flutter analyze`: no issues.
- `flutter test`: all 23 tests passed (19 existing + 4 demo checks).
- `flutter build web --no-wasm-dry-run`: successful JavaScript web build.
- `flutter run -d chrome` with headless browser flags: started the app and
  connected to its debug service successfully.
- Normal Chrome launch smoke check via DevTools: inspected the rendered home
  and chat, discovered Ava, confirmed the demo code, sent `Hello from Chrome`,
  and observed the welcome, simulated reply and delivered status. Screenshots
  confirmed that the persistent Browser Demo notice remained visible.

The new checks cover platform selection, simulated discovery, mandatory
confirmation before sending, welcome/reply/acknowledgement handling, fresh
codes and stable peer history on reconnect, switching peers, history deletion
during chat, renaming and fresh-store reset. A 320 × 568 widget test navigates
home, verification, chat and settings and checks persistent demo labelling
without layout exceptions. Demo storage also checks matching message IDs
across peers and directions.

`flutter test --platform chrome test/demo_test.dart` could not load its renderer
with this installed SDK: the Windows test server returned HTTP 404 for local
CanvasKit files. This affects the SDK test runner, not `flutter run -d chrome`.
The normal tests and web compilation above passed.

An Android APK rebuild was attempted but this Windows PC has no Android SDK
configured (`No Android SDK found`). The original APK results above are prior
validation, not a fresh build on this PC. The existing Android transport,
session cryptography and encrypted-storage tests still pass. Physical phone
testing and independent security review remain outstanding.

The default web build also reports a Wasm dry-run incompatibility in the
existing flutter_secure_storage_web dependency. The Chrome preview uses
JavaScript; `--no-wasm-dry-run` skips that optional compatibility probe.
