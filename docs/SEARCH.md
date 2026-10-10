# Local search testing

Open **Chats** and tap the toolbar **Search chats** icon. Type part of a saved
conversation name or message. Results appear under **Conversations** and
**Messages**. Matching ignores case and surrounding query whitespace; characters
such as `%` and `_` are literal. Urdu and other Unicode text can be searched.

Tap a conversation result to open its history normally. Tap a message result
to open the conversation at a highlighted **Search result** bubble. Older and
newer messages remain reachable by scrolling; **Jump to latest** returns to the
usual newest-message view. Back returns to the results with the query preserved.
If a target was deleted, the chat shows a notice rather than an incorrect match.

Search is local and works offline. Reading search results does not clear unread
counts; opening a visible chat uses the existing read rules. Locking removes the
search screen and cancels its pending work. After unlocking, a new search starts empty.

## Phone checklist

Install `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` over the existing
installation. This feature keeps schema version 2 and your saved history.

- [ ] Find a conversation by part of its name, including different letter case.
      Tap it, check its saved history and return to the same search query.
- [ ] Find an outgoing and an incoming message. Confirm the peer name, preview
      and You prefix, then tap each result to check the highlighted message.
- [ ] Find an older message in a long conversation. Confirm it is visible upon
      opening, scroll both directions, and use Jump to latest.
- [ ] Try Urdu or other Unicode text, emoji and multiline messages. Confirm
      that the result preview includes the matching text.
- [ ] Type quickly, replace the query and clear it. Old results should disappear.
      Check the empty-search hint and a query with no matching history.
- [ ] Leave a message unread and search for it. The count should stay unchanged
      until you open the conversation itself.
- [ ] While search is open, receive a new matching message over an existing
      verified connection. Results should refresh. Search does not create a
      connection or change foreground/background delivery behavior.
- [ ] Enable app lock and lock while search is showing private results. Query
      and results should be hidden. Unlock, open Search and check its empty field.
- [ ] With an active query, delete history from Settings after navigating back.
      Search again and check that deleted names/messages no longer appear.
- [ ] Try large Android text and the keyboard on a small screen, in Light and
      Dark themes. Controls and results should scroll without clipping actions.

The browser demo supports the same controls with its usual temporary history.
It can preview layout and result navigation; phone persistence and native
lifecycle checks remain Android testing.

## Storage, limits and automated checks

Message bodies remain encrypted on disk. Search decrypts batches in memory
without a plaintext search index, query log or extra body copy. Larger histories
take longer to search. Typing is debounced; obsolete queries stop and cannot
replace newer results. New messages and history deletion invalidate results.
The newest 100 matching messages are shown; refine the query when more match.
Conversation-name matches are not subject to that message limit.

Storage tests use real SQLite to check Unicode/case/literal matching, peer and
direction scoping, ciphertext authentication, cross-batch results, cancellation,
limits and unchanged unread state. Controller tests cover stale completion/errors,
clear/dispose/retry and live encrypted-message updates. Widget tests cover name
opening, an older result among 180 variable-height messages, direction-specific
selection, scrolling, Jump to latest, deleted targets, locking, retained queries,
Unicode snippets, large text and a phone-sized keyboard layout.
