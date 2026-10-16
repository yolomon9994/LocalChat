# Auto-lock timing

Implemented locally: 2026-10-16. User handles Git.

## Controls

With app lock enabled, open **Settings > App lock > Auto-lock timing**. Enter
the current app PIN, choose **Immediately**, **30 seconds**, **1 minute** or
**5 minutes**, then tap **Save**. Immediately remains the default for new and
existing installations. Cancel keeps the saved value. Wrong PINs use the same
attempt/cooldown rules as other lock changes. A failed write keeps the previous
setting; re-enter the current PIN to retry. The selector retains your choice.

The delay starts when LocalChat first loses focus, including a system picker or
permission prompt. Inactive, hidden and paused events share that one absence;
they do not restart the timer. Returning before expiry skips another PIN/biometric
unlock. Returning at or after expiry requires authentication. While enabled,
launching a new app process and **Lock now** always require unlocking. Detaching,
starting from an already locked state, or backgrounding during an in-flight lock
operation also requires unlocking. Foreground use does not run an inactivity timer.

## Privacy during the delay

Backgrounding still removes the entire application navigator immediately and
shows a generic privacy cover. Chats, search, settings, verification, dialogs,
keyboard actions and Back cannot expose old routes. A quick valid return opens
Chats, not the previously pushed conversation or dialog. Saved chat/group drafts
retain their existing behavior; unsaved dialog fields are discarded.

App access and foreground revisions still change immediately. New sends,
attachments, verification, QR scanning, nicknames and other old UI callbacks
retain their existing cancellation/access checks. A grace period does not grant
background access. Existing opted-in verified background receiving/relaying keeps
its previous behavior and restrictions; this setting does not add reconnection.
Notification previews are redacted while covered, including the existing native
Android lifecycle protection. A notification tap waits for an accessible foreground
and opens its saved chat after a valid return or explicit unlock after expiry.
Android's screenshot/Recents protection remains on whenever app lock is enabled.

A biometric system dialog may briefly cause an inactive event. It stays covered
without invalidating that specific prompt; actual backgrounding cancels the prompt
and rejects a late result. A PIN/settings operation pending across backgrounding
cannot use the grace period to unlock. A setting write already submitted after
successful PIN authorization may finish, but the interface stays locked.

## Persistence and timing

The existing `app_lock_v1` secure-storage entry now stores a **version-2** record
with `autoLockSeconds` restricted to 0, 30, 60 or 300. Version-1 records read as
Immediately without a startup rewrite; the next successful write uses v2. PIN
hash/salt, PBKDF2 cost, biometric preference and attempt state are unchanged.
Malformed/missing v2 delays fail closed. Older builds cannot read the v2 lock
record; use the updated build after migration. PIN/biometric changes preserve the chosen
delay; disabling and later re-enabling app lock starts at Immediately.

The unlocked grace grant stays in memory. It is never persisted, backed up or
restored. A cancellable one-shot timer expires it while execution is available;
resume also checks wall-clock and elapsed-clock ages, so a suspended timer cannot
extend a grant. Either elapsed limit expires access, and a negative age fails
closed. Clock changes may therefore cause an earlier unlock prompt. Manual lock,
restart/reinitialization, detach and disposal clear outstanding timers/grants.

Browser lock settings and timing remain in memory and reset on reload. Tab/window
focus changes may start the delay. This is app UI access control, not new database
PIN encryption or protection from a compromised OS. See [APP_LOCK.md](APP_LOCK.md).

No Android permissions/native code, chat schema, backup payload, identity or wire
format changes. SQLite stays 14 and encrypted chat backups retain v1-v11 imports;
app-lock settings remain excluded. Timer tests declare the already-cached
`fake_async` 1.3.3 package as a direct dev dependency; runtime packages are unchanged.

## Validation

Commands, actual results and development corrections are recorded in
[VALIDATION.md](VALIDATION.md). New automated cases cover v1 migration/v2 validation,
each delay and exact boundary, lifecycle chains, timers, clock changes, cold/manual
lock, cancellation/disposal, PIN authentication/write failures, pending operations,
biometrics, privacy routes/Back/drafts, notification taps and enlarged-text controls.
Automated adapters and fake clocks do not establish physical phone reliability.

## Manual Android/browser checklist

- Update an existing PIN-enabled installation. Immediately should remain selected;
  a full app restart must ask for the PIN before history opens.
- Select each delay using the correct PIN. Reject a wrong PIN; cancel an edit;
  restart and check the saved selection. Change the PIN and biometric preference:
  the delay stays. Disable/re-enable app lock: it starts at Immediately.
- With 30 seconds selected, switch apps from a direct/group chat, Settings,
  search, QR verification and an open dialog. The app must hide immediately.
  Return quickly: no PIN, Chats opens, and Back cannot restore the old route.
- Stay away beyond the delay or suspend/lock the phone long enough, then return:
  PIN/biometrics must be required. Repeat for 1 and 5 minutes. Device screen lock
  does not substitute for the app's chosen timing; check behavior on real hardware.
- Tap Lock now, then leave/return within the delay: it must stay locked. Force-close
  or restart during a grace period: the next launch must ask for authentication.
- Use the system attachment picker or a permission prompt and return before/after
  expiry. Follow existing attachment review/retry controls; nothing sends without
  the usual foreground/unlock/session checks. Check saved drafts after reopening.
- Background while a PIN check/settings save or biometric prompt is pending.
  Returning must require a fresh unlock; a late result cannot reveal a chat.
  Normal biometric prompt focus changes must still allow a successful unlock.
- With message previews enabled, check notification redaction and Recents while
  away. Tap a notification during/beyond the delay; it opens only when access is
  allowed. Check existing verified background text receiving/relay separately.
- Test TalkBack focus, large system/app text, narrow screens and the keyboard.
  Timing choices, current-PIN entry and Save/Cancel must remain reachable.
- Browser: switch focus/tabs, confirm the cover and timing behavior; reload clears
  demo settings. Do not infer Android biometrics/Recents behavior from this demo.

## Source

- [Lock controller and record](../lib/services/app_lock_controller.dart)
- [Settings and PIN dialog](../lib/features/app_lock_settings.dart)
- [Root privacy routing](../lib/main.dart)
- [Controller tests](../test/auto_lock_test.dart)
- [UI tests](../test/auto_lock_screen_test.dart)
