import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/app_lock_controller.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'auto_lock_test.dart' show TimingLockStorage;
import 'lock_test_support.dart';

void main() {
  late TimingLockStorage storage;
  late AppLockController lock;
  late ChatController c;
  late DemoStore store;
  late MemoryNotificationPlatform alerts;
  late DateTime wall;
  late Duration elapsed;
  setUp(() async {
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.contextMenu,
            (_) async => null,
          );
      await BrowserContextMenu.disableContextMenu();
    }
    wall = DateTime.utc(2026, 10, 16);
    elapsed = Duration.zero;
    storage = TimingLockStorage();
    lock = testLock(storage: storage, now: () => wall, elapsed: () => elapsed);
    await lock.initialize();
    await lock.enable('123456');
    await lock.setAutoLockDelay(AutoLockDelay.seconds30, '123456');
    store = DemoStore();
    await store.open();
    await store.savePeer('alice', 'Alice');
    await store.saveMessage(
      const ChatMessage(
        id: 'm',
        peerId: 'alice',
        text: 'Private saved text',
        timestamp: 1,
        outgoing: false,
        status: 'received',
      ),
    );
    await store.saveDraft('alice', 'Unsent draft');
    alerts = MemoryNotificationPlatform();
    c = ChatController(
      DemoTransport(),
      store,
      isDemo: true,
      notifications: ChatNotifications(alerts, isDemo: true),
    );
  });
  tearDown(() {
    c.dispose();
    lock.dispose();
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    }
  });

  Future<void> turn(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 30));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await t.pumpAndSettle();
  }

  Future<void> unlock(WidgetTester t) async {
    await t.enterText(find.widgetWithText(TextField, 'App PIN'), '123456');
    await t.tap(find.text('Unlock'));
    await turn(t);
  }

  Future<void> show(WidgetTester t) async {
    await t.pumpWidget(LocalChatApp(controller: c, appLock: lock));
    await turn(t);
    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.text('Private saved text'), findsNothing);
    await unlock(t);
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Future<void> settings(WidgetTester t) async {
    if (find.byType(SettingsScreen).evaluate().isEmpty) {
      await t.tap(find.byTooltip('Settings'));
      await turn(t);
    }
    final timing = find.byKey(const ValueKey('auto-lock-timing'));
    if (timing.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        timing,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
    }
    await t.ensureVisible(timing);
    await t.pumpAndSettle();
    expect(timing.hitTestable(), findsOneWidget);
    await t.tap(timing);
    await turn(t);
  }

  Future<void> select(WidgetTester t, String value) async {
    await t.ensureVisible(find.byKey(const ValueKey('auto-lock-delay')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('auto-lock-delay')).hitTestable(),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('auto-lock-delay')));
    await t.pumpAndSettle();
    final option = find.text(value).last;
    await t.ensureVisible(option);
    await t.pumpAndSettle();
    expect(option.hitTestable(), findsOneWidget);
    await t.tap(option);
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t, String pin) async {
    await t.enterText(find.widgetWithText(TextField, 'Current app PIN'), pin);
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await turn(t);
  }

  void away(WidgetTester t) =>
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  void back(WidgetTester t, int seconds) {
    wall = wall.add(Duration(seconds: seconds));
    elapsed += Duration(seconds: seconds);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets(
    'Timing settings require PIN, save the chosen delay, cancel and retry after failure',
    (t) async {
      await show(t);
      await settings(t);
      await select(t, '1 minute');
      await save(t, '000000');
      expect(lock.autoLockDelay, AutoLockDelay.seconds30);
      expect(find.textContaining('Incorrect PIN.'), findsOneWidget);
      storage.failAt = storage.writes + 2;
      await save(t, '123456');
      expect(lock.autoLockDelay, AutoLockDelay.seconds30);
      expect(
        find.text('Could not update app lock. Please try again.'),
        findsOneWidget,
      );
      storage.failAt = null;
      await save(t, '123456');
      expect(lock.autoLockDelay, AutoLockDelay.minute1);
      expect(find.byType(AlertDialog), findsNothing);
      await settings(t);
      await select(t, '5 minutes');
      await t.tap(find.text('Cancel'));
      await turn(t);
      expect(lock.autoLockDelay, AutoLockDelay.minute1);
    },
  );

  testWidgets(
    'A delayed authorized save can finish after its PIN dialog closes without unlocking or stale callbacks',
    (t) async {
      await show(t);
      await settings(t);
      await select(t, '5 minutes');
      storage.gateAt = storage.writes + 2;
      await t.enterText(
        find.widgetWithText(TextField, 'Current app PIN'),
        '123456',
      );
      await t.tap(find.text('Save'));
      for (var i = 0; i < 20 && !storage.entered.isCompleted; i++) {
        await t.pump(const Duration(milliseconds: 30));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      expect(storage.entered.isCompleted, isTrue);
      away(t);
      await turn(t);
      back(t, 1);
      // The lock intentionally shows a busy spinner until the gated save ends.
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AppLockScreen), findsOneWidget);
      storage.release.complete();
      await turn(t);
      expect(lock.autoLockDelay, AutoLockDelay.minutes5);
      expect(lock.canAccess, isFalse);
      expect(t.takeException(), isNull);
      await unlock(t);
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Quick switch destroys private routes immediately and resumes home without PIN, preserving draft',
    (t) async {
      await show(t);
      await t.tap(find.byKey(const ValueKey('conversation-alice')));
      await turn(t);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Private saved text'), findsOneWidget);
      final revision = c.interactionRevision;
      away(t);
      expect(c.appAccessible, isFalse);
      expect(c.appForeground, isFalse);
      expect(c.interactionRevision, greaterThan(revision));
      await turn(t);
      expect(find.byKey(const ValueKey('app-privacy-cover')), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('Private saved text'), findsNothing);
      await t.binding.handlePopRoute();
      await turn(t);
      expect(find.byType(ChatScreen), findsNothing);
      back(t, 29);
      await turn(t);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AppLockScreen), findsNothing);
      expect(find.byType(ChatScreen), findsNothing);
      await t.tap(find.byKey(const ValueKey('conversation-alice')));
      await turn(t);
      expect(find.text('Unsent draft'), findsOneWidget);
    },
  );

  testWidgets(
    'Resume rechecks expiry even when background timers have not advanced',
    (t) async {
      await show(t);
      away(t);
      await turn(t);
      back(t, 30);
      await turn(t);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(c.appAccessible, isFalse);
      await unlock(t);
      expect(find.byType(HomeScreen), findsOneWidget);
      lock.lock();
      await turn(t);
      expect(find.byType(AppLockScreen), findsOneWidget);
      away(t);
      back(t, 1);
      await turn(t);
      expect(find.byType(AppLockScreen), findsOneWidget);
    },
  );

  testWidgets(
    'An actual timer expires under the privacy cover; resume still requires PIN',
    (t) async {
      await show(t);
      away(t);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 30));
      expect(lock.locked, isTrue);
      expect(find.byKey(const ValueKey('app-privacy-cover')), findsOneWidget);
      back(t, 30);
      await turn(t);
      expect(find.byType(AppLockScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Background closes an unsaved PIN dialog; short return retains neither dialog nor input',
    (t) async {
      await show(t);
      await settings(t);
      await select(t, '5 minutes');
      await t.enterText(
        find.widgetWithText(TextField, 'Current app PIN'),
        '123456',
      );
      away(t);
      await turn(t);
      expect(find.byType(AlertDialog), findsNothing);
      back(t, 1);
      await turn(t);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(lock.autoLockDelay, AutoLockDelay.seconds30);
      await settings(t);
      expect(
        t
            .widget<TextField>(
              find.widgetWithText(TextField, 'Current app PIN'),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'Notification taps wait under the cover and open only after a valid return',
    (t) async {
      await show(t);
      away(t);
      await turn(t);
      alerts.tapEvents.add('alice');
      await turn(t);
      expect(c.notifications.pendingPeer, 'alice');
      expect(find.byType(ChatScreen), findsNothing);
      expect(alerts.accessible, isFalse);
      back(t, 1);
      await turn(t);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Private saved text'), findsOneWidget);
      away(t);
      await turn(t);
      alerts.tapEvents.add('alice');
      await turn(t);
      back(t, 30);
      await turn(t);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(c.notifications.pendingPeer, 'alice');
      await unlock(t);
      expect(find.byType(ChatScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Timing controls and PIN dialog remain usable at narrow width with enlarged text',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      // Standalone settings allows a real root MediaQuery scale on dialog routes.
      await t.runAsync(c.initialize);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2.34)),
            child: child!,
          ),
          home: SettingsScreen(controller: c, appLock: lock),
        ),
      );
      await turn(t);
      final timing = find.byKey(const ValueKey('auto-lock-timing'));
      await t.scrollUntilVisible(
        timing,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(timing);
      await t.pumpAndSettle();
      expect(timing.hitTestable(), findsOneWidget);
      await t.tap(timing);
      await turn(t);
      await select(t, '5 minutes');
      await save(t, '123456');
      expect(lock.autoLockDelay, AutoLockDelay.minutes5);
      expect(t.takeException(), isNull);
    },
  );
}
