# Local message notifications

Open **Settings → Notifications** and enable **Message notifications**.
Notifications are off on a new install. Android 13+ asks for notification
permission when you enable them; earlier Android versions use the system app
notification setting. A denied permission does not delete messages. If Android
blocks the app or its **Messages** channel, Settings shows an explanation and a
shortcut to Android notification settings. Returning to the app refreshes status.
The permission prompt or system settings can lock LocalChat; unlock to continue.

## Privacy and delivery

- Previews are off by default. Alerts say **LocalChat — New message. Unlock
  LocalChat to read.** They include neither the sender name nor the message body.
- **Show message previews** is an explicit choice. Sender/text appear only while
  LocalChat is unlocked and in the foreground, outside the chat being read.
  Preview text is limited to 256 characters. Device-lock-screen content remains
  generic through Android's private visibility/public notification version.
- Locking or backgrounding replaces existing preview alerts with generic alerts.
  Turning previews off does the same. Previously dismissed alerts stay dismissed.
  Android notification history, notification listeners, watches and other OS
  integrations may retain a preview already delivered; redaction cannot erase
  their copies. Leave previews off for this privacy boundary.
- One notification per peer is updated with the latest arrival. Notifications
  appear only for new, verified incoming messages after local persistence.
  Identical retries, outgoing messages, imported history and unverified frames
  do not create alerts. Notification failures cannot prevent persistence or ACKs.
- Reading the visible, unlocked foreground chat suppresses its alerts and removes
  its existing notification. Other chats, including archived chats, can notify.
- Tapping an alert opens that saved conversation. Cold-start and warm taps retain
  only the peer ID while locked; unlocking remains required. An active connection
  awaiting code confirmation still requires both phones to verify before showing
  its history. Back returns to the home screen. A deleted chat cannot be recreated
  by its old notification, and deletion cancels its alert.
- Disabling notifications removes current alerts. Clearing all history removes
  all alerts and pending tap targets. Preferences stay local to this phone and
  are excluded from chat export/import.

These are local Android notifications for messages the running app actually
receives. There is no cloud push, foreground service, background delivery promise
or automatic reconnect. Keep both apps running with a verified connection for
reliable tests; vendor battery restrictions/process termination can stop receipt.
The browser demo offers temporary settings only and requests no browser permission
or OS notification. It does not validate Android notification behavior.

## Two-phone checklist

Record phone models, Android versions and results. Hardware checks are pending.

- [ ] Fresh install: notification/preview switches are off. Turn notifications
  on; grant Android 13+ permission. Restart and confirm choices persist.
- [ ] Deny permission, then grant it through Android settings. Also disable just
  the Messages channel. Status refreshes on return/unlock without reconnecting.
- [ ] Verify both phones. Receive text while viewing Chats or Settings: one generic
  alert appears, tapping opens the correct chat and clears its unread count.
- [ ] Receive while reading that chat: no alert. Put a dialog/other screen over it
  or leave the app: a received message can alert and stays unread until read.
- [ ] Receive multiple messages: the peer alert updates. Connect another peer and
  confirm its alert has a distinct tap target. Archived chats still notify.
- [ ] Enable previews while foregrounded outside the chat. Receive text and check
  its preview; Lock now/background/disable previews replaces it with generic text.
  Check the phone lock screen as well. Dismiss an alert before locking: it stays gone.
- [ ] With app lock enabled, tap an alert when locked and after force-closing the
  app. No history appears until the correct PIN/biometric unlock; then the intended
  chat opens. Tapping must never confirm a fresh connection's security code.
- [ ] Lose an ACK and explicitly Retry after reconnecting/verifying. With receiver
  history retained, the identical message produces no extra alert or unread count.
- [ ] Disable notifications and receive: history/unread state updates without an
  alert. Delete one chat or all history: corresponding alerts disappear. An old
  tap cannot restore deleted records. Importing a backup creates no alerts.
- [ ] Check small-screen/enlarged-text settings, Android 7–12 compatibility, themes
  and vendor sound/vibration behavior. OS channel settings control interruption.

Implementation: Dart `ChatNotifications` and Android `MessageNotifications` use
the existing MethodChannel architecture with no new package dependency. Android
guidance: [notification creation](https://developer.android.com/develop/ui/compose/notifications/create-notification)
and [notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission).
Automated checks are recorded in [VALIDATION.md](VALIDATION.md). The user handles Git.
