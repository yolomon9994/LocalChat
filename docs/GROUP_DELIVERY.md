# Group delivery feedback

Implemented locally: 2026-10-17. Baseline `492dbb5`; user handles Git.

## What the status means

Outgoing group text, images and files show a status for each original recipient:

- **Received**: that phone reported saving the complete message or attachment.
  This does not prove that the person read it. Guests receive other members'
  receipts through the trusted host.
- **Pending confirmation**: this attempt is still waiting for a receipt.
- **Unconfirmed**: no receipt proves delivery. The message might have arrived;
  sending it again creates a new message and may produce a duplicate.

When the host observes an admitted member disconnecting, leaving or being
removed, pending receipts for that member become unconfirmed immediately.
Guests do the same when the next validated roster omits that member. Confirmed
receipts remain received, and other pending text recipients keep their timers.
Resolved messages release their pending-send slots, so a departed member cannot
keep the four-text-attempt limit occupied until timeout.

Rows explain events observed during this app session: member disconnected or
left, host removal (on the host), host connection ended, confirmation timeout,
membership rejection, interrupted sending or an attachment transfer stopping.
A lost connection cannot prove whether someone intentionally left, lost radio
access or closed the app. A guest learns departures from the host's roster and
cannot distinguish removal from a voluntary departure. Reasons are observations,
not delivery proofs or signed statements from the recipient.

Names from the observed roster remain available for departed recipients during
this session. Otherwise the existing short identity ID is used. Reasons and
these remembered names are temporary memory only: restart/import on another
phone retains the saved received/unconfirmed states and uses **no receipt
available** when no reason was observed locally. Late valid receipts replace
uncertainty and remove its explanation. Deletion prunes associated details.

## Leaving, host loss and attachments

Ending a session marks remaining pending receipts unconfirmed and keeps all
received confirmations. Complete saved messages, image/file bytes, drafts,
unread state, timestamps and organization are preserved. Incomplete incoming
attachment buffers are discarded by the existing transfer cancellation logic.
Membership changes still cancel active attachment work; completed recipients
retain their copies and receipts. New members receive future messages only.

A failed status write shows an error and does not fabricate a persisted outcome
or prevent removing/closing the lost link. Saved pending state can remain until
the existing timeout/restart recovery succeeds.

Offline saved chats explain recovery:

- The original host can use **Host this group again** and compare fresh codes
  with each returning member.
- Guests ask the original host to reopen the group, then use **Open group
  finder** to reach discovery. Opening the finder alone does not discover, join,
  verify or resend anything. An existing running group disables this shortcut.
- Saved history and drafts remain usable while offline. Rejoining requires
  fresh explicit verification on both phones. Messages are never resent
  automatically; there is no group outbox, retry or host migration.

The finder callback rechecks foreground/unlock access, interaction revision,
route, history existence and running/busy state. Background/return, locking or
leaving the route invalidates captured callbacks. The app's root privacy cover
and route removal continue to protect delivery details.

## Storage and compatibility

Only the existing receipt strings are saved. Additional explanations and roster
name caches are neither persisted, backed up nor transmitted. SQLite remains
schema 14; encrypted backups remain payload v11 with older imports supported.
No signed envelope, wire payload, capability, permission or dependency changes.
Existing peers remain compatible; their own receipt-display behavior is unchanged.
Browser simulation exercises shared code without proving phone radio reliability.

## Validation

Commands, actual results and fixture corrections are in
[VALIDATION.md](VALIDATION.md). New tests cover text departures/removal, partial
receipts, pending-slot cleanup, host loss, restart/backup exclusion, late valid
receipts, failed status writes, interrupted image/file delivery, newcomer history,
UI/semantics, offline recovery, stale callbacks, PIN privacy and 320 x 568 layouts
at 2.34 text scaling. Android system/radio behavior remains a physical check.

## Three-phone checklist

Use one host and two guests; record device models and Android versions.

- Send text to both guests. Confirm each status means saved, not read. Interrupt
  one guest before confirmation and check that only its pending row becomes
  unconfirmed when departure is observed; the other received row stays received.
- Remove a member on the host. Check the host's removal explanation and the
  remaining guest's roster-based departure explanation. Retain the departed
  member's session label; do not label an unknown disconnect as intentional.
- End hosting during a partly confirmed guest-authored message. Check offline
  guidance, preserved confirmations/history/draft and no automatic resend.
- Repeat during image/file upload and host relay. Complete saved copies remain
  viewable/exportable; partial buffers and progress stop. Newly joining members
  do not receive old messages or attachments.
- Reopen the original group and join again. Both sides compare fresh codes.
  Check history/drafts and ensure no old unconfirmed message is resent.
- Restart or transfer a backup: saved statuses survive, while detailed session
  reasons fall back to no receipt available. No unconfirmed status claims failure.
- Test narrow screens, large text, TalkBack and keyboard navigation. Check PIN,
  quick background/return and stale finder callbacks cannot expose routes.

## Source

- [Delivery details](../lib/services/group_delivery.dart)
- [Group controller](../lib/services/group_controller.dart)
- [Attachment handling](../lib/services/group_attachments.dart)
- [Group UI](../lib/features/group_screen.dart)
- [Controller/transfer checks](../test/group_delivery_test.dart)
- [UI checks](../test/group_delivery_screen_test.dart)
