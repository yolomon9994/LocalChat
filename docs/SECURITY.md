# Security model and protocol v1

This is a prototype, not an audited secure messenger. Selecting cryptographic primitives does not establish protocol security. Do not use it for high-risk communications until the design and implementation have been independently reviewed.

## Threat model

The browser demo can host/join private in-tab simulated groups. Remote identities,
confirmations, messages and receipts are simulated, although shared controllers
exercise the normal encrypted/signed protocol. Only remote demo participants
confirm automatically; the visible local user must still confirm. No sockets,
external peers, OS background service, persistent secure storage or Android trust
shortcut is introduced. Each tab/reload has independent temporary state; demo
backups remain separate from phone backups. See [BROWSER_GROUPS.md](BROWSER_GROUPS.md).

The implementation aims to protect message content against passive radio/network interception and reject modified/replayed frames. Active impersonation is addressed only when users compare the complete security code over an independent trusted channel, or scan each other's current session QR in person, and both explicitly confirm. A display name or a Wi-Fi Direct pairing prompt is not identity verification.

Encryption does not hide traffic existence, sizes, timing, Wi-Fi addresses, advertised names, handshake names or identity public keys. It cannot prevent jamming, discovery spoofing, denial of service, malware, rooted-device compromise, screenshots or a verified peer sharing the text. DNS-SD names are untrusted and public. This release does not automatically trust a previously seen identity.

## Handshake

Each install generates an Ed25519 identity seed and retains it in platform-backed secure storage. Each connection generates a fresh X25519 ephemeral key pair and 32-byte random challenge.

The hello contains protocol version 1, `kind=hello`, identity public key, ephemeral public key, challenge, display name and an Ed25519 signature. The signed canonical byte representation is UTF-8 JSON of the ordered array:

`["LocalChat/hello/1", identityBase64, ephemeralBase64, challengeBase64, name]`.

The peer validates the version, key lengths, name bounds and signature. Self-reflection and repeated hellos are rejected. The canonical hellos are sorted by base64 identity string and prefixed with `LocalChat/transcript/1`; SHA-256 yields the session transcript hash. X25519 agreement is followed by HKDF-SHA256 using this hash as salt. Distinct info labels `LocalChat/1/low-to-high` and `LocalChat/1/high-to-low` derive independent 32-byte directional keys. All-zero agreement is rejected.

The 80-bit displayed code is the first 10 bytes of SHA-256(`LocalChat/SAS/1` || transcriptHash), rendered as five hexadecimal groups. The code binds both identities, ephemeral keys, challenges and names. Both peers must compare it in person (or scan each other's current session QR) and explicitly send an encrypted `verified` payload before text is accepted. Fresh connections always require new verification. A 90-second connection/verification deadline limits unattended connections.

There is no Double Ratchet, post-compromise recovery, offline prekey messaging or per-message forward secrecy. Fresh ephemeral agreement limits exposure across sessions if only a long-term identity key is later obtained, assuming ephemeral secrets have not been retained. Dart does not guarantee zeroization or immediate erasure of temporary key material.

## QR comparison of the live session

The QR contains a bounded public version-1 JSON payload with direct/group mode,
the full 256-bit existing transcript hash, and sender/receiver identity public-key
IDs. A scan must match the live session with reciprocal identities. It contains
no identity seed, shared secret or reusable credential. Showing/scanning a QR
does not change the hello/signature/key derivation or encrypted verified payload.
Scanning alone does not trust: a separate local confirmation and the remote
confirmation are still required. Manual comparison remains compatible.

The app captures the exact controller/session/link and foreground/access revision
before navigation or queued confirmation and rechecks after encryption and send.
Reconnects, privacy changes, selection changes and timeouts invalidate requests.
If an encrypted confirmation is interrupted, its session/link is closed to avoid
reusing a consumed frame sequence. Group QR verifies only that host-guest link;
it does not authenticate the roster independently of the host or join a room.

Android scanning uses bundled barcode models and requests only QR detection,
without returned images. Permission denial/errors retain manual fallback. Camera
startup/shutdown is serialized across views, including late permission replies;
privacy loss closes the view and stops capture without automatic resumption.
Browser/unsupported platforms never start the plugin's web/CDN scanner.

Compare directly with the intended person's phone through a trusted in-person
channel. A relayed screenshot is public session information, not proof of who
is holding the connected phone. Physical optical decoding/first-use offline and
OS permission behavior remain unvalidated; see [QR_VERIFICATION.md](QR_VERIFICATION.md).
No stored trust, SQLite schema or backup-format change is introduced.

## Frames and payloads

Direct chats use one socket. Hosted groups use a trusted host and separate
host–guest sockets, ephemeral keys, counters and both fresh confirmations. Guests
verify the host and trust its admission of other members. The host decrypts,
stores and forwards text, images and files; group encryption does not conceal them from the host.
Names, titles and pairing prompts remain untrusted. See the detailed
[hosted group trust model and wire design](GROUP_CHATS.md).

Group images negotiate encrypted `group-image-v1` on every admitted link. Their
author signs the existing group context with domain `LocalChat/group-image/1`,
adding canonical PNG metadata (dimensions, length, SHA-256) before recipients.
The text signature domain and old text records are unchanged. Signed offers and
bounded chunks travel inside per-link encrypted frames; the shared attachment
engine checks chunk order, length, digest and decoded pixels before saving.
The host saves uploads before forwarding; recipients save before final receipts.
Generic `groupReceipt` cannot replace a recipient's image completion at the host.
Host trust still permits withholding and false receipt claims. All apps need
foreground unlock; membership changes cancel active images. Source/prepared limits
match direct images, with 16 MiB saved image/file bytes combined per group. Inline image bytes
use existing encrypted group-record AAD, without a schema change. Payload-v5
backups validate signatures/hashes and retain v1–v4 imports and the 20 MiB archive
cap. See [group-image protocol and interruptions](GROUP_IMAGES.md).

Group files negotiate encrypted `group-file-v1` independently of image support.
Authors sign the same room context under `LocalChat/group-file/1`, including
canonical name/MIME/length/SHA-256. Existing text/image signature bytes are
unchanged. Opaque nonempty files are bounded to 8 MiB; safe names never become
filesystem paths. Signed offers and acknowledged chunks use the shared group
attachment relay and existing per-link encrypted counters. Completion receipts
follow local persistence; the trusted host saves before relay and can read files.
Lock/background/membership changes stop partial transfers, with no auto-resume.
Complete bytes stay inline in encrypted group records; files use schema 9
and group drafts add schema 10, followed by group metadata in schema 11. Export
requires confirmation and produces an unprotected copy outside the app. Payload-v6
backups validate names/digests/signatures and combined group limits, retain v1–v5
imports and the 20 MiB archive cap, and never send restored files. See
[group-file protocol and physical checks](GROUP_FILES.md).

Group types `groupVerified`, `groupRoster`, `groupText`, `groupReceipt` and
`groupRejected` travel inside existing sealed frames. Authors sign ordered UTF-8
JSON of `["LocalChat/group-text/1", groupId, hostPublicBase64, roomEpoch,
membershipRevision, messageId, authorPublicBase64, authorName, timestamp, text,
sortedRecipientIds]`. Receivers check signature, fields, current group/epoch,
host-approved author and exact recipients. The host also binds submissions to
their verified sending link. Clients pin the actual verified host key. A fresh
random room epoch and advancing roster revision prevent reuse after rehosting or
membership changes; stale recipient submissions get an encrypted rejection.
Invalid/unverified/replayed/forged frames close the offending link. Identical
signed author/message IDs do not persist twice while receiver history is retained.

Persistence precedes receipts/forwarding. Guest receipts are authenticated at the
host, then reported through it. Receipts do not prove a person read the text;
the trusted host can withhold text, lie about receipts/rosters or admit a lookalike
identity despite author signatures. Pending attempts become unconfirmed after
30 seconds or disconnect/restart. No automatic group retry/outbox operates.
Originating sends/admission require foreground unlock; receiving/relay on already
admitted links may continue while the process runs. Optional background protection
now shares the existing service with direct chats. It starts from foreground
unlock after fresh group admission, with native checks of the current room and
Dart-authorized live link IDs. Pending/unverified sockets do not authorize or
retain protection. Per-frame wake work is bounded and released after processing,
including invalid/ignored frames. Direct/group generations and service epochs
isolate cleanup and stale Stop actions; no new wire payload, membership trust,
permissions or background originating-send/attachment capability is added.
See [GROUP_BACKGROUND.md](GROUP_BACKGROUND.md) for behavior and hardware checks.
Removing a member closes its socket and updates the
roster; it cannot erase old copies or prevent other members sharing them.

Native limits: seven guest sockets, eight roster members, 65,536-byte frames,
15-second partial-read/write deadlines and 90-second pending joins. New members
receive no old history. Host closure ends the room; explicit rehosting creates a
new epoch and requires fresh confirmations. No host migration, auto-connect or
session key restoration exists. Schema 7 encrypts whole group records with the
local history key and AAD `LocalChat/group-history/1/<groupId>`; only random IDs
remain plaintext. Author signatures are checked on receiving/backup import
before an authenticated local write; local reads rely on AEAD protection.
Each saved group is bounded to 10,000 messages. Version-2 backup payloads add
bounded validated groups and convert imported pending receipts to unconfirmed.
New builds retain v1 import and the v1 encrypted envelope/KDF; older builds reject
group payloads. Import ends group links, never sends/joins and preserves conflicts.

TCP framing is a 4-byte unsigned big-endian byte count followed by UTF-8 JSON, maximum 65,536 bytes. Invalid sizes, malformed UTF-8 or partial frames taking over 15 seconds cause closure. The idle first byte can wait indefinitely. Direct sessions have one socket with no forwarding; the hosted group exception is described above.

Sealed frame fields: `v`, `kind=sealed`, `session`, `seq`, `nonce`, `body`, `tag`. XChaCha20-Poly1305 uses a random 24-byte nonce. The authenticated additional data is UTF-8 JSON of `["LocalChat/frame/1", sessionHashHex, sequence]`. Receive counters advance only after successful authentication and parsing. Sequences must be contiguous; duplicates, reordering, wrong sessions, invalid lengths and authentication failures close the connection. A serialized controller queue prevents concurrent counter/writer races.

Core payload types are `verified`, `text` and `ack`, with negotiated image/file operations described below. Message IDs, timestamps and content are inside authenticated ciphertext. Text is limited to 4096 UTF-8 bytes. Acknowledgements are also encrypted and sent only after successful decryption and local persistence.

Direct-chat images negotiate `image-v1` in encrypted verification. Image offers,
ready/chunk/receipt/completion/cancellation payloads use the same sealed frames
and ordered counters; older peers continue text without image support. Source
images are decoded/resized/re-encoded without source metadata. Transfers are
bounded to 2 MiB and 1600 pixels/side with one 12 KiB chunk outstanding per
direction. Exact order/size/hash and decoding precede an atomic receiver commit
and final receipt. Both apps require foreground unlock; cancellation/lock/loss
discard partial incoming bytes and leave outgoing attempts unconfirmed. No
automatic image outbox/resume operates; explicit retry retains original IDs.
Schema 8 encrypts image bytes and metadata separately under the history key,
binding peer, ID, direction and image kind through separate AAD namespaces.
Kind and existing message metadata remain plaintext. V3 backups include bounded
validated images while retaining v1/v2 imports and the existing archive cap/KDF.
See [image limits, wire/storage design and phone checks](IMAGE_SHARING.md).

Saved chats accept an encrypted offline outbox. Queued messages transmit only
after both phones verify the current session, for that identity, with the sender
unlocked and foregrounded. At most four attempts await ACK; after 30 seconds,
disconnect or restart an attempted message becomes unconfirmed. Unconfirmed
messages require explicit Retry, preserving ID/text/timestamp. The receiver
acknowledges an identical existing record without inserting it or changing its
read state/activity; conflicting text/timestamps close the session. Dedupe only
lasts while receiver history is retained. New text creates a new ID.

The queued→sending state is persisted before transport submission. A final
access check follows encryption; a gate change discards the unsent frame and
session to avoid a sequence gap. Already submitted writes can complete while
locked, and receiving/ACKs retain the existing app-lock model. ACKs only confirm
IDs attempted in the current verified session, including late ACKs after timeout.
There is no automatic reconnect. See [outbox behavior and tests](OUTBOX.md).

## At-rest data

Local notifications are opt-in, with sender/body previews disabled by default.
Generic alerts send only the peer ID to Android. Sender-only mode omits the body
across the native bridge; full preview opt-in passes bounded plaintext sender/text
to the OS only while unlocked and foregrounded; Android
private visibility and a generic public version protect device-lock-screen
content. Lock/background and preview disabling redact active previews; OS
notification history/listeners/connected devices can retain earlier plaintext
and cannot be erased by this app. Native pause also gates/redacts previews before
Dart lifecycle processing. Native preferences contain notification enablement
and preview mode only;
tap intents and redaction bookkeeping retain peer IDs without names or bodies.
Cold/warm taps wait for app unlock and saved-history validation, and never bypass
fresh session verification. New persisted incoming rows notify; retained-history
duplicate retries and backup imports do not. Notification failures are isolated
from the encrypted protocol. Optional background protection uses a separate,
generic Connection notification; message-alert cancellation cannot remove it.
There is no cloud push.
See [notification privacy and testing](NOTIFICATIONS.md).

An independent random 32-byte key encrypts message bodies using XChaCha20-Poly1305, stored as base64(nonce || tag || ciphertext). AAD binds the peer ID, message ID and direction. Message IDs are scoped by peer and direction so a received ID cannot replace an outgoing record. SQLite stores peer IDs, names, timestamps, directions, delivery state and local read state without encryption. Chats list previews decrypt the existing message body in memory; no additional plaintext preview is stored. Read state is local and is not sent as a network read receipt. The storage key and Ed25519 seed use `flutter_secure_storage` backed by Android's platform security facilities. These are software-accessible secrets, not claims of non-exportable hardware X25519 or Ed25519 keys.

Local search decrypts existing message bodies in memory in cancellable batches.
It does not store a plaintext index, search query log or additional message copy.
Opening search results uses the existing app-lock and visible-conversation read
gates. Locking removes search routes and cancels pending result updates.

Group search scans the authenticated histories already decrypted for saved
groups, with cooperative cancellation and a newest-100 message-result cap.
Result snapshots contain IDs/display text, without attachment contents. Group
names, message text, image labels and file labels/filenames can match; draft and
attachment contents are excluded. No index, persisted query or protocol change
is added. Backgrounding clears results and cancels work; returning unlocked
refreshes the query. Locking clears the query and rejects stale navigation.
Opening archived matches preserves local choices and visible-group read gates.

Drafts use the same history key with fresh random nonces and a separate AAD
domain: UTF-8 JSON `["LocalChat/draft/1", peerId]`. Group drafts use a separate
`group_drafts` table in schema 10 and domain `["LocalChat/group-draft/1", groupId]`.
Their bodies are encrypted with the same history key; IDs remain metadata.
One queue orders direct/group draft saves, backups, deletion and atomic message
acceptance. v7 backups validate group references/bounds and keep existing local
drafts. See [GROUP_DRAFTS.md](GROUP_DRAFTS.md). Direct draft rows contain only the
peer ID and encrypted body. Moving ciphertext between targets or modifying
it fails authentication. Drafts do not enter message search or create plaintext
preview copies. A serialized draft queue orders saves, send cleanup and history
deletion. Clearing history deletes drafts too, subject to the same forensic-wipe
limits as messages. Draft plaintext can remain in process memory while locked;
the existing UI access-control boundary applies. Browser drafts are memory only.

Group pin/archive flags are unencrypted local metadata columns in schema 11.
They follow the same list-organization rules as direct chats. Group messages and
drafts remain encrypted, and metadata changes preserve their ciphertext. Flags
never enter the radio protocol or author signatures. Serialized management actions
check access revisions, while transactional history writes retain current choices.
Payload-v8 backups authenticate choices in the encrypted archive, validate their
boolean types, preserve existing destination choices and retain v1-v7 imports.
See [GROUP_MANAGEMENT.md](GROUP_MANAGEMENT.md).

Pin and archive flags are unencrypted peer metadata. Archiving changes list
placement rather than privacy or delivery rules: archived text remains stored
encrypted, searchable after unlock, and readable through the active chat.
Deleting an individual conversation removes its messages, draft and peer row
in a transaction; it disconnects that peer's active session first. Its queued
draft writes are invalidated without dropping other peers' edits. This deletes
local records, not the other phone's history or forensic copies. Reconnecting
and exchanging new messages can create a new conversation with that identity.

Private contact nicknames use a nullable encrypted peer column in schema 14,
with the existing history key and domain `["LocalChat/contact-nickname/1", peerId]`.
There is no plaintext nickname search index. Peer IDs and advertised names remain
ordinary metadata. Nicknames affect local labels only; verification and outgoing
reply names retain the actual peer/session names. V11 password-encrypted archives
include optional nicknames; existing destination choices win on merge. See
[CONTACT_NICKNAMES.md](CONTACT_NICKNAMES.md).

Android cloud backup and device transfer are excluded to avoid moving a database without its secure-storage keys. Uninstalling loses identity and chat history. Clearing history deletes database records, not a guaranteed forensic wipe of SQLite journals or flash storage. A device lock and OS security are still required.

## Implementation boundaries

Manual backups use a separate password-derived key (PBKDF2-HMAC-SHA256, 600,000
iterations, 256 bits), fresh salt/nonce and XChaCha20-Poly1305. The versioned
header is authenticated; file and payload limits are enforced. Only encrypted
bytes go through the native file picker/browser download. The encrypted archive
includes the private identity seed: possession of the file and password allows
identity impersonation. There is no password recovery. Import authenticates and
validates before preview, then re-encrypts text with destination history keys.
Existing records win conflicts; database writes form one transaction.
Newly imported queued/sending records become unconfirmed and require explicit
Retry; imports never silently transmit pending messages.

Identity transfer is explicit and limited to empty destinations. A vault journal
and transactional database receipt recover interrupted identity writes on open.
The old phone must stop using that identity. History-only imports retain the
destination identity and do not themselves authenticate any nearby peer.
Passwords/previews lose their UI references on background or route disposal;
encrypted selection can survive system-picker locking. Managed-memory erasure
is not guaranteed. See [backup format and tests](BACKUPS.md).

Optional app lock gates startup before chat storage is opened and removes all
application routes immediately on background. The default requires immediate
re-authentication; PIN-authorized 30-second, 1-minute and 5-minute choices retain
an in-memory grant for a quick return to Chats. Launch/manual lock always require
authentication. Resume checks expiry independently of background timer delivery. A salted
PBKDF2-HMAC-SHA256 verifier and PIN attempt/cooldown state use secure storage;
the PIN is not stored in plaintext. Android biometrics use the OS biometric-only
prompt, with the LocalChat PIN as fallback. `FLAG_SECURE` is enabled while app
lock is configured to block screenshots and hide Recents previews. Grace never
keeps chat/notification previews accessible in background; access revisions still
invalidate old actions. Lock record v2 stores only the configured duration, not
a live grant. See [AUTO_LOCK_TIMING.md](AUTO_LOCK_TIMING.md).

This is UI access control, not additional PIN encryption of the database or
biometric-bound storage keys. An established connection may remain active while
locked, and unlocked data can remain in process memory. Android biometric,
lifecycle, secure-storage and screenshot behavior requires physical phone
testing. See [app lock testing](APP_LOCK.md).

Wi-Fi Direct communication uses Android's `INTERNET` permission because TCP sockets require it. There is no application API endpoint, telemetry SDK, account service or backend. The group owner listens on port 45873. The listener is not an identity check: the signed handshake plus mandatory code comparison is the application-layer gate. A nearby attacker could occupy the single connection and cause denial of service.

Optional `remoteMessaging` foreground-service protection retains the current
Activity/Flutter session while backgrounded. It starts only from foreground
unlock after both phones verify, bound to native socket generation/service epoch.
Native promotion failure/cancellation is guarded; stale Stop actions cannot close
a later protection session. Stop is an explicit local operation allowed while
locked: it closes transport/advertising, disables the preference and preserves
history/drafts/outbox. Closing the Activity/task/process ends protection; there is
no sticky/boot restart, alternate engine or restoration of session keys.

Notifications/status retain only fixed generic text and control tokens, with no
peer identity/name/body. An unexported service owns bounded frame-processing wake
locks (15-second timeout, completion/disconnect/destruction cleanup), never an
idle CPU/Wi-Fi lock. Foreground unlock still gates new queued sending; existing
receiving/persistence/ACK rules remain. Doze/vendor settings can interrupt receipt;
battery exemption is user-controlled and not automatically requested. Local
permission/notification checks stop an invalid service; this is not a peer
heartbeat. OS suspension can interrupt transport and background delivery is not
guaranteed. Idle socket failure may become visible only when sending or when
Android reports group/TCP loss. No automatic reconnect. See [background limits](BACKGROUND_CONNECTION.md).

Manual recovery checks radio/permissions on foreground/unlock without starting
discovery or connecting. Revoked access closes existing verification. The last
device hint is an in-memory Wi-Fi address/name from the current nearby list,
not a trusted identity. Reconnect always performs a new signed handshake and
both-phone code comparison; queued delivery remains scoped to the learned
cryptographic identity. Settings shortcuts use fixed system intents and add no
permissions. See [connection recovery](CONNECTION_RECOVERY.md).

## Direct-chat files

Direct-chat files negotiate `file-v1` inside encrypted verification. Offers bind
sanitized filename, length and SHA-256 digest; content is opaque, nonempty and
bounded to 8 MiB. Shared image/file transfers use exact indexed 12 KiB chunks,
per-stage timeouts and persistence before final receipts. Both apps must be
unlocked and foregrounded. No automatic file outbox or resume operates. One
outgoing attachment is allowed across kinds, with at most one incoming per kind.
Older peers retain the capabilities they support. File names, contents and
receipts are encrypted on the wire, without changing the handshake or counters.

Schema 9 adds encrypted file bytes and metadata using the history key with AAD
`LocalChat/file/1/<peer>/<id>/<direction>` and
`LocalChat/file-message/1/<peer>/<id>/<direction>`. Message/bytes writes, deletion
and imports are transactional. Existing text/image/group records remain compatible.
Kind/peer/ID/direction/time/status metadata stays plaintext. Payload-v4 archives
include validated files and retain v1/v2/v3 reads, the existing encrypted envelope
and 20 MiB total limit. Imported pending attachments are unconfirmed, never sent.

Picker selections seal filename and bytes in memory until unlocked review/send.
Files are not opened or executed by LocalChat. A verified peer can send unwanted
contents; filename/digest validation does not assess the contents of a document.
Explicit **Save to phone** creates a copy outside LocalChat's app lock/encryption;
the user confirms this before choosing its destination. Authorized export may
finish while the system picker locks/backgrounds the app. Chat deletion cannot
erase exported copies. No plaintext temporary file is created by LocalChat, but
temporary managed/native buffers do not guarantee forensic erasure. See
[file controls and hardware checks](FILE_SHARING.md).

## Explicit text copying

Message-copy actions require foreground unlock and an existing text message in
its current route. Access/message revisions reject stale menu callbacks after
lock/background, deletion or route removal. Copy menus and active confirmations
are dismissed on invalidation; delayed platform writes cannot show stale feedback.
No extra plaintext index, stored clipboard value or wire message is introduced.

Copied text is placed on the system/browser clipboard outside LocalChat's history
encryption and app lock. An already authorized platform write may finish after
locking, and copies survive app locking or chat deletion. LocalChat does not
read or clear the clipboard on lock, avoiding overwriting newer clipboard data.
See [copy controls and manual checks](MESSAGE_COPY.md).

## Reply quotations

Direct reply metadata is inside authenticated encrypted text payloads, negotiated
with reply-v1. Local direction is inverted on receipt and scoped to the peer;
reference IDs cannot open another chat. Unsupported peers retain plain text, and
queued replies are not stripped or sent without capability support.

Group reply envelopes use signature domain LocalChat/group-reply/1, including
canonical reference ID, author ID, name and bounded preview alongside existing
session/roster/recipient context. All admitted members need group-reply-v1.
Signature verification rejects changed, added or removed quote fields; the
trusted host decrypts and relays quotes as it does other group text. A quoted
author need not remain in the roster. A preview is claimed by the replying sender,
not separate cryptographic proof from the original author. Replying intentionally
shares this bounded preview with current recipients, including new members.

Schema 12 binds encrypted quote drafts to target and direct/group scope with
LocalChat/reply-draft/1 AAD. Direct reply kind uses LocalChat/reply-message/1 AAD
and encrypts answer+quote together; kind/direction/time/status and draft targets
remain local plaintext metadata. Existing ciphertext is preserved during upgrade.
Payload-v9 archives validate quotes/signatures and retain v1-v8 imports, merge
conflict handling, destination encryption and explicit identity migration rules.

Reply actions recheck foreground/unlock, revisions, message scope and route/
lifetime; quote previews hide on background and PIN removes routes/menus. Existing
verified background storage/receipts still work, while new sends/admissions retain
foreground gates. Notifications never append the quoted preview. See
[reply controls and validation](MESSAGE_REPLIES.md).

## Before a production release

Obtain an independent protocol/code review; test on several Android vendors and API levels; fuzz framing/handshake parsing; consider a reviewed protocol library, key pinning and identity-change UX, robust bounded storage and background lifecycle support. Use a private release signing key rather than the provided debug build configuration.

## Private starred-message references

Stars are local, never included in direct/group wire payloads or group signatures.
Schema 13 stores a canonical target/message/direction-or-author reference encrypted
with the history key using XChaCha20-Poly1305 and LocalChat/star/1/<id> AAD. Row IDs
are HMAC-SHA256 over LocalChat/star-key/1/<canonical-reference>, keyed by the same
history key; database metadata alone does not expose the reference or allow an
unkeyed message-ID lookup. Row counts and ciphertext sizes remain visible. Existing
message metadata is unchanged. Deletion and star cleanup are transactional.

V10 password-encrypted archives include stars; validation requires an exact scoped
original in the archive. Merge skips conflicting originals, retains destination
stars and re-encrypts imported references. Stars are additive, with no unstar
history. Existing archive KDF, identity migration and demo/phone separation apply.
Foreground/PIN/route/revision guards reject obsolete actions and delayed navigation;
the saved list clears decrypted rows when backgrounded/locked. Already-authorized
storage writes may finish after locking. See STARRED_MESSAGES.md and VALIDATION.md.

## Chat-list preview privacy

An independent secure preference can omit direct chat snippets from Chats and
archive widget/semantics trees. Loading/unreadable preferences hide snippets.
Group rows and draft summaries retain summary-only behavior. This is a display
choice: names/counts/times, explicit search, Starred messages and opened history
remain available after unlock. No body/index is copied or deleted. Preview
preferences are excluded from backups. Dart/native notification modes separately
enforce hidden/sender/full choices, with redaction before setting changes and
conservative in-session filtering after a failed restrictive save. See
[PREVIEW_PRIVACY.md](PREVIEW_PRIVACY.md).
