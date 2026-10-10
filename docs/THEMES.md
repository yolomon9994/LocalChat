# Theme setup and testing

Open Settings from either Chats or Nearby and scroll to **Appearance**.
Choose **Light**, **Dark** or **Follow system**, then **Mint**, **Blue**,
**Purple** or **Amber**. Changes apply immediately after the preference saves,
including the current Settings screen. The initial appearance is Dark/Mint.

Android stores your selection locally, separately from chat history and lock
settings. Restarting the app or deleting chat history preserves it. Browser
Demo choices reset on reload, like its other settings.

## Phone checklist

Install the updated `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`,
or run `flutter run -d DEVICE_ID`.

- [ ] Try Light and Dark with each palette. Inspect Chats, Nearby and Settings.
- [ ] Open a saved chat or connect/verify with a second phone. Check incoming
      and outgoing text, timestamps, delivery labels and the connection notice.
- [ ] Select Follow system and change Android's light/dark setting. Return to
      the app and confirm its appearance follows the phone. Fixed Light/Dark
      should keep their chosen brightness when the phone's setting changes.
- [ ] Change appearance from Settings on Nearby, then go back. Nearby should
      remain selected. An unsaved display-name edit should survive a theme change.
- [ ] With app lock enabled, lock and unlock the app. The lock screen should use
      the chosen theme. Unlock should return to Chats as before.
- [ ] Close and reopen the app and check the saved appearance, including the
      initial lock screen. Try this with the phone offline.
- [ ] Increase Android text size and confirm the controls wrap and scroll.

The browser can preview controls and colors using `flutter run -d chrome`;
it does not validate Android preference persistence or hardware behavior.

## Failure behavior and automated checks

If saved preferences cannot be read or are invalid, the app uses Dark/Mint and
shows a recoverable Appearance error. Choosing a setting saves a fresh preference.
If a save fails, the applied theme and selected controls keep their previous
values and show an error so you can retry. Appearance errors do not grant access
through app lock.

`test/appearance_test.dart` uses memory storage and failure doubles to check
restart persistence, malformed/unreadable preferences and failed-save retry.
Widget tests cover system brightness, Settings changes, route/edit/tab retention,
the lock screen, small-screen enlarged-text controls, and incoming/outgoing
message contrast of at least 4.5:1 in all eight light/dark palette combinations.
Connection and demo notice color pairs also meet that contrast threshold.
