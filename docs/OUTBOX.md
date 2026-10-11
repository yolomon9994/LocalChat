# Offline outbox and message retry

Open a saved conversation while disconnected, type text, and tap **Queue
message**. Android saves the message with an encrypted body. Its matching draft
is removed in the same database transaction. Queued counts appear in Chats and
the conversation header. Browser Demo keeps its outbox only until reload.

Reconnect through Nearby and compare the fresh security code on both phones.
Both must tap **Codes match**. Queued messages for that verified identity then
send automatically, oldest queued first, while the sender is unlocked and in
the foreground. This also applies to archived chats and when viewing another
conversation. Connecting to a different identity never sends that queue.

There is no automatic discovery, reconnect or background sending in this
milestone. A saved chat can accept queued text while its connection awaits
verification; an unknown peer cannot accept text until verified.

## Message states and actions

| State | Meaning and available action |
|---|---|
| `queued` | Saved locally, waiting to send. **Cancel queued** removes it after confirmation. |
| `sending` | An attempt has started; awaiting its encrypted acknowledgement. Cannot cancel. |
| `delivered` | The peer decrypted and stored it. This is not a read receipt. |
| `unconfirmed` | The attempt ended without confirmed delivery. It may already be on the other phone. **Retry** requires confirmation. |

**Retry now**, or **Queue retry** while disconnected, keeps the original ID,
timestamp and text. The receiving phone acknowledges an identical saved copy
without inserting it again or adding another unread count. That protection
requires the receiver to retain its message history; deleting it can allow a
retried message to appear again. Sending the same text as a new message creates
a new ID. An existing ID with different text/timestamp fails the security check.

An acknowledgement normally arrives immediately; after 30 seconds an attempt
becomes unconfirmed. A late acknowledgement can still confirm that attempt in
the same session. At most four attempts await acknowledgement at once. A socket
failure closes the connection: attempted messages become unconfirmed, while
unsent messages stay queued. Unconfirmed messages never retry automatically.

Storage errors pause the affected outbox. Resolve the error, then use **Resume
outbox**, or reconnect and verify again. Status must be saved before a wire send.
Invalid or unsaved text keeps its draft; a message already accepted locally
clears that draft even if the later transport attempt fails. Newer draft edits
are preserved. Deleting a conversation or all history removes its queue too.

## Persistence, locking and backups

Android restarts preserve queued messages; leftover `sending` records become
unconfirmed. Schema 6 adds only an outbox lookup index and preserves existing
encrypted history, identity, drafts and chat flags. Status/IDs/timestamps remain
unencrypted metadata under the existing storage model. No new payload type,
dependency or Android permission is required.

Locking or backgrounding pauses new outgoing attempts. An already submitted
transport write can complete, and the established session can still receive
text and acknowledgements under the existing app-lock model. A gate change
during frame encryption discards the frame and connection; reconnect and verify
again. Queued text does not appear on the lock screen.

Backups include the queue, but newly imported `queued` and `sending` messages
become **unconfirmed** and require explicit Retry. Import never sends messages.
Install the updated app on both phones before transferring a backup containing
queued records; older builds reject that status. Existing destination records
and their states still win during a merge.

## Two-phone checklist

- [ ] Update both phones without uninstalling. Existing history/drafts remain.
- [ ] Disconnect, queue two messages containing Urdu, emoji and newlines, and
      verify the composer clears and queued counts increase. Receiver gets none.
- [ ] Restart the sender; queued text/counts persist. Reconnect, confirm only one
      phone, and verify nothing sends. Confirm the second: each message arrives
      once, in queue order, and changes to delivered.
- [ ] Queue for two peers; verify only the connected identity receives its queue.
      Repeat with an archived chat and while viewing a different conversation.
- [ ] Cancel a queued message, first declining and then confirming; it stays
      absent after restart/reconnect and is never received.
- [ ] Interrupt delivery before its acknowledgement (timing is hardware
      dependent). Verify attempted text becomes unconfirmed and reconnecting
      alone does not resend it. Explicit Retry preserves its ID and, if already
      stored by the receiver, creates no duplicate or extra unread badge.
- [ ] Lock/background before queued delivery starts; new outgoing attempts wait
      for foreground/unlock. Check fresh verification after any lost connection.
- [ ] Use disposable data to delete a queued conversation/all history; it must
      not reappear or send after reconnect.
- [ ] Export queued messages and import on a destination: new pending records
      show unconfirmed, and reconnect does not send them until explicit Retry.
- [ ] Check Retry/Cancel dialogs at enlarged text with a keyboard and both themes.

Automated protocol, SQLite and widget checks are recorded in
[VALIDATION.md](VALIDATION.md). Physical Wi-Fi Direct/lifecycle tests remain
pending; the user handles staging, committing and pushing after testing.
