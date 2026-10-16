import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/features/nearby_tab.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'automatic_reconnect_test.dart';
import 'lock_test_support.dart';

void main() {
  late ChatController c;
  late RetryTransport transport;
  late RetryStorage storage;
  setUp(() async {
    storage = RetryStorage();
    transport = RetryTransport();
    c = await retryController(
      transport,
      storage: storage,
      enabled: false,
      delays: const [
        Duration(seconds: 30),
        Duration(seconds: 30),
        Duration(seconds: 30),
      ],
    );
  });
  tearDown(() => c.dispose());

  Future<void> turn(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 30));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await t.pumpAndSettle();
  }

  Future<void> show(WidgetTester t, Widget home, {bool large = false}) async {
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(large ? 2.34 : 1)),
          child: child!,
        ),
        home: home,
      ),
    );
    await turn(t);
  }

  Widget nearby() => ListenableBuilder(
    listenable: c,
    builder: (_, _) => Scaffold(
      body: NearbyTab(controller: c, onConnect: (_) {}),
    ),
  );
  Future<void> visible(WidgetTester t, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
  }

  Future<void> waiting(WidgetTester t) async {
    await t.runAsync(() => c.setAutomaticReconnectEnabled(true));
    await t.runAsync(transport.lose);
    await turn(t);
    expect(c.automaticReconnectActive, isTrue);
  }

  testWidgets(
    'Opt-in settings default off, show temporary demo scope and recover from failed saves',
    (t) async {
      await show(t, SettingsScreen(controller: c));
      final toggle = find.byKey(const ValueKey('automatic-reconnect-setting'));
      await visible(t, toggle);
      expect(t.widget<SwitchListTile>(toggle).value, isFalse);
      expect(
        find.text('Temporary in this demo tab. Retries are simulated.'),
        findsOneWidget,
      );
      storage.failWrite = true;
      await t.tap(toggle);
      await turn(t);
      expect(c.reconnectPreferences.enabled, isFalse);
      expect(
        find.text('Could not save automatic reconnection. Please try again.'),
        findsOneWidget,
      );
      storage.failWrite = false;
      await t.tap(toggle);
      await turn(t);
      expect(c.reconnectPreferences.enabled, isTrue);
      expect(storage.value, contains('"enabled":true'));
    },
  );
  testWidgets(
    'Nearby shows attempt status and Cancel stops waiting without another connect',
    (t) async {
      await waiting(t);
      await show(t, nearby());
      expect(find.textContaining('attempt 1/3'), findsOneWidget);
      final cancel = find.byKey(const ValueKey('cancel-automatic-reconnect'));
      await visible(t, cancel);
      await t.tap(cancel);
      await turn(t);
      expect(c.automaticReconnectActive, isFalse);
      await t.drag(find.byType(Scrollable).first, const Offset(0, 1000));
      await turn(t);
      expect(
        find.textContaining('Automatic reconnection cancelled'),
        findsOneWidget,
      );
      expect(transport.addresses.length, 1);
    },
  );
  testWidgets(
    'Chat shows fresh-code verification and Cancel rejects the captured confirmation',
    (t) async {
      await t.runAsync(() async {
        await c.setAutomaticReconnectEnabled(true);
        await transport.lose();
        await retryUntil(() => c.automaticReconnectActive);
        // The other phone reconnects first; the pending timer must be cancelled.
        await transport.demo.connect('demo-ava');
        await retryUntil(() => c.code != null);
      });
      final request = c.directVerification!;
      await show(t, ChatScreen(controller: c));
      expect(
        find.textContaining('Reconnected. Compare the fresh code'),
        findsOneWidget,
      );
      expect(c.ready, isFalse);
      final cancel = find.byKey(const ValueKey('cancel-automatic-reconnect'));
      await visible(t, cancel);
      await t.tap(cancel);
      await turn(t);
      expect(await t.runAsync(() => c.confirmCode(request: request)), isFalse);
      expect(c.code, isNull);
      expect(c.ready, isFalse);
    },
  );
  testWidgets(
    'Settings and cancellation stay reachable on narrow screens at enlarged text',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await show(t, SettingsScreen(controller: c), large: true);
      final toggle = find.byKey(const ValueKey('automatic-reconnect-setting'));
      await visible(t, toggle);
      await t.tap(toggle);
      await turn(t);
      await t.runAsync(transport.lose);
      await turn(t);
      await show(t, nearby(), large: true);
      final cancel = find.byKey(const ValueKey('cancel-automatic-reconnect'));
      await visible(t, cancel);
      await t.tap(cancel);
      await turn(t);
      expect(c.automaticReconnectActive, isFalse);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Covered settings callback cannot enable retries after backgrounding',
    (t) async {
      await show(t, SettingsScreen(controller: c));
      final toggle = find.byKey(const ValueKey('automatic-reconnect-setting'));
      await visible(t, toggle);
      final callback = t.widget<SwitchListTile>(toggle).onChanged!;
      c.setAppForeground(false);
      callback(true);
      await turn(t);
      expect(c.reconnectPreferences.enabled, isFalse);
      expect(storage.value, isNull);
      c.setAppForeground(true);
      await turn(t);
      expect(c.automaticReconnectActive, isFalse);
    },
  );
  testWidgets(
    'PIN removes reconnect controls and an obsolete Cancel cannot affect the unlocked app',
    (t) async {
      final peer = c.connectedPeer!;
      final lock = testLock();
      await t.runAsync(() async {
        await lock.initialize();
        await lock.enable('123456');
        lock.lock();
      });
      final appearance = AppearanceController(MemoryAppearanceStorage());
      addTearDown(lock.dispose);
      addTearDown(appearance.dispose);
      (c.notifications.platform as MemoryNotificationPlatform).launchPeer =
          peer;
      await t.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await turn(t);
      await t.runAsync(() => lock.unlockPin('123456'));
      await turn(t);
      expect(
        c.ready,
        isTrue,
        reason: 'The original verified connection remains live',
      );
      expect(c.appForeground, isTrue);
      expect(c.appAccessible, isTrue);
      await waiting(t);
      await turn(t);
      final cancel = find.byKey(const ValueKey('cancel-automatic-reconnect'));
      await visible(t, cancel);
      final callback = t.widget<TextButton>(cancel).onPressed!;
      lock.lock();
      await turn(t);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('automatic-reconnect-status')),
        findsNothing,
      );
      callback();
      await turn(t);
      expect(c.automaticReconnectActive, isFalse);
      await t.runAsync(() => lock.unlockPin('123456'));
      await turn(t);
      expect(find.byType(ChatScreen), findsNothing);
      expect(transport.addresses.length, 1);
    },
  );
}
