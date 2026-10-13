# Saved group drafts

Implemented: 2026-10-12. Open any saved group and type unfinished text. Each
group remembers its own draft, including spaces, newlines, emoji and other
scripts. You can edit while offline; sending still requires the active group
and verified members. Drafts never send automatically when you reconnect.

On Android, drafts restore after leaving/reopening a group, locking/unlocking,
and normal app restarts. Rehosting the same group keeps its draft. Browser demo
storage is temporary memory and is lost on reload.

Each edit schedules a local save. Queued rapid edits coalesce to the latest
text. A process killed before a write completes can lose the last in-flight
edit. A failed save keeps the text in the current session and shows **Retry
draft**; resolve the error before exporting/importing a backup. A failed load
disables editing until retry succeeds, protecting an unreadable saved draft.

Sending clears only the captured, unchanged draft, in the same transaction as
the outgoing message. Newer edits survive. Validation, access or storage failures
keep the draft. Once the message is saved, transport/receipt failures leave it
unconfirmed in history; they do not recreate a draft or prove non-delivery.
Attaching, reviewing, discarding or sending an image/file preserves text drafts.

Erasing the composer removes that draft. Confirmed group-history deletion removes
its draft as well; Delete all chat history removes direct and group drafts.
Other groups and same-ID direct chats remain separate. Drafts do not change
message previews, unread counts, chat ordering or message search.

## Storage and backups

SQLite schema **10** adds `group_drafts(id, body)` without rewriting existing
history. Bodies use the history key and XChaCha20-Poly1305; authenticated data is
UTF-8 JSON `["LocalChat/group-draft/1", groupId]`. IDs remain visible as metadata.
Drafts are capped at 1 MiB UTF-8; the composer allows 4096 characters and sending
retains the group protocol's 4096-byte limit.

One application draft queue orders direct/group writes, deletion, atomic send
cleanup and backups. Draft revisions preserve edits made while a send/import is
in progress. Storage failures roll back message acceptance, deletion and mixed
imports. Direct drafts retain their existing table and authentication domain.

Archives with nonempty group drafts use payload **v7**, with `groupDrafts` rows
containing `group` and exact `text`. Current builds import v1-v8; older builds
reject v7. Every imported draft must reference a validated group, with no duplicate
IDs, empty text or oversized body. Existing nonempty destination drafts win.
An absent draft can import even when no new group messages are added. A group ID
owned by a conflicting host receives neither that host's history nor draft.

Both history-only imports and identity transfer to an empty destination include
group drafts. Imported drafts never send or restore sessions. The encrypted file
envelope, password derivation and 20 MiB archive limit remain unchanged. See
[BACKUPS.md](BACKUPS.md) and automated results in [VALIDATION.md](VALIDATION.md).

Pinning/archiving groups preserves their drafts. Group organization adds schema
11 metadata columns; archives with group choices select v8. Current builds import
v1-v8. See [GROUP_MANAGEMENT.md](GROUP_MANAGEMENT.md).

## Phone checklist

Physical checks are pending; automated tests do not establish hardware results.

- [ ] Install the updated APK over the current app; existing direct/group history,
      attachments, drafts, identity and settings remain intact.
- [ ] Type spaces, newlines, emoji and non-Latin text in two groups and a direct
      chat. Leave/reopen each; check the exact text and independent drafts.
- [ ] Disconnect and edit an offline group draft. Send stays disabled. Rejoin and
      compare fresh codes; the draft stays until you explicitly send it.
- [ ] Lock while a group composer is open. Its text disappears behind PIN. Unlock
      and reopen it; check the draft. Restart the app after a save and check again.
- [ ] Send valid text to a verified group; it appears once in history and the
      draft clears. Try empty/whitespace or oversized UTF-8 text; it remains.
- [ ] Type another message during a slow send; the new draft survives. Interrupt
      delivery after local acceptance; history shows uncertainty without a second
      copy returning to the composer.
- [ ] Pick/review/discard and send both an image and a file; text remains saved.
- [ ] Export/import a password-protected backup with group drafts and attachments.
      Check history-only identity preservation, local-draft precedence, and
      identity transfer to an empty new phone. Nothing sends automatically.
- [ ] Delete one group after confirming; only its history/draft disappears.
      Delete all history; both direct and group drafts disappear.
