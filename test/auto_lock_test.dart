import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/services/app_lock_controller.dart';
import 'app_lock_test.dart' show FakeBiometrics;
import 'lock_test_support.dart';

class TimingLockStorage extends MemoryLockStorage {
  int writes = 0;
  int? failAt, gateAt;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(String? value) async {
    final attempt = ++writes;
    if (attempt == gateAt) {
      entered.complete();
      await release.future;
    }
    if (attempt == failAt) throw StateError('private storage failure');
    await super.write(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var wall = DateTime.utc(2026, 10, 16);
  var elapsed = Duration.zero;
  Future<AppLockController> make({
    LockStorage? storage,
    Biometrics? biometrics,
  }) async {
    final c = testLock(
      storage: storage,
      biometrics: biometrics,
      now: () => wall,
      elapsed: () => elapsed,
    );
    addTearDown(c.dispose);
    await c.initialize();
    if (c.enabled) {
      await c.unlockPin('123456');
    } else {
      await c.enable('123456');
    }
    return c;
  }

  setUp(() {
    wall = DateTime.utc(2026, 10, 16);
    elapsed = Duration.zero;
  });
  void advance(Duration value) {
    wall = wall.add(value);
    elapsed += value;
  }

  test(
    'V1 migrates to immediate without startup rewrite; V2 saves only the delay and locks on restart',
    () async {
      final storage = MemoryLockStorage();
      final initial = await make(storage: storage);
      final raw = jsonDecode(storage.value!) as Map;
      raw['version'] = 1;
      raw.remove('autoLockSeconds');
      storage.value = jsonEncode(raw);
      final original = storage.value;
      final restarted = testLock(storage: storage);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(storage.value, original);
      expect(restarted.autoLockDelay, AutoLockDelay.immediately);
      expect(restarted.canAccess, isFalse);
      await restarted.unlockPin('123456');
      await restarted.setAutoLockDelay(AutoLockDelay.minutes5, '123456');
      final updated = jsonDecode(storage.value!) as Map;
      expect(updated['version'], 2);
      expect(updated['autoLockSeconds'], 300);
      expect(updated['hash'], raw['hash']);
      expect(updated['salt'], raw['salt']);
      expect(updated.containsKey('pin'), isFalse);
      final cold = testLock(storage: storage);
      addTearDown(cold.dispose);
      await cold.initialize();
      expect(cold.autoLockDelay, AutoLockDelay.minutes5);
      expect(cold.locked, isTrue);
      expect(cold.canAccess, isFalse);
      expect(initial.autoLockDelay, AutoLockDelay.immediately);
    },
  );

  test(
    'Invalid or missing V2 timing fails closed, with no unsupported timeout accepted',
    () async {
      final storage = MemoryLockStorage();
      await make(storage: storage);
      final saved = jsonDecode(storage.value!) as Map;
      for (final value in [null, -1, 1, 31, 600, '30', 30.0, true]) {
        storage.value = jsonEncode({...saved, 'autoLockSeconds': value});
        final lock = testLock(storage: storage);
        await lock.initialize();
        expect(lock.storageFailed, isTrue);
        expect(lock.canAccess, isFalse);
        lock.dispose();
      }
      final absent = Map.of(saved)..remove('autoLockSeconds');
      storage.value = jsonEncode(absent);
      final lock = testLock(storage: storage);
      addTearDown(lock.dispose);
      await lock.initialize();
      expect(lock.storageFailed, isTrue);
      storage.value = jsonEncode({...saved, 'version': 3});
      await lock.initialize();
      expect(lock.storageFailed, isTrue);
    },
  );

  test(
    'Every delay covers immediately, returns before deadline and requires PIN at exact expiry',
    () async {
      final lock = await make();
      for (final delay in AutoLockDelay.values) {
        if (lock.locked) await lock.unlockPin('123456');
        await lock.setAutoLockDelay(delay, '123456');
        lock.lifecycle(AppLifecycleState.inactive);
        expect(lock.covered, isTrue);
        expect(lock.canAccess, isFalse);
        if (delay.seconds == 0) {
          expect(lock.locked, isTrue);
          lock.lifecycle(AppLifecycleState.resumed);
          expect(lock.canAccess, isFalse);
          continue;
        }
        advance(
          Duration(seconds: delay.seconds) - const Duration(microseconds: 1),
        );
        lock.lifecycle(AppLifecycleState.resumed);
        expect(lock.canAccess, isTrue);
        lock.lifecycle(AppLifecycleState.inactive);
        advance(Duration(seconds: delay.seconds));
        lock.lifecycle(AppLifecycleState.resumed);
        expect(lock.locked, isTrue);
        expect(lock.canAccess, isFalse);
      }
    },
  );

  test(
    'Inactive, hidden and paused share one grant; a foreground return starts the next absence',
    () async {
      final lock = await make();
      await lock.setAutoLockDelay(AutoLockDelay.seconds30, '123456');
      lock.lifecycle(AppLifecycleState.inactive);
      advance(const Duration(seconds: 20));
      lock.lifecycle(AppLifecycleState.hidden);
      advance(const Duration(seconds: 9));
      lock.lifecycle(AppLifecycleState.paused);
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isTrue);
      lock.lifecycle(AppLifecycleState.inactive);
      advance(const Duration(seconds: 20));
      lock.lifecycle(AppLifecycleState.paused);
      advance(const Duration(seconds: 10));
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isFalse);
    },
  );

  test(
    'Timer expires while away; cancellation prevents an old timer locking a resumed app',
    () async {
      final lock = await make();
      await lock.setAutoLockDelay(AutoLockDelay.seconds30, '123456');
      fakeAsync((time) {
        lock.lifecycle(AppLifecycleState.inactive);
        time.elapse(const Duration(seconds: 29));
        expect(lock.locked, isFalse);
        expect(lock.canAccess, isFalse);
        time.elapse(const Duration(seconds: 1));
        expect(lock.locked, isTrue);
        lock.lifecycle(AppLifecycleState.resumed);
        expect(lock.canAccess, isFalse);
        expect(time.nonPeriodicTimerCount, 0);
      });
      await lock.unlockPin('123456');
      fakeAsync((time) {
        lock.lifecycle(AppLifecycleState.inactive);
        time.elapse(const Duration(seconds: 10));
        lock.lifecycle(AppLifecycleState.resumed);
        expect(lock.canAccess, isTrue);
        time.elapse(const Duration(minutes: 6));
        expect(lock.canAccess, isTrue);
        expect(time.nonPeriodicTimerCount, 0);
      });
    },
  );

  test(
    'Wall rollback, wall jump and elapsed expiry fail closed even without a running timer',
    () async {
      final lock = await make();
      await lock.setAutoLockDelay(AutoLockDelay.seconds30, '123456');
      for (final mode in ['rollback', 'jump', 'elapsed']) {
        lock.lifecycle(AppLifecycleState.inactive);
        if (mode == 'rollback') {
          wall = wall.subtract(const Duration(seconds: 1));
        }
        if (mode == 'jump') wall = wall.add(const Duration(seconds: 30));
        if (mode == 'elapsed') elapsed += const Duration(seconds: 30);
        lock.lifecycle(AppLifecycleState.resumed);
        expect(lock.canAccess, isFalse, reason: mode);
        await lock.unlockPin('123456');
      }
    },
  );

  test(
    'Manual lock, detached, initialization and already-locked exits never get a grace grant',
    () async {
      final lock = await make();
      await lock.setAutoLockDelay(AutoLockDelay.minutes5, '123456');
      lock.lifecycle(AppLifecycleState.inactive);
      lock.lock();
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isFalse);
      await lock.unlockPin('123456');
      lock.lifecycle(AppLifecycleState.inactive);
      lock.lifecycle(AppLifecycleState.detached);
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isFalse);
      lock.lifecycle(AppLifecycleState.inactive);
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isFalse);
      await lock.unlockPin('123456');
      lock.lifecycle(AppLifecycleState.inactive);
      await lock.initialize();
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isFalse);
    },
  );

  test(
    'Timing edits require PIN, retain old delay on write failure, and preserve it through PIN/biometric edits',
    () async {
      final storage = TimingLockStorage();
      final lock = await make(storage: storage, biometrics: FakeBiometrics());
      expect(
        await lock.setAutoLockDelay(AutoLockDelay.minute1, '000000'),
        isFalse,
      );
      expect(lock.autoLockDelay, AutoLockDelay.immediately);
      // The first write resets the successful PIN attempt; fail the actual setting write.
      storage.failAt = storage.writes + 2;
      expect(
        await lock.setAutoLockDelay(AutoLockDelay.minute1, '123456'),
        isFalse,
      );
      expect(lock.autoLockDelay, AutoLockDelay.immediately);
      expect(jsonDecode(storage.value!)['autoLockSeconds'], 0);
      storage.failAt = null;
      expect(
        await lock.setAutoLockDelay(AutoLockDelay.minute1, '123456'),
        isTrue,
      );
      expect(await lock.setBiometric(true, '123456'), isTrue);
      expect(await lock.changePin('123456', '654321'), isTrue);
      expect(lock.autoLockDelay, AutoLockDelay.minute1);
      lock.lock();
      expect(await lock.unlockPin('654321'), isTrue);
      expect(lock.autoLockDelay, AutoLockDelay.minute1);
      expect(await lock.disable('654321'), isTrue);
      await lock.enable('123456');
      expect(lock.autoLockDelay, AutoLockDelay.immediately);
    },
  );

  test(
    'Background during a pending timing write locks immediately and rejects overlapping operations',
    () async {
      final storage = TimingLockStorage();
      final lock = await make(storage: storage);
      await lock.setAutoLockDelay(AutoLockDelay.minute1, '123456');
      storage.gateAt = storage.writes + 2;
      final saving = lock.setAutoLockDelay(AutoLockDelay.minutes5, '123456');
      await storage.entered.future;
      expect(
        await lock.setAutoLockDelay(AutoLockDelay.seconds30, '123456'),
        isFalse,
      );
      lock.lifecycle(AppLifecycleState.inactive);
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isFalse);
      storage.release.complete();
      expect(await saving, isTrue);
      expect(lock.canAccess, isFalse);
      expect(await lock.unlockPin('123456'), isTrue);
      expect(lock.autoLockDelay, AutoLockDelay.minutes5);
    },
  );

  test(
    'Biometric inactive prompt stays covered; real background invalidates its late acceptance',
    () async {
      final bio = FakeBiometrics();
      final lock = await make(biometrics: bio);
      await lock.setAutoLockDelay(AutoLockDelay.minutes5, '123456');
      await lock.setBiometric(true, '123456');
      lock.lock();
      bio.pending = Completer<bool>();
      final unlock = lock.unlockBiometric();
      lock.lifecycle(AppLifecycleState.inactive);
      expect(lock.canAccess, isFalse);
      bio.pending!.complete(true);
      expect(await unlock, isTrue);
      expect(lock.canAccess, isFalse);
      lock.lifecycle(AppLifecycleState.resumed);
      expect(lock.canAccess, isTrue);
      lock.lock();
      bio.pending = Completer<bool>();
      final late = lock.unlockBiometric();
      lock.lifecycle(AppLifecycleState.inactive);
      lock.lifecycle(AppLifecycleState.paused);
      lock.lifecycle(AppLifecycleState.resumed);
      bio.pending!.complete(true);
      expect(await late, isFalse);
      expect(lock.canAccess, isFalse);
    },
  );

  test(
    'A PIN check pending across background/return cannot change timing or grant access',
    () async {
      Completer<List<int>>? gate;
      final storage = MemoryLockStorage();
      final lock = testLock(
        storage: storage,
        hasher: (pin, salt) => gate?.future ?? fastTestPinHash(pin, salt),
      );
      addTearDown(lock.dispose);
      await lock.initialize();
      await lock.enable('123456');
      await lock.setAutoLockDelay(AutoLockDelay.minute1, '123456');
      gate = Completer<List<int>>();
      final pending = lock.setAutoLockDelay(AutoLockDelay.minutes5, '123456');
      lock.lifecycle(AppLifecycleState.inactive);
      lock.lifecycle(AppLifecycleState.resumed);
      gate.complete(base64Decode(jsonDecode(storage.value!)['hash'] as String));
      expect(await pending, isFalse);
      expect(lock.autoLockDelay, AutoLockDelay.minute1);
      expect(lock.canAccess, isFalse);
    },
  );

  test(
    'Disposal cancels a grace timer and cannot notify or resume the controller',
    () async {
      final lock = testLock();
      await lock.initialize();
      await lock.enable('123456');
      await lock.setAutoLockDelay(AutoLockDelay.seconds30, '123456');
      fakeAsync((time) {
        lock.lifecycle(AppLifecycleState.inactive);
        expect(time.nonPeriodicTimerCount, 1);
        lock.dispose();
        expect(time.nonPeriodicTimerCount, 0);
        time.elapse(const Duration(minutes: 6));
        lock.lifecycle(AppLifecycleState.resumed);
        expect(lock.canAccess, isFalse);
      });
      expect(await lock.unlockPin('123456'), isFalse);
    },
  );
}
