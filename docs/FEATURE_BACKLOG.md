# LocalChat feature backlog

Created: 2026-10-10. Keep this file updated as features are implemented and tested.
Work on one feature at a time; validate it before the user commits and starts the next.

## Current milestone: Optional automatic reconnection for direct chats

Implemented locally: 2026-10-17. Baseline `9203437`; user handles Git.
See [AUTOMATIC_RECONNECT.md](AUTOMATIC_RECONNECT.md).

- [x] Default-off saved preference; temporary browser controls and generic retry.
- [x] Three attempts with 2/5/10-second waits for a selected verified target.
- [x] Current-list address gate, signed identity continuity and fresh verification.
- [x] Status/Cancel in Nearby/chat; stale operation and privacy/lifecycle guards.
- [x] Keep history/drafts/outbox evidence; no group or attachment auto-resume.
- [x] Focused 55 checks, six Chrome UI cases, clean analysis and final Android/web builds.
- [x] All 624 tests (33 new) pass; see VALIDATION.md.
- [ ] Physical two-phone/OS/TalkBack checklist in AUTOMATIC_RECONNECT.md.
- [ ] User reviews, commits and pushes the milestone.

## Clearer group delivery feedback: implemented and committed

Implemented locally: 2026-10-17. Committed by the user as `9203437`.
See [GROUP_DELIVERY.md](GROUP_DELIVERY.md).

- [x] Resolve a departing/removed recipient's pending status immediately.
- [x] Preserve confirmed receipts, other pending text attempts and saved content.
- [x] Local session explanations and remembered recipient names; restart fallback.
- [x] Offline original-host/guest recovery guidance and guarded finder shortcut.
- [x] Text/image/file interruption, error, privacy and enlarged-text tests.
- [x] Focused tests, six Chrome UI checks, clean analysis and Android/web builds.
- [x] All 591 tests (19 new) pass; see VALIDATION.md.
- [ ] Physical three-phone/TalkBack checklist in GROUP_DELIVERY.md.
- [x] User committed group delivery feedback as `9203437`.

## Preview privacy controls: implemented and committed

Implemented locally: 2026-10-16. Committed by the user as `492dbb5`.
See [PREVIEW_PRIVACY.md](PREVIEW_PRIVACY.md).

Resumed and automated validation completed on 2026-10-17. The Chrome fixture
stall is fixed. Results and remaining device checks are recorded in
[VALIDATION.md](VALIDATION.md). Subsequently committed by the user as `492dbb5`.

- [x] Saved Hide chat-list previews toggle, shared with archived direct chats.
- [x] Preserve names/counts/times/history/drafts; group rows retain summary-only text.
- [x] Hidden, Sender only and Sender and message notification choices.
- [x] Legacy preference migration, safe fallback and Dart/native payload enforcement.
- [x] Active-alert redaction, rapid privacy guards and restrictive-failure suppression.
- [x] Independent local preference and temporary browser controls; no backup/wire change.
- [x] Focused tests: 33 passed; analysis: no issues.
- [x] All 572 tests (15 new), six Chrome UI checks and Android/web builds; see VALIDATION.md.
- [ ] Physical notification/restart/TalkBack checklist in PREVIEW_PRIVACY.md.
- [x] User committed the preview privacy milestone as `492dbb5`.

## Configurable auto-lock timing: implemented and committed

Implemented: 2026-10-16. Committed by the user as `f8c9cdc`.
See [AUTO_LOCK_TIMING.md](AUTO_LOCK_TIMING.md).

- [x] PIN-authorized Immediately/default, 30-second, 1-minute and 5-minute choices.
- [x] Immediate privacy cover, route removal and access/foreground invalidation.
- [x] One absence deadline; timer and resume checks, clock-change fail-closed behavior.
- [x] Launch/manual/detach/locked/busy states cannot inherit an unlocked grant.
- [x] V1->v2 secure lock record; PIN/biometric changes retain delay, generic retry.
- [x] Notification redaction/tap gating and existing background/session rules retained.
- [x] All 557 tests (20 new), eight Chrome UI checks and clean analysis.
- [x] Android/web builds and final review; see VALIDATION.md.
- [ ] Physical timing/biometric/notification/TalkBack checklist in AUTO_LOCK_TIMING.md.
- [x] User committed the milestone as `f8c9cdc`.

## Private contact nicknames: implemented and committed

Implemented: 2026-10-16. Committed by the user as `6e5afe8`.
See [CONTACT_NICKNAMES.md](CONTACT_NICKNAMES.md).

- [x] Set/edit/remove private labels from saved direct chat options and toolbar.
- [x] Original phone name remains separate; nicknames never enter wire/reply metadata.
- [x] Chat titles/lists, original-name and nickname search, starred-message labels.
- [x] Encrypted schema-14 storage, migration, restart and deletion cleanup.
- [x] V11 encrypted archives; older imports and destination-choice precedence.
- [x] Foreground/privacy/route guards, generic errors and enlarged-text editor.
- [x] All 537 tests (21 new), seven Chrome UI checks and clean analysis.
- [x] Android/web builds and final review; see VALIDATION.md.
- [ ] Physical phone/TalkBack checklist in CONTACT_NICKNAMES.md.
- [x] User committed the milestone as `6e5afe8`.

## Optional vibration feedback: implemented and committed

Implemented: 2026-10-16. Committed by the user as `f045c38`.
See [ACTION_FEEDBACK.md](ACTION_FEEDBACK.md).

- [x] Default-off saved toggle and explicit Try vibration control in Settings.
- [x] Android light touch feedback; browser/demo and unsupported paths stay silent.
- [x] Accepted direct/group text, attachments, explicit retries and code/QR actions.
- [x] Single-use requests with route, privacy, lifecycle and preference revision guards.
- [x] Platform errors/pending pulses never block or fail the accepted action.
- [x] Independent secure preference, recoverable read/write errors and no new permission.
- [x] All 516 tests (16 new), eight Chrome UI checks and clean analysis.
- [x] Final Android/web builds and diff review; see VALIDATION.md.
- [ ] Physical haptic/system-setting and TalkBack checks in ACTION_FEEDBACK.md.
- [x] User committed the milestone as `f045c38`.

## Text size and high contrast: implemented and committed

Implemented: 2026-10-15. Committed by the user as `09533a1`.
See [ACCESSIBILITY.md](ACCESSIBILITY.md).

- [x] Follow system / Larger (+15%) / Largest (+30%), preserving device scaling.
- [x] High contrast across light/dark palettes and device high-contrast support.
- [x] Live preview and preferences shared with Settings, chats, dialogs and PIN.
- [x] Backward-compatible appearance v2 storage, atomic parsing and failed-save retry.
- [x] Retain already-higher container contrast; matching group/attachment foregrounds.
- [x] Combined large-text layouts and bounded browser demo notice.
- [x] All 500 tests (12 new), 12 Chrome checks and clean analysis.
- [x] Final Android/web builds and diff review; see VALIDATION.md.
- [ ] Manual phone/browser/TalkBack checklist in ACCESSIBILITY.md.
- [x] User committed the milestone as `09533a1`.

## QR session verification: implemented and committed

Implemented: 2026-10-15. Committed by the user as `d84c754`.
See [QR_VERIFICATION.md](QR_VERIFICATION.md).

- [x] Show/scan QR for direct and individual pending host/guest connections.
- [x] Full transcript/reciprocal identity binding; wrong/self/old/member QR rejection.
- [x] Explicit local confirmation, both peers required and manual-code fallback.
- [x] Foreground/PIN/revision/session guards before and after queued async work.
- [x] Android-only camera, bundled offline models, denial/error/manual guidance.
- [x] Camera shutdown on match/exit/privacy loss and late-permission serialization.
- [x] All 488 tests (32 new) and 11 Chrome UI checks pass; clean analysis.
      Android/web builds and diff review pass; see VALIDATION.md.
- [ ] Manual phone/browser/TalkBack checks; see QR_VERIFICATION.md.
- [x] User committed the milestone as `d84c754`.

## Starred messages: implemented and committed

Implemented: 2026-10-15. Committed by the user as `04f5682`.
See [STARRED_MESSAGES.md](STARRED_MESSAGES.md).

- [x] Star/Unstar menus, selection actions, semantics and bubble markers.
- [x] Saved direct/group text, replies, images and files; archived history included.
- [x] Chats toolbar list, remove stars and exact direction/author original anchors.
- [x] Preserve drafts, unread while browsing, organization and receipts.
- [x] Foreground/PIN/revision/route guards and delayed-load cancellation.
- [x] Schema 13 encrypted references, keyed IDs, restart and atomic cleanup.
- [x] V10 encrypted backups, safe merge, identity rules and star counts in preview.
- [x] All 456 tests and 11 Chrome UI checks pass; clean analysis, Android/web
      builds and diff review. See [VALIDATION.md](VALIDATION.md).
- [ ] Manual Android/browser checks; see [STARRED_MESSAGES.md](STARRED_MESSAGES.md).
- [x] User committed the milestone as `04f5682`.

## Replies to text messages: implemented and committed

Implemented: 2026-10-14. Committed by the user as `4dae7fe`.
See [MESSAGE_REPLIES.md](MESSAGE_REPLIES.md).

- [x] Reply/Copy menus in direct/group text bubbles, selection and accessibility.
- [x] Author/preview composer card, cancel preserving text and independent drafts.
- [x] Sent/received quotes, exact original anchors and unavailable/Jump to latest.
- [x] PIN/foreground/revision gates, stale cancellation rejection and generic alerts.
- [x] Encrypted direct reply outbox/retry; capability gates preserve legacy plain text.
- [x] Signed group quotes, trusted-host relay and all-member reply capability gates.
- [x] Schema 12 encrypted quote drafts, atomic acceptance, migration and rollback.
- [x] V9 mixed backups retain older imports, destination choices and identity rules.
- [x] Final checks 2026-10-15: all 430 tests and 12 Chrome UI checks pass; clean
      analysis, Android/browser builds and review. See [VALIDATION.md](VALIDATION.md).
- [ ] Manual phone/browser checks; see [MESSAGE_REPLIES.md](MESSAGE_REPLIES.md).
- [x] User committed the milestone as `4dae7fe`.

## Copy text messages: implemented and committed

Implemented: 2026-10-14. Committed by the user as `b9ef43c`; local `origin/main`
matches. See [MESSAGE_COPY.md](MESSAGE_COPY.md).

- [x] Full-message copy in direct/group chats, offline history and search anchors.
- [x] Preserve selection, with Copy message/Copy selection and Select all.
- [x] Browser right-click menu and screen-reader Copy message action.
- [x] PIN/foreground/message/route gates, stale callback rejection and dismissal.
- [x] Exact Unicode/multiline text, generic success/failure and duplicate-tap guard.
- [x] Preserve drafts, history, receipts and chat organization; no storage changes.
- [x] All 395 tests and 13 Chrome checks pass; clean analysis, Android/browser builds
      and review. See [VALIDATION.md](VALIDATION.md).
- [ ] Manual clipboard/phone/browser checks; see [MESSAGE_COPY.md](MESSAGE_COPY.md).
- [x] User commits text copying (`b9ef43c`); local `origin/main` matches.

## Browser group simulation: implemented and committed

Implemented: 2026-10-13. Committed by the user as `83fc101`; the local
`origin/main` reference matches. See [BROWSER_GROUPS.md](BROWSER_GROUPS.md).

- [x] Browser factory selects in-tab simulated host/guests; Android keeps native transport.
- [x] Create/find/join with clear demo labels and explicit local code confirmation.
- [x] Signed/encrypted simulated messages, member receipts and image/file transfers.
- [x] Saved drafts, unread, pin/archive, search, deletion and demo backups work.
- [x] Rehosting/rediscovery require fresh confirmation; mode changes cancel old replies.
- [x] PIN/access gates, isolated tabs and stop/disposal/initialization cancellation.
- [x] All 382 tests pass, clean analysis, Android/browser builds and review.
- [x] All 20 new checks pass in headless Chrome; see [VALIDATION.md](VALIDATION.md).
- [ ] Manual browser checklist; see [BROWSER_GROUPS.md](BROWSER_GROUPS.md).
- [x] User commits browser group simulation (`83fc101`); local `origin/main` matches.

## Background protection for hosted groups: implemented and committed

Implemented: 2026-10-13. Committed by the user as `734ea96`; the local
`origin/main` reference matches. See [GROUP_BACKGROUND.md](GROUP_BACKGROUND.md).

- [x] Reuse Keep connection active for admitted, freshly verified group links.
- [x] Foreground-unlock startup, native live-link/access checks and generic Stop.
- [x] Locked/background text receive/save/ACK and trusted-host relay/receipts.
- [x] Preserve privacy, unread, drafts and pin/archive; keep new sends/admission/
      attachments foreground-only.
- [x] Bound received-frame wake work; release on processing/error/cancellation.
- [x] Handle member departure, last verified-link loss, mode changes and stale Stop.
- [x] Group Retry/settings guidance, no failed-start retry loop and no auto-reconnect.
- [x] All 22 new controller/channel/widget checks pass.
- [x] All 362 tests pass, clean analysis, final Android/browser builds and review;
      see [VALIDATION.md](VALIDATION.md).
- [ ] Physical three-phone/lifecycle/battery checks; see [GROUP_BACKGROUND.md](GROUP_BACKGROUND.md).
- [x] User commits group background protection (`734ea96`); local `origin/main` matches.

## Saved group message search: implemented and committed

Implemented: 2026-10-13. Committed by the user as `6f342bb`; the local
`origin/main` reference matches. See [GROUP_SEARCH.md](GROUP_SEARCH.md).

- [x] Search saved group names/messages from Chats, including archived groups.
- [x] Scoped group search, literal Unicode matching, author/time and highlights.
- [x] Exact author/message anchors, lazy surrounding history and Jump to latest.
- [x] Preserve drafts/organization/unread; refresh receiving/imports/deletion.
- [x] Cancel stale work, clear locked/background results and gate navigation.
- [x] Search existing decrypted histories without a plaintext index; schema 11
      and v1-v8 backups stay compatible.
- [x] All 340 tests pass, clean analysis, Android/browser builds and review;
      see [VALIDATION.md](VALIDATION.md).
- [ ] Physical phone checklist; see [GROUP_SEARCH.md](GROUP_SEARCH.md).
- [x] User commits group search (`6f342bb`); local `origin/main` matches.

## Pinning and archiving group chats: implemented and committed

Implemented: 2026-10-13. Committed by the user as `f07316d`; the local
`origin/main` reference matches this commit. See [GROUP_MANAGEMENT.md](GROUP_MANAGEMENT.md).

- [x] Pin/unpin groups with stable ordering and unchanged activity/read state.
- [x] Archive/unarchive from saved lists and chat screens; combined archive counts.
- [x] Keep messages, attachments, drafts, notifications and active connections.
- [x] PIN/foreground gates, stale-menu rejection and generic error handling.
- [x] Schema 11 preserves existing ciphertext; history writes retain local choices.
- [x] V8 mixed backups retain v1-v7 imports and destination-choice precedence.
- [x] All 324 tests pass, clean analysis, final Android/browser builds and review;
      see [VALIDATION.md](VALIDATION.md).
- [ ] Physical checks; see [GROUP_MANAGEMENT.md](GROUP_MANAGEMENT.md).
- [x] User commits group pin/archive (`f07316d`); local `origin/main` matches.

## Saved group drafts: implemented and committed

Implemented: 2026-10-12. Committed by the user as `2a83b30`.
See [GROUP_DRAFTS.md](GROUP_DRAFTS.md).

- [x] Independent encrypted group drafts; offline editing and exact restoration.
- [x] Restore on navigation, PIN unlock, rehosting and Android restart.
- [x] Atomic text acceptance clears only the captured draft; failed sends and newer edits survive.
- [x] Retry for load/save errors; image/file flows preserve drafts.
- [x] Schema 10 preserves existing history; v7 backups retain v1-v6 imports.
- [x] Safe merge, deletion and import/send race handling across direct/group drafts.
- [x] All 303 tests pass, clean analysis, Android/browser builds and review;
      see [VALIDATION.md](VALIDATION.md).
- [ ] Physical phone checks; see [GROUP_DRAFTS.md](GROUP_DRAFTS.md).
- [x] User commits group drafts (`2a83b30`).

## Files in hosted groups: implemented and committed

Implemented: 2026-10-12. Committed by the user as `5a92e71`.
See [GROUP_FILES.md](GROUP_FILES.md).

- [x] Pick/review/discard local files up to 8 MiB; preserve composer text.
- [x] Signed encrypted upload/host relay, progress/cancel and individual receipts.
- [x] Shared group attachment handling, safe names, independent capability gates.
- [x] Foreground/privacy/membership gates and encrypted pending selections.
- [x] Encrypted stored files and confirmed offline export; PIN covers dialogs.
- [x] Payload-v6 mixed backups retain v1–v5 imports; SQLite stays schema 9.
- [x] All 279 tests pass, clean analysis, final Android/browser builds and review;
      see [VALIDATION.md](VALIDATION.md).
- [ ] Physical three-phone checks; see [GROUP_FILES.md](GROUP_FILES.md).
- [x] User commits group files (`5a92e71`).

## Images in hosted groups: implemented and committed

Implemented: 2026-10-12. Committed by the user as `318b304`.
See [GROUP_IMAGES.md](GROUP_IMAGES.md).

- [x] Group image pick/review/discard, signed upload and trusted host relay.
- [x] Per-link progress/cancel and complete-store individual receipts.
- [x] Foreground/unlock gates, sealed selections and membership cancellation.
- [x] Encrypted saved PNGs, offline zoom, generic previews and PIN route removal.
- [x] All-member capability negotiation; older members retain text.
- [x] Payload-v5 backups retain v1–v4 imports; SQLite schema remains 9.
- [x] All 250 tests pass, clean analysis, Android/browser builds and diff review;
      see [VALIDATION.md](VALIDATION.md).
- [ ] Physical three-phone checks; see [GROUP_IMAGES.md](GROUP_IMAGES.md).
- [x] User commits group images (`318b304`).

## File sharing in direct chats: implemented and committed

Implemented and validated, 2026-10-12. Committed by the user as `3ec26b5`.

- [x] Pick a local nonempty file up to 8 MiB, review/discard and explicitly send.
- [x] Shared encrypted chunk engine, safe names, digest/length checks, progress/cancel.
- [x] Foreground/unlock gates, sealed pending selections and explicit original-ID retry.
- [x] Encrypted saved files, offline confirmed export, unread/privacy/deletion behavior.
- [x] Schema 9 and v4 backups retain existing history and older archive imports.
- [x] All 228 tests pass and final analysis is clean; see [VALIDATION.md](VALIDATION.md).
- [x] Final code/diff review, Android/browser builds and documentation.
- [ ] Physical two-phone checks; see [FILE_SHARING.md](FILE_SHARING.md).
- [x] User commits direct file sharing (`3ec26b5`).

## Image sharing in direct chats: implemented and committed

- [x] Pick a local image, preview/discard and explicitly send after verification.
- [x] Bound source size/pixels; resize/re-encode PNG without source metadata.
- [x] Encrypted acknowledged chunks, progress/cancellation and complete-store receipts.
- [x] Foreground/unlock gates; no automatic image outbox, retry or resume.
- [x] Encrypted saved images, offline zoom viewing, unread/privacy/deletion behavior.
- [x] Schema 8 preserves existing records; v3 backups include validated images
      while retaining v1/v2 imports and safe merge/identity rules.
- [x] Older peers retain text support; browser recipient/receipts remain simulated.
- [x] All 203 tests pass, clean final analysis and Android/browser builds;
      see [VALIDATION.md](VALIDATION.md).
- [x] User commits image sharing (`aea566b`).
- [ ] Physical two-phone checks; see [IMAGE_SHARING.md](IMAGE_SHARING.md).

## Hosted nearby group text chats: implemented and committed

- [x] Create/find/join one nearby Android-hosted group; up to eight members
      including the host, subject to hardware capacity.
- [x] Separate host–guest encrypted sessions and both fresh confirmations;
      host approves members and reads/relays messages. The UI explains this trust.
- [x] Signed author/group/epoch/roster/recipient envelopes, per-member receipts,
      membership updates/removal, dedupe and isolated bad-link closure.
- [x] Encrypted saved history, unread counts, lock-aware notification taps,
      offline viewing, confirmed deletion and original-host rehosting.
- [x] Schema 7 preserves direct chats; backups include validated groups with
      version-2 payloads, version-1 import compatibility and safe merging.
- [x] No old history for new members; no automatic reconnect/retry, host migration
      or group background-service claim. Direct outbox/background mode stay intact.
- [x] All 185 tests pass, clean final analysis and Android/browser builds;
      see [VALIDATION.md](VALIDATION.md).
- [x] User commits hosted group chats (`819ac32`).
- [ ] Physical three-phone checks; see [GROUP_CHATS.md](GROUP_CHATS.md).

## Optional background connection protection: implemented and committed

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
- [x] User commits background connection protection (`24d52b5`).
- [ ] Physical phone/Doze/vendor testing;
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

- [x] Hosted group text chats: create/find/join, member list, host–guest verification,
      per-member receipts and saved history. Host must remain connected and is a
      trusted relay; see [GROUP_CHATS.md](GROUP_CHATS.md). Hardware checks pending.
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
- [x] Optional direct-chat automatic reconnection with fresh verification.
      All 624 tests pass; physical checks pending. See AUTOMATIC_RECONNECT.md.
- [x] Pin, archive and delete individual conversations.
- [x] Connection troubleshooting: Wi-Fi, permissions, discovery, retry actions
      and manual Reconnect to a device still listed.
- [x] Local notifications with hidden message previews by default and lock-aware taps.
- [x] Optional background connection mode with battery/connection controls;
      protects a current running verified direct/group session, subject to Doze/vendor limits.
- [x] Copy text messages in direct/group chats, including selection and offline history.
- [x] Reply to text messages in direct/group chats, with quotes, drafts and backups.
- [x] Starred messages in direct/group chats, with encrypted persistence and backups.
- [x] QR session verification for direct/group links; Android camera and manual fallback.
      Physical offline/camera checks pending; see QR_VERIFICATION.md.
- [x] Accessibility: adjustable text size and high contrast; see ACCESSIBILITY.md.
- [x] Optional vibration feedback; Android action pulses with saved opt-in.
      Physical checks pending; see ACTION_FEEDBACK.md.
- [x] Direct-chat images: encrypted transfer, progress, cancellation, bounds,
      preview, offline viewer and encrypted backup support; hardware checks pending.
- [x] Direct-chat files: implemented with bounds/progress/cancel, encrypted
      storage/backups and explicit offline export; hardware checks pending.
- [x] Group images: signed encrypted upload/relay, progress/cancellation,
      individual receipts, offline viewing and backups; hardware checks pending.
- [x] Group files: signed upload/relay, progress/cancel, individual receipts,
      encrypted history/backups and confirmed offline export; hardware checks pending.
- [x] Private local contact nicknames independent of advertised display names.
      Physical checks pending; see CONTACT_NICKNAMES.md.

## Later refinements discussed

- [x] Saved group drafts; encrypted storage and backup support. Hardware checks pending.
- [x] Group pin/archive; persisted choices and backup support. Hardware checks pending.
- [x] Saved group message search; 340 tests pass. Physical checks pending.
- [x] Group background protection; 362 tests pass. Physical checks pending.
- [x] Browser group simulation; 382 tests and 20 Chrome checks pass. Manual checks pending.

- [x] Configurable auto-lock timing with immediate privacy and notification redaction.
      Physical checks pending; see AUTO_LOCK_TIMING.md.
- [x] Chat-list privacy and three notification preview modes.
      Physical checks pending; see PREVIEW_PRIVACY.md.
- [x] Clearer group delivery feedback for member departures and host loss.
      All 591 tests pass; physical checks pending. See GROUP_DELIVERY.md.
- [x] Backup format versioning, validation and explicit identity-migration flow.

## Proposed order after app lock

1. Chats/Nearby navigation (committed).
2. Themes (committed).
3. Chats list previews/unread state, local search and drafts (committed),
   conversation management (committed).
4. Encrypted backups and phone migration (committed).
5. Offline outbox and retry (committed), connection troubleshooting/manual
   reconnection and notifications (committed), background connection support (committed).
6. Hosted group text chat (committed).
7. Direct-chat image/file sharing and group images/files (committed).
8. Saved group drafts, group pin/archive and group search (committed).
9. Group background protection (committed), browser group simulation (committed).
10. Copy text messages (committed); replies to text messages (committed).
11. Starred messages (committed).
12. QR scanning for session verification (committed).
13. Accessibility: adjustable text size and high contrast (committed); optional
    vibration feedback (committed).
14. Private local contact nicknames (committed).
15. Configurable auto-lock timing (committed).
16. Preview privacy controls (committed).
17. Clearer group delivery feedback for departures and host loss (committed).
18. Optional direct-chat automatic reconnection with fresh verification (current).

The user chose app lock first so it can be tested before committing. This order
can change; unchecked items are plans, not existing capabilities.
