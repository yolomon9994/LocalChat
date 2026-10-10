# Saved message drafts

Open any saved conversation and type a message. The composer remembers each
chat's unfinished text separately, including whitespace, newlines and emoji.
You can write a draft while offline; Send is enabled only for the connected,
verified peer. Reconnecting still requires comparing the security code.

On Android, draft bodies are encrypted with the chat-history key and restored
after navigation, locking/unlocking and normal app restarts. Browser Demo uses
temporary memory, so reloading the tab loses drafts along with demo history.

Each edit schedules a save immediately. Rapid edits waiting in the queue are
coalesced to the latest text; the most recent in-flight edit may be lost if the
process is killed before its write finishes. A failed save keeps the text in
the current app session and shows a Retry action. A failed load disables the
composer until retried so an unreadable saved draft cannot be overwritten.

After a successful transport write, the captured draft is cleared even if you
have left the chat. Newer edits and other chats' drafts are preserved. Invalid
or failed sends keep their draft. Transport acceptance is separate from the
delivery acknowledgement: an unconfirmed message may already have arrived.
There is no automatic resend or offline outbox.

Erasing the composer removes that chat's draft. Settings → Delete all chat
history also removes all drafts and clears any open composer, while keeping
your identity and appearance/app-lock settings. Drafts do not change chat
ordering or unread counts and are excluded from message search.
Deleting history also deselects an offline conversation; reconnect to start a
new chat. An existing connected session can continue with an empty composer.

## Phone checklist

- [ ] Install the new APK as an update; existing messages and unread badges remain.
- [ ] Type a draft with newlines, surrounding spaces, emoji and non-Latin text.
      Go Back, reopen the chat and check that the text is unchanged.
- [ ] Create distinct drafts for two peers. Switching chats restores the right one.
- [ ] Disconnect, reopen saved history and edit its draft; Send stays disabled.
- [ ] Leave the app, unlock it if needed and reopen the chat. The draft returns
      and no composer text appears on the lock screen.
- [ ] Wait briefly for persistence, close/restart the app and check both drafts.
      Android restoration uses the same peer identity, not its advertised name.
- [ ] Reconnect and compare codes. The draft stays hidden during verification
      and returns afterward; sending clears it and keeps other chats' drafts.
- [ ] Send and immediately go Back. Reopening the chat shows an empty composer
      after a successful send, with the outgoing message in history.
- [ ] A rejected message (for example 1400 `界` characters exceeding the 4096-byte
      send limit) keeps the draft; shorten it and retry successfully.
- [ ] If a write fails during a disconnect, the draft stays. Inspect unconfirmed
      history before manually retrying because the message may already have arrived.
- [ ] Erase a draft, restart and confirm it stays empty. Delete all history only
      with disposable test data, then confirm all messages and drafts are gone.
- [ ] Check multiline drafts with a keyboard, enlarged text and light/dark themes.
- [ ] Browser Demo restores drafts during navigation but resets them on reload.

## Implementation and automated checks

`LocalStore` schema 3 adds `drafts(peer, body)`. Draft bodies use
XChaCha20-Poly1305 with fresh nonces, the existing secure-storage history key,
and AAD `JSON(["LocalChat/draft/1", peer])`. Database upgrades from versions
1 and 2 preserve messages, identity and read state. No new dependency, wire
payload or native Android change is needed.

`DraftController` belongs to `ChatController` so queued writes survive route
disposal. Its queue is separate from protocol work. Editing revisions protect
newer text from send cleanup; a deletion generation prevents pending older
edits from resurrecting erased drafts. Load/save errors are generic and
retryable. Plaintext can remain in controller memory under the existing lock
model; draft encryption does not add PIN-bound encryption or forensic deletion.

Tests cover encrypted SQLite persistence/reopening, authentication and peer
binding, version-1/2 upgrades, per-peer restoration, failed load/save/delete,
retry, pending writes, disposal, newer edits during sends, wrong-peer prevention,
failed/invalid sends, navigation, locking, history deletion, leaving during a
send and a 320 × 568 layout with enlarged text and keyboard insets.
