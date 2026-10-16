# Optional vibration feedback

Implemented locally: 2026-10-16. Baseline `09533a1` (text size/high contrast).
The user reviews, stages, commits and pushes after testing.

## Controls and behavior

Open **Settings → Action feedback** and enable **Vibration feedback**. It starts
off. Enabling it saves the preference without producing a pulse. **Try vibration**
requests one light Android touch-feedback pulse so you can check the setting.

With feedback enabled, a successful user action can request one pulse:

- Send/queue direct text, or explicitly retry an unconfirmed direct message.
- Send direct/group images or files, including explicit direct attachment retries.
- Send group text, including a quoted reply.
- Confirm a direct or individual host–guest connection using manual comparison
  or the explicit **Verify connection** button after a matching QR scan.

A pulse means the local action was accepted. Queuing offline text still needs a
fresh verified connection before delivery. Local verification still needs the
other phone's independent confirmation. A matching QR scan alone does not pulse
or trust a peer. Delivery receipts and automatic outbox work do not request pulses.

Failed/cancelled actions do not pulse. If you leave/cover the route, lock or
background before completion, its old request cannot produce feedback after
returning. Changing the setting invalidates pending requests, even if it is
turned back on. Overlapping native requests coalesce; they do not form a queue.

The application never waits for the physical pulse to finish before completing
the action. Missing hardware, unsupported platforms and platform errors do not
turn an accepted message/confirmation into an error. Once a request has already
been handed to Android it cannot be recalled by this Dart implementation.

## Android and browser behavior

The adapter calls Flutter's **HapticFeedback.lightImpact**, which uses Android
**VIRTUAL_KEY** touch feedback. It follows the system's touch-feedback preference
and available hardware; enabling LocalChat's setting cannot force a disabled
system effect. This adds no vibration permission, native code or package.
Actual strength and behavior depend on the phone and need physical testing.

References: [Flutter lightImpact API](https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html)
and [Android touch-feedback guidance](https://developer.android.com/develop/ui/views/haptics/haptic-feedback).

Browser demo can preview/save the toggle in memory until reload but never requests
action vibration. **Try vibration** is disabled there and on unsupported platforms.
The app's demo flag also blocks output when a supported adapter is injected.

This setting controls these additional action pulses. Android notification
vibration, keyboard feedback and Flutter's standard control feedback retain
their existing system behavior and settings.

## Persistence and privacy

Android stores a small version-1 enabled/disabled record separately in the existing
secure-storage vault. No theme record is rewritten. Missing settings mean off;
invalid/unreadable settings fail closed with a generic recoverable error.
Failed saves preserve the previous applied/saved value and offer retry; controls
are disabled while saving. Disabling can fail, so check the displayed switch/error.
Initialization failures do not prevent chat initialization.

Feedback tickets are single-use in-memory objects bound to the service, preference
revision, originating route and controller foreground/access revision. They carry
no message content and are not stored, exported or transmitted. Controller disposal
invalidates them. Demo/unsupported paths cannot emit action feedback.

The preference survives history deletion and Android restarts, and is independent
of chat backups and identity transfer. SQLite stays schema 13, encrypted backups
stay v10, and no wire payload, identity or trust rule changes.

## Validation

See [VALIDATION.md](VALIDATION.md) for exact commands, results and ignored logs.
Eight service/platform checks cover default-off persistence, malformed/read errors,
save failures/overlap, stale/single-use/foreign/disposed requests, coalescing,
platform errors, demo/unsupported suppression and the actual Android method-channel
request. Eight UI checks cover Settings/test/save retry, accepted/failed direct
text, programmatic work, privacy/routes, nonblocking output, demo silence, manual
group confirmation/signed sends, explicit QR confirmation and 320 × 568 at 2.34 text.

Fake haptic adapters and channel interception prove request behavior, not that a
phone vibrated. Physical system-preference handling and actuator behavior remain
pending.

## Phone and browser checklist (pending)

- [ ] Upgrade a phone with existing chats/themes/PIN. Confirm feedback defaults off
      and normal sending/verification does not gain an extra action pulse.
- [ ] Enable feedback and tap Try vibration with Android touch feedback enabled.
      Disable Android touch feedback and try again; LocalChat must not force it.
      Record phone model, Android version, hardware behavior and system settings.
- [ ] Restart while enabled, check the saved switch, then disable/restart and check
      it remains off. Confirm history deletion does not reset the preference.
- [ ] Send/queue direct text, replies, images and files; try explicit retries.
      Confirm one local pulse on accepted actions and no second pulse for ACKs
      or automatic outbox sending after fresh verification.
- [ ] Verify direct chat with manual codes and QR. Scanning alone must not pulse;
      explicit local confirmation can pulse while waiting for the other phone.
- [ ] Host/join a group and verify one link. Send group text/replies/images/files;
      check one local pulse per accepted action, with no relay/receipt pulse.
- [ ] Cancel a review, fail a send, cover/leave the screen, lock or background during
      a pending operation. Returning/unlocking must not produce an old pulse.
- [ ] Disable/re-enable feedback during an operation; check no old pulse is replayed.
- [ ] Check no-vibrator/disabled-haptic behavior where available; messages and code
      confirmations must remain usable. Notification vibration stays independent.
- [ ] Check large text, high contrast and TalkBack for the switch, Try vibration and
      local-action explanation. Browser demo stays silent and resets on reload.
