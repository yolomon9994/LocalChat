# Saved group message search

Implemented: 2026-10-13. From **Chats**, tap **Search chats** to search saved
direct chats and groups together. Group-name matches appear under **Groups**;
message matches appear under **Group messages**, with their author and time.
Open a saved group and tap **Search group messages** to search only that group.

Search works offline, including archived groups. Matching ignores case and
surrounding query whitespace; `%`, `_` and regex characters are literal.
Urdu, emoji and multiline text are supported. Saved image labels and file labels/
filenames are searchable; image/file contents and unfinished drafts are excluded.
Matching text is highlighted in result previews and selected text messages.

Tap a group-name result to open its saved history normally. Tap a message result
to open at that exact author/message key, even in a long history or when two
authors used the same message ID. Scroll both directions for surrounding history.
**Jump to latest** opens the newest messages. Back keeps the query and results.
A removed target shows a notice rather than highlighting another message.

Search shows the newest **100 matching group messages** across the chosen scope;
refine the query when the limit notice appears. Direct results retain their
separate existing 100-message limit. Pinning does not change message-result order.
Receiving, imports, deletion and archive changes refresh open search results.

Viewing results leaves unread counts alone. Opening a foreground, visible group
uses the existing read rules; covering it with search stops visible-chat reading.
Search never joins, verifies, rehosts or unarchives a group, and preserves drafts.
Locking removes search routes, clears the query and cancels pending work. While
backgrounded, results are cleared and searches pause; returning unlocked refreshes
the existing query. Unlocking after a PIN lock starts a new empty search.

## Storage and privacy

Group search scans the authenticated, decrypted histories already loaded by
GroupController. It yields regularly, cancels obsolete work, and retains only
result IDs/display text, without attachment bytes. There is no plaintext index,
query log, extra persisted message copy or new network operation. SQLite remains
schema **11**; backups retain their existing v1-v8 compatibility and limits.
Browser searches cover saved/imported in-memory groups; real nearby group hosting
and receiving still require Android.

## Phone checklist

Install `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` over the existing
app. Automated checks and local log paths are in [VALIDATION.md](VALIDATION.md).
These physical checks remain pending:

- [ ] Turn mobile data off and search a saved group by name from Chats. Include
      an archived group; opening it keeps its archive choice and saved draft.
- [ ] Search an older incoming and outgoing text message. Check author, time and
      highlights; open the exact match, scroll both directions, Jump to latest,
      and return to the same query.
- [ ] Search from inside a group. Matching text in other groups or direct chats
      should be excluded. Check clear, whitespace, no results and rapid edits.
- [ ] Try Urdu, emoji, multiline messages and literal `%`/`_`/`[]` characters.
      Search a saved filename or Image label; file contents and drafts stay absent.
- [ ] Search an unread message without opening it; the count stays unchanged.
      Receive a matching verified message while searching; results and unread
      counts update, and the group stays archived if it was archived.
- [ ] Lock with private results visible. Unlock and reopen search; it starts
      empty. Without PIN locking, background/foreground the app and check the
      paused search refreshes on return.
- [ ] Restart the phone/app, search saved messages again, and import a backup.
      Imported group messages appear, with unchanged drafts and organization.
- [ ] Try 100+ matches, narrow screens, larger text and light/dark themes. Refine
      the query after the limit notice; keep the keyboard and results usable.
