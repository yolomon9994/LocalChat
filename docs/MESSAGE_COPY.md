# Copying text messages

Implemented: 2026-10-14. Available in direct chats and saved/active groups,
including archived chats, offline history and messages opened from search.

Long-press a message's bubble padding or timestamp, then tap **Copy**. This
copies the full message exactly, including whitespace, line breaks and Unicode,
without its author, timestamp or delivery labels. In the browser, right-click
the bubble to open the same menu. Back, Escape or tapping outside cancels it.

Long-press the text itself to keep normal text selection. Its toolbar offers
**Copy message** for the entire body, **Copy selection** for the selected text,
and **Select all** when available. **Reply** now shares these menus; see
[reply controls](MESSAGE_REPLIES.md). The search highlight remains selectable.
Screen readers also have a **Copy message** custom action on the text bubble.
Image/file bubbles keep their existing viewing and saving controls.

Successful copying shows **Message copied.** A rejected clipboard write shows
**Could not copy. Try again.** without platform details or message content.
Browser clipboard access depends on the browser's permissions and secure
context; use the locally served demo or an HTTPS deployment.

Copying requires an initialized, unlocked app in the foreground and the
original text message still present in that conversation. Lock/background,
deletion, message replacement and route disposal invalidate captured menu
callbacks. A hidden route cannot copy. Reopening or unlocking does not revive
an old callback. Duplicate taps while a clipboard write is pending do not
create additional writes. Privacy changes dismiss the menu/selection toolbar
and an active copy confirmation. A pending write does not show a late
confirmation after the app becomes inaccessible.

Copied text goes to the operating system/browser clipboard outside LocalChat's
encryption and app lock. An already authorized platform write can finish after
locking; LocalChat cannot undo that write. It does not read, retain or clear
clipboard contents on lock, so another application's newer clipboard data is
not overwritten. Chat deletion cannot erase a previously copied value.

Copy actions do not send messages or change drafts, delivery receipts, chat
organization or history. Opening a visible chat still follows the existing
read/unread rules. No schema, backup format, wire protocol, native permission or
dependency changes are needed.

## Implementation and validation

`lib/features/text_message_actions.dart` shares full-body/selected-text clipboard
actions, route/message/access checks, dismissal, failure feedback and semantics
between both screens. Direct targets use peer/message/direction; group targets
use group/author/message. `HighlightedSearchText` accepts the same toolbar
builder for highlighted group history. Browser startup disables its native
context menu so Flutter can provide the message actions and normal selection
menus throughout the demo.

The APIs were checked against the installed Flutter SDK and official
[selection-menu documentation](https://api.flutter.dev/flutter/widgets/EditableText/contextMenuBuilder.html),
[browser menu control](https://api.flutter.dev/flutter/services/BrowserContextMenu/disableContextMenu.html)
and [clipboard write API](https://api.flutter.dev/flutter/services/Clipboard/setData.html).

Automated checks are in `test/message_copy_test.dart`; commands, results and
ignored log paths are recorded in [VALIDATION.md](VALIDATION.md). Clipboard
method calls are intercepted in widget tests to inspect exact writes and
simulate platform errors/delays; actual phone/browser permission and paste
behavior require the checklist below.

## Manual checklist (pending)

- [ ] On Android, copy incoming and outgoing text, including queued text while
      offline. Paste into another text field and compare Unicode, spaces and
      line breaks. Confirm only the body was copied.
- [ ] In a hosted group, copy your own and another author's messages; repeat
      with saved/archived history and an older search result. Check drafts,
      pin/archive choices and delivery status remain intact.
- [ ] Long-press text, use Copy message, select a smaller portion, and use Copy
      selection. Check dragging handles and Select all still work.
- [ ] Open the copy menu, then lock/background the app. Confirm it disappears;
      return/unlock and open a fresh menu. Repeat with a selection toolbar.
- [ ] Verify the app does not erase a copied value on lock or chat deletion.
      Confirm the previous clipboard is unchanged after canceling a copy menu.
- [ ] Run `flutter run -d chrome`. Repeat full/selected copy and right-click
      dismissal; paste elsewhere. Check browser clipboard rejection feedback
      and retry, with its normal permissions and HTTPS/localhost environment.
- [ ] Check TalkBack's Copy message action, enlarged text on a small screen,
      theme contrast and Android back/browser Escape dismissal.

Record device/browser/version and outcomes. Automated clipboard mocks and
browser simulation do not establish physical clipboard or networking behavior.
