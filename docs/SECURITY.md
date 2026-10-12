# Security model and protocol v1

This is a prototype, not an audited secure messenger. Selecting cryptographic primitives does not establish protocol security. Do not use it for high-risk communications until the design and implementation have been independently reviewed.

## Threat model

The implementation aims to protect message content against passive radio/network interception and reject modified/replayed frames. Active impersonation is addressed only when users compare the complete security code over an independent trusted channel and both explicitly confirm. A display name or a Wi-Fi Direct pairing prompt is not identity verification.

Encryption does not hide traffic existence, sizes, timing, Wi-Fi addresses, advertised names, handshake names or identity public keys. It cannot prevent jamming, discovery spoofing, denial of service, malware, rooted-device compromise, screenshots or a verified peer sharing the text. DNS-SD names are untrusted and public. This release does not automatically trust a previously seen identity.

## Handshake

Each install generates an Ed25519 identity seed and retains it in platform-backed secure storage. Each connection generates a fresh X25519 ephemeral key pair and 32-byte random challenge.

The hello contains protocol version 1, `kind=hello`, identity public key, ephemeral public key, challenge, display name and an Ed25519 signature. The signed canonical byte representation is UTF-8 JSON of the ordered array:

`["LocalChat/hello/1", identityBase64, ephemeralBase64, challengeBase64, name]`.

The peer validates the version, key lengths, name bounds and signature. Self-reflection and repeated hellos are rejected. The canonical hellos are sorted by base64 identity string and prefixed with `LocalChat/transcript/1`; SHA-256 yields the session transcript hash. X25519 agreement is followed by HKDF-SHA256 using this hash as salt. Distinct info labels `LocalChat/1/low-to-high` and `LocalChat/1/high-to-low` derive independent 32-byte directional keys. All-zero agreement is rejected.

The 80-bit displayed code is the first 10 bytes of SHA-256(`LocalChat/SAS/1` || transcriptHash), rendered as five hexadecimal groups. The code binds both identities, ephemeral keys, challenges and names. Both peers must compare it in person and send an encrypted `verified` payload before text is accepted. Fresh connections always require new verification. A 90-second connection/verification deadline limits unattended connections.

There is no Double Ratchet, post-compromise recovery, offline prekey messaging or per-message forward secrecy. Fresh ephemeral agreement limits exposure across sessions if only a long-term identity key is later obtained, assuming ephemeral secrets have not been retained. Dart does not guarantee zeroization or immediate erasure of temporary key material.

## Frames and payloads

Direct chats use one socket. Hosted groups use a trusted host and separate
host–guest sockets, ephemeral keys, counters and both fresh confirmations. Guests
verify the host and trust its admission of other members. The host decrypts,
stores and forwards text and images; group encryption does not conceal them from the host.
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
match direct images, with 16 MiB saved image bytes per group. Inline image bytes
use existing encrypted group-record AAD, without a schema change. Payload-v5
backups validate signatures/hashes and retain v1–v4 imports and the 20 MiB archive
cap. See [group-image protocol and interruptions](GROUP_IMAGES.md).

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
admitted links may continue while the process runs. Groups have no background
service in this version. Removing a member closes its socket and updates the
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
Generic alerts send only the peer ID to Android. Preview opt-in passes bounded
plaintext sender/text to the OS only while unlocked and foregrounded; Android
private visibility and a generic public version protect device-lock-screen
content. Lock/background and preview disabling redact active previews; OS
notification history/listeners/connected devices can retain earlier plaintext
and cannot be erased by this app. Native pause also gates/redacts previews before
Dart lifecycle processing. Native preferences contain only notification booleans;
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

Drafts use the same history key with fresh random nonces and a separate AAD
domain: UTF-8 JSON `["LocalChat/draft/1", peerId]`. SQLite stores only the
peer ID and encrypted draft body. Moving ciphertext between peers or modifying
it fails authentication. Drafts do not enter message search or create plaintext
preview copies. A serialized draft queue orders saves, send cleanup and history
deletion. Clearing history deletes drafts too, subject to the same forensic-wipe
limits as messages. Draft plaintext can remain in process memory while locked;
the existing UI access-control boundary applies. Browser drafts are memory only.

Pin and archive flags are unencrypted peer metadata. Archiving changes list
placement rather than privacy or delivery rules: archived text remains stored
encrypted, searchable after unlock, and readable through the active chat.
Deleting an individual conversation removes its messages, draft and peer row
in a transaction; it disconnects that peer's active session first. Its queued
draft writes are invalidated without dropping other peers' edits. This deletes
local records, not the other phone's history or forensic copies. Reconnecting
and exchanging new messages can create a new conversation with that identity.

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

Optional app lock gates startup before chat storage is opened and hides all
application routes on launch/background until the user authenticates. A salted
PBKDF2-HMAC-SHA256 verifier and PIN attempt/cooldown state use secure storage;
the PIN is not stored in plaintext. Android biometrics use the OS biometric-only
prompt, with the LocalChat PIN as fallback. `FLAG_SECURE` is enabled while app
lock is configured to block screenshots and hide Recents previews.

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

## Before a production release

Obtain an independent protocol/code review; test on several Android vendors and API levels; fuzz framing/handshake parsing; consider a reviewed protocol library, key pinning and identity-change UX, robust bounded storage and background lifecycle support. Use a private release signing key rather than the provided debug build configuration.
