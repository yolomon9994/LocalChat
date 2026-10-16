# Optional automatic reconnection for direct chats

Implemented locally: 2026-10-17. Baseline `9203437`; user handles Git.

## Controls

In **Settings > Connection recovery**, enable **Automatically reconnect direct
chats**. It is off by default. Android saves the preference in the independent
`automatic_reconnect_v1` secure-storage entry; browser/demo controls are temporary.
Unreadable/malformed settings remain off. Failed writes retain the applied choice
and show a generic retry error. Turning the setting off cancels the current burst
immediately even if saving that choice fails; it never silently resumes that burst.

After an unexpected loss of a connection you selected and verified, the app can
make up to **three attempts**, waiting **2, 5 and 10 seconds** before successive
attempts. Each attempt checks Nearby prerequisites and the current device list.
The existing connection/verification timeout still applies; OS pairing callbacks
and radio recovery can take additional time. This is not an overall wall-clock
deadline or a guarantee that Android will restore the link.

Status and **Cancel reconnection** appear in Nearby and in the affected direct
chat. Once a link presents the expected signed identity, status asks you to
**compare the fresh code on both phones**. There are no more automatic attempts
while waiting for that comparison. The existing QR/manual comparison and both
explicit confirmations are required before messaging resumes. Cancelling during
pairing/verification requests native disconnect, hides the code and rejects stale
confirmation callbacks. An old Cancel callback cannot cancel a later connection.

## Which device can be retried

The eligible target is the last device **selected on this phone** and fully
verified in the current app run. Its Nearby address and verified identity are
held only in memory. The device must still be present under that address in the
current Nearby list. This version does not start discovery automatically, guess
by display name, search all saved contacts or learn a new address for an identity.
If the address disappears or changes, scan and connect manually.

On an automatic attempt, the signed hello must identify the same peer as the
lost verified session. A different identity closes the link before displaying
its comparison code or loading its history, and stops the burst. This continuity
check is not automatic trust: the fresh session still needs both confirmations.
Display names are public and can be copied; they never select an alternate target.

If the other phone reconnects first during the waiting period, the pending timer
is cancelled and the same identity/fresh-verification rules apply. An incoming
session without a locally selected verified target does not create its own retry
target. The phone that originally selected Connect drives recovery in this version.

## Stop conditions and privacy

- Manual disconnect, Cancel, disabling the setting, starting/scanning/connecting
  manually, changing connection mode, renaming, importing or clearing history,
  deleting the retry target and disposal stop the current burst.
- Locking or leaving the foreground cancels timers and pending automatic work,
  including during an auto-lock grace period. A quick return does not resume a
  cancelled burst. Loss events queued before/during that absence cannot arm a
  new burst after return. If an existing verified connection remains live through
  backgrounding, a later newly observed loss in the foreground can be eligible.
- Wi-Fi/permission/Location/service prerequisites, an absent address, status-check
  failure, security failure or exhausted attempts stop recovery with guidance.
  No permission prompt, system-settings opening, background service startup or
  permission/battery exemption is initiated by the retry loop.
- If Android cannot close a cancelled/failed automatic connection, the app
  rejects late session activity, ends the burst and shows Restart nearby guidance
  rather than leaving an active retry or exposing raw platform errors.
- A successfully exchanged hello pauses retries for fresh verification. Losing
  that unverified link or reaching its verification timeout ends the burst.
  An initial manually initiated connection that was never verified does not
  start automatic recovery.
- Cancelling/exhausting an automatic attempt rejects late incoming direct
  connection/frame callbacks until a new explicit Nearby action. This prevents
  delayed pairing events from recreating a cancelled session.

All radio attempts remain serialized with normal connection/frame processing.
Timers and awaited readiness/connect/hello operations recheck current ownership,
foreground/unlock access and interaction revision. Cancellation requests native
pairing shutdown promptly; Android ultimately controls the system pairing UI.
The root privacy cover and existing lock-aware notification behavior are unchanged.

## History, outbox and compatibility

Chats, drafts, organization, identity and received/unconfirmed evidence are kept.
Only already queued outgoing text can drain after the fresh session has been
verified on both phones and remains unlocked/foregrounded. Unconfirmed messages
still require explicit Retry. Images/files do not resume automatically.

The preference, target, retry budget, timers and session keys are excluded from
chat backups. A cold restart remembers only the opt-in, with no automatic target
or connection attempt. Group discovery/rejoining/verification stay manual; the
host must reopen the original group. There is no host migration or group outbox.

No dependency, permission, native bridge, wire, signature, SQLite schema or backup
format changes. SQLite remains 14; encrypted backups remain v11 with older
imports supported. Existing peers can reconnect using normal fresh verification.

## Validation and phone checklist

Commands, results and fixture corrections are in [VALIDATION.md](VALIDATION.md).
Browser simulation checks shared behavior, not Android radio/OS reliability.
The demo's Disconnect action is intentional and does not trigger retries;
automated fake transports inject unexpected losses for coverage. Use phones
to check real interrupted-link recovery.

- On both phones, open Nearby and advertise; on one, select and verify the other.
  With the setting off, interrupt the link: no automatic pairing should occur.
- Enable the setting, establish a verified connection and interrupt it. Keep the
  apps open/unlocked. Check attempt status and the 2/5/10-second waits after
  failures; pairing time is additional. Exhaustion stops after three attempts.
- Restore the link and compare a new code on both phones. Confirm on just one:
  queued text must still wait. Confirm on both: queued IDs send once, drafts stay,
  and unconfirmed messages/attachments do not resend automatically.
- Cancel while waiting, during Android pairing and at fresh-code verification.
  Check late callbacks cannot reopen that cancelled session. Explicit Connect or
  Go nearby should still work afterwards.
- Repeat with PIN, background/quick return, expired auto-lock grace, Wi-Fi off,
  revoked Nearby permission, Location off on older Android and unavailable peers.
  No background retry or automatic permission/settings prompt should appear.
- Move away/change the device address: scan and reconnect manually. On a test
  reinstall with a changed identity at the same address, automatic continuity
  checks must close it; manual connection still needs a fresh comparison.
- Restart both phones. The opt-in persists on Android, but there is no automatic
  connection until another selected session has been verified and later lost.
- Check group mode, import/delete/rename, TalkBack, keyboard and narrow screens
  with large text. Record device models, Android versions and observed results.

## Source

- [Preference storage](../lib/services/reconnect_preferences.dart)
- [Retry orchestration](../lib/services/automatic_reconnect.dart)
- [Controller integration](../lib/services/chat_controller.dart)
- [Settings](../lib/features/automatic_reconnect_settings.dart)
- [Status controls](../lib/features/automatic_reconnect_status.dart)
- [Controller checks](../test/automatic_reconnect_test.dart)
- [UI checks](../test/automatic_reconnect_screen_test.dart)
