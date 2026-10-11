# LocalChat project context

Updated: 2026-10-11. The workspace is authoritative; read README.md,
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
Chats list improvements were committed as `c233159`, and local search as
`a2c7aa3`; drafts were committed as `9e90550`, and conversation management as
`8f55377`; encrypted backups/phone migration were committed as `63eff9f`.
The current milestone is offline outbox and message retry.
Work on one milestone at a
time; the user will stage, commit and push it themselves after testing.

## Offline outbox and message retry milestone

- Saved chats accept queued text offline; fresh verification on both phones
  enables automatic draining only for that connected identity, including archived
  chats and while another chat is selected. No automatic reconnect/background mode.
- Schema 6 adds `message_outbox(peer,outgoing,status)`. Local acceptance saves an
  encrypted queued message and removes its captured draft in one transaction.
  DraftController revision/generation guards preserve newer edits and deletions.
- Durable queued→sending transition precedes transport. At most four attempts
  await encrypted ACK, with a 30-second timeout. Disconnect/restart marks attempts
  unconfirmed and retains unsent queued records. New attempts require unlocked,
  foreground access; a gate change during encryption discards the session to avoid
  sequence gaps. In-flight writes/receiving/ACKs retain the existing lock model.
- Retry is explicit and retains ID/text/timestamp. Duplicate incoming records
  must match body/timestamp before ACK; identical records retain read state/activity.
  Only IDs attempted in the current verified session can be ACKed; late ACKs count.
  Dedupe requires retained receiver history, so this is not exactly-once delivery.
- UI shows queued counts, Cancel queued and confirmed Retry, plus Resume outbox
  after storage failures. Unconfirmed messages never resend automatically.
- Backups accept queued state, but newly imported queued/sending become unconfirmed
  so imports cannot silently transmit. Older builds reject queued backup records.
- See `docs/OUTBOX.md` and `docs/VALIDATION.md` for checks/results. Changes remain
  uncommitted for the user; physical phone tests remain pending.
  All 118 tests pass, final targeted checks pass, analysis is clean and fresh
  Android/browser builds succeed.

## Encrypted backups and phone migration milestone

- Settings → Chat backups exports/imports password-protected `.lcbackup` files.
  Includes messages, read/delivery state, drafts, pin/archive choices and private
  identity seed. Native SAF streams only encrypted bytes, bounds input size and
  requests no broad storage permission. Browser uses `package:web` file APIs.
- `core/chat_backup.dart` validates version-1 JSON before merging, verifies the
  seed/public identity relationship, bounds records and references, and uses
  PBKDF2-HMAC-SHA256 (600k, 256-bit) plus XChaCha20-Poly1305. Fresh 16-byte salt,
  24-byte nonce; authenticated magic/version/salt. Limit 20 MiB + 65-byte envelope.
- Preview shows additions, duplicates/conflicts and retained drafts. The final
  transaction recalculates counts. Existing names/flags/messages/state/nonempty
  drafts win. Dedupe keys include peer/id/direction. `sending` and `queued` import as
  `unconfirmed`; importing neither sends nor acknowledges. Bodies are encrypted
  again with the destination history key; settings/display name stay local.
- Default history-only import retains identity. User explicitly chose support
  for transferring identity to an empty phone too. That checkbox requires no
  chats/messages/drafts, stops transport and tells the user to retire the old
  phone. Fresh verification is still required on reconnect.
- Schema 5 adds `backup_receipt(id)` only. Vault `identity_import_pending_v1`
  records old/new seeds and operation ID before a migration transaction; a
  receipt commits with the merge. Recovery chooses new seed when committed,
  old seed otherwise. A failed final vault write blocks controller messaging
  until restart recovery; cleanup removes the vault journal before the receipt.
- Backup operations use the protocol queue and draft queue. Pending saves settle
  before snapshots. Import refreshes draft cache without overwriting newer edits,
  plus conversation/historyRevision state for search. Draft errors block backups.
- `BackupScreen` drops password fields/decrypted preview on background/disposal.
  Only selected ciphertext is retained in ChatController across system-picker
  locking; after unlock return to backups and enter password again. Import
  access tokens reject confirmations from an earlier unlock. A confirmed atomic
  import can finish while hidden. Demo/native archives cannot be mixed.
- Tests include crypto tampering/password/KDF, payload bounds, merges, rollback,
  journal recovery/vault failure, schema upgrades, concurrent draft edits, screen
  flows, explicit migration, native channel, phone text size and lock/picker flow.
  See `docs/BACKUPS.md` for hardware checks and `docs/VALIDATION.md` for results.
  All 99 tests pass, static analysis is clean and fresh Android/browser builds
  succeed. User committed this as `63eff9f`; hardware checks are pending.

## Conversation management milestone

- Chat rows have a menu for Pin/Unpin, Archive/Unarchive and confirmed Delete.
  Pinned chats precede others; activity order applies within each group. Pinning
  does not change message timestamps, draft text or unread counts.
- `LocalStore` schema 4 adds unencrypted `pinned`/`archived` flags on peers,
  defaulting to false for existing history. Native and demo savePeer/saveMessage
  preserve flags. Schema 1/2/3 upgrades retain messages, drafts, identity and
  read state. Browser choices stay in memory and reset on reload.
- `ChatsTab` filters the primary/archived lists, with separate scroll keys.
  The main list links to `ArchivedChatsScreen` and shows its chat/unread totals.
  Archived chats stay archived on incoming messages and remain searchable;
  name/message results label their archive state. Opening reads normally but
  does not unarchive. Unarchive preserves its existing pin choice.
- `ChatController` serializes management actions, reports generic failures and
  increments historyRevision for search refresh. viewHistory rejects a deleted
  conversation instead of selecting a stale search/list result.
- Per-chat deletion disconnects the target if it is the active session, then
  transactionally deletes its messages, draft and peer metadata. Other peers,
  identity, settings and the other person's history remain. A failed deletion
  retains saved data; a prior disconnect may already have happened.
- `DraftController` now tracks both global and per-peer deletion generations.
  Targeted deletion clears only that peer's cache and invalidates its queued
  writes; another peer's drafts keep saving. The selected deleted chat clears.
- Menu state stays with keyed chat cards when pinning changes order. Archive
  routes and deletion dialogs use the existing lock-covered navigator. Error
  banners have a scrollable height limit so large text leaves room for the list.
- Phone checks are in `docs/CONVERSATION_MANAGEMENT.md`. Committed as `8f55377`;
  validation results are in `docs/VALIDATION.md`.
  All 82 tests pass, static analysis is clean and Android/browser builds succeed.

## Saved drafts milestone

- Every selected conversation has its own composer draft. Offline history
  allows editing and queuing; transmission remains gated on a verified connection. Drafts
  preserve whitespace, newlines and Unicode exactly; sending trims as before.
- `LocalStore` schema 3 adds `drafts(peer, body)`. Draft text is encrypted with
  the existing history key using XChaCha20-Poly1305 and domain-separated AAD
  `JSON(["LocalChat/draft/1", peer])`. Empty drafts delete their record. Version
  1/2 upgrades preserve messages, identity and read state. Drafts are excluded
  from search, previews, activity sorting and unread state.
- `draft_controller.dart` belongs to `ChatController`, rather than a route.
  It loads per peer and serializes/coalesces writes outside the protocol queue.
  Edits update memory immediately and enqueue persistence without a debounce.
  Storage failures keep edits in memory with generic retry notices; a failed
  load disables editing until retried so saved text is not overwritten.
- `sendText` returns a local-acceptance boolean and captures the selected peer
  and matching draft revision. The outbox milestone now clears that revision
  atomically when saving a queued message. Newer edits, other peers and failed
  local acceptance keep their drafts. Local acceptance does not mean delivered;
  encrypted acknowledgements still decide delivery status.
- History deletion runs on the draft write queue and transactionally clears
  messages, drafts and peers. A generation invalidates queued older edits;
  cached drafts and open composers reset only after successful deletion.
  Deleted offline conversations are deselected; the active session can continue.
- Locking disposes the composer route; reopening after unlocking restores its
  saved text. Plaintext can remain in controller memory under the existing app
  lock model. Browser drafts use `DemoStore` memory and reset with the tab.
- All 73 tests pass, static analysis is clean and Android/browser builds succeed;
  results are in `docs/VALIDATION.md`. Phone testing is in `docs/DRAFTS.md`.
  The user committed this as `9e90550`.

## Local search milestone

- Chats has a toolbar Search action. `chat_search_screen.dart` displays
  separate name and message matches, context snippets, empty/error/retry states
  and a clear action. Matching is a case-insensitive literal substring;
  surrounding query whitespace is ignored. Browser behavior matches Android.
- `LocalStore.search` decrypts ciphertext batches in memory, with cancellation
  checks and event-loop yields. It returns the newest 100 message matches and
  a refinement notice if more exist. No plaintext index, schema change or new
  dependency is introduced. Larger histories require scanning more ciphertext.
- `chat_search_controller.dart` debounces typing and rejects obsolete results
  and errors. A `ChatController.historyRevision` signal refreshes search on new
  messages, verified peer-name updates and history deletion. Search runs outside
  the serialized protocol queue and does not mark messages read.
- Selecting a result reloads history; `viewHistory` now returns success and
  updates selection only after history/summary loads succeed. Failed opens stay
  on the current screen. A message result passes full peer/id/direction identity.
- `ChatScreen` anchors the matching message with two lazy slivers, highlights
  its bubble and offers Jump to latest. Older/newer history remains reachable
  with variable message heights. Missing/deleted targets show a notice.
- Locking disposes the search navigator route, query and results and cancels
  pending work. Returning from a result normally preserves the search query.
- Added nine search checks and extended ciphertext-authentication coverage.
  Validation: all 61 tests pass, clean analysis and successful Android/browser builds.
  Phone checks are in `docs/SEARCH.md`. The user committed this as `a2c7aa3`.

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
  The user committed this milestone as `c233159`.

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
- Both apps must remain open for transmission. Offline queues wait for a freshly
  verified connection; unconfirmed attempts require explicit Retry.
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
`yolomon9994`; repository: `LocalChat`. Before the outbox milestone, the working tree
was clean and `main` matched the locally recorded `origin/main`. Do not stage,
commit, publish or push without a new user request; the user will commit this
milestone themselves. No open-source license has been selected.
