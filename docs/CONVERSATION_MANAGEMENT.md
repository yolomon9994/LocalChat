# Conversation management

Tap the three-dot menu beside a chat for **Pin chat**, **Archive chat**, or
**Delete chat**. The same menu offers **Unpin chat** or **Unarchive chat** when
applicable. Android remembers these choices; Browser Demo resets on reload.

Pinned chats appear first. Within the pinned and unpinned groups, the existing
message/activity ordering applies. Pinning does not alter activity timestamps,
unread state, stored messages or drafts.

Archived conversations move to **Archived chats**, accessible from Chats.
Its entry shows the number of chats and any unread messages. New incoming
messages keep a chat archived. Opening it clears unread state through the
existing visibility/lock rules without unarchiving it. Search includes archived
history and labels matching conversations/messages. Unarchive brings a chat
back to the main list with its history, draft and previous pin choice intact.
Archiving an active chat keeps its connection and the Active chat shortcut.

Delete asks for confirmation and removes only that conversation's messages,
draft, unread state and pin/archive flags from this phone (or demo tab).
The other person's history, your identity, other chats and app settings stay.
Deleting the active chat disconnects it first; both phones must verify again
after reconnecting. Fresh messages can create a new conversation. Deletion is
permanent, subject to the same forensic-wipe limitations as Delete all history.

If an action fails, a generic error is shown and the action can be retried.
A failed storage deletion keeps saved data; an active connection may already
have been disconnected. Pending draft saves are ordered before deletion and
stale edits for that peer are invalidated, so they cannot recreate its draft.
Stale list/search results cannot open a deleted conversation.

## Phone checklist

- [ ] Install as an update over the existing APK. Messages, drafts, identity
      and unread counts remain; existing chats initially have no pin/archive flags.
- [ ] Pin an older chat, check it moves above unpinned chats, then restart the
      app. Unpin it and check the original message/activity ordering returns.
- [ ] Pin several chats and check new activity orders them within the pinned group.
- [ ] Archive a chat with unread messages and a draft. Its main-list row disappears;
      Archived chats shows its unread count and the chat retains its draft/history.
- [ ] Receive another message while the chat is archived. It stays archived,
      its unread count grows, and opening it clears the count normally.
- [ ] Search for an archived name/message; check the archive label and that
      opening a result preserves the archive choice and restores its draft.
- [ ] Unarchive a pinned chat; check history, draft and pin choice return intact.
- [ ] Archive every conversation. The archive link stays accessible and the
      main list says all chats are archived. Unarchive the last one to see the
      Archived screen's empty state.
- [ ] With disposable test history, choose Delete and Cancel; nothing changes.
      Confirm Delete and check only that peer's messages and draft disappear,
      including from search and after restarting. Other chats still work.
- [ ] Delete the active chat, check it disconnects, and check the other phone's
      saved history remains. Reconnect, compare codes and start a fresh chat.
- [ ] Lock/background the app while Archived chats or the delete dialog is open.
      No chat/dialog text remains exposed; unlock returns to the main Chats tab.
- [ ] Try long names, unread badges and menus with enlarged text and each theme.
- [ ] Browser Demo mirrors management behavior within the tab and resets on reload.

## Implementation and validation

Schema 4 adds `peers.pinned` and `peers.archived`, both defaulting to zero;
upgrades from versions 1, 2 and 3 preserve encrypted bodies, drafts, identity
and local read state. No new dependency or wire payload is introduced.

Per-peer deletion is transactional. Draft cache invalidation has a per-peer
generation in addition to the global history-deletion generation. Management
actions share the protocol queue and refresh the search revision. Menus stay
with keyed chat cards after reordering. Archive routes/dialogs share app-lock
coverage. A constrained, scrollable error banner preserves list access with
large text on small screens.

Automated checks cover native persistence/upgrades, pin ordering, archival
through names/receipts/new arrivals, targeted deletion and identity retention,
queued draft races, generic failure/retry, stale opens/search refresh, verified
active-peer deletion, peer-history isolation, complete menu flows, confirmation
cancellation, lock coverage, and 320 × 568 layout with 1.5× system text.
