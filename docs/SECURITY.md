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

TCP framing is a 4-byte unsigned big-endian byte count followed by UTF-8 JSON, maximum 65,536 bytes. Invalid sizes, malformed UTF-8 or partial frames taking over 15 seconds cause closure. The idle first byte can wait indefinitely. There is one accepted socket and one conversation per session, and no automatic forwarding.

Sealed frame fields: `v`, `kind=sealed`, `session`, `seq`, `nonce`, `body`, `tag`. XChaCha20-Poly1305 uses a random 24-byte nonce. The authenticated additional data is UTF-8 JSON of `["LocalChat/frame/1", sessionHashHex, sequence]`. Receive counters advance only after successful authentication and parsing. Sequences must be contiguous; duplicates, reordering, wrong sessions, invalid lengths and authentication failures close the connection. A serialized controller queue prevents concurrent counter/writer races.

Payload types are `verified`, `text` and `ack`. Message IDs, timestamps and content are inside authenticated ciphertext. Text is limited to 4096 UTF-8 bytes. Acknowledgements are also encrypted and sent only after successful decryption and local persistence. There is no automatic retransmission or offline outbox. Unconfirmed messages may already exist on the peer, so manual resend can create another message.

## At-rest data

An independent random 32-byte key encrypts message bodies using XChaCha20-Poly1305, stored as base64(nonce || tag || ciphertext). AAD binds the peer ID, message ID and direction. Message IDs are scoped by peer and direction so a received ID cannot replace an outgoing record. SQLite stores peer IDs, names, timestamps, directions, delivery state and local read state without encryption. Chats list previews decrypt the existing message body in memory; no additional plaintext preview is stored. Read state is local and is not sent as a network read receipt. The storage key and Ed25519 seed use `flutter_secure_storage` backed by Android's platform security facilities. These are software-accessible secrets, not claims of non-exportable hardware X25519 or Ed25519 keys.

Android cloud backup and device transfer are excluded to avoid moving a database without its secure-storage keys. Uninstalling loses identity and chat history. Clearing history deletes database records, not a guaranteed forensic wipe of SQLite journals or flash storage. A device lock and OS security are still required.

## Implementation boundaries

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

Foreground UI operation only; OS suspension can interrupt transport. No assurance of background delivery. This release has no heartbeat or automatic reconnect; idle socket failure may become visible only when sending or when Android reports group loss.

## Before a production release

Obtain an independent protocol/code review; test on several Android vendors and API levels; fuzz framing/handshake parsing; consider a reviewed protocol library, key pinning and identity-change UX, robust bounded storage and background lifecycle support. Use a private release signing key rather than the provided debug build configuration.
