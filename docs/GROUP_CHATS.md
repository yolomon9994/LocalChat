# Hosted nearby group chats

Implemented: 2026-10-11. Open the **Group chats** icon in the home toolbar.
Saved groups also appear in **Chats**. Groups support text, images and files with one
Android phone acting as host and up to seven guests (eight phones total).
Actual Wi-Fi Direct capacity and discovery behavior depend on the phones.
Image controls, foreground requirements, limits and three-phone checks are in
[GROUP_IMAGES.md](GROUP_IMAGES.md). File controls and tests are in
[GROUP_FILES.md](GROUP_FILES.md).

## Create and join

1. On the host, choose **Create group**, enter a name, and allow Nearby access.
   Android creates a Wi-Fi Direct group with this phone as owner. Creating or
   finding groups closes any direct-chat connection; saved direct history remains.
2. On guests, open Group chats and choose **Find groups**. Tap the advertised
   group and accept Android's Wi-Fi Direct pairing prompt if shown.
3. The host and each guest compare the **entire fresh code** in person. Both tap
   **Codes match**. A guest is not admitted or included in the member list until
   both confirmations arrive. Joining times out after 90 seconds.
4. Open the active group. View its verified member list and send text. The host
   can reject a pending guest or remove an admitted member. Guests can leave;
   the host can end hosting. No old history is sent to newly admitted members.

Keep the host open and connected for reliable delivery. The existing background
connection setting protects direct chats only; groups have no foreground service
or wake locks in this version. Receiving and forwarding on already verified links
may continue while the process runs, but screen-off/background reliability is not
claimed. New text and membership approval require an unlocked, foreground app.

## Trust and delivery

The host is a **trusted relay**: it decrypts, stores and forwards group text over
separate encrypted host–guest sessions. Guests verify the host, and trust the
host's admission of other members. This is not client-to-client encryption that
conceals messages from the host. Names and advertised group titles are untrusted;
the code comparison verifies a particular connection, not a display name.

Each author signs the group ID, host identity, room epoch, membership revision,
message ID, author key/name, timestamp, text and exact recipient list. Received
signatures are checked before persistence. The host binds a submitted author to
the sending verified link; clients require the author in the host-approved roster.
Modification, author impersonation, wrong-group/session replay and unverified
payloads close the offending link. A membership race rejects an old recipient
list with guidance; check the refreshed list and send again.

Each link uses the existing signed Ed25519 hello, fresh X25519 agreement,
80-bit code, directional XChaCha20-Poly1305 keys and ordered frame counters.
There is no shared long-lived group key to export or leave on a removed member.
Removed members' sockets close and the roster revision advances. Removing someone
does not erase their earlier copies or prevent a trusted member sharing them.
The host can still withhold messages, lie about its roster or reported receipts;
author signatures do not prevent a malicious host admitting a lookalike identity.

Outgoing text is saved before transmission and shows individual received/pending/
unconfirmed receipts for the recipients at send time. A receipt means that phone
reported persistence, not that a person read it; guest receipts are reported through
the host. After 30 seconds, disconnect or restart, outstanding attempts become
unconfirmed. There is no automatic group retry or offline group outbox. Missing
receipts can mean the message arrived: manually sending again creates a new ID.
Identical signed IDs are deduplicated while receiver history is retained.

## Saved history, privacy and backups

Each phone saves only the group messages it received or originated. History opens
offline; reading a visible unlocked group clears its unread count. App lock covers
group routes. Local message notification preferences apply, with generic locked/
background content and taps that wait for unlock before opening the saved group.
Failed notifications cannot prevent persistence or receipts. No alerts are created
by backup import. Group composer text is temporary in this first version.

Group titles, author keys/names, signed envelopes, receipts and read state are in
authenticated encrypted SQLite records. Schema 7 adds `group_history` without
altering direct history. Only each random group ID is a plaintext record key.
There is a limit of 10,000 saved messages per group. Export and delete a full group
before continuing. Confirmed deletion affects this phone and ends its active group;
**Delete all chat history** also removes groups. Pin/archive and local search
currently apply to direct chats; group refinements remain in the backlog.

Encrypted backups include groups. Text-only group archives use payload version 2;
group images use v5 and group files v6, while direct images/files select v3/v4.
Nonempty group drafts select v7. Current builds import v1-v7. The encrypted file envelope/KDF remains version
1, but older builds reject the new payload rather than silently dropping groups.
Import validates signatures and group/host references, merges by group + author +
message ID, keeps existing conflicting records/read state, re-encrypts with local
storage keys, and changes imported pending receipts to unconfirmed. Import ends
the current group and never joins, sends or restores session keys. Identity
transfer requires no saved direct or group history on the destination.

The original host can explicitly **Host this group again** from saved history.
That retains the group ID/history, creates a new room epoch, and requires every
guest to join and compare new codes. There is no automatic reconnect, host
migration or restoration after Activity/process closure. History-only import
does not make the destination the original host; explicit identity transfer can.

Browser preview explains the Android requirement and can display imported demo
group history; it does not simulate discovery, hosting or real group links.

## Saved group drafts

Group composers remember unfinished text independently, including while offline.
Drafts restore through navigation, locking and Android restart; sends clear them
only after atomic local acceptance. Failed saves show Retry draft. Group deletion
removes its draft, and backups include them. See [GROUP_DRAFTS.md](GROUP_DRAFTS.md).
Sending still requires verified members; reconnecting never sends drafts automatically.

## Physical three-phone checks

These are pending. Record phone models, Android versions and actual member limits.

- [ ] Install the updated APK on three phones, with Wi-Fi on, mobile data off and
  no router. Create on one and find/join from both others.
- [ ] Accept native pairing. Verify one guest at a time: one-sided confirmation
  cannot admit or exchange text, mismatches are rejected, and pending joins expire.
- [ ] Exchange text/emoji/Urdu from every phone; author names/identity suffixes
  agree. Verify the 4,096-byte bound and individual receipts for both recipients.
- [ ] Let another member join after a message: it gets the roster and new text,
  never the earlier message. Test leaving/removal and the updated member lists.
- [ ] Remove one guest: the other continues. End hosting or disable host Wi-Fi:
  both guests pause and retain history. Restart and rehost: every code is fresh.
- [ ] Lock/background a phone: no new sends/confirmation; received messages remain
  unread until an unlocked visible group. Record actual delivery interruptions.
- [ ] Enable message alerts; test generic lock-screen content, normal locked tap
  routing, read suppression, per-group cancellation, and missing/deleted histories.
- [ ] Switch back to direct mode: group links close and direct verification/outbox/
  background protection work. Repeat create/find/leave/reconnect rapidly.
- [ ] Reopen saved history after app restart. Delete one group versus all history;
  check other phones retain their copies and no deleted record returns.
- [ ] Export/import direct and group history together on a second phone, repeat
  import for dedupe, and test explicit identity transfer to an empty phone.
- [ ] Test smaller screens, enlarged text, both theme modes and every palette.
- [ ] Test Android 7–12, Android 13 and Android 14+ where available; try additional
  guests to measure hardware limits, and record battery/background behavior.

Android references: [Wi-Fi Direct overview](https://developer.android.com/develop/connectivity/wifi/wifip2p)
and [`createGroup`](https://developer.android.com/reference/android/net/wifi/p2p/WifiP2pManager#createGroup(android.net.wifi.p2p.WifiP2pManager.Channel,%20android.net.wifi.p2p.WifiP2pManager.ActionListener)).
Automated results are in [VALIDATION.md](VALIDATION.md). The user handles Git.
