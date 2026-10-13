# Background connection protection

This setting protects the current verified direct chat or hosted group. Groups
can receive and relay text on admitted links; empty hosting and pending joins do
not start protection. See [GROUP_BACKGROUND.md](GROUP_BACKGROUND.md) for activation,
privacy, member departure, mode changes and the three-phone checklist.
Images and files require both phones unlocked and foregrounded; backgrounding
cancels partial transfers. This setting does not resume them. See
[IMAGE_SHARING.md](IMAGE_SHARING.md) and [FILE_SHARING.md](FILE_SHARING.md).
Group images and files also require participating apps unlocked and foregrounded. Lock,
backgrounding or membership changes stop partial transfers without resuming;
confirmed copies remain. See [GROUP_IMAGES.md](GROUP_IMAGES.md) and
[GROUP_FILES.md](GROUP_FILES.md).

On each phone, open **Settings → Background connection** and turn on **Keep
connection active**. This choice is off on a fresh install and stays local to the
phone, outside chat backups. Allow Android notifications when prompted. If the
app locks during the prompt, unlock to continue; enabling never bypasses the PIN.

Connect through Nearby and compare the fresh security code on both phones. The
service starts only after both phones confirm, while LocalChat is unlocked and
in the foreground. Enabling the switch while offline only saves the preference;
it does not scan, connect or confirm a peer. A handshake that finishes while
locked/backgrounded waits for foreground unlock before starting protection.

## Controls and privacy

- The **Connection** notification channel is separate from **Messages**. It must
  be allowed for protection to start. Message alerts can stay off independently.
  Settings has a channel shortcut, current protection status and Retry after a
  failed service start. Service failure does not invalidate an otherwise verified
  conversation or prevent foreground message delivery.
- The ongoing notification says **LocalChat connection active** and has **Stop**.
  It contains no peer name, identity, security code, message body or unread count.
  Tapping its body opens the existing app through the normal lock screen.
- **Stop** works while locked or backgrounded. It disconnects and stops nearby
  advertising, disables the preference and removes the ongoing notification.
  History, unread state, drafts and queued messages remain. Returning to the app
  cannot restart that connection. Enable again and reconnect/verify to resume.
- Turning the Settings switch off removes protection but keeps the current
  conversation connected for normal use. Disconnect in Nearby to close the link.
  Disabling message alerts/clearing history never removes the service notification.
- While protected and backgrounded, received verified text messages decrypt, persist
  and ACK, with generic message alerts if enabled. They stay unread until actually
  viewed. PIN locking, hidden previews and both-phone verification stay in force.
  Queued sending still requires foreground unlock; the service does not drain it
  or automatically retry unconfirmed messages.
- Link loss stops protection and releases processing resources. An active
  protected link that ends unexpectedly gets a generic connection-ended
  notification; Settings/Nearby show recovery guidance. Reconnect and compare
  both fresh codes. An old Stop action cannot stop a later protection session.

## Battery and lifecycle limits

The foreground service protects the **current running app session** while using
Home, another app or the screen lock. It keeps the process eligible to run;
it does not create another Flutter engine or retain a closed Activity. Closing
the Activity (including Back if it finishes it), removing its task, force-stopping,
rebooting or process termination ends the connection. The service is not sticky, has no boot receiver
and never restores cryptographic session state. Reopen and reconnect manually.

There is no indefinite CPU or Wi-Fi wake lock. A received frame may acquire a
partial wake lock for at most 15 seconds to cover decrypt/save/ACK; completion
releases it when pending frame work finishes. Disconnect/service destruction
also releases it. The service periodically checks whether its connection,
nearby permission and notification access are still valid; revoked access ends it.
This checks local state, not peer responsiveness: there is no wire heartbeat,
and an idle dead peer can remain unnoticed until TCP/Android reports the loss.

Android Doze and vendor battery restrictions can still suspend network delivery.
**Open battery settings** opens Android's optimization list (with an app-settings
fallback). The user chooses any exemption manually; the app requests no automatic
exemption permission and changes no battery settings. The displayed exemption
is Android's reported value and does not cover every vendor's restrictions.
Test screen-off delivery on your phones before relying on it. Increased radio
and processing activity costs battery even though idle CPU is not held awake.

The browser demo has temporary simulated controls and no OS service, battery
settings or screen-off-delivery claim.

## Two-phone checklist

Hardware checks remain pending. Record models, Android versions, outcomes and
battery use on Android 7–12, Android 13 and Android 14+ if available.

- [ ] Fresh install: switch off. Enable while offline: preference saves, no scan
  or service notification. Deny notification permission: mode stays off with guidance.
- [ ] Allow notifications; disable Messages only: Connection can still run.
  Disable Connection only/global notifications: starting protection gives guidance.
- [ ] Connect and confirm only one phone: no service. Confirm both while
  foreground/unlocked: one generic ongoing notification per enabled phone.
- [ ] Enable after an already verified connection: protection starts. Finish
  peer confirmation while locked: it waits for foreground unlock.
- [ ] Press Home/switch apps, then receive text. It persists, ACKs and alerts
  generically; open/unlock the right chat and check unread clearing.
- [ ] Lock the screen for 5, 15 and 30 minutes and test delivery with optimization
  enabled and with an explicitly chosen exemption. Record Doze/vendor interruptions.
- [ ] Queue text, background/lock before both verify, then finish verification.
  It sends only after foreground unlock, in order, with original IDs/draft intact.
- [ ] Tap ongoing Stop while locked/backgrounded: both the link and advertising
  stop, preference is off, notification disappears, history/drafts/outbox remain.
  Returning/relaunching does not reconnect or re-enable the preference.
- [ ] Turn the Settings switch off: ongoing notification disappears; foreground
  messaging remains usable. Toggle rapidly, disconnect or lock during startup:
  no stale notification, false active status, duplicate service or hung UI.
- [ ] Disable message alerts and clear history while protected: ongoing notification
  remains. Deleting the active conversation or moving identity closes protection.
- [ ] Lose Wi-Fi/peer/group/permission: protection stops, a generic loss notice
  appears where applicable and recovery never skips fresh code confirmation.
- [ ] Revoke notification access while running: the service stops after its next
  local check. Android's Task Manager Stop/force-stop ends the app; relaunch requires
  reconnecting. Finish the Activity/remove task/reboot: no service restart or orphan.
- [ ] Check small-screen/enlarged-text Settings, themes and battery/channel shortcuts.

Implementation: native `ConnectionService` uses `remoteMessaging`, with
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_REMOTE_MESSAGING` and `WAKE_LOCK`.
Activation is tied to the native direct/group transport generation, admitted group
links and a service epoch. No new
dependencies, database schema, backup format or encrypted wire payloads are added.
See Android's [service types](https://developer.android.com/develop/background-work/services/fgs/service-types),
[foreground-service launch rules](https://developer.android.com/develop/background-work/services/fgs/launch),
[Doze restrictions](https://developer.android.com/training/monitoring-device-state/doze-standby)
and [wake-lock practices](https://developer.android.com/develop/background-work/background-tasks/awake/wakelock/best-practices).
Automated results are in [VALIDATION.md](VALIDATION.md). The user handles Git.
