# Validation for v0.1.0

## Conversation management milestone — 2026-10-11

Checked with Flutter 3.38.7 / Dart 3.10.7 on the same Windows/Android SDK setup.

- `flutter analyze`: no issues.
- `flutter test`: all 82 tests passed (73 existing + 9 new checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, with the same
  optional Cupertino font warning recorded below.

Real SQLite tests cover flag persistence, pin ordering without changing activity,
preservation through rename/duplicate/delivery/read updates, incoming activity
remaining archived, archive flags in search results, targeted message/draft
deletion, identity/other-peer retention, and schema-3 upgrades. Existing schema-1
and schema-2 fixtures now model their old peer table accurately and upgrade to
schema 4 with preserved encrypted history, drafts and unread state.

Draft checks verify that deleting one peer invalidates its queued edits while
another peer's draft persists. Encrypted linked-peer checks verify archival
through a live received message, active-peer disconnect on deletion, removal
of local data and preservation of the other phone's history. Failure checks
cover retained draft/state, generic errors, retry, deleted-result invalidation
and rejecting stale opens.

Widget tests cover pin/unpin, archive/unarchive, searching archived history,
draft restoration, empty archive states, delete cancellation/confirmation,
lock removal of archive routes/dialogs, and long names/unread/menu/error flows
at 320 × 568 with 1.5× system text. The error banner is constrained and scrollable
so it cannot consume the list; the temporary snackbar is allowed to expire
before the test uses the list again. The existing wrong-peer send and draft
error fixtures now seed their conversations before opening saved history.

Pin/archive flags are local unencrypted metadata; message/draft encryption and
wire payloads are unchanged. No new dependency or native Android code change.
Deleting active history disconnects first; a failed storage deletion can leave
the session disconnected while retaining data. Physical Android persistence,
upgrades and two-phone behavior remain user testing; follow
[the conversation management checklist](CONVERSATION_MANAGEMENT.md).

## Saved drafts milestone — 2026-10-10

Checked with Flutter 3.38.7 / Dart 3.10.7 on the same Windows/Android SDK setup.

- `flutter analyze`: no issues.
- `flutter test`: all 73 tests passed (61 existing + 12 new checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, with the same
  optional Cupertino font warning recorded below.

Real SQLite checks cover encrypted exact-text draft restoration after reopening,
fresh nonces, peer-bound authentication, tampering, empty draft deletion,
unchanged activity/unread state, search exclusion, history deletion and upgrades
from schema 1 and 2 to 3. Unicode drafts can remain saved even when their UTF-8
bytes exceed the send limit and need editing before sending.

Draft-controller checks cover per-peer and per-revision isolation, failed
load/save/delete, retry, pending writes around history deletion, restoration
in a new controller and completion after disposal. Encrypted linked-peer tests
verify successful send cleanup, preservation after write/validation failures,
newer edits during a send and wrong-peer prevention after a queued selection
change. The pending-send fixture drains its acknowledgement before teardown.

Widget checks cover offline editing with Send disabled, exact restoration on
Back and peer switches, locking/unlocking, clearing open composers, deselecting
deleted offline chats, errors/retry with a 320 × 568 enlarged-text keyboard
layout, and navigating away during a successful send. Existing lock, theme,
search, unread, navigation, demo and protocol regressions continue to pass.

No new dependencies, wire payloads or native Android changes were introduced.
Draft text uses the existing history key with domain-separated AAD. Draft
persistence is asynchronous and failed saves are visible/retryable; abrupt
termination before the latest write completes can lose that edit. Browser
drafts reset on reload. Physical Android restart/upgrade/lifecycle checks remain
user testing; follow [the draft checklist](DRAFTS.md) before committing.

## Local search milestone — 2026-10-10

Checked with Flutter 3.38.7 / Dart 3.10.7 on the same Windows/Android SDK setup.

- `flutter analyze`: no issues.
- `flutter test`: all 61 tests passed (52 existing + 9 search checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, with the same
  optional Cupertino font warning recorded below.

Real SQLite checks cover literal/case/Unicode search, peer/direction scoping,
unchanged unread state, history deletion, results across multiple ciphertext
batches, newest-match limits and cancellation. The existing ciphertext-tamper
test now also confirms that search rejects modified stored message bodies.

Search-controller checks cover obsolete completion/errors, clear/dispose/retry
and history invalidation. An encrypted in-memory peer exchange verifies that a
new incoming message refreshes results without being marked read by search.
Widget checks open name matches, preserve the query on Back, open an older
message among 180 variable-height messages with direction-specific identity,
scroll both sides of the match and return to latest. They also exercise deleted
targets, private-result removal when locked, fresh search after unlocking,
Unicode snippets and large text/long queries with a phone-sized keyboard layout.

Search stores no plaintext index or query log and introduces no schema change
or new dependency. It scans/decrypts batches, so large histories take longer;
the UI limits message matches to the newest 100 and offers query refinement.
Protocol, native Android implementation and app-lock authentication behavior
are unchanged. Physical phone layout/lifecycle checks remain user testing;
follow [the search checklist](SEARCH.md) before committing.

## Chats list milestone — 2026-10-10

Checked with Flutter 3.38.7 / Dart 3.10.7 on the same Windows/Android SDK setup.

- `flutter analyze`: no issues.
- `flutter test`: all 52 tests passed (43 existing + 9 new checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, with the same
  optional Cupertino font warning recorded below.

Real SQLite tests cover a version-1 upgrade with preserved encrypted history
and identity, old messages initialized as read, persistent unread/read state,
duplicate handling, previews and message-only ordering. The ciphertext-tamper
check also verifies that summaries reject altered message bodies.

Controller checks exchange encrypted frames through an in-memory transport
and verify that selection alone does not clear unread counts, visible incoming
messages remain read, lock/foreground gates preserve unread messages, queued
reads recheck access, verification hides history and viewing another peer does
not clear the active peer's unread count. Widget checks cover route opening/back,
dialogs, backgrounding with lock disabled, locking/unlocking, badge semantics,
date labels and long previews at 320 × 568 with 1.5× text. Existing demo coverage
now also checks unread peer/direction scoping and deduplication.

The existing lock privacy test now seeds its private message in demo storage
before opening the route, so the new read refresh can load actual saved history.
Its startup withholding, route removal and locked-content assertions remain.

Secure storage, transport and lifecycle checks use doubles; physical Android
upgrade/persistence and two-phone receipt checks remain user testing. Follow
[the Chats list checklist](CHAT_LIST.md) before committing. No new dependencies,
wire protocol or native Android implementation changes were introduced.

## Theme milestone — 2026-10-10

Checked with Flutter 3.38.7 / Dart 3.10.7 on the same Windows/Android SDK setup.

- `flutter analyze`: no issues.
- `flutter test`: all 43 tests passed (36 existing + 7 theme checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, with the same
  optional Cupertino font warning recorded below.

Theme checks cover saved mode/palette restoration, malformed/unreadable
preferences, failed-save recovery, system brightness and fixed-mode overrides.
Widget checks change appearance through Settings and retain the current route,
unsaved name edit and selected tab, then check themed locking/unlocking.
All eight light/dark palette combinations meet 4.5:1 text contrast for actual
incoming/outgoing bubbles and for connection/demo notice color pairs. Controls
also fit a 320 × 568 screen at 1.5× text size without layout exceptions.

Tests use memory preference storage and platform-brightness test values.
Real Android persistence, system-theme changes and visual checks remain phone
testing; follow [the theme checklist](THEMES.md) before committing. No new
dependencies, protocol, chat-storage or native Android changes were introduced.

## Chats / Nearby navigation milestone — 2026-10-10

Checked with Flutter 3.38.7 / Dart 3.10.7 on the same Windows/Android SDK setup.

- `flutter analyze`: no issues.
- `flutter test`: all 36 tests passed (33 existing + 3 navigation checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, with the same
  optional Cupertino font warning recorded below.

Navigation checks cover the empty Chats shortcut without starting discovery,
Settings from either tab, selected-tab retention, independent scroll positions,
inactive-tab accessibility, app locking from Nearby and returning to Chats.
The existing 320 × 568 demo screen test now sends a message, switches tabs,
reopens the connected conversation and active-chat shortcut, disconnects and
reopens saved history, and checks the persistent Browser Demo notice.

No protocol, transport, storage or native Android implementation changed in
this milestone. Automated discovery/chat checks still use the simulated peer;
physical phone navigation, pairing and lifecycle checks remain user testing.
Follow [the navigation checklist](NAVIGATION.md) before committing.

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
