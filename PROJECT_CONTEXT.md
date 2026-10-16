# LocalChat project context

Updated: 2026-10-16. The workspace is authoritative; read README.md,
docs/SECURITY.md, docs/VALIDATION.md and the relevant code before making changes.

## Goal and scope

LocalChat was created in ChatGPT and continued in this Flutter workspace.
It enables nearby offline messaging without a router, mobile data, accounts,
backend, Firebase or cloud database. Version 0.1 is Android-first, with direct
text/images/files and hosted text/image/file groups. Video playback, Bluetooth, multi-hop relaying, iOS and
automatic reconnect are also future work. Local notifications and optional
background protection of the current running verified session are implemented;
Doze/vendor restrictions still apply and hardware reliability is unvalidated.

The complete requested/suggested feature list is in `docs/FEATURE_BACKLOG.md`.
The user chose app lock first and committed it as `df3c2b3`.
Navigation was committed as `abe4dc3`, and themes as `b353956`.
Chats list improvements were committed as `c233159`, and local search as
`a2c7aa3`; drafts were committed as `9e90550`, and conversation management as
`8f55377`; encrypted backups/phone migration were committed as `63eff9f`.
Outbox/retry was committed as `605962e`; connection recovery as `c7d4d6e`.
Notifications were committed as `9bb6c60`, and background protection as `24d52b5`.
Hosted group chats were committed as `819ac32`, and images as `aea566b`.
Direct files were committed by the user as `3ec26b5`.
Group images were committed by the user as `318b304`.
Group files were committed by the user as `5a92e71`.
Group drafts were committed by the user as `2a83b30`.
Group pin/archive was committed by the user as `f07316d`.
Group search was committed by the user as `6f342bb`.
Group background protection was committed by the user as `734ea96`.
Browser group simulation was committed by the user as `83fc101`.
Text copying was committed by the user as `b9ef43c`.
Replies to text messages were committed by the user as `4dae7fe`.
Starred messages were committed by the user as `04f5682`.
QR verification was committed by the user as `d84c754`.
Text size and high contrast were committed by the user as `09533a1`.
Optional vibration feedback was committed by the user as `f045c38`.
Private contact nicknames were committed by the user as `6e5afe8`.
The current milestone is configurable auto-lock timing.
Work on one milestone at a
time; the user will stage, commit and push it themselves after testing.

## Auto-lock timing - implemented locally, 2026-10-16

Baseline: `6e5afe8`; clean worktree at startup. User handles Git.
See docs/AUTO_LOCK_TIMING.md and docs/VALIDATION.md.

- Settings > App lock > Auto-lock timing: current-PIN authorized Immediately
  (default), 30s, 1m or 5m. Version-2 record in app_lock_v1 adds autoLockSeconds;
  v1 migrates as immediate without startup rewrite. Other lock data/cost unchanged.
- Background always closes root routes, covers UI and sets chat access/foreground
  false immediately. A valid quick return skips PIN but opens Chats; pushed routes
  and unsaved dialog/PIN fields do not survive. Existing drafts stay saved.
- One timer/grant per absence, from first loss of focus. Later hidden/paused
  events do not reset it. Resume checks both wall and elapsed ages, including
  exact expiry/negative ages, rather than depending on timer execution.
- Launch/reinitialize, Lock now, detach, already-locked and busy lock operations
  require authentication. Grant is memory-only, cleared on return/lock/disposal.
  Biometric inactive-dialog exception stays covered; real background rejects
  late acceptance. Authorized submitted setting writes can finish without unlock.
- Notification previews redact/taps wait, native FLAG_SECURE stays enabled, and
  existing background receive/relay and stale-action/verification rules remain.
  No native/runtime package, SQLite-14, backup-v11, identity or wire change.
  fake_async 1.3.3 is now an explicit test dependency, already cached/transitive.
- All 557 tests (20 new), eight Chrome UI checks and clean analysis pass.
  Android/web builds and final diff review pass; consult VALIDATION.md. Physical
  timing, system picker, biometric, TalkBack and Recents checks remain pending.
- All changes remain saved locally for user Git, including pubspec.yaml and
  pubspec.lock for the test dependency. Do not start another milestone without
  user direction.

## Private contact nicknames - implemented and committed, 2026-10-16

Baseline: `f045c38`; clean working tree at startup. User handles Git.
See docs/CONTACT_NICKNAMES.md and docs/VALIDATION.md.

- Set/Edit/Remove nickname in saved direct chat options (Chats, archive, toolbar).
  Unicode/single-line, trim and 128 UTF-8 byte bound; original phone name visible.
  Generic errors preserve input for retry; large-text scrollable dialog.
- Conversation.originalName holds the advertised name, nickname is separate,
  name getter resolves the local label. selectedName stays original for replies;
  selectedDisplayName is UI-only. No nicknames sent to peers or used for trust.
- Labels appear in chats/titles/search/stars; both original and private names are
  searchable. Edits refresh historyRevision but preserve drafts/unread/activity,
  organization, outbox and live sessions. Group author names are unchanged.
- SQLite 14 nullable peers.nickname encrypts with existing history key and
  peer-bound nickname AAD. Idempotent migration, restart, deletion and rollback.
  V11 backups validate optional peer nickname; new contacts inherit, existing
  destination choices (including absence) win. Retains v1-v10 imports and existing
  envelope/KDF/identity constraints. Browser uses temporary in-tab DemoStore.
- Editor dismisses/clears on lock/background; controller/store check privacy
  revision and route before writes, including after encryption. Submitted database
  writes can finish. All 537 tests, seven Chrome UI checks and clean analysis
  pass. Final Android APK/web builds and diff review pass; consult VALIDATION.md.
  Physical restart, peer privacy, backup transfer and TalkBack checks remain pending.
- Committed by the user as `6e5afe8`. Auto-lock timing is now the current
  milestone above.

## Action-feedback milestone - implemented locally, 2026-10-16

Baseline: `09533a1`; clean working tree at startup. The user handles Git.
See docs/ACTION_FEEDBACK.md and docs/VALIDATION.md.

- Settings > Action feedback adds Vibration feedback (off by default) and explicit
  Try vibration. Separate action_feedback_v1 secure-storage record; browser/demo
  uses memory and never outputs action vibration. Appearance remains JSON v2.
- Android adapter uses Flutter HapticFeedback.lightImpact (VIRTUAL_KEY), preserving
  OS touch-feedback behavior without adding VIBRATE permission or native code.
- Shared UI helper wraps successful local direct/group text/image/file sends,
  explicit direct retries and manual/QR connection confirmation. No automatic
  outbox, receipt, relay or scan-only pulse. Acceptance is not a delivery receipt
  or the other phone's confirmation. Wire/controllers' trust rules are unchanged.
- Single-use tickets capture preference revision plus origin route and root
  foreground/access revision. Late results after cover/disposal/lock/background
  or preference toggling cannot pulse. Overlapping native requests coalesce;
  errors are swallowed and physical output is never awaited by the action.
  An already submitted Android effect cannot be recalled.
- Eight service/adapter and eight UI checks cover persistence/errors, single-use,
  privacy/revisions, nonblocking native output, demo/unsupported silence, actual
  stored direct text, signed group sends/admission, explicit QR and enlarged UI.
  All 516 tests and eight Chrome UI checks pass; analysis is clean. Final Android
  APK/web builds and review pass; see VALIDATION.md. Actual vibration/OS settings and TalkBack
  remain pending. SQLite 13, backups v10, appearance v2 and dependencies unchanged.
- Committed by the user as `f045c38`. Private contact nicknames are now the
  current milestone above.

## Readability milestone - implemented, 2026-10-15

Baseline: `d84c754`; committed by the user as `09533a1`. The user handles Git.
See docs/ACCESSIBILITY.md, docs/THEMES.md and docs/VALIDATION.md.

- Appearance adds Follow system / Larger (+15%) / Largest (+30%), a high-contrast
  switch and preview. Root MediaQuery composes the existing nonlinear scaler with
  added enlargement; no cap/reduction or replacement of device scaling. Routes,
  profile edits, tabs, drafts and independent lock gating are preserved.
- Both light/dark themes support explicit or OS-reported high contrast in every
  palette. Material contrast level 1 is used, retaining existing container pairs
  with higher contrast. Matching bubble foregrounds fix outgoing group text and
  keep direct/group attachment labels, buttons and icons readable.
- Appearance v2 extends the existing secure-storage entry; v1 mode/palette migrate
  with default new choices and no startup rewrite. Whole-record parsing, save
  serialization, previous applied/saved choices on failure and retry remain.
- Browser preferences remain temporary. Its notice scrolls in a bounded area at
  large text/short windows instead of pushing app content outside the viewport.
- Twelve new migration/scaling/controller/UI checks, including PIN appearance,
  combined 2.34 text on 320 x 568, device high contrast/brightness and all enhanced
  palettes. All 500 tests and 12 Chrome checks pass; analysis is clean.
  Android APK/web builds and diff review pass; see VALIDATION.md.
  Actual Android restart/font settings, TalkBack and manual browser checks remain
  pending. No native/permission/package/wire changes; SQLite 13 and backups v10.
- Committed by the user as `09533a1`. Optional vibration is the current
  milestone above.

## QR-verification milestone - implemented, 2026-10-15

Baseline: `04f5682`; committed by the user as `d84c754`. The user handles Git.
See docs/QR_VERIFICATION.md and docs/VALIDATION.md for controls/results.

- Show QR / Scan QR for direct and individual pending group links; explicit local
  Verify connection, both peers still required, and original manual controls.
- Bounded six-field JSON binds mode, full signed-hello transcript hash and
  reciprocal public identity IDs. Self/wrong/old/member QR codes fail; no URLs
  open, secrets persist, or protocol payloads change. Group host trust is unchanged.
- Captured requests bind controller/session/link/peer and interactionRevision.
  Controllers recheck before queued encryption and after encryption/send. An
  interrupted encrypted confirmation closes only the same session/affected link.
- Android-only mobile_scanner 7.1.4 with explicitly bundled ML Kit models;
  qr_flutter 4.1.0 renders black/white QR. Manifest camera permission and optional
  camera hardware added. Existing Android toolchain is retained. No web scanner
  or CDN fallback starts; browser QR/manual controls remain simulated.
- Camera stops on match/mode/exit/error/privacy loss. Serialized startup/shutdown
  prevents late permission completion disposing a replacement. First permission
  prompts can expire the view and trigger PIN: unlock/reopen scanning afterward.
- 16 new protocol/controller, five native-platform fake camera and eleven UI
  checks. Tests verify rendered QR pixels, privacy/queue/send races, reconnect,
  explicit two-sided trust, group isolation and enlarged-text/manual controls.
  All 488 tests and eleven Chrome UI checks pass; analysis is clean and final
  Android APK/web builds pass. See VALIDATION.md; actual phone decoding/permission,
  first-use offline and TalkBack checks remain pending, not passed by mocks.
- SQLite stays schema 13; backups stay v10. No history/identity transfer changes.
  Committed by the user as `d84c754`. Text size/contrast is now the current
  milestone above; vibration remains planned.

## Starred-messages milestone - implemented, 2026-10-15

Baseline: `4dae7fe`; committed by the user as `04f5682`.
See docs/STARRED_MESSAGES.md and docs/VALIDATION.md. The user handles Git.

- Private local stars cover direct/group text, replies, images and files. Shared
  menus/selection/semantics offer Star/Unstar; attachment menus omit text actions.
  Bubble markers and a Chats toolbar saved list include archived histories.
  Exact direction/author anchors reuse lazy history; drafts/organization stay intact.
- Schema 13 adds message_stars: HMAC-SHA256 keyed reference IDs plus XChaCha20-
  Poly1305 reference ciphertext/AAD. No body copies, migration rewrite, native,
  dependency or wire changes. Browser demo remains in memory.
- V10 archives validate bounded references, preserve old v1-v9 imports, add stars
  only for imported/identical originals, retain destination stars and re-encrypt
  atomically. Preview/success counts explain additive restore without tombstones.
  Existing identity-transfer/history-only rules and archive encryption are unchanged.
- Conversation/group deletion, queued cancellation and clear remove stars atomically.
  Root cache refreshes coalesce and use generation/history revisions. Foreground,
  PIN and route checks invalidate obsolete callbacks; the list clears decrypted
  rows on privacy loss and rejects delayed results. Authorized writes may finish.
- All 456 tests pass, exit 0 (430 existing + 26 new), 4m20s; clean analysis.
  Ten model/controller/archive, eleven UI and five native SQLite cases are new.
  All eleven UI checks also pass in headless Chrome, including actual group-image
  decoding with both frame and real-time clocks driven before route disposal.
  The existing cached-CanvasKit test-server workaround remains necessary.
  Android debug APK and web builds pass; see VALIDATION.md for commands/logs.
  Manual phone/browser/TalkBack checks remain pending. The user committed
  the milestone as `04f5682`.

## Message-replies milestone - implemented, 2026-10-14

Baseline: `b9ef43c`; committed by the user as `4dae7fe`. The user handles Git.
See MESSAGE_REPLIES.md and VALIDATION.md. Final validation on 2026-10-15:
**430 tests pass**, exit 0
(395 prior + 35 new), 4m52s; **12 Chrome UI checks pass**, clean analysis and
Android/browser builds. Manual device/browser checks remain pending.

- MessageReply holds a bounded 512-byte trimmed Unicode preview, author label,
  original ID and local direction (direct) or identity author ID (groups). Direct
  receivers invert reference direction; it remains stable across history/identity
  imports. Quotes are supplied by the responder, not original-author proof.
- Shared text menus/selection/semantics add Reply beside Copy. Both screens show
  composer preview/cancel, preserve text, display sent/received quotes, and anchor
  exact older originals using existing lazy lists. Missing/conflicting originals
  show a generic notice. Jump to latest resets scroll without changing drafts.
- DraftController owns quote selection with text/revision/target epochs. Quote-only
  drafts persist, cancellations keep text, save/load failures retry, and matching
  acceptance clears text+quote atomically. Newer edits and quotes not included in
  a send are preserved. Deleted histories cannot regain queued draft writes.
- SQLite 12 adds encrypted reply_drafts with scope/target AAD and an authenticated
  direct-message kind reply; ordinary plaintext-in-ciphertext bodies, including
  literal JSON, retain their format. Old ciphertext is not rewritten on upgrade.
  Group quotes remain in encrypted signed group history. No native/package changes.
- Direct verified features negotiate reply-v1; outbox retries retain metadata/ID.
  Older peers keep plain text; a queued reply waits at the front rather than losing
  its quote. Group links/rosters negotiate group-reply-v1; all admitted members
  must support it. The group-reply/1 signature domain binds quote fields, context
  and recipients; modification/insertion/removal fails. Departed authors can be
  quoted. Replies deliberately share that preview with current/new members.
- V9 quote-bearing archives include reply-only drafts and mixed histories; v1-v8
  imports remain supported. Plain exports keep their applicable previous version.
  Safe merge compares quotes, destination drafts win, migration re-encrypts data
  and imported pending replies remain unconfirmed, never automatically sent.
- interactionRevision records foreground/access changes for reply operations
  without changing existing background-service authorization. Selection, cancel,
  navigation and sending recheck privacy/source/route/lifetime. Quote cards hide on
  background/lock and notifications retain only answer bodies. Group acceptance
  interrupted by privacy keeps unconfirmed history and preserves newer drafts.
- New coverage: 17 model/protocol/draft/archive, 12 UI (including live group send)
  and six native encrypted migration/reopen/rollback/import checks. Initial focused
  passes corrected stale schema expectations/idempotent migration fixtures and UI
  label/finder issues. The live group UI fixture now drives fake-clock UI work
  and real-time crypto/peer queues together; waiting on idle without pumping
  caused the old fixture stall. Temporary probes were removed. One existing
  400ms file-transfer check failed during concurrent builds, passed in isolation
  unchanged, and passed in the final complete regression without builds running.
- Browser direct demo acknowledges replies and quotes its response to a quoted
  answer. Simulated group controllers use the same new features and signatures.
  Browser test fixtures acknowledge the engine-only context menu channel, run
  cryptography outside fake time, and use the cached-CanvasKit server workaround.
  Physical/manual checks remain pending. The user commits/pushes themselves.

## Message-copy milestone - implemented, 2026-10-14

Baseline: `83fc101`; the user committed this milestone as `b9ef43c`.
The user handles Git.
See docs/MESSAGE_COPY.md and docs/VALIDATION.md.

- Shared TextMessageActions wraps text bubbles in both screens. Bubble padding/
  timestamps support long-press and browser secondary-click -> Copy; text keeps
  selection with Copy message, Copy selection and Select all. Custom semantics
  provide a screen-reader action; highlighted group search remains selectable.
- Exact original bodies (Unicode/whitespace/newlines) are written via Flutter
  Clipboard.setData. Failure/success notices are generic. A pending write rejects
  duplicate taps; copies do not change drafts/history/receipts/organization.
- Guard initialized/foreground/unlocked state, current route, access revision,
  message key/body/kind and widget lifetime. Root notifications synchronously
  invalidate callbacks on privacy/target loss; surviving overlays close at the
  frame boundary. Lock removes pushed dialogs/routes as before. Delayed platform
  completions cannot show a stale confirmation. Direct keys include direction;
  group keys include author to handle colliding message IDs.
- Browser startup disables the native context menu so Flutter-rendered selection
  actions work. No native, dependency, schema, backup or wire changes.
- Clipboard data is outside app encryption/lock; authorized writes can finish
  after locking and are not automatically erased. Existing keyboard selection
  shortcuts remain Flutter behavior. Do not claim secure clipboard erasure.
- Thirteen new widget checks intercept Clipboard method calls for exact values,
  errors/delays, privacy/deletion races, PIN removal, group search/drafts/flags,
  same-ID directions/authors, small-screen semantics, right-click dismissal and
  attachment isolation. Final full regression: **395 passed**, exit 0 (382 prior
  + 13 new), 5m06s; separate final VM13 and Chrome13 checks pass. Analysis is clean
  and Android/browser builds pass. See VALIDATION.md for exact commands/logs.
- Chrome uses the existing cached-CanvasKit test-server workaround. Widget tests
  acknowledge the browser context-menu engine channel and intercept clipboard
  calls; actual browser permission/paste behavior remains a manual check. Fixture
  backup/PIN crypto uses real time and read-state snapshots wait for the opening
  read to settle. Temporary probes were removed. No SDK or app protocol changes.
- Manual clipboard paste/browser-permission and Android device checks are pending.

## Browser-group milestone - implemented, 2026-10-13

Baseline: `734ea96`. The user committed this milestone as `83fc101`.
The user handles Git. See docs/BROWSER_GROUPS.md and docs/VALIDATION.md.

- main.createDemoController() explicitly injects DemoGroupTransport only for the
  browser factory. Android retains WifiGroupTransport/LocalStore/native services.
  ChatController exposes simulatedGroups/canUseGroups for UI capability gates;
  fallback demo/test controllers do not accidentally start simulated peers.
- DemoGroupTransport creates private GroupControllers and in-memory endpoints,
  with stable per-tab simulated identities and ordinary encrypted handshakes,
  signed group envelopes, rosters, receipts and image/file transfers. Hosting
  offers Ava/Noah pending guests; discovery offers Ava's Weekend plans room with
  Noah as another guest. Remote demo participants confirm automatically; the
  visible local controller still needs explicit Codes match and foreground access.
- Simulated members greet/reply through the real controller, without canned
  receipt success or a protocol shortcut. Root history/drafts/unread/search/
  pin/archive/delete and demo-only backups use the existing storage/controller.
  Rehosting preserves local history/choices and starts a fresh epoch; rediscovery
  retains the per-tab simulated host and room while requiring new confirmation.
- Generations filter stale queued events; stopping/mode switching closes hidden
  controllers and cancels reply/verification/receipt timers. Initialization checks
  cancellation before attaching listeners. Root disposal closes demo streams and
  private stores. Separate tabs/reloads have independent temporary data.
- Group hub/create/verification/chat screens identify the demo; real Android
  code-comparison and host-trust instructions remain. Browser rehosting works;
  PIN locking hides routes/dialogs and preserves local admission/send gates.
  Background controls are simulated, with no OS service/network/hardware claim.
- Final full regression: **382 passed**, exit 0 (362 prior + 20 new), including
  15 protocol/controller and five widgets. Analysis is clean; final Android arm64
  APK and browser builds pass. No packages/native/schema/backup/wire changes.
- Chrome checks initially stalled because Flutter 3.38.7's Windows test server
  returned 404 for present CanvasKit files (fromUri creates backslashes but the
  handler checks a forward-slash prefix). A workspace-only CDP helper serves
  exact cached SDK assets to the isolated test browser; app/SDK are unchanged.
  Chrome smoke test passes; final Chrome protocol and UI runs pass **15 + 5**
  checks, exit 0. VM widget fixtures use real-time guest setup/confirmation and
  PIN hashing, and explicitly dispose pending verification timers before checks.
  Helpers/raw logs are ignored in .dart_tool. Manual browser/physical checks remain
  pending. Never claim simulation validates Android networking/security/battery.

## Group-background milestone - implemented, 2026-10-13

Baseline: `6f342bb`. The user committed this milestone as `734ea96`.
The user handles Git. See docs/GROUP_BACKGROUND.md and docs/VALIDATION.md.

- Reuses BackgroundConnection/ConnectionService and the existing local opt-in.
  GroupController exposes current transportGeneration/backgroundReady (at least
  one admitted/verified link) and receives the shared BackgroundConnection.
  Empty hosting, discovery and pending/unverified links cannot start protection.
- Native direct generations are nonnegative; group generations are negative
  `-(transportEpoch + 1)`. Group connected/frame events carry this token. Dart
  synchronizes admitted IDs via background groupLinks; native checks current
  room/live admitted sockets and local access. Group status/Stop includes the
  generation; direct cleanup and stale Stop/status cannot affect another lease.
- Root requests group protection on verified topology changes, explicit opt-in/
  Retry and foreground/unlock, rather than on every received message/draft update.
  Failures leave foreground group messaging usable, with group-capable Settings Retry.
  Starting requires foreground unlock; an already authorized start may complete
  while locked. There is no background new-send/admission/attachment capability.
- Locked/background hosts save signed text before relaying and return receipts;
  guests persist/ACK. Existing visible-read gates and generic alerts preserve
  unread/privacy, drafts, organization and attachments. One verified member
  leaving keeps the host protected; losing the last releases protection despite
  pending guests. Notification Stop ends/leaves the room and disables preference.
- Authorized native group frames acquire bounded existing wake work; held flags
  reach Dart and complete in finally, including malformed/ignored/stale frames.
  Native cancellation before delivery and service/connection teardown release it.
  Unverified links do not acquire this group wake work. No idle CPU/Wi-Fi lock.
- Settings/group hub explain group text support and foreground attachment limits.
  No packages, native permissions, schema, backup payload or encrypted wire change.
  SQLite remains schema 11 and backups retain v1-v8 compatibility. Browser has
  simulated controls; hardware group hosting/background protection is Android-only.
- 22 new checks pass (19 controller/channel and three Settings/PIN widgets),
  including signed three-phone relay, approvals, privacy/unread/drafts/flags,
  Stop/loss, member departure, mode switching, stale events, queued start/sync
  cancellation, held-frame cleanup, permission/service failure and explicit Retry.
  Final full regression: **362 passed**, exit 0 (340 prior + 22 new), with
  `--concurrency=2 --timeout=2m`; clean analysis and final Android/browser builds.
  Ignored logs are in .dart_tool. Physical screen-off/Doze/vendor/lifecycle checks
  remain pending and must not be represented as validated hardware delivery.

## Group-search milestone - implemented, 2026-10-13

Baseline: `f07316d`. The user committed this milestone as `6f342bb`.
The user handles Git. See docs/GROUP_SEARCH.md and docs/VALIDATION.md.

- Shared ChatSearchController/ChatSearchScreen search direct chats plus saved
  group names/messages, or scope to one group from its toolbar. Archived groups
  are included; viewing/opening does not unarchive them or alter drafts.
- core/group_search.dart scans already authenticated/decrypted group histories,
  yields every 128 messages and between groups, and keeps the newest 100 hits
  by timestamp/group ID/author-message key. Snapshots retain display text and IDs,
  never attachment bytes. Text, image labels and file labels/filenames match;
  literal case-insensitive Unicode queries exclude drafts and file contents.
- GroupController.historyRevision advances on successful reloads. Search reacts
  to receiving, imports, metadata updates and deletion, cancelling old generations.
  Synchronous root access/foreground notifications clear/cancel search work;
  background return refreshes queries, while PIN locks clear them permanently.
- GroupChatScreen accepts exact focusMessageKey/searchQuery, anchors the result
  between lazy older/newer slivers, highlights selectable text and offers Jump to
  latest. Ordinary saved views also build messages lazily. Missing targets show
  a notice. Existing route visibility gates keep search from reading hidden groups.
- Global/scoped search uses existing history storage without a new plaintext index,
  schema migration, backup payload or network operation. SQLite stays schema 11
  and backups retain v1-v8 compatibility. Browser covers saved/imported demo groups.
- Added scan/controller, widget and SQLite checks for Unicode/literal matching,
  bounds/order, cancellation, actual signed receiving, import refresh, PIN/background,
  exact anchors with colliding IDs, drafts/unread, small-screen text and reopen.
- Final full regression: **340 passed**, exit 0 (324 prior + 16 new), using
  `--concurrency=2 --timeout=2m`. Analysis is clean; arm64 debug APK and browser
  builds pass. Logs are ignored in .dart_tool. Physical checks remain pending.
  Group background protection is committed; browser group simulation is also committed.

## Group-management milestone - implemented, 2026-10-13

Baseline: `2a83b30`. The user committed this milestone as `f07316d`.
Do not stage/commit/push for the user. See docs/GROUP_MANAGEMENT.md and VALIDATION.md.

- GroupHistory includes local pinned/archived choices; stable ordering puts pins
  first, then saved activity and ID. Model parsing defaults older records to false.
- Schema 11 adds plaintext group_history metadata columns, matching direct-chat
  organization flags. Migration and flag changes preserve existing ciphertext.
  Transactional history writes preserve current metadata even for stale snapshots.
- GroupController serializes metadata changes, checks captured access revisions
  and refreshes saved/active histories. Rehosting loads the latest saved record,
  retaining messages/choices and rejecting deleted or wrong-host snapshots.
- Shared GroupChatTile/GroupMenu appear in Chats, the group hub, Archived chats and
  chat toolbars. Menus reject disposed/stale/locked actions; failures show errors.
  Stable row keys preserve open menus when incoming activity reorders groups.
  Combined archive shortcuts include direct/group unread counts. New messages do
  not unarchive groups. The hub keeps an active-room card for connection controls.
- Payload v8 records nondefault group choices while retaining v1-v7 imports. Existing
  destination choices win; new groups inherit incoming choices. Mixed attachments,
  drafts and empty-phone identity migration retain existing validation and limits.
- Archiving preserves drafts, messages, attachments, read state, receiving/alerts
  and active sessions. No native/package/permission or network-protocol changes.
- Final full regression: **324 passed**, exit 0 (303 prior + 21 new), using
  `--concurrency=2 --timeout=2m`; analysis is clean. Final arm64 debug APK and
  browser builds pass and include stable row keys. Logs are in .dart_tool and
  ignored; results are recorded in docs/VALIDATION.md. Physical checks remain pending.
  Physical group-management checks remain pending; see GROUP_MANAGEMENT.md.

## Group-draft milestone - implemented, 2026-10-12

Baseline: `5a92e71`. The user committed this milestone as `2a83b30`.
The user handles Git. See docs/GROUP_DRAFTS.md and docs/VALIDATION.md.

- The existing DraftController now distinguishes direct/group targets and shares
  one queue across ChatController and GroupController for writes, backups,
  deletion and atomic local acceptance. Standalone group controllers own their
  draft controller; the app injects its existing instance.
- Schema 10 adds encrypted group_drafts with separate authenticated domain
  UTF-8 JSON ["LocalChat/group-draft/1", groupId]. Existing tables/keys remain.
- Group screens load/restore exact drafts, allow offline editing, disable on
  unreadable loads and expose Retry draft on failures. Text sends clear captured
  drafts atomically; new edits, failed sends and attachment flows preserve text.
- Payload v7 includes groupDrafts with validated group references and 1 MiB text
  bounds, while retaining v1-v6 imports. Destination drafts win; conflicting
  hosts cannot acquire imported drafts. Mixed imports/deletion/send cleanup roll
  back on failure. Normal history-only and empty-phone identity imports work.
- Final regression on 2026-10-13: **303 passed**, exit 0
  (`.dart_tool/group-draft-final-tests.log`), using two-minute test timeouts for
  the existing SQLite search stress check. All 10 group-screen checks pass,
  analysis is clean and arm64 Android/browser builds pass. No new packages,
  permissions or native changes. The user reviews/tests/commits next.
- Browser demo remains memory only; no group outbox. Group pin/archive, search,
  background protection and in-tab simulation are implemented separately.
  Simulated remote replies are labeled demo. Physical checks remain pending.

## Group-file milestone — implemented and validated, 2026-10-12

Baseline: `318b304`. The user committed this milestone as `5a92e71`.
Do not stage/commit/push for the user. No packages, permissions or native changes.

- `group_attachments.dart` now owns shared image/file room binding, per-link
  attachment engines, host relay, individual receipts, cancellation and privacy.
  `GroupImages` preserves existing image behavior; `GroupFiles` uses the existing
  local ChatFiles picker/save bridge. Both share serialized session counters,
  while keeping independent transfer and capability state.
- Encrypted `group-file-v1` must be supported by every admitted member. Older
  image builds keep text/images. Signed `LocalChat/group-file/1` metadata includes
  canonical filename/MIME/length/SHA-256 plus exact group/host/epoch/roster/author/
  time/recipients. Existing text/image signatures are unchanged. The trusted host
  decrypts/saves uploads before relay; recipients save before completion receipts.
- Nonempty opaque files up to 8 MiB, safe names (120 Unicode code points), 12 KiB
  acknowledged chunks, 30-second stage/receipt waits, per-member progress/cancel.
  Images/files can interleave on the same encrypted links. Each kind has one
  outgoing per author/link; busy recipients become unconfirmed rather than queued.
- Group screen provides attach/review/discard preserving composer text, safe file
  bubbles and confirmed Save to phone while offline. Exported copies leave app
  encryption and may finish if the authorized system save picker triggers locking.
  Rechecks prevent invoking the picker if access changes while loading history.
- Lock/background/disconnect/membership changes stop partial transfers, preserve
  received receipts and complete copies, and invalidate late/pending selections.
  Author backgrounding after upload sends host abort. No automatic retry/resume;
  explicitly selecting/sending again uses a fresh ID. Pending names/bytes are sealed
  in memory while locked. Notification/list previews use the generic label File.
- Inline file bytes use existing encrypted group-history records/AAD; schema stays
  9. The 16 MiB cap now counts group images/files combined; 10,000 messages remain.
  Backup payload v6 supports mixed attachments and retains v1–v5 imports. Envelope,
  KDF and the 20 MiB plaintext archive limit (including base64) are unchanged.
- New tests: 21 protocol/controller/picker/export checks, four backup/bounds checks,
  two widgets and two SQLite encryption/reopen/backup/rollback checks. The shared
  relay regression caught an incorrect type guard; corrected file and image tests
  pass. Targeted final run: 68 passed. Full regression: **279 passed**, exit 0
  (250 existing + 29 new checks). Final review fixed Windows-encoded progress
  punctuation; all seven group-screen tests pass afterward. Final analysis is
  clean, and refreshed arm64 APK/web builds passed, exit 0, including that cleanup.
  Existing optional Cupertino font warning remains on web. Final diff/code/docs
  review is clean. Results are in `docs/VALIDATION.md`.
- `docs/GROUP_FILES.md` records controls, trust, protocol/storage, limits and pending
  three-phone checks. Runtime logs stay local/ignored at `.dart_tool/group-file-*`.

APK: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
Remaining: physical three-phone checks and user's review/commit/push.
Do not repeat passing checks unless code changes or a new concern justify it.
Generation helper `.dart_tool/group_file_implementation.py` has already run;
do not rerun it or old file helpers (they duplicate edits).

## Group-image milestone — committed, 2026-10-12

Committed by the user as `318b304`, based on `3ec26b5`.
Do not stage/commit/push for the user. No packages, permissions or native changes.

- `group_images.dart` adapts the existing ImageTransfers/attachment engine per
  verified host–guest link. Author-signed PNG offers use `LocalChat/group-image/1`
  and exact group/epoch/roster/recipients; group text signature bytes are unchanged.
- Encrypted `group-image-v1` capability on every admitted member gates image
  controls. Sources use existing 8 MiB/40 MP preparation, 1600 px sides and 2 MiB
  PNG bounds. The trusted host decrypts/saves uploads before relaying. Durable
  recipient completion produces individual receipts; generic text receipts
  cannot bypass the image engine. Notifications/list previews say Image.
- Group screen provides attach/review/discard, member/direction progress, cancel,
  individual receipt counts, offline zoom and lock cache eviction. Text is retained
  during preview/discard. Picker returns while locked are encrypted in memory.
- Transfers require foreground unlock. Cancel/lock/background/membership changes
  discard partial bytes and stop relays, preserving received receipts. Author
  backgrounding after upload sends host abort. No automatic group retry/resume;
  manually selecting/sending again gets a fresh ID. One outgoing per author/link;
  busy recipient links become unconfirmed instead of queuing another image.
- Complete bytes inline in encrypted group_history records, capped to 16 MiB
  image bytes/group plus 10,000 messages. SQLite stays schema 9. Backup payload
  v5 supports mixed group images/direct files and retains v1–v4 imports; envelope,
  KDF and 20 MiB plaintext archive cap stay unchanged, including base64 expansion.
- `docs/GROUP_IMAGES.md` records controls/trust/wire/storage and the pending
  three-phone checklist. Automated results belong in `docs/VALIDATION.md`.
- New tests: 16 protocol/controller/picker checks, three backups, two widgets
  and one SQLite encryption/reopen/backup/dedupe/deletion check. Initial protocol
  run passed; widgets now pass after real async scheduling for dialog return and
  image decoding. Final full suite/analysis/build logs are `.dart_tool/group-image-*`.

Final validation: **250 tests passed**, exit 0 (228 existing + 22 group-image
checks); clean analysis; final Android arm64 debug APK and browser builds passed,
exit 0. Existing optional Cupertino web-font warning remains. Final code/docs
review and diff whitespace check are clean. Logs remain local/ignored under
`.dart_tool/group-image-*`. APK: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
Do not repeat passing checks unless changes or a new concern justify it.

Remaining for group images: physical three-phone tests.
Do not rerun old `.dart_tool/file_*.py` generation helpers.

## Direct-chat file milestone — committed, 2026-10-12

Committed by the user as `3ec26b5`, based on `aea566b` (image sharing).
Hardware checks remain pending; do not stage/commit/push for the user.

Implemented: opaque nonempty files up to 8 MiB; sanitized bounded filenames;
Android local-only pick/save bridge `ChatFiles.kt`; browser local selection and
download; toolbar attach/review/discard; encrypted pending selection including
filename; saved file bubbles with explicit export confirmation and retry;
foreground/unlock gates, progress/cancel, no auto-resume. Save creates a copy
outside app encryption and may finish during system-picker locking.

`attachment_transfers.dart` shares the original image state machine. Thin
ImageTransfers/FileTransfers wrappers retain image protocol compatibility and
add negotiated encrypted `file-v1` frames. Schema 9 adds files with separate
message/byte AAD, atomic writes/deletion/import; v4 backups retain v1/v2/v3 reads
and the existing envelope/KDF/20 MiB cap. DemoStore/Transport support files.

Final verification:
- Full `flutter test --reporter expanded`: **228 passed**, exit 0 (203 existing
  + 25 file checks). Output: `.dart_tool/file-milestone-tests.log` (ignored by Git).
- Final `flutter analyze`: no issues, exit 0.
- Review fixed long filenames truncated at a dot/space boundary. The full run
  includes a new canonical shortened-name regression test with Unicode.
- Final arm64 debug APK and browser builds pass, exit 0. APK:
  `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`. Browser build retains
  the existing optional Cupertino font warning. Diff whitespace check is clean.
- Physical phone checks remain pending. See `docs/FILE_SHARING.md`.

README/SECURITY/BACKUPS/DEVICE_TESTING/BACKGROUND_CONNECTION/IMAGE_SHARING and
FILE_SHARING/VALIDATION/FEATURE_BACKLOG documentation reflect the completed work.
Remaining for direct files: physical phone checks.
Do not repeat passing tests unless code changes or a new concern requires it.
Generation helpers under `.dart_tool/file_*.py` were already executed; do not
rerun them (they duplicate edits). All resulting source/test files are real
workspace files. No packages or permissions were added.

## Direct-chat image milestone — committed, 2026-10-12

Image changes were committed by the user as `aea566b`. Hardware checks remain pending.

- Android `ImageFiles.kt` uses a local-only image document picker and bounded
  reads, without a new package or storage/gallery permission. Browser selection
  uses local file APIs with a clearly simulated recipient.
- `image_content.dart` bounds sources to 8 MiB/40 MP, resizes to at most 1600
  pixels/side and re-encodes PNG to strip source metadata; first frame only.
  Prepared images are bounded to 2 MiB.
- `ImageTransfers` uses the existing serialized secure session with negotiated
  `image-v1`, one acknowledged 12 KiB chunk at a time, per-direction transfer
  bounds, exact order/size/hash checks, decoding, 30-second stage timers and
  persistence before final receipts. Text interleaves with images. Both apps
  must be unlocked/foregrounded; lock/background/cancel/disconnect discard
  partial incoming bytes and mark outgoing attempts unconfirmed. No auto-resume.
- ChatScreen provides attach/preview/discard, bounded scrollable transfer
  controls, progress/cancel and offline zoom. Explicit image retry reuses its
  original ID; receiver dedupe retains read state and suppresses repeat alerts.
  Prepared picker selections survive locking encrypted in memory, bound to
  their intended identity; review/send wait for unlock. Deletion invalidates
  late picker results. Text drafts are preserved.
- Schema 8 adds message kind and encrypted image rows with separate AAD for
  image bytes and image-message metadata. Message/bytes insert atomically;
  deletion and backup imports are transactional. Existing text/group ciphertext
  and identity remain compatible. Payload-v3 backups contain validated images;
  v1/v2 still import, envelope/KDF and 20 MiB archive bound stay unchanged.
- Image notification/list preview is “Image”; text search excludes image bodies.
  Existing app lock removes viewer/preview routes. Temporary pixels may exist
  in managed memory; cache eviction is not guaranteed forensic erasure.
- `docs/IMAGE_SHARING.md` records controls, limits, wire/storage design, sources
  and the pending two-phone checklist. Final results go in `docs/VALIDATION.md`.
- Full regression suite: 203 tests pass (185 existing + 18 image checks), with
  the final text acknowledgement and offline layout fixes. Final analysis is
  clean and final Android arm64/browser builds pass. The browser retains its
  existing optional Cupertino font warning. Diff check is clean. Physical
  two-phone tests remain pending; the user stages/commits/pushes after testing.

## Hosted group milestone — committed, 2026-10-12

The user committed this milestone as `819ac32`. Hardware checks remain pending.

Implemented:
- `GroupTransport.kt` owns dedicated Android group channels, Wi-Fi Direct owner
  creation, `_localchatg._tcp` host discovery, port 45874 and up to seven guest
  sockets. Direct and group modes are mutually exclusive. Native cleanup has
  epoch guards, per-link writer locks and bounded partial reads/writes.
- `GroupController` serializes per-link `SecureSession` crypto, both fresh code
  confirmations, host admission, rosters/removal, signed authors/recipient sets,
  text relay, per-member receipts, dedupe and unconfirmed delivery. The host is a
  trusted decrypt/store/relay endpoint; clients trust its admission of others.
- `group_screen.dart` provides create/find/join, code cards, members/removal,
  saved history, originating text and confirmed deletion. Home has a Group chats
  icon; saved group cards appear in Chats. Lock and notification routing cover
  groups. Normal notification preferences apply; previews retain existing gates.
- `group_models.dart` validates signatures bound to group/host/epoch/roster/
  author/name/time/text/exact targets. New members receive no old messages.
- SQLite schema 7 encrypts entire group records; random group IDs are plaintext
  keys. Backups add version-2 group payloads with v1 import support; envelope/KDF
  stay v1. Imports merge history safely, never connect/send and make pending
  receipts unconfirmed. Identity migration requires no destination groups and
  refreshes group identity state. Existing direct history/features remain intact.
- Limits: eight members including host (hardware may allow fewer), 4096-byte
  text, 10,000 saved messages/group, 90-second joins and 30-second receipts.
  Original host can explicitly rehost with a fresh epoch/codes. No group outbox,
  automatic retry/reconnect or host migration. Saved drafts, pin/archive,
  search, background protection and browser simulation are implemented separately;
  the original hosted-group milestone did not include these refinements.
- Docs updated: README, SECURITY, BACKUPS, BACKGROUND_CONNECTION, DEVICE_TESTING,
  FEATURE_BACKLOG; full controls/trust/three-phone checklist in GROUP_CHATS.md.

Verified:
- Full `flutter test` on 2026-10-11: **185 passed**, exit 0, after integration and fixes.
  Includes 162 existing tests plus 23 new group checks: 13 protocol/controller,
  four backup, three widget, two SQLite encryption/migration and one native-channel.
- Final `flutter analyze` on 2026-10-12: no issues.
- Final Android arm64 debug APK build on 2026-10-12 passed, including the native
  channel-epoch guard and final Dart/UI changes. Artifact:
  `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- Final `flutter build web --no-wasm-dry-run` on 2026-10-12 passed; the existing
  optional Cupertino font warning remains (the UI uses Material icons).
- `git -c core.safecrlf=false diff --check`: clean.
- Widget fixtures use real async scheduling for cryptography and deletion;
  mixing Flutter's fake clock with real controller queues caused fixture waits.
  Corrected fixtures pass in the full suite. Temporary debug prints were removed.

Next: install the updated APK on three Android phones and follow
`docs/GROUP_CHATS.md`. Hardware discovery/pairing/capacity, Doze/vendor behavior
and battery checks remain pending.

## Background connection milestone

- `BackgroundConnection` / `BackgroundPlatform` implement an injectable status,
  local preference, activation, cancellation and battery/channel settings bridge.
  Root initializes it independently of locked chat storage. Settings offers the
  Keep connection active switch and Retry after startup failure, with demo labels.
- Android `ConnectionService` is unexported, uses `remoteMessaging` and the normal
  foreground-service/type/wake-lock permissions. It protects the existing live
  Activity/Flutter engine without moving crypto or creating a background engine.
  Foreground unlock plus both confirmations gate activation; the native socket
  generation and service epoch reject stale startup/cancel/Stop operations.
- MainActivity retains transport ownership. Home/another app/screen lock retain
  the current session. Activity finish/task removal/process death ends it; no
  sticky restart, boot receiver, automatic reconnect or session-key restoration.
- The separate Connection channel has fixed generic ongoing/connection-loss text
  and an immutable Stop intent scoped to the service epoch. Stop closes sockets,
  advertising and service, disables the preference, preserves history/drafts/outbox
  and works while locked. Turning the Settings switch off only removes protection.
  Message alert cancellation now targets only peer message notifications.
- Frame events carry native generation metadata. The service owns short received-
  frame CPU wake locks with a 15-second timeout; Dart releases after protocol work,
  and native disconnect/destruction also cleans up. No idle CPU/Wi-Fi lock. Local
  access/service checks stop invalid protection; no new wire heartbeat/payload.
- Battery optimization status/shortcuts are advisory and user-controlled, without
  an automatic-exemption permission. Doze/vendor behavior still needs phone checks.
  Receiving/persistence/ACKs and unread/preview privacy work while protected;
  queued sending remains foreground/unlock gated. Backups exclude the preference.
- All 162 tests pass (147 existing + 15 new lifecycle/channel/widget checks).
  Analysis is clean; Android and browser builds pass. Final results and hardware
  checklist are in `docs/VALIDATION.md` and `docs/BACKGROUND_CONNECTION.md`.
  User committed this as `24d52b5`; physical checks are pending.

## Local notification milestone

- `ChatNotifications` owns opt-in preferences, permission status, privacy gates,
  notification operations and pending peer-only taps. Root initializes it before
  chat storage opens so cold-start taps wait safely for app unlock.
- Settings offers enable/disable, previews, denial guidance and Android settings.
  Android `MessageNotifications` uses SharedPreferences booleans and native APIs
  through `dev.localchat/notifications`, plus a dedicated POST_NOTIFICATIONS
  request code (Android 13+). No package, schema, backup or wire changes.
- LocalStore/DemoStore.saveMessage returns whether a new row committed. Only new
  verified incoming text notifies; identical retries retain existing read state
  and do not re-alert. Notifications run separately from persistence/ACKs, and
  errors appear in notification settings rather than failing the secure session.
- Generic defaults omit sender/body from the native bridge. Opt-in previews
  require foreground + unlocked access, bounded by native checks as well as Dart.
  Native pause and Dart lock changes redact active previews. Android private
  visibility/public generic content also applies; earlier OS history/listener
  copies cannot be erased. Native retained tap/redaction state contains peer IDs.
- One alert per peer; actual visible-read gates suppress/cancel alerts. Clear
  history and per-chat deletion cancel them. Backup imports never create alerts.
- Root navigator routes cold/warm taps after unlock + initialization + foreground,
  with access-token, current-target and navigator checks after async history load.
  Activity metadata disables Flutter's automatic deep-link handler so native
  notification URIs reach only this routing path.
  Taps neither auto-connect nor bypass code confirmation. Missing histories get a
  generic notice. Browser demo settings are temporary with no OS notifications.
- All 147 tests pass (132 existing + 15 notification checks); final results and
  hardware checklist are in `docs/VALIDATION.md` and `docs/NOTIFICATIONS.md`.
  User committed this as `9bb6c60`; physical phone checks are pending.
  Background connection protection was added in the next milestone above.

## Connection recovery milestone

- `nearby_support.dart` adds typed issues, access status and injectable NearbyTools.
  Native transport queries radio/support/permission/Location and opens fixed
  Android settings destinations. Demo/custom test transports use simulated checks.
- Nearby shows access checks, completed empty scans, Disconnect and last-device
  Reconnect. Last attempted address/name stays only in memory, requires a current
  nearby list entry and does not substitute for cryptographic identity verification.
- Home/chat recovery cards use wrapping controls and bounded scrolling. Failed
  connect stays in Nearby; successful reconnect opens the handshake. An immediate
  failed attempt restores the prior selected chat rather than renaming its history.
- Chat toolbar explains queued waiting state. Reconnect never confirms codes or
  retries unconfirmed text automatically. The outbox still drains only to its
  verified identity, with foreground/unlock gates.
- Access refresh on foreground/unlock never starts discovery/connection. Missing
  access closes a session; Wi-Fi loss clears discovery/started state. Pending
  start/scan/connect actions reject repeated taps and earlier unlock tokens.
- Kotlin errors carry codes; cancelled callback epochs cannot restart advertising
  or scanning. Async permission errors are guarded and disconnect tolerates revoked
  permission. A stopped P2P channel can be initialized by Go nearby again.
- Connection/verification timeout remains 90 seconds with a cancellation guard;
  idle socket detection and automatic reconnect/background sending are future work.
- No database, wire, dependency or manifest permission changes. Phone checks and
  results are in `docs/CONNECTION_RECOVERY.md` and `docs/VALIDATION.md`. Changes
  were committed by the user as `c7d4d6e`; physical checks are pending.
  All 132 tests pass, static analysis is clean and Android/browser builds succeed.

## Offline outbox and message retry milestone

- Saved chats accept queued text offline; fresh verification on both phones
  enables automatic draining only for that connected identity, including archived
  chats and while another chat is selected. No automatic reconnect/background mode.
- Schema 6 adds `message_outbox(peer,outgoing,status)`. Local acceptance saves an
  encrypted queued message and removes its captured draft in one transaction.
  DraftController revision/generation guards preserve newer edits and deletions.
- Durable queued→sending transition precedes transport. At most four attempts
  await encrypted ACK, with a 30-second timeout. Disconnect/restart marks attempts
  unconfirmed and retains unsent queued records. New attempts require unlocked,
  foreground access; a gate change during encryption discards the session to avoid
  sequence gaps. In-flight writes/receiving/ACKs retain the existing lock model.
- Retry is explicit and retains ID/text/timestamp. Duplicate incoming records
  must match body/timestamp before ACK; identical records retain read state/activity.
  Only IDs attempted in the current verified session can be ACKed; late ACKs count.
  Dedupe requires retained receiver history, so this is not exactly-once delivery.
- UI shows queued counts, Cancel queued and confirmed Retry, plus Resume outbox
  after storage failures. Unconfirmed messages never resend automatically.
- Backups accept queued state, but newly imported queued/sending become unconfirmed
  so imports cannot silently transmit. Older builds reject queued backup records.
- See `docs/OUTBOX.md` and `docs/VALIDATION.md` for checks/results. User committed
  this as `605962e`; physical phone tests remain pending.
  All 118 tests pass, final targeted checks pass, analysis is clean and fresh
  Android/browser builds succeed.

## Encrypted backups and phone migration milestone

- Settings → Chat backups exports/imports password-protected `.lcbackup` files.
  Includes messages, read/delivery state, drafts, pin/archive choices and private
  identity seed. Native SAF streams only encrypted bytes, bounds input size and
  requests no broad storage permission. Browser uses `package:web` file APIs.
- `core/chat_backup.dart` validates version-1 JSON before merging, verifies the
  seed/public identity relationship, bounds records and references, and uses
  PBKDF2-HMAC-SHA256 (600k, 256-bit) plus XChaCha20-Poly1305. Fresh 16-byte salt,
  24-byte nonce; authenticated magic/version/salt. Limit 20 MiB + 65-byte envelope.
- Preview shows additions, duplicates/conflicts and retained drafts. The final
  transaction recalculates counts. Existing names/flags/messages/state/nonempty
  drafts win. Dedupe keys include peer/id/direction. `sending` and `queued` import as
  `unconfirmed`; importing neither sends nor acknowledges. Bodies are encrypted
  again with the destination history key; settings/display name stay local.
- Default history-only import retains identity. User explicitly chose support
  for transferring identity to an empty phone too. That checkbox requires no
  chats/messages/drafts, stops transport and tells the user to retire the old
  phone. Fresh verification is still required on reconnect.
- Schema 5 adds `backup_receipt(id)` only. Vault `identity_import_pending_v1`
  records old/new seeds and operation ID before a migration transaction; a
  receipt commits with the merge. Recovery chooses new seed when committed,
  old seed otherwise. A failed final vault write blocks controller messaging
  until restart recovery; cleanup removes the vault journal before the receipt.
- Backup operations use the protocol queue and draft queue. Pending saves settle
  before snapshots. Import refreshes draft cache without overwriting newer edits,
  plus conversation/historyRevision state for search. Draft errors block backups.
- `BackupScreen` drops password fields/decrypted preview on background/disposal.
  Only selected ciphertext is retained in ChatController across system-picker
  locking; after unlock return to backups and enter password again. Import
  access tokens reject confirmations from an earlier unlock. A confirmed atomic
  import can finish while hidden. Demo/native archives cannot be mixed.
- Tests include crypto tampering/password/KDF, payload bounds, merges, rollback,
  journal recovery/vault failure, schema upgrades, concurrent draft edits, screen
  flows, explicit migration, native channel, phone text size and lock/picker flow.
  See `docs/BACKUPS.md` for hardware checks and `docs/VALIDATION.md` for results.
  All 99 tests pass, static analysis is clean and fresh Android/browser builds
  succeed. User committed this as `63eff9f`; hardware checks are pending.

## Conversation management milestone

- Chat rows have a menu for Pin/Unpin, Archive/Unarchive and confirmed Delete.
  Pinned chats precede others; activity order applies within each group. Pinning
  does not change message timestamps, draft text or unread counts.
- `LocalStore` schema 4 adds unencrypted `pinned`/`archived` flags on peers,
  defaulting to false for existing history. Native and demo savePeer/saveMessage
  preserve flags. Schema 1/2/3 upgrades retain messages, drafts, identity and
  read state. Browser choices stay in memory and reset on reload.
- `ChatsTab` filters the primary/archived lists, with separate scroll keys.
  The main list links to `ArchivedChatsScreen` and shows its chat/unread totals.
  Archived chats stay archived on incoming messages and remain searchable;
  name/message results label their archive state. Opening reads normally but
  does not unarchive. Unarchive preserves its existing pin choice.
- `ChatController` serializes management actions, reports generic failures and
  increments historyRevision for search refresh. viewHistory rejects a deleted
  conversation instead of selecting a stale search/list result.
- Per-chat deletion disconnects the target if it is the active session, then
  transactionally deletes its messages, draft and peer metadata. Other peers,
  identity, settings and the other person's history remain. A failed deletion
  retains saved data; a prior disconnect may already have happened.
- `DraftController` now tracks both global and per-peer deletion generations.
  Targeted deletion clears only that peer's cache and invalidates its queued
  writes; another peer's drafts keep saving. The selected deleted chat clears.
- Menu state stays with keyed chat cards when pinning changes order. Archive
  routes and deletion dialogs use the existing lock-covered navigator. Error
  banners have a scrollable height limit so large text leaves room for the list.
- Phone checks are in `docs/CONVERSATION_MANAGEMENT.md`. Committed as `8f55377`;
  validation results are in `docs/VALIDATION.md`.
  All 82 tests pass, static analysis is clean and Android/browser builds succeed.

## Saved drafts milestone

- Every selected conversation has its own composer draft. Offline history
  allows editing and queuing; transmission remains gated on a verified connection. Drafts
  preserve whitespace, newlines and Unicode exactly; sending trims as before.
- `LocalStore` schema 3 adds `drafts(peer, body)`. Draft text is encrypted with
  the existing history key using XChaCha20-Poly1305 and domain-separated AAD
  `JSON(["LocalChat/draft/1", peer])`. Empty drafts delete their record. Version
  1/2 upgrades preserve messages, identity and read state. Drafts are excluded
  from search, previews, activity sorting and unread state.
- `draft_controller.dart` belongs to `ChatController`, rather than a route.
  It loads per peer and serializes/coalesces writes outside the protocol queue.
  Edits update memory immediately and enqueue persistence without a debounce.
  Storage failures keep edits in memory with generic retry notices; a failed
  load disables editing until retried so saved text is not overwritten.
- `sendText` returns a local-acceptance boolean and captures the selected peer
  and matching draft revision. The outbox milestone now clears that revision
  atomically when saving a queued message. Newer edits, other peers and failed
  local acceptance keep their drafts. Local acceptance does not mean delivered;
  encrypted acknowledgements still decide delivery status.
- History deletion runs on the draft write queue and transactionally clears
  messages, drafts and peers. A generation invalidates queued older edits;
  cached drafts and open composers reset only after successful deletion.
  Deleted offline conversations are deselected; the active session can continue.
- Locking disposes the composer route; reopening after unlocking restores its
  saved text. Plaintext can remain in controller memory under the existing app
  lock model. Browser drafts use `DemoStore` memory and reset with the tab.
- All 73 tests pass, static analysis is clean and Android/browser builds succeed;
  results are in `docs/VALIDATION.md`. Phone testing is in `docs/DRAFTS.md`.
  The user committed this as `9e90550`.

## Local search milestone

- Chats has a toolbar Search action. `chat_search_screen.dart` displays
  separate name and message matches, context snippets, empty/error/retry states
  and a clear action. Matching is a case-insensitive literal substring;
  surrounding query whitespace is ignored. Browser behavior matches Android.
- `LocalStore.search` decrypts ciphertext batches in memory, with cancellation
  checks and event-loop yields. It returns the newest 100 message matches and
  a refinement notice if more exist. No plaintext index, schema change or new
  dependency is introduced. Larger histories require scanning more ciphertext.
- `chat_search_controller.dart` debounces typing and rejects obsolete results
  and errors. A `ChatController.historyRevision` signal refreshes search on new
  messages, verified peer-name updates and history deletion. Search runs outside
  the serialized protocol queue and does not mark messages read.
- Selecting a result reloads history; `viewHistory` now returns success and
  updates selection only after history/summary loads succeed. Failed opens stay
  on the current screen. A message result passes full peer/id/direction identity.
- `ChatScreen` anchors the matching message with two lazy slivers, highlights
  its bubble and offers Jump to latest. Older/newer history remains reachable
  with variable message heights. Missing/deleted targets show a notice.
- Locking disposes the search navigator route, query and results and cancels
  pending work. Returning from a result normally preserves the search query.
- Added nine search checks and extended ciphertext-authentication coverage.
  Validation: all 61 tests pass, clean analysis and successful Android/browser builds.
  Phone checks are in `docs/SEARCH.md`. The user committed this as `a2c7aa3`.

## Chats list milestone

- `Conversation` carries its latest decrypted message and unread count.
  Chats shows a two-line preview, You prefix for outgoing messages, local
  activity time/date and a badge (99+ visually, full count for accessibility).
- `LocalStore` schema version 2 adds per-message `is_read`, with existing
  version-1 history initialized as read. Message bodies remain encrypted;
  previews decrypt the last locally saved message rather than storing a
  plaintext copy. Read state is local unencrypted metadata, not a read receipt.
- Summary queries use indexed last-message and unread lookups. New message
  writes update local activity atomically; duplicate writes, peer name updates,
  read marking and delivery acknowledgements do not reorder conversations.
  Chats with messages precede empty conversations.
- `ChatScreen` uses the root ModalRoute observer to report actual visibility.
  `ChatController` gates read marking on that visibility, foreground state,
  unlocked access and readable history (verification hides active history).
  The protocol queue rechecks these gates before marking read. `main.dart`
  updates access/foreground gates immediately on locking and lifecycle changes.
- Demo storage has matching summary/read behavior, with its usual reload reset.
  Added nine storage, controller and list checks and extended existing demo and
  ciphertext-tampering coverage. See `docs/CHAT_LIST.md` for phone checks.
  Validation: all 52 tests pass, clean analysis and successful Android/browser builds.
  The user committed this milestone as `c233159`.

## Theme milestone

- Settings → Appearance offers Light, Dark and Follow system, plus Mint, Blue,
  Purple and Amber palettes. Defaults remain Dark/Mint until the user changes them.
- `appearance_controller.dart` saves a versioned preference separately in
  secure storage on Android. Browser demo preferences stay in memory and reset
  on reload. Loading failure uses defaults with a recoverable Settings error;
  a failed save preserves the current selection and offers retry.
- `main.dart` loads appearance before displaying the app and supplies both
  Material 3 brightness themes. Preferences are independent of the lock gate.
  Theme changes preserve pushed routes, Settings edits and selected tabs.
- Incoming/outgoing chat text, bubble backgrounds and connection/demo notices
  use matching ColorScheme colors. The lock screen uses the same appearance.
- Added seven checks for persistence, storage errors, device brightness,
  navigation/lock coverage, eight-theme message contrast and enlarged text.
  Validation: all 43 tests pass, clean analysis, successful Android/browser builds.
  Phone checks are in `docs/THEMES.md`. The user committed this as `b353956`.

## Chats / Nearby navigation milestone

- `HomeScreen` is a stateful shell with Material 3 bottom navigation. Chats is
  the default tab; `chats_tab.dart` shows saved history and an active-chat Open
  action. Its empty state links to Nearby without starting discovery.
- `nearby_tab.dart` holds the profile/connection state, Go nearby, scanning,
  permissions/discovery instructions and device connection actions.
- Switching tabs preserves independent scroll positions and existing transport
  state. Returning from a chat or Settings keeps the selected tab.
- App locking removes the entire shell, including both tabs; unlocking starts
  on Chats. Chat protocol and storage remain owned by the same controller.
- Validation: clean analysis, 36 passing tests, successful browser and Android
  debug APK builds. Phone navigation checks are in `docs/NAVIGATION.md`; the
  milestone was committed by the user as `abe4dc3`.

## App lock milestone

- Optional six-digit app PIN, biometric unlock on supported Android phones,
  immediate launch/background locking, manual Lock now and PIN-authorized edits.
- `app_lock_controller.dart` stores a salted PBKDF2 verifier and persisted
  attempt/cooldown state in secure storage. Browser configuration is temporary.
- `main.dart` reads lock settings before chat initialization and replaces every
  app route while locked. Unlock returns to home; existing transport can remain.
- Android now uses FlutterFragmentActivity, AppCompat themes, USE_BIOMETRIC and
  a privacy channel for FLAG_SECURE while app lock is enabled.
- This is UI access control; existing database keys are not bound to biometrics
  or re-encrypted with the PIN. Read `docs/APP_LOCK.md` for limits and phone checks.
- Physical fingerprint, lifecycle and secure-storage checks remain required.
- Uses `local_auth` 3.0.2; minimum Flutter is now 3.38.0 / Dart 3.10.0.
- Automated suite: 33 passing tests. See `docs/VALIDATION.md` for build results.

## Android implementation

- Kotlin WifiP2pManager DNS-SD discovery and framed TCP transport, bridged to
  Flutter through MethodChannel/EventChannel (`MainActivity.kt`, `transport.dart`).
- Ed25519 identity signatures, fresh X25519 session keys, HKDF-SHA256 and
  XChaCha20-Poly1305 (`secure_session.dart`). Both phones must compare and
  explicitly confirm the complete security code on each connection.
- Encrypted message bodies in SQLite, identity/history keys in
  flutter_secure_storage (`local_store.dart`). Ordinary transport metadata remains
  unencrypted; private contact nicknames use encrypted schema-14 metadata.
- Material 3 nearby devices, chat, settings, acknowledgements and saved history,
  coordinated by a serialized ChangeNotifier controller (`chat_controller.dart`).
- Both apps must remain open for transmission. Offline queues wait for a freshly
  verified connection; unconfirmed attempts require explicit Retry.
- The protocol is experimental and has not had an independent security audit.

## Browser preview

Run `flutter pub get`, then `flutter run -d chrome` from this directory.
`createController()` in `lib/main.dart` selects the demo only when `kIsWeb`.
Android keeps `WifiDirectTransport()` and `LocalStore()`.

`lib/demo/demo_transport.dart` supplies Ava and Noah as simulated nearby peers,
answers the shared controller's protocol frames, simulates peer confirmation,
acknowledgements and replies. `lib/demo/demo_store.dart` uses memory only and
never invokes SQLite or platform secure storage. A persistent Browser Demo
notice stays visible on all routes; verification and Settings explain the
simulation. No sockets, radio discovery or real Wi-Fi Direct communication
occur in browser mode. Everything resets when the tab reloads. Demo protocol
encryption is not a claim of communicating securely with another device.

## Validation and outstanding work

The original validation recorded 19 passing tests, clean analysis, a successful
Android debug APK build and verified APK signature with Flutter 3.35.7 /
Dart 3.9.2, Java 17, Android SDK 36 (minimum API 24). This Windows environment
currently has Flutter 3.38.7 / Dart 3.10.7.

The original browser demo checks covered discovery, mandatory confirmation before send,
simulated replies/delivery, fresh verification on reconnect, per-peer history,
live history deletion, rename/reset behavior and persistent demo labelling on
small screens. That milestone passed `flutter analyze`, all 23 tests, and the
JavaScript web build. A headless Chrome smoke check exercised discovery,
verification, sending, simulated delivery and replies. The separate Chrome
test runner has a CanvasKit asset-serving issue in this installed Windows SDK.
The Android SDK is now installed and the app-lock milestone built successfully.
See docs/VALIDATION.md for current results and historical limitations.

Still outstanding: physical two-phone discovery, pairing and messaging,
vendor/API compatibility, Android permission/lifecycle behavior, platform key
storage on hardware, and independent protocol/code security review. Browser
preview and automated tests do not validate these.

## Source control

Local Git history and LocalChat-history.bundle are included. GitHub account:
`yolomon9994`; repository: `LocalChat`. Before the background milestone, the working tree
was clean and `main` matched the locally recorded `origin/main`. Do not stage,
commit, publish or push without a new user request; the user will commit this
milestone themselves. No open-source license has been selected.
