# Image sharing in direct chats

Implemented: 2026-10-12. Update both phones, connect in Nearby and compare/confirm
the fresh code on both. This milestone covers one-to-one images; group attachments
remain planned. Other direct-chat files are covered in [FILE_SHARING.md](FILE_SHARING.md).

## Send and view

1. Tap **Attach image** beside the composer in a verified chat. Choose a local
   image in Android's document picker; no gallery-wide permission is requested.
2. Review it and choose **Send image** or **Discard**. If the picker locks the
   app, unlock, reopen the intended chat and choose **Review image**. The prepared
   selection stays encrypted in process memory until sent/discarded/app closure.
   Selecting an image never sends automatically.
3. Keep both apps unlocked and foregrounded. The recipient automatically accepts
   a bounded image from its verified peer while available. Progress counts
   acknowledged bytes; **delivered** requires complete receiver storage.
4. Tap an image bubble to open the zoomable viewer. Saved images open offline.
   Unread counts, pin/archive, notifications and deletion apply. List/notification
   previews say “Image”; notifications contain no picture. Text drafts are kept
   when attaching an image. Message search searches text.

## Limits and interruption

- Source files: at most 8 MiB and 40 megapixels. Supported Flutter formats are
  decoded, resized to at most 1600 pixels per side and re-encoded as PNG, removing
  source metadata. Animated inputs send only the first frame.
- Prepared images: at most 2 MiB. Choose a smaller image if PNG preparation is
  too large. There is no quality slider or camera capture in this version.
- One incoming and one outgoing transfer at a time, with 12,288-byte chunks and
  one outstanding acknowledged chunk per direction. Text can interleave. Each
  stage times out after 30 seconds without progress.
- **Cancel image transfer**, lock, background or disconnect discard partial
  incoming data and leave outgoing attempts **unconfirmed**. An already running
  receiver commit can finish; the image may have arrived. There is no image
  background transfer, offline outbox or automatic resume.
- **Send image again** explicitly retries after verification using the original
  ID/content/time. Identical retained receiver history prevents duplicates and
  extra unread counts. Deleted history removes that protection. Receipt loss
  does not prove nondelivery.
- Older peers omit the encrypted `image-v1` capability. Text still works and the
  attachment button remains unavailable. Update both phones for images.

## Wire, storage and backups

The signed handshake, two confirmations, directional keys and strict counters
are unchanged. Encrypted `verified` advertises `image-v1`. `imageOffer`,
`imageReady`, `imageChunk`, `imageChunkAck`, `imageComplete`, `imageResult` and
`imageCancel` remain inside authenticated frames under the 65,536-byte bound.
Offers bind ID, timestamp, PNG dimensions, length and SHA-256 digest. Exact chunk
order/length, hash, pixel bounds and decoding are checked before receiving commits.
Malformed frames close the connection. Receipts apply only to the current image
attempt. A verified peer can send unwanted images or share received copies.

Schema 8 adds `messages.kind` and an `images` table. Bytes and metadata use the
history key with XChaCha20-Poly1305 and separate AAD namespaces:
`LocalChat/image/1/<peer>/<id>/<direction>` and
`LocalChat/image-message/1/<peer>/<id>/<direction>`. Metadata/message and bytes
commit together. Existing text/group ciphertext and identity are preserved.
Kind, peer/ID/direction and normal timestamp/status metadata remain plaintext.
Chat/all-history deletion removes image rows transactionally; it does not erase
the other phone or guarantee forensic deletion.

Image archives use payload version 3 with validated inline bytes/metadata/digest.
New builds import versions 1, 2, 3 and 4; older builds reject image archives. The
encrypted envelope/KDF and total 20 MiB archive bound are unchanged, so images
reduce how much history fits in an export. Imports re-encrypt with destination
keys and use existing duplicate/conflict rules. Imported sending attempts become
unconfirmed and never transfer automatically. Oversized exports fail without
changing source history.

Displayed/source pixels exist transiently in managed memory. App lock removes
image routes; viewer cache entries are evicted on disposal. Clearing references
does not promise memory zeroization. Browser demo supports local selection and
simulated receipt; no image reaches a phone and reload clears demo history.
No dependencies were added.

## Physical two-phone checklist

Pending: record phone models, Android versions and outcomes.

- [ ] With mobile data off/no router, verify and send PNG/JPEG both ways. Check
  orientation, colors/transparency, zoom and delivery status.
- [ ] Cancel picker/preview: nothing sends. Attach while keeping a text draft.
- [ ] With app lock enabled, choose an image, unlock, reopen the intended chat,
  review and explicitly send; picker return never transmits on its own.
- [ ] Send a multi-chunk image alongside text. Check responsive progress/cancel.
- [ ] Cancel, lock/background each phone, disconnect and disable Wi-Fi during
  transfer. No partial incoming record or automatic resume should appear.
- [ ] Reconnect/verify and retry. Retained duplicate history creates no extra
  bubble/unread count. Record lost-receipt behavior.
- [ ] Restart and view offline; archive/pin, zoom and lock. Delete a chat/all
  history and confirm image records are removed.
- [ ] Try oversized/corrupt/non-image sources. Check 320-wide screens/enlarged text.
- [ ] Export/import images with text/groups and repeat for dedupe. Check restored
  pictures and archive-size errors preserving source history.
- [ ] An older text-only build still exchanges text and disables images.
- [ ] Test Android 7–12, 13 and 14+, local providers and battery/connection behavior.
  Direct background protection does not resume images.

References: [Android document picker](https://developer.android.com/guide/topics/providers/document-provider),
[Flutter image decoding](https://api.flutter.dev/flutter/dart-ui/instantiateImageCodec.html)
and [PNG encoding](https://api.flutter.dev/flutter/dart-ui/Image/toByteData.html).
Results are in [VALIDATION.md](VALIDATION.md). The user handles Git.
