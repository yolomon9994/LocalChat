# Testing the app lock

App lock is optional and initially disabled. Enable it in **Settings > App
lock > Set up app lock**, enter a six-digit PIN twice, and save. This PIN is
specific to LocalChat and can differ from the phone's screen-lock PIN.

When enabled, LocalChat locks on launch, when leaving the foreground, and when
you tap **Lock now**. Unlock returns to the home screen. Open the connected
conversation again if needed. Locking hides the interface; it does not promise
background delivery or terminate an existing connection.

## Browser preview

Run `flutter run -d chrome`. Set up a PIN in Settings, use **Lock now**, try a
wrong PIN, and then unlock with the correct one. Changing or disabling the PIN
requires the current PIN. The demo notice remains visible on the lock screen.

Demo lock settings live in memory and reset on reload. Fingerprint unlock and
Android secure storage cannot be tested in the browser. Changing focus between
browser windows/tabs may trigger locking through Flutter lifecycle events.

## Android phone checklist

Install the newly built debug APK (normally
`build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`) on a testing phone.
An existing installation with a different signing key cannot be updated in
place; uninstalling deletes history and identity, so use a test device/data.

- [ ] Start with app lock disabled and confirm normal discovery/chat still works.
- [ ] Enable a PIN; reject mismatched confirmation and anything below six digits.
- [ ] Tap **Lock now**; confirm chats and Settings are inaccessible.
- [ ] Try a wrong PIN, then the correct PIN.
- [ ] Fully close and reopen LocalChat; confirm the PIN is required.
- [ ] From home, a chat, and Settings, go to the launcher or switch apps. Return
      and confirm LocalChat remains locked, including when pressing Back.
- [ ] Lock the phone screen and unlock the phone; LocalChat should still ask
      for its own PIN or biometrics.
- [ ] Enter five wrong six-digit PINs; observe a 30-second wait. Restart during
      the wait and confirm it is still enforced. After the wait, unlock.
- [ ] Change the PIN using the current PIN; lock and confirm only the new PIN
      works. Reject changes and disabling with an incorrect current PIN.
- [ ] With enrolled fingerprints/biometrics, enable **Fingerprint / biometrics**
      using the current app PIN. Lock and authenticate using the OS prompt.
- [ ] Cancel the OS prompt and use the app PIN. Test sensor failure/OS lockout
      if practical; neither should bypass the lock or prevent PIN fallback.
- [ ] Switch apps during biometric authentication; return and authenticate
      again. The OS prompt briefly losing focus should not cause a relock loop.
- [ ] On a phone without enrolled biometrics, confirm PIN setup/unlock works
      and the biometric enable switch is unavailable.
- [ ] While app lock is enabled, confirm screenshots are blocked and Recents
      hides the app's contents. Disable locking with the PIN and confirm the
      normal screenshot behavior returns.
- [ ] Disable app lock using the current PIN; restart and confirm no prompt.
- [ ] Recheck Wi-Fi Direct permission prompts, pairing, code verification,
      sending and receiving after the activity migration required for biometrics.

There is no forgotten-PIN recovery. Clearing app data removes history and
identity; do not use that as a normal troubleshooting step.

## Implementation and limits

Startup reads lock configuration before opening chat storage. A locked view
replaces the entire application navigator with a separate lock navigator, so
previously pushed chats, Settings, and dialogs cannot be exposed through Back.

The secure-storage record contains a random 32-byte salt and a 32-byte
PBKDF2-HMAC-SHA256 verifier (600,000 iterations), not the PIN. Native PIN hashing
runs off the UI isolate. Failed PIN checks, retry deadlines, and the biometric
preference persist in the same record. Five wrong valid-length PIN attempts
trigger a 30-second cooldown. Concurrent attempts are rejected; lifecycle
changes invalidate pending unlocks. Storage/configuration failures keep the
interface closed and offer retry.

Android uses `local_auth`'s biometric-only OS prompt, `FlutterFragmentActivity`,
AppCompat themes, and `USE_BIOMETRIC`. The app PIN remains the fallback. The
native privacy bridge sets `FLAG_SECURE` while locking is enabled, including
the initial window until settings are read. Platform implementation guidance:
[local_auth](https://pub.dev/packages/local_auth) and
[local_auth Android setup](https://pub.dev/packages/local_auth_android).

This is an interface access control. The existing history keys are not newly
wrapped with the app PIN or bound to a biometric cryptographic operation. Once
unlocked, decrypted data can remain in process memory. It does not protect
against a compromised OS, rooted-device access, or another participant copying
messages. Continue using the phone's own screen lock.

Automated tests use storage and biometric doubles, plus a real production-KDF
check. Passing them does not establish Android sensor, secure-storage, Recents,
or lifecycle behavior; complete the phone checklist above before calling this
milestone device-tested.

## Commit after testing

The implementation is left unstaged and uncommitted for the user. From the
project folder, inspect changes with `git status` and `git diff`. Once satisfied
with the phone checks, stage the intended files and commit, for example:

```powershell
git add .gitignore docs lib test android/app/src/main pubspec.yaml pubspec.lock README.md PROJECT_CONTEXT.md
git diff --cached --stat
git commit -m "feat: add optional PIN and biometric app lock"
```

Review staged files before committing; leave unrelated changes out. Publishing
or pushing remains a separate user action.
