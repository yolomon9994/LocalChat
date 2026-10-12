# Encrypted chat backups

Implemented: 2026-10-11. Open **Settings → Chat backups**.

## Export

1. Choose a separate password of at least 12 characters, and confirm it.
2. Tap **Export encrypted backup**. Password derivation may take a few seconds.
3. Save the `.lcbackup` file using Android's system picker. Choose a local folder,
   such as Downloads, to keep the whole process offline.
4. Transfer the file to the other phone by USB, nearby file transfer or other
   offline means. Keep the password separately; there is no password recovery.

The file includes all saved chats, messages, read/delivery state, drafts, pin and
archive choices, and the private messaging identity. Anyone who has both the
file and password can read the archive and use that identity. The archive does
not contain the destination's history key, app PIN, biometric or theme settings.
The source display name is shown in the preview; the destination name is kept.
Hosted group history, signed authors, receipts and read state are included too.
Archives containing groups use payload version 2; current builds also import
version 1, while older builds reject group archives. Group sessions/keys are never
restored, and imported pending receipts become unconfirmed. Import ends the current
group. See [GROUP_CHATS.md](GROUP_CHATS.md) for group merge and host identity rules.
Archives containing direct-chat images use payload version 3, including bounded
image bytes, dimensions and SHA-256 digest. New builds import v1/v2/v3/v4; older
builds reject image archives. Images are re-encrypted with destination history
keys and restored pending attempts remain unconfirmed. The 20 MiB total archive
limit still applies; image-heavy exports can exceed it without changing history.
See [IMAGE_SHARING.md](IMAGE_SHARING.md).
Archives containing direct-chat files use payload version 4 with sanitized
filenames, bounded bytes and SHA-256 digests. Images and groups can coexist in
the same archive. Builds without file support reject these archives. Imports
re-encrypt file metadata/bytes atomically and never send them automatically.
The same 20 MiB total limit applies, including base64 attachment data; large
attachments can exhaust it. Source history stays intact after an oversized export.
See [FILE_SHARING.md](FILE_SHARING.md).
Export does not delete or change source history. Failed draft saves/loads must
be resolved before export so the backup does not silently omit unsaved edits.

## Import and phone migration

1. Tap **Choose backup file**, select the transferred file, and enter its password.
2. Tap **Preview import**. A wrong password or damaged file leaves history intact.
3. Review the source, total counts and proposed additions, duplicates/conflicts.
4. Choose the identity option, then press the final import button:
   - **Import history** keeps this phone's current messaging identity.
   - **Transfer messaging identity** is available only when this phone has no
     saved direct/group chats, messages or drafts. It transfers the source identity and stops
     nearby advertising/connections. Stop using LocalChat on the old phone after
     moving; do not run both phones with the same identity. Open Nearby and tap
     Go nearby on the new phone. Existing peers recognize its identity, but both
     phones must compare the fresh security code again.
5. Reopen chats and archived chats to check history, unread state and drafts.

If app lock is enabled, Android's picker can lock the app. Unlock and return to
**Settings → Chat backups**; the selected encrypted file is retained in memory.
Enter its password again. Password fields and decrypted previews are cleared
when backgrounded or when their route closes. Discard selection removes the
retained file. App restart requires selecting the file again. An import already
confirmed can finish while the UI is hidden; it is a single database transaction.

## Merge rules

- Dedupe by peer ID, message ID and outgoing/incoming direction. Matching text
  and timestamp count as a duplicate; differing text/timestamp count as a conflict.
  Image/file metadata and bytes must also match for a duplicate. Existing message content,
  timestamp, read state and status always win.
- Existing chat names and pin/archive choices win. New chats inherit the archive
  choices. New message activity can advance a chat; duplicate-only imports do not.
- Fill empty/missing drafts; retain existing nonempty drafts. Newer local edits
  made while import is working take precedence over imported draft text.
- Imported `sending` or `queued` becomes `unconfirmed`; import never sends messages or
  invents delivery acknowledgements. Incoming unread state is retained.
  Use explicit Retry for newly restored pending messages. Older app builds reject
  queued status in a backup, so update before importing these files.
- Imported bodies get fresh ciphertext under the destination's existing history
  key. Locks, themes, display name and the source phone's data are preserved.
- Preview counts are recalculated at commit, to account for incoming messages.
  A database failure rolls back the entire merge. Identity migration uses a
  secure-storage journal and SQLite commit receipt so restart resolves an
  interrupted switch. A final vault failure blocks nearby messaging and asks
  for restart; the committed history remains recoverable.

## Format and limits

Version 1: `LCBACKUP` (8 bytes), version byte `1`, salt (16), nonce (24),
authentication tag (16), then ciphertext. The magic/version/salt are authenticated
as AAD. PBKDF2-HMAC-SHA256 uses 600,000 iterations and a 256-bit key;
XChaCha20-Poly1305 encrypts the UTF-8 JSON payload. Each export has fresh salt
and nonce. No plaintext backup is written to a temporary file or logged.

The plaintext archive is capped at 20 MiB, with 65 additional envelope bytes;
maximum 5,000 chats, 100,000 messages, 5,000 drafts and 1 MiB per draft. Files,
versions, identity/seed consistency, fields, lengths, references and duplicate
record keys are validated before import. The native reader caps bytes before
decryption. Passwords are exact, untrimmed text: at least 12 Unicode code points
and at most 1,024 UTF-8 bytes. Password guessing remains possible offline;
choose a strong password. This prototype has not had an independent audit.

Passwords and decoded data can exist transiently in managed memory; clearing
fields/references does not promise forensic erasure. Existing app-lock limits
still apply. Backup files contain sensitive identity material and `.gitignore`
excludes `*.lcbackup` to avoid accidental commits.

Browser demo export downloads a file; import selects it locally. Demo and native
phone backups cannot be mixed. Demo imports remain in memory and reset on reload.
Native code uses Android's [Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)
without broad storage permissions. Browser file APIs use
[`package:web`](https://dart.dev/web/libraries).

## Physical phone checklist

- [ ] Export messages in both directions, emoji/Urdu, multiline drafts, unread
      messages, pinned chats and archived chats. Confirm source data is unchanged.
- [ ] Cancel the save and open pickers; neither action changes history.
- [ ] Enable app lock, choose an import file, unlock, return to backups and
      preview with its password. Background during preview: secrets disappear.
- [ ] Wrong password, modified/truncated file and an unrelated file fail safely.
- [ ] Import history into a phone with existing chats/drafts. Existing data wins;
      new chats/messages appear; a repeat import adds no duplicates.
- [ ] Restart Android after import and check text, flags, unread counts and drafts.
- [ ] Move identity to an empty new phone. Stop the old phone, reconnect the new
      phone to an existing peer, compare fresh codes and exchange text both ways.
- [ ] Confirm identity transfer is unavailable when destination history exists.
- [ ] Test airplane mode with Wi-Fi enabled and local file transfer; no Internet
      service is needed. Check at 320-wide layout and enlarged system text.

Automated checks and builds are recorded in [VALIDATION.md](VALIDATION.md).
Physical phone/file-provider/Android Keystore checks remain pending. The user
committed the backup milestone as `63eff9f`.
