# Text size and high contrast

Implemented locally: 2026-10-15. Baseline `d84c754` (QR verification).
The user reviews, stages, commits and pushes the milestone.

## Controls

Open **Settings → Appearance**. Below the existing theme/palette choices:

- **Text size**: Follow system, Larger (+15%), or Largest (+30%). The added
  enlargement multiplies the device's scaled font size. Follow system removes
  only the extra enlargement; it does not reset Android's text preference.
- **High contrast**: stronger text and control colors with the current palette
  and light/dark mode. A device-reported high-contrast preference also applies,
  even when the app's switch is off. The switch records your app preference.
- **Readability preview**: a heading, sample message and smaller detail text
  let you inspect the current settings before returning to a conversation.

Changes apply after a successful save, including the open Settings route,
dialogs, direct/group chats, the demo notice and the PIN screen. Unsaved profile
edits, the selected tab, drafts and conversation state remain intact. Theme
mode and palette selections stay available. Optional vibration is now available in Settings > Action feedback; see
  [ACTION_FEEDBACK.md](ACTION_FEEDBACK.md).

## Persistence and failure behavior

Android keeps all four appearance choices together in the existing secure-storage
preference entry. Appearance JSON version 2 adds textSize/highContrast. Version-1
theme/palette records are accepted without rewriting them during startup and use
Follow system/normal contrast until changed. The next successful save writes v2.

Invalid fields reject the whole saved record before applying any part of it.
Fresh controllers fall back to Dark/Mint, Follow system and normal app contrast,
with the existing recoverable error. Device accessibility preferences still apply.
Failed writes keep both the visible and saved previous choices and allow retry.
Controls are disabled while saving to avoid overlapping preference updates.

Appearance is independent of chat history, the app lock and encrypted backups.
Deleting history does not reset these preferences. Chat SQLite remains schema 13,
backups remain v10 and no wire protocol/native permission/package changes occur.
Browser demo preferences remain in memory and reset on reload. Pending authorized
preference saves can finish after locking; they cannot unlock or expose a chat.

## Rendering

The app composes a TextScaler with the device's existing scaler rather than
replacing it with a linear factor. Nonlinear platform scaling is preserved and
large device text is never capped or reduced by these presets.

Enhanced schemes use Flutter's Material contrast level 1 for every light/dark
palette. Primary/secondary/tertiary/error container pairs retain their original
colors when those already have a higher contrast ratio. This prevents the
generated enhanced theme from reducing contrast for already-readable bubbles.
Message text, icons and attachment buttons use the foreground for their bubble;
group author/time/status text also uses the matching foreground. Search highlights
keep their own secondary-container foreground/background pair.

The browser demo notice gains a bounded scroll area at large text sizes or short
window heights so it remains readable without pushing the app out of view.
QR images retain their independent black-on-white rendering and quiet zone.

Automated checks target at least 7:1 for the enhanced theme's tested text/color
pairs and at least 3:1 for outlines against the page surface. These numerical
checks and layout tests do not establish accessibility conformance for the
whole app; physical readability, TalkBack and actual device behavior need review.

## Automated validation

See [VALIDATION.md](VALIDATION.md) for commands, results and ignored local logs.
Twelve new checks cover legacy preference migration, restart, invalid records,
failed/overlapping writes, nonlinear scaling, actual Settings controls, route/edit/
tab retention, PIN coverage, device high contrast and brightness, all eight
enhanced palettes, 320 × 568 with OS 1.8 × app 1.3 = 2.34 text, the demo notice,
direct/group message colors and draft preservation. Existing appearance, group
search and the complete feature suite are also checked.

## Phone and browser checklist (pending)

Record phone model, Android version, device font/display settings and outcome.

- [ ] Upgrade an install with a saved theme/palette. Verify both are retained and
      the new controls initially show Follow system and high contrast off.
- [ ] Try all text presets with Android default and enlarged text. Check that
      Follow system restores the device size and that app enlargement persists
      after a full restart, including the initial PIN screen.
- [ ] Toggle high contrast in all light/dark palettes. Inspect text, timestamps,
      author names, message states, search highlights, replies, file buttons,
      starred messages, notifications/settings guidance and PIN errors.
- [ ] Enable a device high-contrast preference if exposed by the OS to Flutter;
      inspect its behavior with the app switch off and after brightness changes.
      Android high-contrast-text/display settings can vary by OS/vendor.
- [ ] At 320-pixel-equivalent width and combined large text, open Settings, select
      every preset and scroll to the preview. Check both chat types, Nearby,
      verification/manual controls, QR, backups and dialogs with the keyboard up.
- [ ] Keep an unsaved profile edit and direct/group draft while changing settings.
      Return to the same tab/chat and confirm edits and drafts remain intact.
- [ ] Lock/unlock and switch apps from Settings and a pushed chat/dialog. Confirm
      the chosen readability applies to PIN and content remains inaccessible.
- [ ] Use TalkBack to identify text-size choices, selected state, high-contrast
      switch, preview, message actions and manual verification. Check focus order.
- [ ] Browser: try combined text enlargement in a small window. Scroll the full
      demo notice without losing the app, change settings, lock/unlock, then
      reload and confirm demo choices reset as documented.
