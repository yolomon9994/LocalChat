# QR session verification

Implemented locally: 2026-10-15. Baseline `04f5682` (starred messages).
The user stages, commits and pushes after review/testing.

## How to use it

1. Connect to another phone normally. For a group, select the pending host/guest
   connection being verified. QR verification does not discover or join a group.
2. On one phone tap **Show QR**, and on the other tap **Scan QR**. Allow Android
   camera access when requested. Scan directly from the other phone in person.
3. A matching scan pauses the camera and shows **Verify connection**. Tap it to
   confirm locally. Scanning alone never approves the connection.
4. Switch roles: the first phone scans the second phone's QR and confirms too.
   Alternatively, either side can compare the full displayed security code and
   tap **Codes match**. Both phones must confirm before messaging/admission.

The first phone to confirm can still show its QR while waiting for the other.
Manual code comparison and **Codes differ** remain available. An old QR, your
own QR, a QR for another pending member, or an unrelated URL cannot verify this
connection. Nothing scanned is opened as a link.

Camera scanning is Android-only. Browser demo and other platforms display QR
codes and retain manual comparison without starting the web scanner. Browser
participants and their confirmations remain simulated inside the tab.

## Permission, privacy and offline operation

- Android camera permission is requested only when scanning. Camera hardware is
  optional in the manifest; phones without it can compare codes manually.
- Denial, missing hardware and camera errors show generic guidance and a manual
  fallback. Enable permission in Android app settings and reopen scanning.
- Going inactive/background, locking, disconnecting, timing out or changing the
  selected connection expires the open QR view. Return/unlock and open a fresh
  view; an old callback or late camera result cannot approve a connection.
- The first OS permission dialog may make the app inactive and trigger app lock.
  Finish the permission prompt, unlock if needed, then reopen **Scan QR**. The
  scanner does not automatically resume the expired view. Pending permission
  completion must finish shutting down before another camera view starts.
- `mobile_scanner` 7.1.4 uses bundled Android ML Kit barcode models, explicitly
  configured with `useUnbundled=false`; the APK contains the model assets. First
  scanning is intended to work without Internet/model downloads. Physical first-use
  offline scanning still needs the checks below.
- Only QR barcodes are requested, without returned camera images. Camera input is
  not saved/exported or sent to peers by this implementation. The scanner stops
  on match, leaving scan mode, backgrounding, errors and route disposal.
- QR images use black modules on white with a quiet zone regardless of theme.
  Screen-reader labels and scrolling preserve manual fallback at enlarged text.

Package references: [mobile_scanner 7.1.4 Android build configuration](https://github.com/juliansteenbakker/mobile_scanner/blob/v7.1.4/android/build.gradle),
[mobile_scanner documentation](https://pub.dev/packages/mobile_scanner/versions/7.4.2)
and [qr_flutter QR rendering API](https://pub.dev/documentation/qr_flutter/latest/qr_flutter/QrImageView-class.html).
The newer scanner documentation describes bundled/unbundled and web behavior;
the pinned version's source and built APK were checked for the actual model choice.

## Protocol and trust

The version-1 QR is bounded JSON with exactly six fields: type
`LocalChat/session-verification`, `v=1`, `mode=direct|group`, `session`, `from`,
and `to`. The last three are lowercase 64-character hex digests. The payload is
limited to 512 UTF-8 bytes and contains no identity seed, private ephemeral key,
shared key, chat body or reusable login token. It is not persisted or backed up.

`session` is the full existing SHA-256 signed-hello transcript hash; `from` and
`to` are the SHA-256 identity public-key IDs. A scanner requires the same mode
and transcript hash with sender/receiver reversed. Each reconnect changes the
fresh handshake, so previously displayed QRs cannot approve the new session.
Group confirmation additionally binds the exact pending link/session and running
controller. It is not a group invitation, room credential or proof about every
group member; the existing trusted-host model remains in force.

The UI captures a request before navigation. Controllers recheck owner, exact
session object, link/selected peer, foreground/unlocked state and interaction
revision before queued confirmation, after encryption and after sending. If a
confirmation is interrupted after consuming an encrypted frame sequence, the
same direct session or affected group link is closed rather than reused.
Manual confirmation uses the same request guards. Existing hello signatures,
80-bit codes, HKDF, encrypted verification payloads and transport frames do not
change, so a peer using manual comparison remains compatible.

Scan the actual other phone's screen using a trusted in-person comparison.
A forwarded image is public session data, not proof that the person forwarding
it owns the connected phone. There is no automatic trust of saved identities.
SQLite remains schema 13 and backups remain version 10.

## Automated checks

See [VALIDATION.md](VALIDATION.md) for commands, results and local ignored logs.
Sixteen protocol/controller checks cover malformed/bounded payloads, reciprocal
identities, reconnects, explicit two-sided confirmation, mixed manual/QR use,
timeouts, selected-peer changes, queued/in-flight privacy races, and isolated
group links/rehosting/relay. Five camera tests fake the native platform to check
QR-only setup, denial, errors, late permission results, serial disposal and
inactive shutdown. Eleven widget checks cover rendered QR pixels, confirmation,
retry/mode switching, PIN/stale callbacks, manual waiting, platform fallback,
small enlarged-text screens and a live simulated group connection.

Mocks do not demonstrate actual optical decoding, autofocus or OS permission
behavior on a physical phone. Browser tests do not exercise a real camera.

## Physical acceptance checklist (pending)

Record phone models, Android versions and results. Use two phones for direct
chat and a third phone for simultaneous group-member isolation.

- [ ] Install the testing APK with no prior camera grant; disable Internet/mobile
      data while keeping Wi-Fi enabled. Scan on first use without model downloads.
- [ ] Grant permission, including with app PIN enabled; if the prompt expires the
      view, unlock/reopen Scan. Verify no lingering camera indicator after exit.
- [ ] Deny permission, deny permanently, revoke it in settings, and test unavailable
      hardware where possible. Manual comparison must still work without a crash.
- [ ] Direct chat: show/scan/confirm in both directions; one confirmation alone
      cannot send messages. Then exchange encrypted text and check receipts.
- [ ] Mix QR on one phone with full manual comparison on the other.
- [ ] Scan your own QR, an unrelated URL, an old screenshot after reconnect and
      another pending member's QR. None should approve the current connection.
- [ ] Switch Scan/Show/manual rapidly, exit during permission/startup, lock, switch
      apps and let verification time out. Reopen safely; no stale approval or camera.
- [ ] Host and guest scan each other before group admission. With two pending
      guests, verify only the chosen link; then exchange signed group messages.
- [ ] Rehost/rejoin and reject old QR images. Existing admitted links remain intact
      when a different pending link fails or is rejected.
- [ ] Test light/dark/all palettes, low brightness, focus/distance/rotation, a small
      screen, large OS text, TalkBack labels, scrolling and manual fallback.
- [ ] Browser: show QR/manual flow with demo labels; Scan shows Android-only
      fallback, no permission prompt or scanner/CDN request.
