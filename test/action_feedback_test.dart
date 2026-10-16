import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/services/action_feedback.dart';

class FakeActionHaptics implements ActionHaptics {
  @override
  bool supported = true;
  bool fail = false;
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<void> lightImpact() async {
    calls++;
    await gate?.future;
    if (fail) throw PlatformException(code: 'private-platform-detail');
  }
}

class FailingFeedbackStorage extends MemoryFeedbackStorage {
  bool failRead = false, failWrite = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('private storage detail');
    return super.read();
  }

  @override
  Future<void> write(String value) async {
    writes++;
    await gate?.future;
    if (failWrite) throw StateError('private storage detail');
    await super.write(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default-off preference persists independently and does not pulse on enable',
    () async {
      final storage = MemoryFeedbackStorage(), haptics = FakeActionHaptics();
      final f = ActionFeedback(storage, haptics: haptics);
      addTearDown(f.dispose);
      expect(f.capture(() => true), isNull);
      await f.initialize();
      expect(f.enabled, isFalse);
      expect(f.capture(() => true), isNull);
      expect(await f.setEnabled(true), isTrue);
      expect(haptics.calls, 0);
      final next = ActionFeedback(storage, haptics: haptics);
      addTearDown(next.dispose);
      await next.initialize();
      expect(next.enabled, isTrue);
      final ticket = next.capture(() => true)!;
      await next.complete(ticket);
      await next.complete(ticket);
      expect(haptics.calls, 1);
    },
  );
  test(
    'malformed and unreadable records fail closed with a repairable generic error',
    () async {
      for (final raw in [
        null,
        'not json',
        '[]',
        '{"v":2,"enabled":true}',
        '{"v":1,"enabled":"true"}',
        '{"v":1,"enabled":true,"extra":0}',
      ]) {
        final storage = FailingFeedbackStorage()
          ..value = raw
          ..failRead = raw == null;
        final f = ActionFeedback(storage, haptics: FakeActionHaptics());
        addTearDown(f.dispose);
        await f.initialize();
        expect(f.enabled, isFalse);
        expect(f.loading, isFalse);
        expect(f.error, contains('Could not load'));
        expect(f.error, isNot(contains('private')));
        storage.failRead = false;
        expect(await f.setEnabled(true), isTrue);
        expect(f.error, isNull);
      }
    },
  );
  test(
    'failed saves preserve the setting, reject overlap and invalidate old requests',
    () async {
      final storage = FailingFeedbackStorage(), haptics = FakeActionHaptics();
      final f = ActionFeedback(storage, haptics: haptics);
      addTearDown(f.dispose);
      await f.initialize();
      await f.setEnabled(true);
      final ticket = f.capture(() => true)!;
      final before = storage.value;
      storage.gate = Completer<void>();
      storage.failWrite = true;
      final save = f.setEnabled(false);
      expect(f.capture(() => true), isNull);
      final writes = storage.writes;
      expect(await f.setEnabled(true), isFalse);
      expect(storage.writes, writes);
      storage.gate!.complete();
      expect(await save, isFalse);
      expect(f.enabled, isTrue);
      expect(storage.value, before);
      await f.complete(ticket);
      expect(haptics.calls, 0);
      storage.gate = null;
      storage.failWrite = false;
      expect(await f.setEnabled(false), isTrue);
    },
  );
  test(
    'privacy, preference revisions, disposal and foreign tickets suppress late pulses',
    () async {
      final haptics = FakeActionHaptics();
      final f = ActionFeedback(MemoryFeedbackStorage(), haptics: haptics);
      final other = ActionFeedback(MemoryFeedbackStorage(), haptics: haptics);
      addTearDown(other.dispose);
      await f.initialize();
      await other.initialize();
      await f.setEnabled(true);
      await other.setEnabled(true);
      var current = true;
      final private = f.capture(() => current)!;
      current = false;
      await f.complete(private);
      final old = f.capture(() => true)!;
      await f.setEnabled(false);
      await f.setEnabled(true);
      await f.complete(old);
      final foreign = f.capture(() => true)!;
      await other.complete(foreign);
      final disposed = f.capture(() => true)!;
      f.dispose();
      await f.complete(disposed);
      expect(haptics.calls, 0);
    },
  );
  test(
    'pending pulses coalesce without a queue and platform failures are harmless',
    () async {
      final haptics = FakeActionHaptics()..gate = Completer<void>();
      final f = ActionFeedback(MemoryFeedbackStorage(), haptics: haptics);
      addTearDown(f.dispose);
      await f.initialize();
      await f.setEnabled(true);
      final first = f.complete(f.capture(() => true));
      await f.complete(f.capture(() => true));
      expect(haptics.calls, 1);
      haptics.gate!.complete();
      await first;
      haptics.gate = null;
      haptics.fail = true;
      await f.complete(f.capture(() => true));
      expect(haptics.calls, 2);
      expect(f.error, isNull);
    },
  );
  test('demo and unsupported haptics never invoke an output', () async {
    for (final demo in [false, true]) {
      final haptics = FakeActionHaptics()..supported = demo;
      final f = ActionFeedback(
        MemoryFeedbackStorage(),
        haptics: haptics,
        isDemo: demo,
      );
      addTearDown(f.dispose);
      await f.initialize();
      await f.setEnabled(true);
      await f.complete(f.capture(() => true));
      expect(haptics.calls, 0);
    }
  });
  testWidgets(
    'Android adapter requests the light platform haptic; web remains silent',
    (t) async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await const AndroidActionHaptics().lightImpact();
      expect(calls.length, kIsWeb ? 0 : 1);
      if (!kIsWeb) {
        expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'unsupported platform does not request a haptic channel',
    (t) async {
      expect(const AndroidActionHaptics().supported, isFalse);
      await const AndroidActionHaptics().lightImpact();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
