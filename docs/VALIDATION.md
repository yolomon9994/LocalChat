# Validation for v0.1.0

## Direct-chat files — final checks 2026-10-12

- Full `flutter test --reporter expanded`: **228 passed**, exit 0 (203 existing
  + 25 file checks). Latest output: `.dart_tool/file-milestone-tests.log`, local
  and ignored by Git. Includes the final filename boundary fix.
- Final `flutter analyze`: no issues, exit 0.
- New checks: 14 controller/protocol/picker/save tests, two file backup tests,
  four SQLite encryption/migration/rollback tests, two widgets and three
  filename/metadata/native-channel contract tests.
- Checks cover real encrypted multi-chunk transfers alongside delivered text,
  timeout/missing receipts, original-ID retry/dedupe, lock/background/cancel,
  receiver persistence failures, forged digest/chunk order, bounds, capability
  compatibility, sealed picker return and late-result deletion. Offline save
  checks include lock gates, cancellation and errors. SQLite preserves existing
  text/images/identity across schema 8 to 9 and rolls back file write/import failures.
  Widgets cover 320 × 568 at 1.8× text, review/discard and PIN removing export dialogs.
- Review found and fixed filename truncation leaving a trailing dot/space.
  A new test checks canonical shortened names, including Unicode.
- Final `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  passed, exit 0. APK: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
  Includes the native file picker/save bridge and final filename fix.
- Final `flutter build web --no-wasm-dry-run`: passed, exit 0. Existing optional
  Cupertino font warning remains; the app uses Material icons.
- Final code/documentation review and `git -c core.safecrlf=false diff --check`: clean.
- Physical provider/Wi-Fi Direct/lifecycle/export checks remain pending;
  see [FILE_SHARING.md](FILE_SHARING.md).
- Changes are saved locally, unstaged and uncommitted; the user handles Git.

## Direct-chat image sharing — 2026-10-12

- Full `flutter test --reporter expanded`: **203 passed** (185 existing + 18
  image checks), exit 0. Final run includes the acknowledgement and layout fixes.
- New checks: 11 controller/protocol/picker-lifecycle tests, two image backups,
  two widgets, two SQLite encryption/migration tests and one native-picker contract.
- Final `flutter analyze`: no issues.
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful final APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
  Includes the native picker and final acknowledgement/layout fixes.
- `flutter build web --no-wasm-dry-run`: successful browser build; the existing
  optional Cupertino font warning remains (the UI uses Material icons).
- `git -c core.safecrlf=false diff --check`: clean.

Checks exercise real encrypted multi-chunk transfers alongside delivered text,
per-stage timeout, missing receipts, original-ID retries/dedupe, locked rejection,
sender cancellation, persistence failures without delivery, invalid chunk order
and content hash, byte/pixel bounds, older-peer text compatibility, picker return
while locked and late selection after deletion. Image backups round-trip encrypted
bytes, validate hashes/version gates and re-encrypt safely. SQLite checks include
atomic duplicate handling, encrypted bytes/metadata, reopen, deletion, backup restore
and schema-7 upgrade without losing text. UI checks cover 320 × 568 at 1.8× text,
preview/discard and saved-image zoom routes removed by PIN lock.

Regression testing caught a misplaced text-ACK branch and narrowed offline
composer layout; both were fixed. The v1 fixture omits the new kind column, and
image UI fixtures use real scheduling for crypto and dialog completion.

Physical picker/providers, Wi-Fi Direct throughput, cancellation/lock timing,
orientation and Android lifecycle behavior remain pending. Follow
[IMAGE_SHARING.md](IMAGE_SHARING.md). Changes remain unstaged and uncommitted.

## Hosted nearby group text chats — final checks 2026-10-12

- Full `flutter test` on 2026-10-11: **185 passed** (162 existing + 23 group
  checks), exit 0.
- Group checks: 13 protocol/controller, four backup, three widget, two SQLite
  encryption/migration and one native-channel contract test.
- Final `flutter analyze` on 2026-10-12: no issues.
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful final APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`,
  including the latest native channel-epoch guard and Dart/UI changes.
- `flutter build web --no-wasm-dry-run`: successful browser build; existing
  optional Cupertino font warning remains (the UI uses Material icons).
- `git -c core.safecrlf=false diff --check`: clean.
- Changes remain unstaged and uncommitted; the user handles Git after phone tests.

Tests cover both confirmations and code equality, real encrypted three-phone
relay, signed authors, impersonation/modification/session replay rejection,
membership races/removal/cap, late joins without old history, duplicate IDs,
locked admission/origination, receiving/unread gates, individual missing receipts,
host loss/rehosting, persistence failure before relay/receipt, stop despite storage
failure, validated encrypted backups/merges/identity migration, schema upgrades,
encrypted group records, small-screen/enlarged-text controls, confirmed deletion
and notification taps waiting for PIN. Widget fixtures explicitly use real async
scheduling where cryptography/controller queues require it.

Physical discovery, pairing, guest capacity, background behavior and battery use
are unvalidated. Follow [GROUP_CHATS.md](GROUP_CHATS.md) on three Android phones.

## Optional background connection protection — 2026-10-11

Checked with Flutter 3.38.7 / Dart 3.10.7, Java 21 and Android SDK 36 on Windows.

- Targeted background tests: all **15 passed** (12 service/controller/channel,
  three widget checks).
- `flutter test`: all **162 passed** (147 existing + 15 background checks).
- `flutter analyze`: no issues.
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build; same optional
  Cupertino font warning as previous builds (the UI uses Material icons).
- `git -c core.safecrlf=false diff --check`: clean.

Checks cover opt-in defaults/stored preference without automatic activation,
denied notification access, generation/revision startup cancellation, an already
authorized start finishing after background/lock, Stop invalidating a pending
start, recoverable startup failure, restart with no restored session, both fresh
confirmations plus foreground unlock, locked background persistence/ACK/unread
and generic alerts, foreground-only queued draining with preserved drafts, native
Stop preserving records and disabling mode, loss guidance and the Android channel
generation/settings contract independently of the Messages channel. Linked
transports exchange real encrypted frames; native providers are test doubles.

Widget checks cover native-sized 320 × 568 Settings at 1.8× text, reachable
battery/channel shortcuts after denial and status refresh, and app lock removing
settings while protection remains active. Initial UI fixtures tapped before lazy
scroll layout settled; the corrected fixtures explicitly settle/ensure visibility.
The native-sized fixture supplies memory lock/appearance providers and no browser
banner, matching the Android layout; it does not validate hardware APIs.

Native compilation checks the service/type manifest and Kotlin bridge. There is
no new package, database schema, backup format or wire payload. Message-alert
cancellation is scoped so it cannot remove the ongoing service notification.
Physical foreground-service promotion, ongoing Stop, wake locks, permission
revocation, screen-off/Doze delivery, battery behavior and vendor compatibility
remain pending. Follow [BACKGROUND_CONNECTION.md](BACKGROUND_CONNECTION.md).
Changes are intentionally uncommitted; the user handles Git.

## Local message notifications and privacy — 2026-10-11

Checked with Flutter 3.38.7 / Dart 3.10.7, Java 21 and Android SDK 36 on Windows.

- `flutter test`: all **147 tests passed** (132 existing + 15 notification checks).
- Final targeted notification/widget tests: all **15 passed** after privacy/setup fixes.
- `flutter analyze`: no issues.
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build; same optional
  Cupertino font warning as previous builds (the UI uses Material icons).
- `git -c core.safecrlf=false diff --check`: clean.

Ten service/controller/channel checks cover opt-in defaults, generic payloads
without sender/body, preview redaction, blocked permission and later grant,
visible-chat suppression, independent peer alerts, notification-manager failure
without losing persistence/ACKs, lost-ACK retry dedupe with real encrypted frames,
read/lock/background unread behavior, history deletion, and cold/warm native
channel tap delivery. The existing SQLite test now checks the new committed-row
result for initial and duplicate insertion. Schema/encryption tests still pass.

Five widget checks cover cold-start taps waiting for PIN before opening the
correct history, latest warm tap and route replacement/back behavior, lock during
an async history load, safe deleted-history taps and Settings switches in the
browser demo. The first Settings test needed scrolling to build the lazy list
section; the corrected test passes. Android APIs/permission UI use doubles here;
no physical notification, vendor, channel or OS-history test is claimed.

No new dependencies, database schema or protocol changes. Android adds only
POST_NOTIFICATIONS and a native notification bridge/icon. Hardware checks are in
[NOTIFICATIONS.md](NOTIFICATIONS.md). User committed this as `9bb6c60`.
Automatic Flutter deep-link handling is disabled in the Activity metadata so
peer-specific notification intents use the lock-aware route instead of being
interpreted as named Flutter routes. See [Flutter's handler configuration](https://docs.flutter.dev/cookbook/navigation/set-up-app-links).

## Connection troubleshooting and manual reconnect — 2026-10-11

Checked with Flutter 3.38.7 / Dart 3.10.7, Java 21 and Android SDK 36 on Windows.

- `flutter analyze`: no issues.
- `flutter test`: all **132 tests passed** (118 existing + 14 recovery checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build; same optional
  Cupertino font warning as prior builds. This does not test Android settings.
- `git -c core.safecrlf=false diff --check`: clean.

Ten controller/channel checks cover Wi-Fi/support/Location prerequisites while
preserving drafts, initial permission request and post-grant status refresh,
later permission denial and settings action, typed busy/stale/discovery failures,
generic feedback without raw native details, Wi-Fi/service reset and retry,
duplicate taps and lock during access checks, failed status/settings queries,
cancelled connection deadlines, same-address Reconnect requiring fresh codes
and both confirmations before queued text drains, disappearance requiring a
scan, foreground permission revocation closing verification without deleting
drafts/history, and the three Android settings channel destinations. Linked
transports exchange real encrypted frames; native status/settings calls use
channel doubles, not a physical settings provider.

Four widget checks cover settings recovery and completed-empty scans, failed
connect staying in Nearby, successful reconnect opening the chat, 320 × 568
layout with 1.8× text and reachable wrapped recovery actions, and queue help
being hidden by locking without losing queued history. Native-looking UI
fixtures inject memory lock/appearance providers; they do not claim Keystore
validation. Browser demo regressions continue to pass.

Physical Wi-Fi Direct, permission prompts/revocation, Android settings return,
pairing cancellation and vendor behavior remain pending. Follow
[CONNECTION_RECOVERY.md](CONNECTION_RECOVERY.md). The user committed this
milestone as `c7d4d6e` and handles staging, committing and pushing.

## Offline outbox and message retry — 2026-10-11

Checked with Flutter 3.38.7 / Dart 3.10.7, Java 21 and Android SDK 36 on Windows.

- `flutter analyze`: no issues.
- `flutter test`: all **118 tests passed** (99 existing + 19 outbox checks).
- After adding the final post-encryption access check, all **24 targeted tests**
  in `outbox_test.dart`, `outbox_screen_test.dart` and `chat_controller_test.dart`
  passed again; final analysis remains clean.
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  successful updated APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, with the same
  optional Cupertino font warning as earlier milestones. No browser runtime
  or real radio check is claimed by this compilation.
- `git -c core.safecrlf=false diff --check`: clean.

Twelve protocol/controller checks cover known-identity offline acceptance,
validation/storage failures retaining drafts, both-phone verification, queue
order and archived/unread state, lost ACK and explicit same-ID Retry, late ACK,
foreground/lock gates including a lock during the durable status write,
storage pause/resume, cancellation/history deletion, identity-targeted draining
while viewing another conversation, four-attempt bounds/disconnect recovery,
and conflicting incoming IDs failing without a false ACK. Linked transports
exchange actual encrypted protocol frames; they do not test Wi-Fi Direct radio.

Four additional real SQLite checks cover encrypted queued bodies, atomic draft
cleanup, rollback on failed cleanup, schema-5-to-6 upgrade/restart preservation,
FIFO insertion ordering, conditional peer/direction/status updates, cancellation
that cannot undo delivery, and queued backup export/import as unconfirmed.
Secure-storage doubles do not establish Android Keystore behavior.

Three widget checks cover offline submission/counts, confirmed/declined Cancel,
Retry preserving another draft, lock removing the Retry dialog, and a 320 × 568
layout with enlarged text, keyboard insets, long message text and storage feedback.
The first targeted run exposed a keyboard overflow from an added helper footer;
that footer was removed and the layout checks now pass. The existing demo
duplicate fixture was corrected to use identical text/timestamp; conflicting
records now deliberately fail, matching native behavior.

Physical two-phone delivery, restart/lifecycle, vendor behavior and enlarged
phone text remain pending. Follow [OUTBOX.md](OUTBOX.md). The user committed
the outbox milestone as `605962e`.

## Encrypted backups and phone migration — 2026-10-11

Checked with Flutter 3.38.7 / Dart 3.10.7, Java 21 and Android SDK 36 on Windows.

- `flutter pub get`: succeeded; existing `web` 1.1.1 is now a direct dependency.
- `flutter analyze`: no issues.
- `flutter test`: all **99 tests passed** (82 existing + 17 backup checks).
- `flutter build apk --debug --target-platform android-arm64 --split-per-abi`:
  fresh successful APK at `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- `flutter build web --no-wasm-dry-run`: successful browser build, including the
  browser file APIs; same optional Cupertino font warning as prior builds.
- `git -c core.safecrlf=false diff --check`: clean.

Six codec/draft checks cover password round-trip, fresh salts/nonces, wrong
password and salt/nonce/tag/body tampering, real production PBKDF2 encryption
and decryption, early size/header/version/password rejection, duplicate/orphan/
malformed/oversized records and identity consistency, conflict retention,
explicit demo migration, native/demo separation, and draft edits/deletions
queued during an import. Most UI/state checks use a fast test KDF; the production
600,000-iteration KDF is exercised separately without that test double.

Six additional real SQLite checks cover peer/id/direction dedupe, existing
message/name/flags/status/draft preservation, unread state, fresh destination
ciphertext and restart persistence, whole-merge rollback (also with identity
transfer), invalid data rejection, empty-only migration and retained history
key, committed/uncommitted crash-journal recovery, schema-4-to-5 preservation,
and a failed final vault write recovered by reopening. Earlier schema-1/2/3
upgrade fixtures now finish at schema 5. Vault tests use secure-storage doubles,
and do not claim Android Keystore hardware validation.

Five screen/controller/channel checks cover export confirmation, wrong-password
feedback, preview/cancel/import, duplicate repeat imports, identity retention,
disabled transfer on populated destinations, explicit transfer at 320 × 568
with 1.8× phone text, picker completion after lock disposes its route, empty
password after unlock, lock hiding preview, rejection of old unlock tokens,
draft cache/search revision/unread refresh, encrypted platform-channel payloads,
picker cancellation and file size limits. Screen checks use memory transport,
storage and file-picker doubles. The browser file implementation is compiled;
an actual browser download/upload was not exercised in this milestone.

Physical Android file providers, picker lifecycle, secure-storage migration,
offline phone-to-phone file transfer and reconnection under the transferred
identity remain pending. Follow [BACKUPS.md](BACKUPS.md)'s phone checklist.
No hardware test or independent security audit is claimed. The user committed
the backup milestone as `63eff9f`.

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
