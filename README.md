# LocalChat

Android-first Flutter app for nearby, encrypted, one-to-one text conversations over **Wi-Fi Direct**. No server, account, router, mobile data, Firebase, or cloud database. Wi-Fi radio must be enabled.

## Version 0.1

- Advertise a display name and discover nearby LocalChat phones using Wi-Fi Direct DNS-SD.
- Connect through Android's Wi-Fi Direct pairing flow and exchange framed TCP messages.
- Signed Ed25519 identity + fresh X25519 key exchange for each connection.
- Compare an 80-bit session verification code on both phones before messaging.
- XChaCha20-Poly1305 encrypted text and acknowledgements; reject replayed/modified frames.
- Encrypted local message bodies in SQLite; identity/history keys held by secure storage.
- Delivery status, connection state, saved conversations, disconnect and history deletion.
- Separate Chats and Nearby tabs with bottom navigation; Settings in the toolbar.
- Latest-message previews, activity timestamps, persistent unread badges and
  recent-message ordering in Chats. Opening a visible conversation clears its unread count.
- Offline name/message search from the Chats toolbar; tap a message result to
  open its conversation at the highlighted message.
- Encrypted drafts for each chat, including offline editing; unfinished text
  restores after navigation and Android app restarts and stays after send failures.
- Optional six-digit app PIN, biometric unlock on supported Android phones,
  automatic locking on launch/background, and manual Lock now in Settings.
- Light, dark and follow-system themes with mint, blue, purple and amber palettes;
  choose them in Settings → Appearance. Android remembers your choices.

See [app lock setup and testing](docs/APP_LOCK.md) and the
[feature backlog](docs/FEATURE_BACKLOG.md) for planned additions.
See [Chats / Nearby navigation](docs/NAVIGATION.md) and
[theme setup and testing](docs/THEMES.md) for phone checks.
See [Chats list testing](docs/CHAT_LIST.md) for previews and unread behavior.
See [local search testing](docs/SEARCH.md) for search and message navigation.
See [saved draft testing](docs/DRAFTS.md) for persistence and send behavior.

Bluetooth, media, group chat, relaying, iOS, background delivery, retransmission and notifications are future work. Version 0.1 only operates while both apps remain open. The protocol is experimental and has not had an independent security audit. Read [SECURITY.md](docs/SECURITY.md).

## Run the project

Install Flutter stable **3.38.0 or newer / Dart 3.10.0 or newer** (the app-lock milestone uses `local_auth` 3.0.2), Android Studio with Android SDK 36 and Java 17 or newer. Enable Developer options and USB debugging on a physical Android phone (Android 7/API 24 or newer, with Wi-Fi Direct support).

```bash
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d DEVICE_ID
```

Build an installable testing APK:

```bash
flutter build apk --debug --target-platform android-arm64 --split-per-abi
```

Output: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`. This targets modern 64-bit ARM phones. For older devices, omit both `--target-platform android-arm64` and `--split-per-abi` to build a universal APK. Debug APKs are for testing; configure your own signing key before distributing a production release. Never commit signing keys.

The Android Gradle wrapper is included. Flutter writes the machine-specific `android/local.properties`, which is intentionally ignored by Git. The first development build downloads dependencies; **the installed app uses no Internet service**.

## Chrome browser preview on Windows

From PowerShell in the project directory:

```powershell
flutter pub get
flutter run -d chrome
```

Web runs automatically use **Browser Demo** mode. Open **Nearby**, tap **Go nearby**, choose
**Ava (Demo)** or **Noah (Demo)**, then tap **Codes match** to explore the chat.
Chats is the default tab and lists saved conversations and the active-chat shortcut.
The simulated friend sends a welcome message, acknowledges your messages and
replies automatically. You can disconnect, reopen history, switch demo friends,
rename your profile and delete history in Settings.
You can also try every theme in Settings → Appearance; browser choices reset on reload.

The persistent demo notice appears on every screen. Devices, peer confirmation,
messages and delivery status are simulated inside the browser tab: **no real
Wi-Fi Direct communication takes place**. History, profile name and demo
identities live only in memory and reset on reload. The preview does not use
SQLite or platform secure storage and does not test Android hardware security.
The shared controller exchanges protocol frames with an in-process simulated
peer; this does not represent secure communication with another device.

Android still selects the native Wi-Fi Direct transport, encrypted SQLite store
and platform secure storage. No demo flag is needed and Android never defaults
to demo mode. See [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) for session context.

## Try it on two phones

1. Install the same APK on both phones. Keep them near one another.
2. Turn off mobile data. Disconnect from your router, leaving Wi-Fi on. Airplane mode with Wi-Fi manually re-enabled is another test; some phones disable Wi-Fi Direct in airplane mode.
3. Open LocalChat on both phones. Choose different names in Settings, then open **Nearby** and tap **Go nearby** on each.
4. Allow **Nearby devices** on Android 13+, or Location on older versions. On Android 12 and earlier, also enable the Location system toggle.
5. Scan again if necessary. Tap the other LocalChat phone and accept Android's pairing prompt on the receiving phone.
6. Compare all five security-code groups in person. Both phones must tap **Codes match**. If the codes differ, disconnect.
7. Send text in both directions. `delivered` means the peer decrypted and stored the message, not that a person read it. `unconfirmed` means the acknowledgement was not received; the message may still have arrived.
8. Disconnect and reconnect. The code should change, identity-based history should remain, and both phones must verify again.

Wi-Fi Direct and DNS-SD behavior varies by device vendor. Emulators are not a substitute for two-device testing. See [device test checklist](docs/DEVICE_TESTING.md) for acceptance cases and troubleshooting.

## Architecture

Flutter screens → serialized chat controller → secure session + local store → transport interface → MethodChannel/EventChannel → Kotlin WifiP2pManager + TCP.

| Area | Implementation |
|---|---|
| UI and state | Flutter Material 3 + ChangeNotifier |
| Discovery | Native Wi-Fi Direct DNS-SD; only LocalChat v1 advertisements are listed |
| Connection | Native WifiP2pManager + one socket per session |
| Crypto | `cryptography`; Ed25519, X25519, HKDF-SHA256, XChaCha20-Poly1305 |
| Storage | `sqflite` + encrypted bodies; `flutter_secure_storage` for keys |
| Native bridge | Flutter method and event channels |

ChangeNotifier and sqflite keep this small first release free of code generation; `Transport` allows another radio backend later. Encrypted payloads carry a `type` field, so future media handlers can use a versioned protocol without coupling the UI to sockets. Version 1 currently rejects unsupported payload types.

## Git and GitHub

This project includes a local `main` branch and initial commit, with a clean Flutter/Android `.gitignore`. If you extracted the ZIP, its `.git` directory preserves the history. If your archive tool removes hidden directories, use the accompanying Git bundle or initialize a new repository.

Create an **empty** GitHub repository named `LocalChat` under `yolomon9994` (do not add a README, license or .gitignore). Then, from the project folder:

```bash
git remote add origin https://github.com/yolomon9994/LocalChat.git
git push -u origin main
```

GitHub may ask you to sign in using its credential manager. Never put an access token in source files or commit it. If `origin` already exists, inspect `git remote -v` and use `git remote set-url origin ...` for the intended repository.

The included GitHub Actions workflow runs analysis and tests, builds a testing APK and uploads it as a workflow artifact. Future changes can use:

```bash
git add .
git commit -m "feat: add encrypted image transfer"
git push
```

## References

- [Android Wi-Fi Direct](https://developer.android.com/develop/connectivity/wifi/wifi-direct)
- [Wi-Fi Direct service discovery](https://developer.android.com/develop/connectivity/wifi/nsd-wifi-direct)
- [Dart cryptography APIs](https://pub.dev/documentation/cryptography/latest/)
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)

No open-source license has been selected for this project yet.
