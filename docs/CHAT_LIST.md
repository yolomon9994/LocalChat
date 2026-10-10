# Chats list testing

Chats shows the latest locally saved message, with **You:** for outgoing text,
an activity timestamp and an unread badge. Long previews wrap to two lines and
truncate; line breaks collapse into spaces. Badges show up to **99+**, while
accessibility announces the full count. Empty conversations show **No messages yet**.

Chats with messages appear first, ordered by local time of the latest new
message save. Time labels show today's 24-hour time, Yesterday, or an older
date. A peer's clock cannot move a new arrival behind older messages within
its preview. Reconnection, name updates, acknowledgements, read marking and
duplicate message writes preserve the existing activity order.

Unread counts belong to incoming messages. They clear when the conversation
is visible, the app is in the foreground and unlocked, and history is readable.
Viewing Nearby or the Chats list, selecting a peer for connection, a covering
dialog, or the verification screen does not mark hidden messages as read.
New messages in the visible chat stay read. Reading another saved conversation
does not clear unread messages from the connected peer.

Android persists read state in SQLite. Upgrading from schema version 1 preserves
history and treats existing messages as read, since no earlier read state exists.
Previews use the encrypted message body; no extra plaintext preview is stored.
Read state is local metadata and does not change the sender's delivery status.
Browser Demo uses the same behavior with temporary memory storage.

## Phone checklist

Install the updated `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`
over your existing installation to test migration while keeping its history.
Use two connected, verified phones for new incoming messages.

- [ ] Existing history remains readable after updating. Its initial unread
      count is zero. Check previews, outgoing You prefixes and activity labels.
- [ ] On the receiving phone, leave the chat for Chats or Nearby. Send two
      messages from the other phone. The Chats row should show the latest
      preview and an unread count of two.
- [ ] Open that conversation. The unread count should clear; go back to Chats
      to check. A new incoming message while reading it should keep the count zero.
- [ ] Leave another message unread, close and reopen the app, and check that
      the unread badge and preview persist. Then open it to clear the count.
- [ ] If you have multiple conversations, send/receive a message in an older
      chat and check that it moves first. Reconnecting alone should preserve order.
- [ ] While reading a different saved chat, receive a message from the connected
      peer. Only the connected peer's unread count should increase.
- [ ] Enable app lock, then leave the app while a connection remains active.
      If a message arrives while locked, its badge should remain after unlocking
      to Chats. Open the conversation to clear it. Background receipt depends
      on Android keeping the connection alive.
- [ ] Reconnect with unread history. It should stay unread while comparing
      security codes; opening a chat and completing verification can then clear it.
- [ ] Try large Android text, a long friend name and a multiline message.
      Confirm the preview and badge remain usable in light and dark themes.
- [ ] Delete all chat history in Settings. Rows and unread counts should clear;
      a new incoming message should create a fresh row with correct read state.

## Automated coverage

Storage tests use real SQLite with secure-storage doubles: version-1 upgrade,
encrypted preview retrieval and tamper rejection, read persistence, peer/direction
scoping, duplicate handling and message-only ordering. Controller tests exchange
real encrypted protocol frames through an in-memory transport and exercise
foreground/access/route gates, queued-read races, verification and another peer's history.
Widget tests exercise opening/back, covering dialogs, backgrounding with lock
disabled, locking/unlocking, badge semantics, long previews and enlarged phone text.
These checks do not substitute for Android lifecycle and two-phone testing.
