# Private contact nicknames

Implemented locally: 2026-10-16. The user handles Git.

## Controls

Open a saved direct chat's **Chat options** in Chats, Archived chats or the
conversation toolbar. Choose **Set nickname** or **Edit nickname**, enter a name
and tap **Save**. **Remove nickname** or saving a blank field restores the latest
phone name. Cancel leaves the saved value unchanged. The editor shows the phone's
original name so the private label does not hide that information.

Nicknames appear in saved chat lists, direct conversation titles, search results
and starred-message lists. Search finds either the nickname or the original phone
name, including archived chats. Nicknames are available for saved direct contacts;
group names and group member names retain their existing behavior.

The field trims surrounding whitespace, accepts Unicode and is limited to 128
UTF-8 bytes. Internal line breaks, control characters and directional override/
isolate controls are rejected. Save failures keep the input for retry and show a
generic error. The scrollable dialog supports large text and narrow screens.

## Privacy and persistence

A nickname belongs to the saved peer identity, independent of its advertised
name or Wi-Fi address. Learning a new phone name preserves the nickname. It is
never advertised, sent in handshakes or included in outgoing reply metadata.
The QR screen continues showing the actual session name, and verification codes
retain their existing session binding. A private
label does not establish identity or trust; every new session still needs both
phones to confirm. Local nicknames do not rename a contact on the other phone.

SQLite schema **14** adds a nullable encrypted `peers.nickname` column. It uses
the existing history key with XChaCha20-Poly1305 and AAD
`["LocalChat/contact-nickname/1", peerId]`. Ciphertext cannot be moved between
contacts without failing authentication. There is no plaintext nickname index.
Existing schema-13 data upgrades without rewriting messages, identity, drafts,
read state or chat organization. Advertised peer names retain their existing
plaintext metadata storage; only the private nickname is newly encrypted.

Setting/removing a nickname does not change activity order, pin/archive status,
unread state, drafts, message contents, queued sends or the live connection.
Deleting a conversation or clearing history removes its nickname.

Editing requires foreground access. Lock/background dismisses the editor and
clears unsaved input. Queued work captures the privacy revision and checks the
originating route before writing, including after encryption. Work cancelled
before database submission cannot save a nickname; an already submitted database
write can finish. Successful commits refresh saved labels even if the editor closes.

Browser demo nicknames live only in the current tab and reset on reload. They
are included in separately marked encrypted demo backups, with the existing
phone/demo import separation.

## Encrypted backups

Archives containing nicknames select payload **v11**, with an optional validated
`nickname` string on peer rows. Archives without nicknames keep the existing
minimum format selection. Current builds import v1-v11; older builds reject v11.
The encrypted envelope, password derivation and 20 MiB limit are unchanged.

New contacts inherit nicknames from an archive. Existing destination contacts
keep their local choice, including a removed nickname; importing an old archive
cannot restore it on an existing contact. Delete-and-restore counts as a new
contact. Both history-only imports and identity transfers to an empty phone
support nicknames. Anyone who decrypts the backup can read its nicknames and
identity; the labels are private from peers, not from the backup recipient.

## Validation

Automated results and commands are recorded in [VALIDATION.md](VALIDATION.md).
Tests cover validation, encrypted persistence/authentication, migration, write
rollback, deletion, search refresh, privacy cancellation, backup parsing/merging,
identity rules, actual paired-session reply metadata, UI edits/removal/errors,
unchanged drafts and narrow-screen enlarged text. No physical device is implied
by automated test results.

## Manual phone and browser checklist

- Set a nickname in Chats; verify the same label in an offline conversation,
  Archived chats, both name searches, message search and Starred messages.
- Edit/remove it and cancel an edit; save a Unicode nickname; reject an overlong
  one. Confirm original phone name stays visible in the editor.
- Restart Android and reconnect after the other phone changes its advertised
  name. The nickname stays; compare fresh codes on both phones as usual.
- Send a reply after nicknaming the peer. The other phone must never receive your
  private nickname. Verify group author labels stay unchanged.
- Check unread counts, chat order, drafts, archive/pin and queued messages before
  and after edits. Delete/recreate the chat and confirm the nickname is gone.
- Export/import to an empty destination, with and without identity transfer.
  Merge into an existing contact with another nickname, then with no nickname:
  the destination choice wins. Retain original history if an import fails.
- Lock/background with unsaved input, then return: the editor is dismissed and
  the unsaved nickname is absent. Navigate away while a save is pending.
- Test the keyboard, TalkBack focus/labels and large system/app text on a narrow
  phone. All editor controls should scroll or wrap and remain reachable.
- Browser: edit/search/export/import within a tab; reload resets local labels.

## Source

- [Model and validation](../lib/core/contact_nickname.dart)
- [Encrypted local storage](../lib/core/local_store.dart)
- [Backup validation and merge](../lib/core/chat_backup.dart)
- [Controller](../lib/services/chat_controller.dart)
- [Editor](../lib/features/contact_nickname_dialog.dart)
- [Portable service tests](../test/contact_nickname_test.dart)
- [Editor tests](../test/contact_nickname_screen_test.dart)
- [SQLite tests](../test/local_store_test.dart)
