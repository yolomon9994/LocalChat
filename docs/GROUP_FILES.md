# Files in hosted nearby groups

Implemented: 2026-10-12. Final automated results are recorded in
[VALIDATION.md](VALIDATION.md). Physical three-phone checks remain pending.
The user handles staging, committing and pushing.

## Send and save

1. Update every member's app. Create/join the group and compare the full security
   code on each host–guest pair; both phones must confirm before admission.
2. Open the active group and tap **Attach group file**. Choose a local document,
   review its name, size and recipient count, then **Send file** or **Discard**.
   Composer text is preserved. File contents are opaque; the app does not open,
   execute, extract or convert received files.
3. Keep participating apps unlocked and foregrounded. Guests upload to the host;
   the host saves the complete file before relaying to other members. The host
   can read files as it can group text and images. Send one group file at a time.
4. Progress names the member and direction. The author's bubble shows individual
   receipts; **Received** means a complete file was saved on that phone, without
   proving the person read it. A failed member does not make every receipt fail.
5. Saved file bubbles show the sanitized filename and size. **Save to phone**
   works offline after confirmation. Choose a local folder in the system picker.
   The exported copy is outside LocalChat's app lock and chat encryption. Export
   may finish if the app locks while that authorized system picker is open.

Files are enabled only when all admitted members support `group-file-v1`.
Older image-capable builds can still use text and images; update and reconnect
them to enable files. New members receive no old attachments. Browser builds
can save files from imported demo group history, but have no real group network.

## Limits and interruptions

- Files must be nonempty and at most **8 MiB**. Filenames are canonicalized to
  at most 120 Unicode code points; separators, control/bidi characters and unsafe
  punctuation are replaced, with leading/trailing dots/spaces removed. Names
  never become filesystem paths. MIME is `application/octet-stream`.
- One outgoing file per author and one incoming/outgoing file per host–guest
  link. Images have separate transfer state, sharing the same serialized encrypted
  session. A busy file relay link is marked unconfirmed rather than queuing work.
- Transfers use 12 KiB acknowledged chunks, exact sequence/length/SHA-256 checks
  and 30-second stage inactivity limits. After the host receipt, a guest author
  waits up to 30 seconds for other receipts. Later valid completion can update
  unconfirmed status; no group text receipt can bypass file completion at the host.
- **Cancel file transfers**, lock, background, disconnect and membership changes
  stop active transfers and discard incomplete incoming bytes. Confirmed receipts
  and complete saved copies remain. An author who backgrounds after its upload
  asks the host to stop unfinished relays; it cannot recall existing copies.
- No automatic retry/resume/outbox exists. Review membership and select/send
  again explicitly. A fresh ID can produce another copy for members who received
  the earlier attempt. New connections require fresh security confirmation.
- A picker returning while locked retains an encrypted selection, including its
  name, in memory. Unlock and explicitly review/send. Leaving, deleting or changing
  membership invalidates pending selections and late picker returns.
- Each group's saved **images and files combined** are capped at **16 MiB**, plus
  the existing 10,000-message limit. Export/delete a full group before continuing.
  The separate 20 MiB plaintext backup limit includes base64 expansion and all
  history/direct attachments, so exports can reach that limit sooner. Oversized
  exports fail without changing source history.

## Protocol, storage and backups

`group_attachments.dart` shares the image/file room binding, host relay, receipts,
membership and privacy handling. `GroupImages` and `GroupFiles` retain separate
pickers and transfer states. Each link uses the existing `AttachmentTransfers`
engine and encrypted session counters; native transport and permissions are unchanged.

Authors sign `LocalChat/group-file/1`, group/host/epoch/membership revision, ID,
author/name, timestamp, generic File text, canonical name/MIME/length/SHA-256 and
sorted recipients. Existing text/image signature bytes are unchanged. Receivers
verify signed metadata, current room/roster and exact recipients; the host also
binds the upload author to the verified link.

`groupFileOffer/Ready/Chunk/ChunkAck/Complete/Result/Cancel`, receipt status and
author abort travel inside per-link encrypted frames. The host persists uploads
before forwarding and recipients persist before final receipts. Signed authors
prevent metadata substitution; the trusted host can still withhold files or lie
about membership/receipts.

Complete file bytes are inline in the existing authenticated encrypted group
record, alongside images and receipts. SQLite schema remains 9 and uses existing
group-history AAD; old direct/group records and messaging identity remain intact.
Group history deletion also removes its attachments. Previews/notifications say
**File**, keeping filenames out of those surfaces. App lock removes export dialogs.
Managed-memory clearing is not guaranteed forensic erasure.

Archives containing group files use payload **v6**, with v1–v5 imports retained.
Mixed direct/group text, images and files are supported. Imports validate names,
digests, author signatures and group bounds, merge duplicates/read state, re-encrypt
locally and never start sends. Imported pending receipts become unconfirmed.
Older builds reject v6. The encrypted envelope/KDF and 20 MiB archive limit remain
unchanged. A failed group write rolls back the whole import. See [BACKUPS.md](BACKUPS.md).

## Three-phone checks — pending

Use one host and two guests with Internet/router disconnected. Record models,
Android versions, provider names, throughput and outcomes.

- [ ] Compare codes and send host and guest documents. Confirm original bytes,
  safe names, author/member progress, individual receipts and text interleaving.
  Try image/file transfers together; check controls remain responsive.
- [ ] Try PDF/ZIP/Unicode/long names, local providers, empty/oversized sources,
  cancellations, large text and small screens. Discard preserves composer text.
- [ ] Lock/background each role during upload and relay, and the author after
  host storage. Cancel, disable Wi-Fi and close the host. Check incomplete bytes
  disappear, complete copies remain and unlocking never resumes automatically.
- [ ] Add/remove/leave/rehost while transferring. Check cancellation, preserved
  received receipts, fresh codes and no old files for newcomers. Review members
  before explicit resend and expect possible duplicate copies under a new ID.
- [ ] Connect an older image build: text/images work, files stay disabled. Update
  and reconnect it. Confirm a failed recipient never claims received.
- [ ] Restart/open offline history and save with confirmation; test Cancel,
  locked dialogs and provider write failures. Verify output bytes in a local folder.
  Test locking while the authorized system save picker is already open.
- [ ] Check generic list/notification previews, unread badges and taps waiting
  for PIN. Delete one group versus all history, preserving other local chats.
- [ ] Export/import mixed attachments, repeat for dedupe/read state, and test
  history-only versus identity migration to an empty phone. Test size-limit errors.
- [ ] Record host memory/storage, battery and multi-recipient throughput. Hardware
  capacity and group background protection remain unvalidated/later work.
