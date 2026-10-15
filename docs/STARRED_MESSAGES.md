# Starred messages

Implemented 2026-10-15. Stars are private local bookmarks for saved direct and
group messages, including replies, images and files. They are never sent to peers
and do not require a protocol update on another phone.

## Controls

- Long press a message bubble, or right-click it in the browser, and choose Star.
  A small star marks the bubble. Repeat and choose Unstar to remove the bookmark.
- Text selection menus include Star/Unstar alongside Reply and Copy. Screen
  readers have Star message/Unstar message actions. Attachments have a star-only
  message menu and retain their existing viewing/saving controls.
- From the Chats toolbar, open Starred messages. This combines saved direct and
  group messages, including archived chats, newest message first. Text and file
  names are shortened in the list; images have an Image label.
- Tap a row to open the original conversation at that exact message. Direct IDs
  include direction; group IDs include author identity. Existing lazy history
  anchors and Jump to latest work as before. Viewing a conversation applies its
  normal read behavior. Browsing or unstarring from the saved list does not mark
  its conversations read.
- The row's star button removes the bookmark without opening the conversation.
  Stars do not change drafts, quotes, pin/archive choices, activity or delivery
  receipts. Starring an outgoing queued message does not change its send status.

## Persistence, imports and deletion

Android stores encrypted bookmark references in SQLite schema 13's message_stars
table. Each row uses a history-key HMAC of the canonical reference as its ID and
XChaCha20-Poly1305 ciphertext with LocalChat/star/1/<row-id> AAD. The reference
contains the conversation/group ID, message ID and direction/author; message
bodies and attachments remain in their existing encrypted history. Migration
creates the table without rewriting old messages, drafts or group ciphertext.
Row count and ciphertext lengths remain visible database metadata.

Browser stars are in-memory demo data and reset on reload, like demo history.
No native code, permissions, dependencies or wire formats change.

Archives with stars use payload v10; exports without stars keep their applicable
v1-v9 version. New builds accept v1-v10; older builds reject v10. The encrypted
file envelope, password KDF and size bounds are unchanged. Validation rejects
duplicate, malformed or dangling references and limits stars to 5,000.

History-only import keeps the destination identity; identity transfer still
requires an empty destination phone. Stars are re-encrypted with the destination
history key, alongside the existing transactional import. The preview and success
notice report how many stars will be added. Existing stars are kept, and source
stars are added only for imported or identical existing originals. Conflicting
direct bodies/quotes/attachments or group signatures/hosts never inherit a source
star. Old archives have no unstar tombstones: re-importing an older archive can
restore a star removed locally after that export. The backup screen explains this.

Deleting a conversation/group, cancelling a queued message, or clearing all
history removes its stars in the same SQLite transaction. A cleanup failure rolls
back the corresponding deletion. A star cannot recreate a deleted conversation.
Receipts, read updates, imports and group history saves do not overwrite stars.

## Privacy and errors

Actions require an initialized, foreground, unlocked app and the current route.
Menu and saved-list callbacks captured before background/lock are rejected after
return. Queued controller actions recheck the interaction revision before writes.
An already-authorized storage transaction can finish if the app locks during it;
late completions cannot navigate or expose message content in feedback.

The saved list immediately clears decrypted rows on background/access loss and
discards delayed loads. PIN locking replaces pushed routes as before. Generic
load/write/open errors expose no message bodies or platform exception details;
load errors offer Retry. Reference reloads coalesce and reject stale results so
an older read cannot restore an unstarred cache entry.

## Automated and manual validation

Commands, outcomes and development corrections are recorded in VALIDATION.md.
New tests cover model bounds/scope, demo state, v10 codec/import/identity behavior,
conflicts, deletion, cache races, stale queued actions, generic errors, actual
SQLite migration/reopen/encryption/authentication/rollback, menus, exact anchors,
mixed archived history, file/image controls, PIN/background and enlarged text.

Manual checks still to run:

- On Android, star text, a reply, an image and a file in direct and group chats;
  navigate away, restart the app, and check the saved list and original anchors.
- Check a received and sent direct message with similar content, archived groups,
  draft preservation, Jump to latest, unstar, queued cancellation and deletion.
- Export a password-protected backup; test history-only import and identity
  transfer to an empty phone, including retained destination stars and an older
  backup restoring a previously removed source star.
- Background/lock with a menu/list open; unlock and verify content/action privacy.
  Check TalkBack actions, large fonts, dark/light palettes and attachment controls.
- In a real browser, check right-click and text selection menus, group demo stars,
  list navigation and demo reset on reload. Automated browser checks use simulated
  transports; they do not prove Android hardware or assistive-technology behavior.
