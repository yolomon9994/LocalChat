import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/app_lock_controller.dart';
import 'package:local_chat/services/chat_controller.dart';

import 'lock_test_support.dart';

class FakeBiometrics implements Biometrics {
  bool supported = true;
  bool accepted = false;
  bool throws = false;
  int calls = 0;
  int cancellations = 0;
  Completer<bool>? pending;
  @override
  Future<bool> available() async => supported;
  @override
  Future<bool> authenticate() async {
    calls++;
    if (throws) throw StateError('sensor unavailable');
    return pending?.future ?? accepted;
  }

  @override
  Future<void> cancel() async => cancellations++;
}

class FailingStorage extends MemoryLockStorage {
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('vault unavailable');
    return super.read();
  }

  @override
  Future<void> write(String? value) async {
    if (failWrite) throw StateError('vault unavailable');
    await super.write(value);
  }
}

class CountingDemoStore extends DemoStore {
  int opens = 0;
  @override
  Future<void> open() async {
    opens++;
    await super.open();
  }
}

Future<MemoryLockStorage> configuredStorage() async {
  final storage = MemoryLockStorage();
  final lock = testLock(storage: storage);
  await lock.initialize();
  expect(await lock.enable('123456'), isTrue);
  lock.dispose();
  return storage;
}

void main() {
  test(
    'Production PIN KDF is deterministic and binds both salt and PIN',
    () async {
      final salt = List<int>.filled(32, 1);
      final hash = await hashAppPin('123456', salt);
      expect(hash.length, 32);
      expect(await hashAppPin('123456', salt), hash);
      expect(await hashAppPin('654321', salt), isNot(hash));
      expect(await hashAppPin('123456', List<int>.filled(32, 2)), isNot(hash));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'PIN configuration survives restart without storing plaintext',
    () async {
      final storage = await configuredStorage();
      final saved = jsonDecode(storage.value!) as Map<String, dynamic>;
      expect(saved.containsKey('pin'), isFalse);
      expect(saved['hash'], isNot('123456'));
      expect(base64Decode(saved['salt'] as String).length, 32);
      final lock = testLock(storage: storage);
      addTearDown(lock.dispose);
      expect(lock.canAccess, isFalse);
      await lock.initialize();
      expect(lock.locked, isTrue);
      expect(await lock.unlockPin('000000'), isFalse);
      expect(lock.canAccess, isFalse);
      expect(await lock.unlockPin('123456'), isTrue);
      expect(lock.canAccess, isTrue);
    },
  );

  test(
    'PIN changes, biometrics and disabling require the current PIN',
    () async {
      final storage = await configuredStorage();
      final lock = testLock(storage: storage, biometrics: FakeBiometrics());
      addTearDown(lock.dispose);
      await lock.initialize();
      await lock.unlockPin('123456');
      expect(await lock.changePin('000000', '654321'), isFalse);
      expect(await lock.setBiometric(true, '000000'), isFalse);
      expect(lock.biometricEnabled, isFalse);
      expect(await lock.disable('000000'), isFalse);
      expect(lock.enabled, isTrue);
      expect(await lock.changePin('123456', '654321'), isTrue);
      lock.lock();
      expect(await lock.unlockPin('123456'), isFalse);
      expect(await lock.unlockPin('654321'), isTrue);
      expect(await lock.disable('654321'), isTrue);
      expect(storage.value, isNull);
      expect(lock.enabled, isFalse);
      lock.lock();
      expect(lock.canAccess, isTrue);
    },
  );

  test(
    'Five wrong PINs cause a persistent cooldown, including after restart',
    () async {
      final storage = await configuredStorage();
      var now = DateTime.utc(2026, 10, 10);
      var lock = testLock(storage: storage, now: () => now);
      await lock.initialize();
      for (var i = 0; i < 5; i++) {
        expect(await lock.unlockPin('000000'), isFalse);
      }
      expect(lock.retrySeconds, 30);
      expect(await lock.unlockPin('123456'), isFalse);
      lock.dispose();
      lock = testLock(storage: storage, now: () => now);
      addTearDown(() => lock.dispose());
      await lock.initialize();
      expect(await lock.unlockPin('123456'), isFalse);
      now = now.add(const Duration(seconds: 30));
      expect(await lock.unlockPin('123456'), isTrue);
      expect(lock.retrySeconds, 0);
    },
  );

  test(
    'Storage errors and malformed configuration never bypass locking',
    () async {
      final storage = FailingStorage()..failRead = true;
      final lock = testLock(storage: storage);
      addTearDown(lock.dispose);
      await lock.initialize();
      expect(lock.storageFailed, isTrue);
      expect(lock.canAccess, isFalse);
      expect(await lock.enable('123456'), isFalse);
      storage.failRead = false;
      storage.value = '{broken';
      await lock.initialize();
      expect(lock.canAccess, isFalse);
      storage.value = null;
      await lock.initialize();
      expect(lock.canAccess, isTrue);
      expect(await lock.enable('123456'), isTrue);
      lock.lock();
      storage.failWrite = true;
      expect(await lock.unlockPin('123456'), isFalse);
      expect(lock.canAccess, isFalse);
      storage.failWrite = false;
      expect(await lock.unlockPin('123456'), isTrue);
      storage.failWrite = true;
      expect(await lock.disable('123456'), isFalse);
      expect(lock.enabled, isTrue);
    },
  );

  test(
    'Unavailable, cancelled and failed biometrics leave PIN fallback usable',
    () async {
      final biometric = FakeBiometrics();
      final lock = testLock(biometrics: biometric);
      addTearDown(lock.dispose);
      await lock.initialize();
      await lock.enable('123456');
      expect(await lock.setBiometric(true, '123456'), isTrue);
      lock.lock();
      expect(await lock.unlockBiometric(), isFalse);
      expect(lock.locked, isTrue);
      biometric.throws = true;
      expect(await lock.unlockBiometric(), isFalse);
      expect(lock.locked, isTrue);
      expect(await lock.unlockPin('123456'), isTrue);
      biometric.throws = false;
      biometric.accepted = true;
      lock.lock();
      expect(await lock.unlockBiometric(), isTrue);
      expect(lock.canAccess, isTrue);
      biometric.supported = false;
      await lock.initialize();
      expect(await lock.unlockBiometric(), isFalse);
      expect(await lock.unlockPin('123456'), isTrue);
    },
  );

  test('Backgrounding invalidates a PIN check already in flight', () async {
    final storage = await configuredStorage();
    final pending = Completer<List<int>>();
    final lock = testLock(storage: storage, hasher: (_, _) => pending.future);
    addTearDown(lock.dispose);
    await lock.initialize();
    final unlock = lock.unlockPin('123456');
    expect(await lock.unlockPin('123456'), isFalse); // No overlapping guesses.
    lock.lifecycle(AppLifecycleState.inactive);
    lock.lifecycle(AppLifecycleState.resumed);
    final record = jsonDecode(storage.value!) as Map<String, dynamic>;
    pending.complete(base64Decode(record['hash'] as String));
    expect(await unlock, isFalse);
    expect(lock.locked, isTrue);
  });

  test(
    'OS biometric dialog can unlock, actual backgrounding cancels it',
    () async {
      final biometric = FakeBiometrics()..pending = Completer<bool>();
      final lock = testLock(biometrics: biometric);
      addTearDown(lock.dispose);
      await lock.initialize();
      await lock.enable('123456');
      await lock.setBiometric(true, '123456');
      lock.lock();
      final unlock = lock.unlockBiometric();
      lock.lifecycle(AppLifecycleState.inactive);
      lock.lifecycle(AppLifecycleState.resumed);
      biometric.pending!.complete(true);
      expect(await unlock, isTrue);
      lock.lock();
      biometric.pending = Completer<bool>();
      final backgroundUnlock = lock.unlockBiometric();
      lock.lifecycle(AppLifecycleState.paused);
      lock.lifecycle(AppLifecycleState.resumed);
      biometric.pending!.complete(true);
      expect(await backgroundUnlock, isFalse);
      expect(biometric.cancellations, 1);
      expect(lock.locked, isTrue);
    },
  );

  testWidgets('Startup waits for unlock; backgrounding removes pushed routes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lock = testLock(storage: await configuredStorage());
    final store = CountingDemoStore();
    final chat = ChatController(DemoTransport(), store, isDemo: true);
    addTearDown(chat.dispose);
    addTearDown(lock.dispose);
    await tester.pumpWidget(LocalChatApp(controller: chat, appLock: lock));
    await tester.pumpAndSettle();
    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(store.opens, 0);
    await tester.enterText(find.widgetWithText(TextField, 'App PIN'), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(store.opens, 1);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(AppLockScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AppLockScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.enterText(find.widgetWithText(TextField, 'App PIN'), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(store.opens, 1);
    await store.savePeer('saved', 'Private friend');
    await store.saveMessage(
      const ChatMessage(
        id: 'private',
        peerId: 'saved',
        text: 'Private message content',
        timestamp: 1,
        outgoing: true,
        status: 'delivered',
      ),
    );
    await chat.viewHistory((await store.conversations()).single);
    unawaited(
      Navigator.of(tester.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(controller: chat)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private message content'), findsOneWidget);
    lock.lock();
    await tester.pumpAndSettle();
    expect(find.text('Private message content'), findsNothing);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIN setup confirms matching digits and manual locking works', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lock = testLock();
    final chat = ChatController(DemoTransport(), DemoStore(), isDemo: true);
    addTearDown(chat.dispose);
    addTearDown(lock.dispose);
    await tester.pumpWidget(LocalChatApp(controller: chat, appLock: lock));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set up app lock'));
    await tester.tap(find.text('Set up app lock'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New six-digit PIN'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new PIN'),
      '654321',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('The new PINs do not match.'), findsOneWidget);
    expect(lock.enabled, isFalse);
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new PIN'),
      '123456',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(lock.enabled, isTrue);
    await tester.ensureVisible(find.text('Lock now'));
    await tester.tap(find.text('Lock now'));
    await tester.pumpAndSettle();
    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.textContaining('BROWSER DEMO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
