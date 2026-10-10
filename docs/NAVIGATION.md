# Chats / Nearby navigation

LocalChat now opens on **Chats**. The bottom navigation switches between two
separate views:

- **Chats** lists saved conversations. **Active chat > Open** returns to the
  connected peer, including a session that still needs security-code verification.
  When there is no history, **Find nearby devices** switches to Nearby.
- **Nearby** shows your display name, connection state, **Go nearby**, scanning
  and discovered devices. Selecting a device opens the existing chat/verification
  screen. Merely opening this tab does not start advertising or discovery.

Settings remains in the top toolbar on both tabs. Coming back from Settings or
a chat restores the selected tab. Switching tabs keeps their scroll positions
and the connection active. App locking hides both tabs and their navigation;
unlocking returns to Chats, where an active session can be reopened.

The browser preview still uses simulated peers and temporary history. Use
`flutter run -d chrome`, open Nearby, tap Go nearby, select Ava or Noah, and
confirm the simulated code. Reloading clears the demo state.

## Phone testing before committing

Install `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` over the existing
testing installation, then check:

- [ ] Launch/unlock opens Chats; earlier conversations are still available.
- [ ] Switch to Nearby and use Go nearby / Scan again to discover the other phone.
- [ ] Connect, compare the security codes on both phones, and send a message.
- [ ] Go back, switch to Chats, and reopen the conversation and the active-chat
      shortcut. Switching tabs should not disconnect either phone.
- [ ] Disconnect and reopen saved history from Chats; it remains readable.
- [ ] Open Settings from each tab and return to that same tab.
- [ ] Scroll each list, switch tabs, and confirm each keeps its own position.
- [ ] Lock/background from Nearby and unlock; confirm Chats is shown and the
      active-chat shortcut still opens an existing session.
- [ ] Check both views on a small screen with enlarged system text; content
      should scroll and navigation/Settings should remain reachable.

Themes are the next separate milestone. This change leaves chat encryption,
storage, verification and transport behavior with the existing controller.

The user stages, commits and pushes after testing; these changes are left
unstaged and uncommitted.
