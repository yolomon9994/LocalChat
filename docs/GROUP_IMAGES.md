# Images in hosted nearby groups

Implemented: 2026-10-12. Automated results are recorded in
[VALIDATION.md](VALIDATION.md). Physical three-phone checks remain pending.
The user handles staging, committing and pushing.

## Send and view

1. Update every member's app. Create/join a group and compare the full security
   code on each host–guest pair. Both phones must confirm before admission.
2. Open the active group and tap **Attach group image**. Pick a local image,
   review the preview and recipient count, then choose **Send image** or
   **Discard**. Your composer text is preserved.
3. Keep the author, host and recipients unlocked and foregrounded. A guest uploads
   to the host; the host saves the complete image before forwarding it to the
   other members. The host can read the image, as it can group text.
4. Progress shows the member and direction for each active link. The author's
   message shows individual receipts. **Received** means a complete image was
   saved on that member's phone; it does not mean the person viewed it.
5. Tap a saved image to zoom, including offline. App lock covers group history,
   image previews and the viewer. Notifications and list previews say **Image**.

Image controls are disabled if any admitted member lacks `group-image-v1`
support. Text remains available. Update that member's app and verify a fresh
connection to enable group images. New members receive no previous history.
Browser builds can display imported demo group images, but do not simulate a
real host or group transfer.

## Limits and interruptions

- Source: at most 8 MiB and 40 megapixels. Preparation uses the first frame,
  resizes to at most 1600 pixels per side and re-encodes PNG without source
  metadata. Prepared PNG: at most 2 MiB. Camera capture is later work; group
  files are covered in [GROUP_FILES.md](GROUP_FILES.md).
- One outgoing image per author and one outgoing/incoming image per host–guest
  link. A busy relay link marks that recipient unconfirmed; it does not queue
  another image. Send one group image at a time for predictable delivery.
- Transfers use 12 KiB chunks, one acknowledgement at a time, with 30-second
  stage inactivity limits. The author also has a 30-second receipt wait after
  the host upload completes. A later valid receipt can update unconfirmed status.
- **Cancel image transfers**, lock, backgrounding, disconnect or membership
  changes stop active transfers and discard incomplete incoming bytes. Confirmed
  receipts stay received, and complete copies already saved remain on those
  phones. Backgrounding the author after its host upload also requests that the
  host stop unfinished relays. A disconnected author cannot recall existing copies.
- There is no automatic retry, resume or group outbox. Review the current member
  list and select/send again explicitly; that creates a new message ID and may
  create another copy for members who already received the first attempt.
- A picker returning while locked retains only an encrypted pending selection in
  memory. Unlock and explicitly review/send. Membership changes, leaving or
  deleting the group invalidate that selection and late picker results.
- Saved groups are bounded to 10,000 messages and 16 MiB of complete image/file bytes
  per group. Export and delete a full group before continuing. The backup's
  separate 20 MiB plaintext limit includes base64, direct attachments and history;
  an image-heavy group can exceed that archive limit before reaching its own cap.

## Protocol, storage and backups

Existing group text signatures stay compatible. Images use the separate
`LocalChat/group-image/1` signature domain, binding the group, host, room epoch,
membership revision, ID, author/name, timestamp, generic text, canonical PNG
metadata (dimensions, byte length, SHA-256) and sorted recipient identities.
The host binds an upload's author to its verified sending link. Receivers check
the current epoch, exact roster and metadata before accepting bounded chunks.

`group_attachments.dart` shares image/file relay, privacy and receipt handling;
the image wire format and signature domain remain compatible.
`groupImageOffer/Ready/Chunk/ChunkAck/Complete/Result/Cancel`, plus receipt-status
and author-abort messages, travel inside the existing per-link encrypted session.
The shared attachment engine checks order, length, digest and decoded pixels.
Completion receipts follow durable local storage. A group text receipt cannot
substitute for an image transfer completion. Author signatures prevent metadata
impersonation; the trusted host can still withhold images or misreport receipts.

Complete PNG bytes are inline inside the existing encrypted `group_history`
record with its existing history key/AAD. Schema remains 9; direct text, images,
files and old group records are preserved. Pending receipts become unconfirmed
after restarting. No packages, Android permissions or native transport changes
were needed. Cache eviction on locking is not guaranteed forensic memory erasure.

Archives with group images use payload **v5**, or **v6** when group files are
also present, or **v7** when group drafts are included. Current builds import v1-v8.
They can include direct text/images/files and groups together. Import validates
author signatures and PNG bytes, safely merges by group/author/ID, re-encrypts
locally and never starts transfers. Older builds reject v5. The encrypted file
envelope and password derivation remain unchanged. See [BACKUPS.md](BACKUPS.md).

Group drafts are saved independently; see [GROUP_DRAFTS.md](GROUP_DRAFTS.md).
Pinned/archived groups select payload v8; see [GROUP_MANAGEMENT.md](GROUP_MANAGEMENT.md).

## Three-phone checks — pending

Record phone models, Android versions and outcomes; use one host and two guests
with Internet/router disconnected. Automated protocol tests do not validate radios.

- [ ] Verify all three phones; send a host image and then a guest image. Confirm
  previews, direction/member progress, author labels and individual receipts.
  Send text during a transfer and check both message types remain usable.
- [ ] Use large/rotated/provider images, cancellation and rejected oversized
  sources. Check prepared dimensions, no source metadata, small screens and
  enlarged text. Discard a preview and confirm composer text remains.
- [ ] Lock/background each role during upload and relay, and the author after
  the host receipt. Check incomplete images disappear, complete copies remain,
  receipts are honest, and unlocking never resumes automatically.
- [ ] Cancel, disable Wi-Fi, leave/end hosting, remove/add a member and rehost.
  Check transfers stop, received receipts survive, fresh codes are needed and
  newcomers receive no old images. Manually resend after reviewing membership.
- [ ] Mix an older text-only group build: text works, image controls are disabled.
  Update and reconnect it. Check a failed recipient does not claim received.
- [ ] Restart and open saved images offline; zoom, rotate and lock the viewer.
  Check unread badges and generic locked/background notifications and tap routing.
- [ ] Export/import mixed group images/direct attachments, repeat for dedupe,
  test history-only and empty-phone identity migration, and delete one/all groups.
  Check oversized exports fail without changing source history.
- [ ] Record throughput, host memory/storage use, battery and provider/lifecycle
  interruptions. Group background-service protection remains future work.
