# Direct-chat file sharing

Implemented: 2026-10-12. All 228 automated tests pass, analysis is clean, and
final Android/browser builds pass. Physical phone checks remain pending.
Changes remain local and uncommitted; the user handles Git.

## Controls and limits

- Update both phones, connect and confirm the fresh code on both.
- Tap **Attach file** in the chat toolbar. Pick a local document, review its
  sanitized name and size, then explicitly choose **Send file** or **Discard**.
- Files must be nonempty and at most **8 MiB**. Contents are transferred exactly;
  embedded document metadata is retained. Files are not rendered or executed.
- Both phones must remain unlocked and in the foreground. Progress, cancellation,
  30-second inactivity timeouts and explicit original-ID retries follow images.
- Lock/background/disconnect/cancel discard partial incoming contents and mark
  saved outgoing attempts unconfirmed. An already started receiver commit may
  finish. No file outbox, background transfer or automatic resume.
- A picker result returning while locked stays encrypted in process memory,
  including its filename. Unlock and open the intended chat to **Review file**.
  Deleting that chat invalidates late picker results. Text drafts are preserved.
- Received files are accepted automatically from the verified available peer.
  A complete validated database commit is required before a delivery receipt.
- **Save to phone** works offline on saved messages and asks for confirmation.
  Choose a local destination in Android's system picker. This explicit export
  creates a copy outside LocalChat's encryption and app lock; it may complete
  while the picker backgrounds/locks the app. Cancelling leaves chat history intact.
- Browser selection/downloads use local file APIs. The recipient and receipts
  are simulated; reload clears demo history. Native picker/provider behavior is
  not covered by the browser simulation.
- Files are direct-chat only. Group attachments remain planned.

## Implementation

`ChatFile` binds sanitized filename, byte length and SHA-256 digest. MIME is fixed
to `application/octet-stream`; a filename never becomes a filesystem path.
Android uses local-only `ACTION_OPEN_DOCUMENT` / `ACTION_CREATE_DOCUMENT` and
bounded reads, with no new storage permissions or dependencies.

`AttachmentTransfers` is the shared image/file stop-and-wait engine. Existing
`image-v1` frames retain their format; encrypted `verified` adds `file-v1`.
`fileOffer`, `fileReady`, `fileChunk`, `fileChunkAck`, `fileComplete`, `fileResult`
and `fileCancel` use the existing authenticated session and counters. Chunks are
12,288 bytes, with one outstanding chunk per transfer and encrypted frames under
65,536 bytes. Exact order/length, digest and filename bounds are checked. One
outgoing attachment/picker is allowed across kinds; each kind bounds one incoming
transfer. Malformed frames close the connection. Older peers keep text/image
support according to their negotiated capabilities.

Schema **9** adds a `files` table. Message metadata and bytes commit atomically
under the history key, with separate authenticated namespaces:
`LocalChat/file-message/1/<peer>/<id>/<direction>` and
`LocalChat/file/1/<peer>/<id>/<direction>`. Existing text/image/group ciphertext
and identity are preserved. Kind/peer/ID/direction and timestamps/status remain
plaintext, as before. Search excludes file bodies; list/notification previews
say **File**. Deletion removes local rows transactionally, not exported copies.

Archives containing files use payload **v4**, including validated bytes/metadata.
Imports retain v1/v2/v3 compatibility, re-encrypt destination records, deduplicate
matching attachments and never schedule transfers. Existing content wins on
conflict. The encrypted envelope/KDF and **20 MiB total archive limit** remain;
base64 attachments consume that budget. Oversized exports fail without changing
history. Transient plaintext buffers exist in managed/native memory; this does
not promise forensic erasure.

## Pending physical checks

- [ ] Record both phone models and Android versions; disconnect Internet/router.
- [ ] Verify and send PDF, text, binary and Unicode-named files both ways.
      Save locally and compare their bytes/hash with the source.
- [ ] Cancel picker, preview and save dialog; confirm no unintended transmission.
- [ ] With app lock enabled, pick a file, unlock, review and explicitly send.
- [ ] Send a multi-chunk file alongside text; check progress and delivered status.
- [ ] Cancel, background/lock each phone, disable Wi-Fi or disconnect mid-transfer;
      confirm no partial saved incoming message or automatic resume.
- [ ] Reconnect/verify and retry using the original ID; retained receiver history
      should produce no duplicate message or extra unread alert.
- [ ] Restart and save a file offline; test read counts, pin/archive, deletion,
      privacy, small screens and enlarged text.
- [ ] Try empty/oversized files, local document providers, cancelled/unwritable
      save destinations and safe filename handling.
- [ ] Export/import mixed text/images/files/groups; repeat import for dedupe.
      Check the archive limit leaves source history intact.
- [ ] Test an older image-capable peer: text/images still work and files are disabled.

Automated outcomes: [VALIDATION.md](VALIDATION.md).
Android API reference: [Access documents and other files](https://developer.android.com/training/data-storage/shared/documents-files?hl=en).
