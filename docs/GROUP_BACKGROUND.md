# Background protection for hosted groups

Implemented: 2026-10-13. On each participating Android phone, open **Settings →
Background connection** and enable **Keep connection active**. The same local,
off-by-default preference protects a verified direct chat or a hosted group.
It is not included in backups. See [BACKGROUND_CONNECTION.md](BACKGROUND_CONNECTION.md)
for notification permission, battery settings and common lifecycle limits.

The host needs at least one admitted, freshly verified guest. A guest needs its
verified host link and accepted group roster. Empty hosting, discovery, pending
joins and one-sided confirmation do not start protection. Start requires foreground
unlock and the allowed **Connection** notification channel. Verification completed
while locked/backgrounded waits for foreground unlock before starting protection.
A start already authorized in the foreground can finish while the app is locked.

## Text delivery and privacy

- The existing generic **LocalChat connection active** notification contains no
  group name, member names, security code, message content or unread count.
- Existing verified links may receive, decrypt and save signed text while
  backgrounded/locked. A host saves before relaying to its admitted guests; guests
  save before acknowledging, and the host relays individual receipts to authors.
- Background text stays unread until viewed in a foreground, unlocked group.
  Opt-in message alerts remain generic while locked/backgrounded, even when
  previews are enabled. Drafts, pin/archive choices and saved attachments remain.
- New text, member approval, images and files still require foreground unlock.
  Partial attachments cancel on lock/background without automatic resumption.
  A pending guest is excluded from protected links until fresh approval.
- One member leaving does not end the host's protection while another admitted,
  verified link remains. Losing the last such link releases protection, even if
  pending guests remain; empty hosting can continue without protection.

## Stop, recovery and mode changes

**Stop** on the ongoing notification works while locked/backgrounded. On a host
it ends hosting and all links; on a guest it leaves the host. It disables the
preference, removes protection and preserves saved history/drafts/organization.
Returning to the app does not reconnect or re-enable it.

Turning the Settings switch off removes protection while preserving the running
group for normal foreground use. Enable again to protect a currently verified
group, or rejoin/rehost and compare fresh codes after disconnection.

If starting the service fails, foreground messaging remains usable. Settings
shows guidance and **Retry connection protection** for a verified group, even
without a direct chat. Normal incoming messages do not continually retry a failed
service. Explicit Retry, foreground/unlock or a verified topology change can
attempt protection again. Permission/channel denial has its existing guidance.

Switching between nearby direct chats and groups closes the previous mode and
releases its protection. A replacement group requires fresh confirmations.
An old Stop/status event or late direct-chat cleanup cannot stop a newer group
lease. Deleting the active group or restoring a backup stops its connections.
There is no automatic reconnect, host migration, restored session key or group outbox.

## Implementation and limits

The existing Android `ConnectionService` is shared by both modes. Direct socket
generations are nonnegative; group room generations are negative, derived from
the native transport epoch. Dart synchronizes only admitted link IDs to the
background bridge. Native eligibility checks the current room, live admitted
sockets and local access; raw/unverified sockets cannot keep the service active.
Service epochs still reject old notification Stop intents. This local bridge
metadata does not change encrypted network frames or membership trust.

Received frames on authorized group links use the existing bounded partial wake
lock (up to 15 seconds per acquisition). Group Dart processing completes frame
work after decrypt/persist/relay/receipt handling, including ignored or malformed
frames. Native cancellation before Dart delivery, disconnect and service teardown
also release work. Unverified links do not acquire this group wake lock. No idle
CPU/Wi-Fi wake lock or wire heartbeat is added.

Protection applies to the current running Activity/Flutter session. Finishing the
Activity, task removal, force-stop, process termination or reboot ends it. Android
Doze/vendor restrictions can still interrupt delivery; hardware reliability and
battery costs remain unvalidated. Browser controls remain simulated; real nearby
group hosting/background protection require Android.

No new dependencies, Android permissions, database schema, backup payloads or
wire messages are introduced. SQLite remains schema 11 and backups retain v1-v8
compatibility. Android's documented [foreground-service launch rules](https://developer.android.com/develop/background-work/services/fgs/launch)
and [service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
were checked for the existing `remoteMessaging` service integration.

## Three-phone checklist

Install `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` on all phones.
Physical checks are pending. Record models, Android versions, outcomes and battery
use; include Android 7–12, Android 13 and Android 14+ where available.

- [ ] Upgrade over existing data; direct/group history, drafts, attachments,
      pin/archive choices and the saved opt-in setting remain.
- [ ] Enable while offline/empty hosting; no service yet. Discover, join and
      confirm only one side; no service. Confirm both sides while foregrounded:
      one generic ongoing notification per enabled phone.
- [ ] Finish verification with a guest locked/backgrounded; its protection waits
      for foreground unlock. Add a pending guest while the protected host is
      locked; no admission until the host returns and compares/confirms the code.
- [ ] Background/lock the host and send text from guest A to guest B. Both receive
      saved signed text, the author sees per-member receipts, and the host's
      unread count grows. Message alerts reveal no private previews.
- [ ] Background/lock a guest and send host text. It persists and acknowledges;
      returning locked does not read it, and opening after unlock does.
- [ ] Archive/pin the host's active room, leave a draft, and repeat receiving.
      Choices/drafts remain. Locked/backgrounded originating sends stay blocked;
      image/file transfers cancel and do not automatically resume.
- [ ] Disconnect one guest while another remains; host protection stays active.
      Lose the last verified guest with a pending guest present; protection ends
      and recovery requires fresh verification. Revoke Wi-Fi/Nearby/notification
      access and verify cleanup/guidance after native detection.
- [ ] Tap ongoing Stop on the locked host: all links/hosting end, preference is
      off, history/drafts remain. Repeat on a guest: it leaves, while the host
      continues with other verified guests. Unlocking/relaunching never reconnects.
- [ ] Disable protection in Settings and keep messaging in the foreground.
      Enable again. Deny the Connection channel and check guidance/Retry; granting
      it and explicit Retry recovers without changing group trust.
- [ ] Switch from group to direct and back; each mode needs fresh verification,
      with one service notification. Rehost a saved room, then try an old Stop
      notification action; it must not stop the replacement.
- [ ] Delete the active group or import a backup; protection ends with connections.
      Restart after task removal/Activity closure/force-stop/reboot; no automatic
      service/session restoration or orphan notification.
- [ ] Test 5/15/30 minutes with screen off and optimization enabled, then with an
      explicitly chosen exemption. Record Doze/vendor stalls, receipts and battery
      use. Check long sessions, simultaneous guest messages, larger text and themes.

Automated results and ignored local log paths are in [VALIDATION.md](VALIDATION.md).
The user reviews, commits and pushes this milestone.
