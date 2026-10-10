# LocalChat feature backlog

Created: 2026-10-10. Keep this file updated as features are implemented and tested.
Work on one feature at a time; validate it before the user commits and starts the next.

## Current milestone: app lock

- [x] Optional six-digit app PIN, with confirmation during setup.
- [x] Optional fingerprint/biometric unlock, with app PIN fallback (phone validation pending).
- [x] Lock on launch and when leaving the foreground; manual Lock now action.
- [x] Require the current PIN to change the PIN, disable locking, or change biometrics.
- [x] Store a salted PIN verifier in secure storage; slow repeated guesses.
- [x] Cover all routes, including chats and Settings, while locked.
- [x] Automated PIN, persistence, cooldown, biometric and lifecycle checks.
- [ ] Physical Android PIN/fingerprint/lifecycle testing; see [checklist](APP_LOCK.md).
- [ ] User reviews and commits the tested milestone.

## User-requested features

- [ ] Group chats: create/invite, member list, verification, per-member delivery.
      Start with a nearby host that must remain connected; plan group encryption
      and membership changes before changing the current one-peer protocol.
- [ ] Theme modes: light, dark, and follow system.
- [ ] Color palettes: mint, blue, purple, amber; persist the selection.
- [ ] Bottom navigation with separate Chats and Nearby screens; toolbar Settings.
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

1. Chats/Nearby navigation and themes.
2. Chat management, search, unread state and drafts.
3. Encrypted backups and phone migration.
4. Reliable reconnection, queued messages and notifications.
5. Group chat and attachments.

The user chose app lock first so it can be tested before committing. This order
can change; unchecked items are plans, not existing capabilities.
