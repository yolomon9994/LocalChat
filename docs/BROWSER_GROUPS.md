# Browser group simulation

Implemented: 2026-10-13. Run `flutter run -d chrome`, then open **Group chats**
from the home toolbar. The persistent browser notice and group screens identify
this as a demo. Members, remote confirmations, messages and receipts are
simulated within one browser tab; no phones or other browser tabs are connected.

## Try hosting or joining

- **Create demo group**: enter a name. Ava and Noah appear as pending simulated
  guests. Their side confirms automatically; tap **Codes match** for each member
  yourself. Until you confirm, that member is not admitted. On real Android
  phones, compare the whole code on both phones in person.
- **Find demo groups**: select **Weekend plans (Demo)**, hosted by Ava. Tap
  **Codes match** to try joining. Noah is another simulated guest. The host and
  remote members approve their simulated side automatically.
- Send text and receive signed simulated replies, with per-member receipts.
  The existing image/file controls also transfer to the simulated recipients.
  These flows exercise the shared protocol, without proving network delivery.
- Remove a pending/admitted member when hosting, or end/leave the group. Its
  saved history remains available offline. Rehost your own saved group with
  fresh confirmations. Rediscovery keeps Ava's demo-host identity and saved room
  within the same tab, with a fresh room epoch and new local confirmation.

Groups use the existing draft, unread, pin/archive, search, deletion and demo
backup behavior. Archiving preserves an active demo connection and saved draft;
search includes archived groups. Demo backups stay separate from phone backups.
Switching to direct demo chats ends the group connection; starting/finding a group
closes the direct connection. Ending a group cancels its pending simulated replies.

PIN locking hides group routes/dialogs and keeps local sending/admission gated.
An already admitted simulated member may send a queued reply while you are away;
it follows the existing incoming/unread rules. Background controls are temporary
simulations, with no Android service or reliable screen-off-delivery claim.

Everything stays in memory: history, drafts, simulated identities, settings and
remote stores reset on reload. Separate tabs have independent identities/worlds.
Use a demo backup to preserve visible history before reloading if desired.

## Implementation

`DemoGroupTransport` connects private in-memory endpoints to the existing
`GroupController`, using ordinary fresh encrypted handshakes, signed group
envelopes, roster/receipt handling and attachment transfers. Only remote demo
participants confirm automatically; the visible local controller still waits for
its explicit confirmation. Simulated peers do not become a trust shortcut on
Android. Android retains `WifiGroupTransport`, encrypted SQLite and native service
handling; only the browser factory selects the simulation.

World generations filter stale queued events. Stop/disposal closes private peers
and cancels reply/verification/receipt timers; initialization checks cancellation
before attaching listeners. No sockets, platform channels, cloud services, new
dependencies, database schema, backup payload or encrypted wire messages are
introduced by the simulation. Real Wi-Fi Direct discovery, Android biometrics/
secure storage and background/battery behavior still require phone testing.

## Browser checklist

Automated results and local log paths are in [VALIDATION.md](VALIDATION.md).
Run the preview from PowerShell in the project folder:

```powershell
flutter run -d chrome
```

- [ ] Create a demo group; confirm Ava and Noah separately. Check simulation
      labels, distinct verification codes and no admission before your tap.
- [ ] Send text, Unicode and multiline messages; check simulated replies and
      each member's received status. Send an image and a small file, then view
      their saved copies. Background/lock still gates new sends/attachments.
- [ ] Find/join Ava's demo room and confirm its host. Send text through the
      simulated host and check Noah's replies and individual receipts.
- [ ] Reject/remove a member. The remaining group still works. End/leave and
      reopen saved history; rehost your own group with fresh confirmation.
- [ ] Save a draft, pin/archive the group and search an older message. Opening
      a search match keeps the archive/draft; deletion requires confirmation.
- [ ] Lock with verification or a create dialog open. Private routes disappear;
      unlock starts from Chats and a dismissed dialog cannot start a group.
- [ ] Switch between direct/group demos; old replies do not enter a replacement
      session. Try temporary background controls; all status remains labeled demo.
- [ ] Export/import a demo backup. Reload the tab and check data resets; another
      tab cannot discover or message your group.
- [ ] Try narrow layouts, larger text and light/dark themes.

Manual visual/browser interaction checks and physical Android regressions remain
separate from the automated protocol/widget checks. The user handles Git.
