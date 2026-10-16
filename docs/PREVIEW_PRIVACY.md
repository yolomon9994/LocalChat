# Preview privacy

Implemented locally: 2026-10-16. User handles Git.

## Chat lists

In **Settings > Preview privacy**, enable **Hide chat-list previews** to replace
saved direct-message snippets with **Message preview hidden** in Chats and
Archived chats. Names/nicknames, unread badges, timestamps, queued counts and
pin/archive controls remain visible. Empty conversations still say No messages yet.

Group rows already show only names, counts and status, including the group hub;
they continue omitting message text, attachment filenames and draft contents.
Direct and group draft text stays inside its conversation. This setting does
not hide search results, Starred messages or opened chats; opening a conversation
still shows its saved messages and restores its draft. It does not delete or
modify history, unread state, drafts, outbox, chat organization or backups.

The default preserves existing visible chat snippets. While the preference is
loading or cannot be read/validated, snippets stay hidden. Android saves a strict
version-1 `{v, hidden}` record in the independent `preview_privacy_v1` secure-storage
entry. Failed writes keep the previous applied choice and show a generic retry
error; the user can retry the toggle. Browser settings reset on tab reload.
Chat-list privacy preferences are excluded from exported chat archives.

## Notification choices

In **Settings > Notifications**, enable message notifications, then choose:

- **Hidden** (default): generic LocalChat alert, with neither sender nor body.
- **Sender only**: sender/conversation name, with a generic body.
- **Sender and message**: sender/conversation name and the existing bounded preview.

Sender means the existing direct-peer or group notification title. Private contact
nicknames retain their existing local-only behavior. No name/body is sent across
the Android bridge in Hidden mode, and Sender only never sends a message body.
Both Dart and Android enforce these choices. Every mode remains generic when
locked, backgrounded or covered during an auto-lock grace period. Android's
private visibility/generic public notification remains unchanged.

Existing `previews=false/true` choices read as Hidden/Sender and message. New
Android settings store `previewMode` as hidden/sender/message. The legacy boolean
is true only for Sender and message, so an older build treats Sender only as
Hidden. Unknown explicit modes fail closed to Hidden. There is no eager startup
rewrite; the next configuration save writes the explicit mode. Names/bodies are
not stored in preferences or tap intents. Notification choices stay local and
are excluded from chat backups. Browser controls use temporary memory without
OS/browser notification permission requests.

Changing the mode first redacts active previews; existing alerts stay generic
until a new message arrives. Expanding previews never reconstructs old plaintext
or resurrects dismissed notifications. Redaction bookkeeping retains peer IDs
only. A failed restrictive change retains the saved mode but suppresses extra
fields in this running session until an explicit mode save succeeds; retry in
Settings. Native configuration also redacts before attempting persistence.

Rapid background/return events cannot skip queued redaction or replay an old
access grant. Sender/body still require current foreground/unlocked access.
Already delivered OS notifications, notification history/listeners, watches and
other integrations may retain previous previews; changing settings cannot erase
their copies. Keep notification previews Hidden if that boundary matters.

Receiving/persistence/ACK behavior, permissions, duplicate suppression, routing,
connection protection and fresh session verification are unchanged. No new
permission, runtime dependency, chat schema or encrypted archive format is added.
SQLite stays 14 and backup imports retain v1-v11 support.

## Automated validation

Commands, actual results and development corrections are recorded in
[VALIDATION.md](VALIDATION.md). Tests check preference persistence/errors,
legacy/invalid notification modes, raw channel payloads, redaction and rapid
privacy transitions, pending/failed restrictive changes, widget and screen-reader
text omission, archived/group rows, draft/history preservation, settings retry,
opened chats and narrow-screen enlarged-text controls. Channel/OS adapters are
fakes; Android system presentation/redaction needs physical validation.

## Manual Android/browser checklist

- Update an existing install. Chat-list snippets remain visible by default;
  legacy notification previews off/on map to Hidden/Sender and message.
- Enable Hide chat-list previews. Check Chats, Archived chats and group hub:
  snippets/draft text are absent, with names/counts/times still usable. Check
  TalkBack does not announce a hidden snippet.
- Restart Android and confirm the saved choice. Toggle off and confirm direct
  snippets return. Check unread, pin/archive, order, draft and outbox state.
- Open a hidden chat: full content and saved draft remain available. Search and
  Starred messages intentionally retain content. Export/import does not replace
  the destination's preview preferences or alter the archived message bodies.
- Choose each notification mode and receive verified direct/group text, images
  and files outside the chat being read. Sender only must never show message or
  attachment body text. Hidden must omit both name and text.
- Switch from full to sender-only/hidden with an alert already present. It becomes
  generic. Dismiss one first: switching modes must not restore it. Switching back
  to full leaves old alerts generic until another message arrives.
- Background/lock, including within an auto-lock grace period: all modes are
  generic and old alerts redact. Test quick app switching, device lock screen,
  notification taps, denied permission and Android's Messages channel settings.
- With large system/app text, narrow screens, TalkBack and keyboard, check both
  controls and all three notification choices remain reachable/readable.
- Browser: repeat list/control checks. Reload resets choices; there are no actual
  OS notification or persistent secure-storage claims for the browser demo.

## Source

- [Chat-list preference](../lib/services/preview_privacy.dart)
- [Preview settings](../lib/features/preview_privacy_settings.dart)
- [Notification controller/channel](../lib/services/chat_notifications.dart)
- [Android enforcement](../android/app/src/main/kotlin/dev/localchat/app/MessageNotifications.kt)
- [Unit/channel tests](../test/preview_privacy_test.dart)
- [UI tests](../test/preview_privacy_screen_test.dart)
