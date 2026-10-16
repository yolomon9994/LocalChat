import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:local_chat/services/app_lock_controller.dart';

// A fast deterministic test double for state/UI checks. The production KDF is
// exercised separately; tests must not spend 600,000 iterations per UI action.
Future<List<int>> fastTestPinHash(String pin, List<int> salt) async =>
    (await Sha256().hash([...salt, ...utf8.encode(pin)])).bytes;

AppLockController testLock({
  LockStorage? storage,
  Biometrics? biometrics,
  DateTime Function()? now,
  Duration Function()? elapsed,
  PinHasher? hasher,
}) => AppLockController(
  storage: storage ?? MemoryLockStorage(),
  biometrics: biometrics ?? NoBiometrics(),
  hasher: hasher ?? fastTestPinHash,
  now: now,
  elapsed: elapsed,
  isDemo: true,
);
