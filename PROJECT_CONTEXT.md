# LocalChat project context

Updated: 2026-10-10. The workspace is authoritative; read README.md,
docs/SECURITY.md, docs/VALIDATION.md and the relevant code before making changes.

## Goal and scope

LocalChat was created in ChatGPT and continued in this Flutter workspace.
It enables nearby offline messaging without a router, mobile data, accounts,
backend, Firebase or cloud database. Version 0.1 is Android-first and text only.
Images and videos are planned later. Bluetooth, group chat, relaying, iOS,
background delivery and notifications are also future work.

The complete requested/suggested feature list is in `docs/FEATURE_BACKLOG.md`.
The user chose app lock first and committed it as `df3c2b3`.
Navigation was committed as `abe4dc3`, and themes as `b353956`.
The current milestone is Chats list improvements. Work on one milestone at a
time; the user will stage, commit and push it themselves after testing.

## Chats list milestone

- `Conversation` carries its latest decrypted message and unread count.
  Chats shows a two-line preview, You prefix for outgoing messages, local
  activity time/date and a badge (99+ visually, full count for accessibility).
- `LocalStore` schema version 2 adds per-message `is_read`, with existing
  version-1 history initialized as read. Message bodies remain encrypted;
  previews decrypt the last locally saved message rather than storing a
  plaintext copy. Read state is local unencrypted metadata, not a read receipt.
- Summary queries use indexed last-message and unread lookups. New message
  writes update local activity atomically; duplicate writes, peer name updates,
  read marking and delivery acknowledgements do not reorder conversations.
  Chats with messages precede empty conversations.
- `ChatScreen` uses the root ModalRoute observer to report actual visibility.
  `ChatController` gates read marking on that visibility, foreground state,
  unlocked access and readable history (verification hides active history).
  The protocol queue rechecks these gates before marking read. `main.dart`
  updates access/foreground gates immediately on locking and lifecycle changes.
- Demo storage has matching summary/read behavior, with its usual reload reset.
  Added nine storage, controller and list checks and extended existing demo and
  ciphertext-tampering coverage. See `docs/CHAT_LIST.md` for phone checks.
  Validation: all 52 tests pass, clean analysis and successful Android/browser builds.
  This milestone remains unstaged and uncommitted for the user.

## Theme milestone

- Settings → Appearance offers Light, Dark and Follow system, plus Mint, Blue,
  Purple and Amber palettes. Defaults remain Dark/Mint until the user changes them.
- `appearance_controller.dart` saves a versioned preference separately in
  secure storage on Android. Browser demo preferences stay in memory and reset
  on reload. Loading failure uses defaults with a recoverable Settings error;
  a failed save preserves the current selection and offers retry.
- `main.dart` loads appearance before displaying the app and supplies both
  Material 3 brightness themes. Preferences are independent of the lock gate.
  Theme changes preserve pushed routes, Settings edits and selected tabs.
- Incoming/outgoing chat text, bubble backgrounds and connection/demo notices
  use matching ColorScheme colors. The lock screen uses the same appearance.
- Added seven checks for persistence, storage errors, device brightness,
  navigation/lock coverage, eight-theme message contrast and enlarged text.
  Validation: all 43 tests pass, clean analysis, successful Android/browser builds.
  Phone checks are in `docs/THEMES.md`. The user committed this as `b353956`.

## Chats / Nearby navigation milestone

- `HomeScreen` is a stateful shell with Material 3 bottom navigation. Chats is
  the default tab; `chats_tab.dart` shows saved history and an active-chat Open
  action. Its empty state links to Nearby without starting discovery.
- `nearby_tab.dart` holds the profile/connection state, Go nearby, scanning,
  permissions/discovery instructions and device connection actions.
- Switching tabs preserves independent scroll positions and existing transport
  state. Returning from a chat or Settings keeps the selected tab.
- App locking removes the entire shell, including both tabs; unlocking starts
  on Chats. Chat protocol and storage remain owned by the same controller.
- Validation: clean analysis, 36 passing tests, successful browser and Android
  debug APK builds. Phone navigation checks are in `docs/NAVIGATION.md`; the
  milestone was committed by the user as `abe4dc3`.

## App lock milestone

- Optional six-digit app PIN, biometric unlock on supported Android phones,
  immediate launch/background locking, manual Lock now and PIN-authorized edits.
- `app_lock_controller.dart` stores a salted PBKDF2 verifier and persisted
  attempt/cooldown state in secure storage. Browser configuration is temporary.
- `main.dart` reads lock settings before chat initialization and replaces every
  app route while locked. Unlock returns to home; existing transport can remain.
- Android now uses FlutterFragmentActivity, AppCompat themes, USE_BIOMETRIC and
  a privacy channel for FLAG_SECURE while app lock is enabled.
- This is UI access control; existing database keys are not bound to biometrics
  or re-encrypted with the PIN. Read `docs/APP_LOCK.md` for limits and phone checks.
- Physical fingerprint, lifecycle and secure-storage checks remain required.
- Uses `local_auth` 3.0.2; minimum Flutter is now 3.38.0 / Dart 3.10.0.
- Automated suite: 33 passing tests. See `docs/VALIDATION.md` for build results.

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

The original browser demo checks covered discovery, mandatory confirmation before send,
simulated replies/delivery, fresh verification on reconnect, per-peer history,
live history deletion, rename/reset behavior and persistent demo labelling on
small screens. That milestone passed `flutter analyze`, all 23 tests, and the
JavaScript web build. A headless Chrome smoke check exercised discovery,
verification, sending, simulated delivery and replies. The separate Chrome
test runner has a CanvasKit asset-serving issue in this installed Windows SDK.
The Android SDK is now installed and the app-lock milestone built successfully.
See docs/VALIDATION.md for current results and historical limitations.

Still outstanding: physical two-phone discovery, pairing and messaging,
vendor/API compatibility, Android permission/lifecycle behavior, platform key
storage on hardware, and independent protocol/code security review. Browser
preview and automated tests do not validate these.

## Source control

Local Git history and LocalChat-history.bundle are included. GitHub account:
`yolomon9994`; repository: `LocalChat`. Before the Chats list milestone, the working tree
was clean and `main` matched the locally recorded `origin/main`. Do not stage,
commit, publish or push without a new user request; the user will commit this
milestone themselves. No open-source license has been selected.
