# Replies to text messages

Implemented: 2026-10-14. Direct chats and hosted groups support replies to saved
text messages, including archived chats and messages opened from search.

## Using replies

Long-press a text message or its bubble padding and choose **Reply**. The browser
also supports right-click; the text-selection toolbar and screen-reader actions
include Reply alongside the copy controls. Reply quotes the message, independent
of any smaller text selection. Image/file bubbles retain their existing actions.

The composer shows the quoted author and a short preview. Type your answer and
send it normally. **Cancel reply** removes the quote and keeps your answer text.
Each conversation has its own reply draft. Android saves both parts encrypted
through navigation, locking and restart; browser drafts reset on tab reload.
Selecting a quote without typing still creates a saved draft.

Sent and received replies display their quote above the answer. Tap it to open
the original message in the same conversation; **Jump to latest** returns to the
newest messages. The lookup uses message ID plus direction for direct chats and
message ID plus author for groups. The saved preview must also match the local
original. A conflicting saved preview is treated as unavailable. Only this
bounded preview is compared; the quote is not proof of the original full body.

If the original is missing, the reply keeps its preview and shows **Original
message unavailable.** No older history is downloaded or requested. The preview
is trimmed and limited to 512 UTF-8 bytes without splitting a Unicode code point;
the card displays at most two lines. Long messages keep their full original body.
Copy message on a reply copies its answer body, as before.

## Sending, compatibility and privacy

Direct replies can enter the encrypted outbox while offline. Sending waits for
fresh verification and negotiated `reply-v1` support. An older peer still accepts
ordinary text. If a queued reply reaches the front of the outbox while connected
to an older version, it stays queued: update that peer or cancel that queued
reply to allow later messages through. The quote is never silently stripped.
Retries keep the original message ID and quote, so identical retries deduplicate.

Hosted groups negotiate `group-reply-v1` and include reply support in the host's
roster. Every admitted member and the host must support replies. An older member
disables reply sending, with guidance in the composer; ordinary group text still
works and the draft is kept. Saved group reply drafts can be edited offline, but
groups still have no offline outbox. A quoted author may have left the group.
Replying to old text intentionally shares its preview with current recipients,
including newly admitted members; it does not transfer the original history.

Reply selection, cancellation, quote navigation and new sending require foreground
unlock. Privacy changes invalidate captured actions, hide quote previews and
remove menus. PIN locking removes the entire Navigator as before. Temporary
foreground loss/return cannot revive an obsolete asynchronous reply selection.
Verified background receiving/storage/ACKs use the existing direct/group rules;
notifications use only the answer body and never add the quoted preview.

Send captures the current text and quote. Acceptance clears both draft parts
atomically only if that revision still matches. Failed saves keep both parts,
and edits made while a save is pending survive for the next draft. Quote save/load
errors use the existing draft Retry action; unresolved draft errors block export.
Group replies interrupted after local acceptance remain unconfirmed, following
existing group delivery behavior.

A quotation is supplied by the replying sender. Encryption authenticates the
sender's payload, and group signatures bind the quote to the replying author;
the preview is not a separate signature or proof from the original author. The
trusted host still reads and relays group messages and their quotes. No new
permissions, dependencies, transport sessions or verification shortcut are added.

## Storage and backups

SQLite schema **12** adds `reply_drafts`, with target/type metadata and an encrypted
quote body authenticated to that conversation and direct/group scope. It preserves
existing ciphertext on upgrade. Structured draft changes write text and quote in
one transaction; accepted sends, chat deletion and history deletion remove both.

Direct reply bodies use the existing messages table with kind `reply` and AAD
`LocalChat/reply-message/1/<peer>/<id>/<direction>`. Both the answer and quotation
are encrypted. Ordinary text, including literal JSON, keeps its previous format.
Group reply envelopes use signature domain `LocalChat/group-reply/1`, covering
the reference ID, author, name and preview along with existing group/session/
roster/recipient fields. Stored group histories retain their existing encryption.

Backups containing message or draft quotes select payload **v9**, retaining
v1-v8 import support and the same encrypted envelope, password KDF and total
limits. Exports without quotes keep the existing applicable version. Quote-only
drafts are included. Imports validate quote kinds/bounds/signatures before preview
and re-encrypt with destination keys; changed quote metadata counts as a conflict.
Existing destination drafts win, and imports never automatically send replies.
Direct reference directions survive history-only and identity-transfer imports.

## Validation

Model/protocol/draft/archive checks are in `test/message_reply_test.dart`, UI
checks in `test/message_reply_screen_test.dart`, and encrypted migration/reopen/
rollback/import checks in `test/local_store_test.dart`. Results and log paths are
recorded in [VALIDATION.md](VALIDATION.md). Existing copy tests cover the expanded
menu; browser UI checks use the existing test-harness platform acknowledgments.
Automated transports and browser simulation do not establish physical networking,
background reliability or biometric behavior.

## Manual checklist (pending)

- [ ] On two updated Android phones, verify and exchange text replies to incoming
      and self-authored messages. Check quotes, delivery status and original jumps.
- [ ] Reply to an older search result and an archived chat; check navigation,
      exact originals, Jump to latest, organization and independent drafts.
- [ ] Select a quote, type, cancel, navigate away, lock/unlock and restart. Check
      exact text restoration and quote-only drafts; cancel keeps answer text.
- [ ] Queue a reply offline, reconnect and verify. Test explicit retry after loss
      and verify no duplicate or extra unread count on the receiving phone.
- [ ] Connect to a previous app version: plain text works and queued replies wait
      with guidance. Cancel the queued reply or update/reverify that peer.
- [ ] On three phones, send host and guest replies with per-member receipts.
      Quote a departed author; admit a new member and verify only the intentional
      quoted preview is shared. Add an older member and check reply guidance.
- [ ] Export/import v9 mixed histories and quote-only drafts. Check password errors,
      safe merging, retained destination drafts, history-only import and identity
      migration to an empty phone. Test older archives as well.
- [ ] Remove an original through history changes/import conflicts and check the
      retained quote's unavailable notice; it must not open another conversation.
- [ ] Open a Reply menu or selection toolbar, then lock/background. Check removal,
      hidden quote previews, fresh actions after return and generic notifications.
- [ ] Run `flutter run -d chrome`; exercise direct replies and simulated hosted/joined
      group replies. Check right-click, selection menus, reset on reload and labels.
- [ ] Check TalkBack Reply/Copy actions, large text on a small screen and all themes.

Record phone model, Android/browser version and outcomes before marking these done.
