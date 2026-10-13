# Pinning and archiving groups

Implemented: 2026-10-13. Open the options menu beside a saved group in **Chats**,
**Group chats**, or **Archived chats**. The same menu is available inside its chat.

- **Pin group** keeps it ahead of unpinned groups. Within each section, groups
  remain ordered by saved activity, with stable IDs breaking ties. Pinning does
  not change activity timestamps or unread counts. **Unpin group** restores the
  usual ordering.
- **Archive group** moves its saved row into **Archived chats**. New messages
  keep it there. The archive shortcut counts both direct chats and groups, with
  their combined unread messages.
- **Unarchive group** returns it to Chats and the saved-group list. Its pin choice
  is retained, including while archived.

Messages, images, files, drafts and read/delivery state are preserved. Archiving
keeps an active group connected and leaves notification behavior unchanged.
Opening archived history or a notification uses the existing foreground/PIN read
gates. Notification taps can open archived groups without unarchiving them.
The group hub's active-room card remains available for controlling an active
archived room, while its saved row lives in Archived chats.

Pin/archive menus reject stale actions after navigation, locking or a change of
foreground access. Failed writes leave the existing choices and show an error.
Deleting group history still requires its existing confirmation and removes its
draft and attachments. Browser demo choices last until the tab reloads.

## Storage and backups

SQLite schema **11** adds `pinned` and `archived` columns to `group_history`,
defaulting to false for existing groups. Migration preserves existing encrypted
records, drafts, identity and settings. These flags are plaintext local metadata,
like direct-chat pin/archive choices. Messages and drafts retain their encryption.
Changing a flag does not rewrite the encrypted group body.

History writes preserve the latest stored choices in one transaction. Receipts,
read marking, incoming attachments and stale snapshots cannot overwrite them.
Explicit rehosting loads the latest saved group, preserving newer messages and
choices while creating a fresh session and requiring new verification.
Choices are local to the phone and never sent to group members.

Backups with a pinned or archived group use payload **v8**, including boolean
group choices. They can include all direct/group text, images, files and drafts.
Current builds import v1-v8; earlier archives default missing group choices to
false. Existing destination choices win, including false values, while newly
imported groups inherit the archive's choices. Conflicting group hosts retain
the destination record. Invalid flags and flags in older payload versions are
rejected. Identity transfer still requires an empty destination phone.

The encrypted file envelope/KDF and 20 MiB limit remain unchanged. Archives
without group choices retain the appropriate earlier payload version. See
[BACKUPS.md](BACKUPS.md) and [VALIDATION.md](VALIDATION.md).

## Phone checklist

Physical checks remain pending; record models, Android versions and outcomes.

- [ ] Install the updated APK over the existing app. Check direct/group messages,
      attachments, drafts, identity, settings and unread state.
- [ ] Pin an older group in Chats and Group chats. It moves ahead of newer
      unpinned groups; unpinning restores activity order.
- [ ] Archive a group. Its saved row disappears from Chats and the group hub,
      and appears in Archived chats alongside archived direct chats.
- [ ] Check combined archive counts and unread totals. Open the group from
      Archived chats; messages, attachments and its composer draft remain intact.
- [ ] Archive a connected group while another member sends text, an image and a
      file. Keep apps foregrounded and unlocked. Delivery continues, unread
      messages count, and the group stays archived after incoming messages.
- [ ] Unarchive from inside the group and from its list menu. Preserve its pin,
      draft and history. Rehost the same archived group and check its latest data.
- [ ] Restart after saves; choices and ordering persist. Lock with a group menu
      or Archived chats open; PIN covers everything. Unlock and tap a group
      notification; it opens its saved history without unarchiving it.
- [ ] Export/import a v8 mixed backup. New groups inherit choices; destination
      groups retain their own choices and drafts. Also import an older backup.
- [ ] Test long group names, 1.8x text, light/dark themes and narrow screens.
      Pin/archive menus and history remain accessible.
