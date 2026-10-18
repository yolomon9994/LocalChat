# Android hardware test checklist

Prepared: 2026-10-18. App source: `0293b61`, version `0.1.0+1`.
All boxes start unchecked: automated tests do not establish real-device results.
Record Pass, Fail or Blocked for each case; tick only after observing a pass.

Testing APK built and signature-checked on 2026-10-18:

```text
build/hardware-testing/LocalChat-0.1.0-0293b61-universal-debug.apk
Version: 0.1.0 (1), package: dev.localchat.app
Minimum Android: 7.0 / API 24; target API: 36
Architectures: armeabi-v7a, arm64-v8a, x86_64
Size: 189,649,067 bytes (180.9 MiB)
SHA-256: 50fd7a2cdedf130438a59e317aa7a3aac3d30381f6a6c122f734917a1e352dc4
```

Build outputs are ignored by Git. Keep this named APK for this round so all
phones use the same artifact; a later build can overwrite `app-debug.apk`.

## Install and prepare

- Use **two physical phones** for direct chats and **three** for hosted groups.
  Android 7/API 24 or newer and Wi-Fi Direct support are required. Try different
  manufacturers and Android versions where available; record missing coverage.
- Install the same universal **debug testing APK** on every phone. It contains
  ARM 32-bit, ARM 64-bit and x86-64 builds; it is not a production release.
- Copy the APK by USB or another file-transfer method, open it on the phone, and
  allow that file manager to install apps if Android asks. Launch LocalChat.
  USB debugging is unnecessary for installation from the phone's file manager.
- Existing compatible debug installs can be updated in place. If Android reports
  a signing conflict, export a backup before considering removal: uninstalling
  or clearing app storage deletes local history, identity and lock settings.
- Start with disposable conversations, images and files. Export before destructive
  tests. Identity migration is a separate test; never operate both phones with
  the same transferred messaging identity.
- Turn **mobile data off**, disconnect from any router, and keep **Wi-Fi on**.
  Use locally saved files. This checks the intended offline Wi-Fi Direct path.
  Start with both apps unlocked and visible; test background behavior separately.
- Record phone labels A/B/C, model, Android version, APK name and test date.
  On a first run, work through sections 1-4 before testing optional features.

## 1. Installation, permissions and discovery (two phones)

- [ ] **First launch/relaunch:** opens without crashing on each device. If updating,
  saved identity, conversations and preferences remain available.
- [ ] **Offline discovery:** use Nearby > Go nearby on both phones, scan and find
  the intended device without router access or mobile data. Names are readable.
- [ ] **Permissions:** test denial, grant and later revocation. Android 13+ uses
  Nearby devices; Android 7-12 needs Location permission and Location enabled.
  Errors explain recovery, settings shortcuts work, and returning rechecks access.
- [ ] **Wi-Fi/empty results:** disable Wi-Fi, scan with no peer available, and let
  a scan finish. Guidance and Scan again remain usable; the app does not hang.
- [ ] **Pairing and stale devices:** connect and accept Android's invitation;
  repeat after the other phone leaves range. A stale device fails safely and a
  new scan/manual connection recovers. Swap which phone initiates.

Detailed recovery cases: [DEVICE_TESTING.md](DEVICE_TESTING.md) and
[CONNECTION_RECOVERY.md](CONNECTION_RECOVERY.md).

## 2. Verification and direct messaging (two phones)

- [ ] **Fresh code:** both phones show the same five code groups. Confirm on only
  one: messaging remains gated. Confirm on both: exchange text in both directions.
  Disconnect/reconnect: a fresh comparison and both confirmations are required.
- [ ] **QR camera:** scan the intended peer's current QR with mobile data off,
  including first use. Confirm both phones explicitly. Wrong/self/old codes do
  not verify. Camera denial permits manual-code comparison; leaving or locking
  stops scanning. See [QR_VERIFICATION.md](QR_VERIFICATION.md).
- [ ] **Content and receipts:** send multiline text, emoji and Urdu, and send from
  both phones at once. Content is correct and delivered appears only after an
  acknowledgement. Oversized text is rejected without losing the draft.
- [ ] **Interrupted delivery:** interrupt a send or leave range. Pending text
  becomes unconfirmed when appropriate; the app never treats uncertainty as a
  successful delivery. Saved history survives reopening the app.
- [ ] **Offline outbox:** queue text in a saved chat, restart, manually reconnect
  and verify both phones. Queued text sends in order only while unlocked and
  foregrounded. Cancelled queued text stays cancelled. Explicit unconfirmed Retry
  preserves its ID and creates no duplicate when the receiver retains history.
  See [OUTBOX.md](OUTBOX.md).

## 3. Optional automatic reconnection (two phones)

- [ ] **Default off:** interrupt a verified link without pressing Disconnect.
  There is no automatic connection attempt while the setting is off.
- [ ] **Opt-in recovery:** on the phone that selected Connect, enable Settings >
  Connection recovery. Establish/verify a link, then interrupt it while both apps
  stay visible/unlocked. Observe at most three attempts with 2/5/10-second waits
  between failures; native pairing/request time is additional. Fresh codes and
  both confirmations still gate queued text. Try both initiating phones.
- [ ] **Cancel and interruption:** cancel while waiting, pairing and comparing
  codes. Late callbacks cannot reopen the cancelled session. Locking, backgrounding
  or disabling the setting stops that burst; a quick return does not resume it.
- [ ] **Recovery limits:** remove the peer, disable Wi-Fi or revoke permission.
  Recovery stops with guidance, without prompting for permission automatically.
  A changed/missing address requires scanning/manual connection. Restart retains
  the opt-in but starts no connection. Images/files do not resume automatically.

Full timing, identity-change and cancellation cases:
[AUTOMATIC_RECONNECT.md](AUTOMATIC_RECONNECT.md). Use an actual interruption;
the app's intentional Disconnect action must not trigger automatic recovery.

## 4. PIN, fingerprint and privacy (each phone)

- [ ] **PIN lifecycle:** set and confirm a six-digit PIN; test wrong PIN/cooldown,
  cold launch, Lock now and PIN-authorized change/disable. History remains intact.
- [ ] **Fingerprint/biometrics:** on supported phones, enable and test success,
  cancellation/failure and PIN fallback. Unsupported devices remain usable by PIN.
- [ ] **Auto-lock timing:** test Immediately, 30 seconds, 1 minute and 5 minutes,
  returning both before and after expiry. Content hides as soon as the app loses
  foreground even during grace; cold launch/manual lock always require unlock.
- [ ] **OS privacy and routes:** background from a chat, Settings and QR view;
  inspect Recents and screenshots, unlock and use system pickers/biometric prompts.
  Private content and stale dialogs/actions must not remain exposed or bypass PIN.
- [ ] **Preview controls:** hide chat-list previews and inspect Chats/archive,
  including TalkBack. Names/counts remain; snippets are omitted. Toggle notification
  modes below and verify these are independent settings that persist after restart.

See [APP_LOCK.md](APP_LOCK.md), [AUTO_LOCK_TIMING.md](AUTO_LOCK_TIMING.md) and
[PREVIEW_PRIVACY.md](PREVIEW_PRIVACY.md).

## 5. Notifications and screen-off delivery (two phones)

- [ ] **Permission/alerts:** enable notifications; test denial and recovery on
  Android 13+. Receive from the other phone while reading another screen. Reading
  that conversation suppresses redundant alerts. Alerts require actual receipt.
- [ ] **Preview modes/taps:** test Hidden, Sender only and Sender and message,
  unlocked and locked. Locking or restricting previews redacts active alerts;
  tapping waits for unlock and opens the correct chat without exposing content.
- [ ] **Background opt-in:** enable Keep connection active for a verified live
  session; background/lock the receiver and send text. Check history/receipts after
  return, ongoing notification and Stop. No new outgoing/attachment work starts
  while locked/backgrounded; process termination requires manual recovery.
- [ ] **Battery/vendor behavior:** repeat with screen off for 5 and 15 minutes,
  battery saver and the manufacturer's normal battery restrictions. Record actual
  results and settings; OS interruption is possible and must not imply delivery.

See [NOTIFICATIONS.md](NOTIFICATIONS.md) and
[BACKGROUND_CONNECTION.md](BACKGROUND_CONNECTION.md).

## 6. Direct images and files (two phones)

- [ ] **Pick/send/view:** select local images and documents, preview and send both
  ways; verify progress, receipt, offline image zoom and file Save a copy. Open
  the exported file and compare its contents to the original. Try different local
  document providers, Unicode names and cancelling a picker/save operation.
- [ ] **Limits and failures:** try an unsupported/oversized image, empty file and
  file over 8 MiB. Prepared images are capped at 2 MiB. Rejection is clear and
  preserves existing history; see the linked guides for all image/source limits.
- [ ] **Interrupt/cancel/retry:** cancel mid-transfer, disconnect, lock/background
  either phone and retry explicitly after verification. Partial data must not be
  shown as complete or automatically resumed; completed attachments survive restart.

See [IMAGE_SHARING.md](IMAGE_SHARING.md) and [FILE_SHARING.md](FILE_SHARING.md).

## 7. Saved chats and everyday controls (each phone)

- [ ] **Navigation/unread:** switch Chats/Nearby/Settings, receive in another chat,
  and reopen it. Previews, times, ordering and unread counts update correctly.
- [ ] **Drafts and organization:** edit separate offline drafts; navigate, lock and
  restart. Pin, archive/unarchive, receive into an archived chat, then delete one
  disposable conversation. Other chats remain; deleted drafts do not reappear.
- [ ] **Search/nicknames:** search older message text and original/private names;
  jump to the correct original without losing drafts. Nicknames persist locally
  and do not replace the name advertised to the other phone.
- [ ] **Copy/reply/star:** copy full and selected Unicode text, paste elsewhere,
  reply and jump to the original, star/unstar and open saved stars offline after
  restart. Deleted originals show unavailable guidance instead of wrong content.

Detailed cases: [CHAT_LIST.md](CHAT_LIST.md), [DRAFTS.md](DRAFTS.md),
[CONVERSATION_MANAGEMENT.md](CONVERSATION_MANAGEMENT.md), [SEARCH.md](SEARCH.md),
[CONTACT_NICKNAMES.md](CONTACT_NICKNAMES.md), [MESSAGE_COPY.md](MESSAGE_COPY.md),
[MESSAGE_REPLIES.md](MESSAGE_REPLIES.md) and [STARRED_MESSAGES.md](STARRED_MESSAGES.md).

## 8. Themes, accessibility and vibration (each phone)

- [ ] **Appearance:** try light, dark and system mode with all four palettes;
  change the system theme, restart and inspect chats, attachments, dialogs and PIN.
- [ ] **Readability/TalkBack:** combine the largest OS font/display settings with
  app text-size presets and high contrast on the smallest phone. Controls stay
  reachable with the keyboard open. TalkBack reads labels/statuses correctly and
  omits hidden snippets. Check scrolling, focus and navigation in both chat modes.
- [ ] **Vibration:** default off is silent. Enable, use Try vibration and perform
  accepted sends/verifications. Check with Android touch feedback enabled/disabled;
  pulses never block an action or fire from a stale locked/background operation.

See [THEMES.md](THEMES.md), [ACCESSIBILITY.md](ACCESSIBILITY.md) and
[ACTION_FEEDBACK.md](ACTION_FEEDBACK.md).

## 9. Encrypted backups and phone migration (two phones)

- [ ] **Export/restore:** export a password-protected `.lcbackup` using Android's
  file picker, transfer it locally and preview/import history on the other phone.
  Check messages, images/files, drafts, pin/archive, replies, stars and nicknames.
- [ ] **Merge/failure:** import twice without duplicates; wrong password, damaged
  file, picker cancellation and cancelled final import leave destination history
  intact. Imported pending text is unconfirmed and requires explicit Retry.
- [ ] **Identity transfer:** with an empty destination, explicitly transfer identity,
  stop using the source phone, then reconnect to an existing peer and compare fresh
  codes. History-only import retains the destination identity; a populated phone
  cannot use identity transfer. PIN/local device settings are not restored.

Follow [BACKUPS.md](BACKUPS.md) for exact merge rules, limits and migration steps.
Use a spare/empty device or back up first; do not erase a daily-use install just
to satisfy this test.

## 10. Hosted groups (three phones: A host, B/C guests)

- [ ] **Create/find/join:** A hosts, B/C discover and join, each comparing fresh
  codes with A. Unverified guests cannot exchange messages; verify the member list.
- [ ] **Text/receipts:** send from A/B/C, including simultaneous text/emoji/Urdu,
  replies and stars. Both guests receive relayed content; receipts identify each
  recipient correctly. New members do not automatically receive old history.
- [ ] **Images/files:** send from the host and each guest; inspect relayed bytes,
  per-recipient receipts, offline views/exports and progress/cancel behavior.
  Locking/backgrounding or membership changes stops partial transfers safely.
- [ ] **Departure/delivery feedback:** remove or disconnect one guest during text
  and attachments. Confirmed recipients stay confirmed; the absent recipient is
  unconfirmed with useful guidance. Other connected members remain usable.
- [ ] **Host loss/rejoin:** interrupt A. Guests receive clear recovery guidance;
  there is no automatic host replacement. A reopens the original group, guests
  find/rejoin and compare fresh codes. History stays; nothing resends silently.
- [ ] **Background host:** opt in to Keep connection active, lock/background A,
  send text B-to-C and C-to-B, then check relay, receipts, notification privacy,
  Stop and screen-off/battery behavior. Attachments still need foreground access.
- [ ] **Saved groups:** restart and check independent group drafts, unread state,
  pin/archive, saved search, copying/replies/stars and backup/restore. Group recovery
  remains manual even when direct automatic reconnection is enabled.

See [GROUP_CHATS.md](GROUP_CHATS.md), [GROUP_IMAGES.md](GROUP_IMAGES.md),
[GROUP_FILES.md](GROUP_FILES.md), [GROUP_DELIVERY.md](GROUP_DELIVERY.md),
[GROUP_BACKGROUND.md](GROUP_BACKGROUND.md), [GROUP_DRAFTS.md](GROUP_DRAFTS.md),
[GROUP_MANAGEMENT.md](GROUP_MANAGEMENT.md) and [GROUP_SEARCH.md](GROUP_SEARCH.md).

## Record results and report failures

Copy this template for each run. Avoid private conversations/passwords in reports.
If only two phones are available, mark group cases Blocked rather than passed.

```text
Date / APK filename / app source commit:
A: model / Android version:
B: model / Android version:
C: model / Android version (or unavailable):
Network: mobile data off, router disconnected, Wi-Fi on?
Relevant permissions / battery restrictions / lock and background settings:
Checklist section and case:
Result: Pass / Fail / Blocked
Steps to reproduce:
Expected:
Observed (include exact error and sender/receiver delivery states):
Frequency (for example, 2 of 5 attempts):
Screenshot or redacted crash log if available:
```

Passing this checklist records observed behavior on the listed devices; it does
not establish support for every Android manufacturer or replace a security audit.
