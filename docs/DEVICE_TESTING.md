# Two-device acceptance tests

Readability has a [text-size/high-contrast checklist](ACCESSIBILITY.md), including
OS font settings, theme migration, restart/PIN, combined enlargement, TalkBack and
small-screen browser notices. Vibration feedback has its own
[action-feedback checklist](ACTION_FEEDBACK.md), including system haptic settings,
restart, direct/group actions, demo silence and late-result privacy.

QR verification has a [camera/direct/group checklist](QR_VERIFICATION.md), including
first-use offline models, permission/PIN behavior, both confirmations, old/wrong QR
rejection and camera shutdown. Automated camera tests use a fake native platform.

Starred messages have a [saved-message checklist](STARRED_MESSAGES.md), including
restart, exact original jumps, deletion and encrypted v10 backups.

Replies have a [direct/group checklist](MESSAGE_REPLIES.md), including quote
drafts, original jumps, outbox retry, older peers, group receipts and v9 backups.

Text copying has a [clipboard checklist](MESSAGE_COPY.md), including full/selected
text, group/search history, PIN/background dismissal, paste and accessibility.

Browser group UI/protocol simulation has a separate [checklist](BROWSER_GROUPS.md);
it does not replace physical phone testing.

Group background protection uses the [three-phone checklist](GROUP_BACKGROUND.md),
including locked host relaying, member departure, Stop and screen-off battery limits.

Group search uses the [search checklist](GROUP_SEARCH.md), including archived
history, exact older-message navigation, unread/draft preservation and PIN gates.

Group pin/archive uses the [organization checklist](GROUP_MANAGEMENT.md), including
upgrade/restart, archive counts, receiving while archived, PIN and v8 backups.

Saved group drafts require the [draft checklist](GROUP_DRAFTS.md), including
navigation/PIN/restart restoration, offline editing, sends and migration.

Hosted group chats additionally require the [three-phone checklist](GROUP_CHATS.md).
Group images have a separate [three-phone checklist](GROUP_IMAGES.md), including
host/guest relays, individual receipts and membership/lock interruptions.
Group files require the [file checklist](GROUP_FILES.md), including three-phone
relay, provider save failures, offline export and mixed attachment backups.
Direct-chat images have a separate [two-phone checklist](IMAGE_SHARING.md) for
picker locking, progress/cancel, retries, offline viewing and image backups.
Direct-chat files have a [file-sharing checklist](FILE_SHARING.md) for selection,
transfer interruptions, offline saving, filenames, provider errors and backups.

These tests require physical hardware and are **not marked as passed** by the automated protocol tests. Record phone model, Android version and outcomes when testing.

For encrypted file export/import, merging and identity transfer, also follow
the [backup phone checklist](BACKUPS.md).
For queuing, retry and lifecycle gates, follow the [outbox checklist](OUTBOX.md).
For settings shortcuts and reconnect, follow the [recovery checklist](CONNECTION_RECOVERY.md).
For message alerts, permission and lock-aware taps, follow the [notification checklist](NOTIFICATIONS.md).
For screen-off receipt, ongoing Stop and battery limits, follow the [background checklist](BACKGROUND_CONNECTION.md).

| Case | Expected behavior |
|---|---|
| Fresh install on Android 13+ | Nearby device permission requested, no Location runtime request |
| Android 7–12 | Location permission requested; Location toggle required for scanning |
| Permission denied/revoked | Actionable error, no crash or plaintext fallback |
| Settings recovery | Appropriate settings screen opens; return/unlock rechecks access without auto-connecting |
| Access revoked in verified chat | Session/verification clears; saved history and drafts remain |
| Wi-Fi disabled | Instructions to enable Wi-Fi; no mobile data fallback |
| No router, mobile data off | Both phones discover/connect/chat using Wi-Fi Direct |
| Discovery | Only LocalChat v1 service advertisements appear |
| Completed empty scan | Progress ends; empty-result instructions and Scan again remain usable |
| Device disappears | Failed connect stays in Nearby; Scan again removes the old list before rediscovery |
| Pairing | Receiver accepts the system Wi-Fi Direct invitation |
| Security code | All five groups match on both phones |
| Only one phone confirms | No text transmission; new peers cannot submit, saved chats can queue |
| Codes differ | Disconnect; no text exchange |
| Text and Unicode | Correct text in both directions, including emoji and Urdu |
| Large text | 4096-byte limit applied; longer UTF-8 payload rejected |
| Delivery acknowledgement | Sender changes from sending to delivered after peer stores text |
| Connection dropped before ack | Sender marks message unconfirmed; retains history |
| Offline outbox | Queue in saved chat, restart, reconnect and verify both; ordered delivery |
| Unconfirmed retry | Explicit confirmation, original ID retained; no duplicate if receiver retains history |
| Cancel queued | Confirmed deletion before sending; never sends on later reconnect |
| Lock/background | New queued attempts pause until unlocked and foregrounded |
| Imported pending messages | Newly imported queued/sending become unconfirmed; explicit Retry required |
| Relaunch | Names, identity and encrypted-body history persist; sending leftovers are unconfirmed |
| Reconnect | Fresh code, mandatory verification, same peer's saved history |
| Reconnect shortcut | Last listed address only; fresh handshake and both-phone confirmation before queued delivery |
| Simultaneous sending | Correct order per sender, no nonce/counter race |
| Rename | Connection closes; tap Go nearby again to advertise new name |
| Delete history | Messages/conversations disappear locally |
| Peer leaves range | Connection ends or next send fails; no silent delivered status |
| Third device connects | Single-session behavior; no unverified messages accepted |

## Troubleshooting

- Keep both apps in the foreground and both radios on. Some vendor firmware suppresses service discovery while a group is already formed.
- Try scanning again on both phones after the 15-second scan window. A peer may remain in the current list until the next scan; tapping a stale peer can fail and require another scan.
- If Wi-Fi Direct is busy, disconnect, close and reopen both apps, then try again. You may need to remove an existing Wi-Fi Direct connection in system settings.
- On older Android, enable Location in system settings as well as granting permission. No app location data is collected.
- Not all Android phones support Wi-Fi Direct. This version has no Bluetooth fallback.
- A failed/unconfirmed status does not prove nondelivery; it only means no acknowledgement was received.
- Emulator-to-emulator tests cannot validate the real Wi-Fi Direct path.

Useful development commands:

```bash
flutter devices
flutter run -d FIRST_DEVICE_ID
flutter run -d SECOND_DEVICE_ID
adb logcat -s flutter AndroidRuntime
```

Never include secret keys or private conversations in diagnostic logs. The native transport does not log frame contents.

## Starred messages

Run the Android/browser/restart/import/privacy checklist in
[STARRED_MESSAGES.md](STARRED_MESSAGES.md). Automated results are in VALIDATION.md;
physical-device and TalkBack checks remain pending.
