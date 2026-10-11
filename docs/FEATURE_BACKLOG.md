# LocalChat feature backlog

Created: 2026-10-10. Keep this file updated as features are implemented and tested.
Work on one feature at a time; validate it before the user commits and starts the next.

## Current milestone: Optional background connection protection

- [x] Opt-in Keep connection active switch, persisted locally on Android.
- [x] Start only from foreground unlock after both fresh confirmations; protect
      the current running session without automatic discovery/reconnection.
- [x] Separate generic Connection notification with Stop, permission/channel
      guidance, status, Retry and user-controlled battery-settings shortcut.
- [x] Stop disconnects/ends advertising while locked; preserves history/drafts/
      outbox and disables the preference. Epochs reject obsolete Stop actions.
- [x] Background receiving/persistence/ACKs retain privacy and unread gates;
      new queued sends still wait for foreground unlock.
- [x] Bound received-frame wake locks; cleanup on completion/disconnect/service
      destruction; no idle CPU lock, sticky/boot restart or restored session keys.
- [x] Detect reported connection loss/invalid local access; show recovery guidance
      without a wire heartbeat or changing encrypted payloads.
- [x] All 162 tests pass (147 existing + 15 new); final analysis/build results are in
      [VALIDATION.md](VALIDATION.md).
- [ ] Physical phone/Doze/vendor testing and user's commit;
      see [background checklist](BACKGROUND_CONNECTION.md).

## Local message notifications and privacy: implemented and committed

- [x] Opt-in Settings controls; previews disabled by default.
- [x] Android permission/channel status, request and notification-settings shortcut.
- [x] New persisted verified incoming messages notify; suppress visible-chat alerts
      and identical retries. Notification failures leave message delivery intact.
- [x] Generic locked/background alerts; redact active previews on privacy changes.
- [x] Cold/warm tap opens the intended saved chat after unlock, with no verification bypass.
- [x] Per-peer alerts; reading/deleting cancels them, imports never create alerts.
- [x] Temporary browser settings without browser OS alerts; no background service.
- [x] All 147 tests pass; final analysis/build results are in [VALIDATION.md](VALIDATION.md).
- [x] User commits notifications (`9bb6c60`).
- [ ] Physical phone testing; see [notification checklist](NOTIFICATIONS.md).

## Connection troubleshooting and easier reconnection: implemented and committed

- [x] Typed guidance for Wi-Fi, permission, Location, busy, stale peer and service failures.
- [x] Android Wi-Fi/app-permission/Location settings shortcuts, with safe fallback.
- [x] Access checks on request and foreground/unlock; revoked access closes verification.
- [x] Scan progress versus completed empty results; reject overlapping recovery actions.
- [x] Manual Reconnect to a device still listed; always require fresh two-phone verification.
- [x] Explain queued waiting state; preserve drafts/history and identity-targeted delivery.
- [x] Failed connect stays in Nearby; connection/verification timeout is retryable.
- [x] All 132 tests pass, clean analysis and fresh Android/browser builds;
      see [recovery checklist](CONNECTION_RECOVERY.md).
- [x] User commits connection recovery (`c7d4d6e`).
- [ ] Physical phone testing.

## Offline outbox and message retry: implemented and committed

- [x] Queue text in saved chats while disconnected; encrypted Android persistence.
- [x] Clear matching drafts atomically with local acceptance; preserve newer edits.
- [x] Send queued text in order after both phones verify the fresh connection.
- [x] Pause new attempts while locked/backgrounded; drain only the verified identity.
- [x] Queued counts, confirmed Cancel, explicit Retry and storage-error Resume.
- [x] Retry original IDs; reject conflicting duplicates and avoid extra unread counts.
- [x] Bound in-flight attempts; timeouts/disconnects/restarts become unconfirmed.
- [x] Imported pending messages become unconfirmed and never send automatically.
- [x] All 118 tests pass, final targeted checks pass, clean analysis and fresh
      Android/browser builds; see [outbox checklist](OUTBOX.md).
- [x] User commits outbox and retry (`605962e`).
- [ ] Physical phone testing.

## Encrypted backups and phone migration: implemented and committed

- [x] Settings export to a password-encrypted, versioned `.lcbackup` file.
- [x] Include messages, drafts, unread state and pin/archive choices.
- [x] Local Android system file picker and browser demo file download/selection.
- [x] Validate/decrypt before preview; confirmed merge preserves existing data.
- [x] Duplicate/conflict handling; fresh destination encryption and atomic rollback.
- [x] History-only import plus explicit identity transfer to an empty phone.
- [x] Recover interrupted identity switches with vault journal/SQLite receipt.
- [x] Lock clears passwords/previews; encrypted selection survives picker locking.
- [x] All 99 tests pass, clean analysis and fresh Android/browser builds;
      see [backup checklist](BACKUPS.md).
- [x] User commits backups and phone migration (`63eff9f`).
- [ ] Physical phone testing.

## Conversation management: implemented and committed

- [x] Per-chat menu with Pin/Unpin, Archive/Unarchive and confirmed Delete.
- [x] Persist Android pin/archive choices; pinned chats precede other chats.
- [x] Separate Archived list, with unread totals and empty states.
- [x] New messages keep archived chats archived; restoring retains pin/history/draft.
- [x] Search includes archived chats and labels their results.
- [x] Delete only the selected chat's messages/draft; disconnect its active session.
- [x] Prevent pending draft saves and stale search results from restoring deleted data.
- [x] Database upgrades preserve encrypted history, drafts, identity and unread state.
- [x] All 82 tests pass, clean analysis and fresh Android/browser builds.
- [x] User commits conversation management (`8f55377`).
- [ ] Physical phone testing; see [conversation management checklist](CONVERSATION_MANAGEMENT.md).

## Saved message drafts: implemented and committed

- [x] Separate drafts for each conversation, editable while offline.
- [x] Restore exact text after navigation, locking and Android app restarts.
- [x] Encrypt Android draft bodies; temporary browser drafts reset on reload.
- [x] Keep drafts after validation/storage failures; clear only the accepted
      revision atomically when saving an outgoing message to the outbox.
- [x] Draft load/save errors have a retry action; failed loads prevent overwriting.
- [x] Delete all chat history also removes saved drafts and the open composer.
- [x] Database upgrades preserve messages/read state; typing does not reorder
      conversations, change unread counts or appear in message search.
- [x] All 73 tests pass, clean analysis and fresh Android/browser builds.
- [x] User reviews and commits the saved drafts milestone (`9e90550`).
- [ ] Physical phone draft testing;
      see [draft checklist](DRAFTS.md).

## Local chat search: implemented and committed

- [x] Search action in the Chats toolbar, with conversation-name and message results.
- [x] Case-insensitive literal substring matching, including Unicode text.
- [x] Search encrypted history in memory, with no extra plaintext index.
- [x] Debounce typing, cancel obsolete results and refresh on new messages/deletion.
- [x] Open a conversation or anchor/highlight a matching message; Jump to latest.
- [x] Search preserves unread counts; lock removes query/results along with routes.
- [x] Storage, stale-result, live-update, long-history jump and phone-layout checks.
- [x] All 61 tests pass, clean analysis and fresh Android/browser builds.
- [x] User reviews and commits the local search milestone (`a2c7aa3`).
- [ ] Physical phone local search testing;
      see [search checklist](SEARCH.md).

## Chats list improvements: implemented and committed

- [x] Latest-message previews, with a You prefix for outgoing text.
- [x] Last activity time: time today, Yesterday, or an older date.
- [x] Persistent unread counts for incoming messages; open a visible, unlocked
      conversation to clear its badge. Incoming messages while reading stay read.
- [x] Most recent local message activity first; reconnecting, renaming, delivery
      acknowledgements and duplicate messages keep the existing order.
- [x] Database upgrade preserves history; existing messages start read.
- [x] Migration, persistence, visibility, lock, ordering and enlarged-text checks.
- [x] All 52 tests pass, clean analysis and fresh Android/browser builds.
- [x] User reviews and commits the Chats list milestone (`c233159`).
- [ ] Physical phone Chats list testing; see [checklist](CHAT_LIST.md).

## Themes: implemented and committed

- [x] Light, dark and follow-system modes in Settings → Appearance.
- [x] Mint, blue, purple and amber palettes across tabs, chats, Settings and lock.
- [x] Save Android choices independently of chat history; temporary browser choices.
- [x] Readable theme colors for chat bubbles and connection/demo notices.
- [x] Automated persistence, failure recovery, system mode, navigation, lock,
      contrast and small-screen checks.
- [x] All 43 tests pass, clean analysis and fresh Android/browser builds.
- [x] User reviews and commits the theme milestone (`b353956`).
- [ ] Physical phone theme testing; see [theme checklist](THEMES.md).

## Chats / Nearby navigation: implemented and committed

- [x] Default Chats tab with saved conversations and an active-chat shortcut.
- [x] Separate Nearby tab with discovery, scanning and connection controls.
- [x] Bottom navigation; Settings remains in the toolbar on either tab.
- [x] Keep connection state and separate scroll positions when switching tabs.
- [x] Automated navigation checks (36 passing tests), clean analysis and fresh Android/browser builds.
- [x] User reviews and commits the navigation milestone (`abe4dc3`).
- [ ] Physical phone navigation testing; see [phone checklist](NAVIGATION.md).

## App lock: implemented and committed

- [x] Optional six-digit app PIN, with confirmation during setup.
- [x] Optional fingerprint/biometric unlock, with app PIN fallback (phone validation pending).
- [x] Lock on launch and when leaving the foreground; manual Lock now action.
- [x] Require the current PIN to change the PIN, disable locking, or change biometrics.
- [x] Store a salted PIN verifier in secure storage; slow repeated guesses.
- [x] Cover all routes, including chats and Settings, while locked.
- [x] Automated PIN, persistence, cooldown, biometric and lifecycle checks.
- [ ] Physical Android PIN/fingerprint/lifecycle testing; see [checklist](APP_LOCK.md).
- [x] User reviews and commits the tested milestone (`df3c2b3`).

## User-requested features

- [ ] Group chats: create/invite, member list, verification, per-member delivery.
      Start with a nearby host that must remain connected; plan group encryption
      and membership changes before changing the current one-peer protocol.
- [x] Theme modes: light, dark, and follow system.
- [x] Color palettes: mint, blue, purple, amber; persist the Android selection.
- [x] Bottom navigation with separate Chats and Nearby screens; toolbar Settings.
- [x] Portable chat export/import: password-encrypted archive, transferable
      without Internet, import preview, safe merging and duplicate detection.
      Re-encrypt imported history with destination keys. Explicit identity
      transfer is available on an empty destination; history-only import retains identity.

## Suggested quality-of-life features

- [x] Unread badges, latest-message previews, latest activity timestamps and
      recent-message ordering.
- [x] Local conversation and message search.
- [x] Saved drafts across navigation and restarts (Android); temporary browser drafts.
- [x] Offline outbox and retry after fresh verification; distinguish queued,
      sending, delivered and unconfirmed messages; retry by original ID.
- [ ] Automatic reconnection with troubleshooting and fresh verification.
- [x] Pin, archive and delete individual conversations.
- [x] Connection troubleshooting: Wi-Fi, permissions, discovery, retry actions
      and manual Reconnect to a device still listed.
- [x] Local notifications with hidden message previews by default and lock-aware taps.
- [x] Optional background connection mode with battery/connection controls;
      protects the current running verified session, subject to Doze/vendor limits.
- [ ] Reply to messages, copy actions, and starred messages.
- [ ] QR scanning for session verification (bind to the verified session).
- [ ] Accessibility: adjustable text size, contrast and optional vibration.
- [ ] Images and files: transfer progress, cancellation and size limits.
- [ ] Private local contact nicknames independent of advertised display names.

## Later refinements discussed

- [ ] Configurable auto-lock timeout and privacy for chat/notification previews.
- [ ] Group delivery behavior when members leave or the host disconnects.
- [x] Backup format versioning, validation and explicit identity-migration flow.

## Proposed order after app lock

1. Chats/Nearby navigation (committed).
2. Themes (committed).
3. Chats list previews/unread state, local search and drafts (committed),
   conversation management (committed).
4. Encrypted backups and phone migration (committed).
5. Offline outbox and retry (committed), connection troubleshooting/manual
   reconnection and notifications (committed), background connection support (current).
6. Group chat and attachments.

The user chose app lock first so it can be tested before committing. This order
can change; unchecked items are plans, not existing capabilities.
