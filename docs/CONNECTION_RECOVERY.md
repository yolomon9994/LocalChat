# Connection troubleshooting and reconnect

Open **Nearby** and use **Check access** to inspect Wi-Fi Direct support, the
Wi-Fi radio, nearby permission and, on older Android, the Location switch. This
check does not start discovery or request permission. **Go nearby** starts
advertising and a scan, requesting the required Android permission when needed.

Recovery guidance appears on the home and chat screens. Actions depend on the
problem; saved messages and drafts remain available.

| Problem | Recovery |
|---|---|
| Wi-Fi off | **Open Wi-Fi settings**, enable Wi-Fi on both phones, return and tap **Go nearby**. |
| Permission denied/revoked | **Open app settings**, grant Nearby devices or Location as appropriate, return and **Check access**. |
| Older Android Location switch off | **Open Location settings**, enable the switch, return and try again. |
| Android reports busy | Finish/cancel pairing or use **Disconnect**, then **Scan again**. Reopen both apps if it persists. |
| Device no longer available | **Scan again** with both apps open; select a device from the refreshed list. |
| Connection lost or timed out | **Reconnect** if the last device is still listed; otherwise scan again. Compare fresh codes. |
| Wi-Fi Direct service stopped | **Go nearby** tries to initialize it again. Reopen the app if Android still fails. |
| Wi-Fi Direct unsupported | Saved history still works; this release has no alternate radio. |
| Settings cannot open | Open Android Settings manually. |

The nearby empty state distinguishes an active scan from a completed scan with
no devices. A scan lasts up to 15 seconds. Both phones should be close, unlocked,
foregrounded and running **Go nearby**. Use **Disconnect** before starting a scan
when a session/pairing is already active. Start, scan and connect controls reject
repeated taps while their operation is pending.

## Reconnect and queued messages

Nearby shows the **Last device** attempted during this app session. **Reconnect**
is available when its address remains in the current nearby list and no session
or pairing is active. A new scan clears the old list first. Addresses can change;
after disappearance or restart, scan and select the phone again. The last-device
hint is memory only and is not saved contact identity or automatic trust.

Reconnect opens a fresh handshake and security-code comparison. Both phones
must tap **Codes match** before queued text sends. History and the outbox follow
the cryptographic identity learned from that handshake, never the display name
or Wi-Fi address. A different identity cannot receive the old identity's queue.
Unconfirmed messages still require explicit Retry. See [OUTBOX.md](OUTBOX.md).

Tap **Why messages are queued** in a chat's toolbar to see whether it needs a
connection, both-phone verification, foreground access or storage recovery.
Locking hides that dialog with the rest of the app. This milestone provides
manual recovery; it does not automatically reconnect, confirm codes or enable
background delivery. Idle connection loss can still wait for a send or an
Android group-loss event to become visible; there is no heartbeat.

## Android and browser behavior

Returning to the foreground/unlocking rechecks access without starting discovery
or connecting. If access was revoked, a verified session closes. Switching off
Wi-Fi clears stale device/scan state and requires **Go nearby** after re-enabling.
Settings may trigger the existing app lock; unlock before using recovery controls.
Actions queued before a lock are rejected using the existing access token.

The bridge emits typed errors rather than exposing platform exception details.
Native advertising/scanning callbacks reject cancelled operations and handle
permission changes; disconnect can finish locally even after permission loss.
Settings intents open Wi-Fi, LocalChat's app details or Location, with general
Android Settings as fallback. No new permissions, dependencies, database schema
or wire payload are introduced. Official references: [Android Wi-Fi permissions](https://developer.android.com/develop/connectivity/wifi/wifi-permissions),
[Wi-Fi Direct APIs](https://developer.android.com/reference/android/net/wifi/p2p/WifiP2pManager)
and [Settings intents](https://developer.android.com/reference/android/provider/Settings).

Browser Demo uses simulated healthy access checks and does not open Android
settings. It can exercise manual reconnection and fresh verification; it cannot
validate Android radio, permission, settings or vendor behavior.

## Physical phone checklist

- [ ] Update both phones without uninstalling; confirm messages/drafts remain.
- [ ] Start with Wi-Fi off. Check access shows it off; the settings shortcut opens
      Wi-Fi settings. Enable Wi-Fi, return/unlock and use Go nearby successfully.
- [ ] Deny the permission prompt. App settings guidance appears without a crash.
      Grant permission in settings and retry. Repeat after revoking permission
      from an established session; verification must clear and drafts remain.
- [ ] On Android 7–12, check Location permission and the Location system switch.
      The shortcut opens Location settings. On Android 13+, Nearby devices is
      used and the app does not request Location permission.
- [ ] Scan with no other phone advertising. Progress ends and the empty result
      offers instructions; Scan again works without overlapping scans.
- [ ] Move a listed phone out of range/disable its app and try connecting. Failure
      stays in Nearby with recovery guidance; scan again clears stale devices.
- [ ] Disconnect a verified chat, queue text and use Reconnect for the listed
      device. The code changes; confirming only one phone sends nothing. Confirm
      both and check ordered delivery. Unconfirmed text requires explicit Retry.
- [ ] Switch off Wi-Fi during a scan and during a chat; progress/devices clear,
      verification resets, saved history remains and restarting nearby works.
- [ ] Try repeated taps during start, scan and pairing; one operation proceeds.
      Cancel pairing/disconnect, then retry without waiting for the old deadline.
- [ ] Enable app lock; visit settings and return. Unlock, recheck access and
      reconnect. Old dialogs/actions must not bypass the lock or verification.
- [ ] Check recovery buttons at enlarged system text on a small phone in both themes.

Automated checks/builds are in [VALIDATION.md](VALIDATION.md). Physical phone,
settings-provider and vendor checks remain pending. The user handles Git.
