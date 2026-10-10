# LocalChat feature backlog

Created: 2026-10-10. Keep this file updated as features are implemented and tested.
Work on one feature at a time; validate it before the user commits and starts the next.

## Current milestone: Themes

- [x] Light, dark and follow-system modes in Settings → Appearance.
- [x] Mint, blue, purple and amber palettes across tabs, chats, Settings and lock.
- [x] Save Android choices independently of chat history; temporary browser choices.
- [x] Readable theme colors for chat bubbles and connection/demo notices.
- [x] Automated persistence, failure recovery, system mode, navigation, lock,
      contrast and small-screen checks.
- [x] All 43 tests pass, clean analysis and fresh Android/browser builds.
- [ ] User tests themes on a phone and commits this milestone;
      see [theme checklist](THEMES.md).

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
- [ ] Portable chat export/import: password-encrypted archive, transferable
      without Internet, import preview, safe merging and duplicate detection.
      Re-encrypt imported history with destination keys. Decide explicitly
      whether a phone migration also transfers the messaging identity.

## Suggested quality-of-life features

- [ ] Unread badges, latest-message previews, and latest activity timestamps.
- [ ] Local conversation and message search.
- [ ] Saved drafts across navigation and restarts.
- [ ] Offline outbox, reconnection and retry after verification; distinguish
      queued, delivered and unconfirmed messages; prevent duplicate resends.
- [ ] Pin, archive and delete individual conversations.
- [ ] Connection troubleshooting: Wi-Fi, permissions, discovery, retry actions.
- [ ] Local notifications with optional hidden message previews.
- [ ] Optional background connection mode with battery/connection controls.
- [ ] Reply to messages, copy actions, and starred messages.
- [ ] QR scanning for session verification (bind to the verified session).
- [ ] Accessibility: adjustable text size, contrast and optional vibration.
- [ ] Images and files: transfer progress, cancellation and size limits.
- [ ] Private local contact nicknames independent of advertised display names.

## Later refinements discussed

- [ ] Configurable auto-lock timeout and privacy for chat/notification previews.
- [ ] Group delivery behavior when members leave or the host disconnects.
- [ ] Backup format versioning, validation and explicit identity-migration flow.

## Proposed order after app lock

1. Chats/Nearby navigation (committed).
2. Themes (current milestone).
3. Chat management, search, unread state and drafts.
4. Encrypted backups and phone migration.
5. Reliable reconnection, queued messages and notifications.
6. Group chat and attachments.

The user chose app lock first so it can be tested before committing. This order
can change; unchecked items are plans, not existing capabilities.
