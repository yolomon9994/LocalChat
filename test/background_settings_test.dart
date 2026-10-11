import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/background_connection.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/appearance_controller.dart';

import 'lock_test_support.dart';

class SettingsPlatform extends MemoryBackgroundPlatform {
  final destinations = <String>[];
  @override
  Future<void> openSettings(String target) async => destinations.add(target);
}

class ReadySettingsController extends ChatController {
  ReadySettingsController(BackgroundConnection background)
    : super(
        DemoTransport(),
        DemoStore(),
        isDemo: true,
        background: background,
      ) {
    initialized = true;
    loading = false;
  }
  @override
  bool get ready => true;
}

void main() {
  Future<void> showSwitch(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Keep connection active'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Keep connection active'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Background switch and guidance fit a small phone with enlarged text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = ChatController(DemoTransport(), DemoStore());
      final lock = testLock();
      final appearance = AppearanceController(MemoryAppearanceStorage());
      addTearDown(lock.dispose);
      addTearDown(appearance.dispose);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await showSwitch(tester);
      expect(c.background.enabled, false);
      await tester.tap(find.text('Keep connection active'));
      await tester.pumpAndSettle();
      expect(c.background.enabled, true);
      expect(c.background.active, false);
      await tester.ensureVisible(
        find.text('Waiting for an unlocked, verified connection.'),
      );
      expect(
        find.text('Waiting for an unlocked, verified connection.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Open battery settings'));
      expect(find.text('Open battery settings'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'Denied permission guidance and battery/channel shortcuts remain reachable',
    (tester) async {
      final platform = SettingsPlatform()..allowed = false;
      final c = ChatController(
        DemoTransport(),
        DemoStore(),
        isDemo: true,
        background: BackgroundConnection(platform),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await showSwitch(tester);
      await tester.tap(find.text('Keep connection active'));
      await tester.pumpAndSettle();
      expect(c.background.enabled, false);
      expect(
        find.text(
          'Allow Android notifications and the Connection channel, then try again.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Connection notification settings'));
      await tester.tap(find.text('Connection notification settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open battery settings'));
      await tester.tap(find.text('Open battery settings'));
      await tester.pumpAndSettle();
      expect(platform.destinations, ['notifications', 'battery']);
      platform.batteryExempt = true;
      c.setAppForeground(false);
      c.setAppForeground(true);
      await tester.pumpAndSettle();
      expect(
        find.text('Android battery-optimization exemption is enabled.'),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'App lock removes background settings while an active lease remains protected',
    (tester) async {
      final platform = SettingsPlatform();
      final c = ReadySettingsController(
        BackgroundConnection(platform, isDemo: true),
      );
      final lock = testLock();
      await lock.initialize();
      await lock.enable('123456');
      addTearDown(c.dispose);
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'App PIN'),
        '123456',
      );
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await showSwitch(tester);
      await tester.tap(find.text('Keep connection active'));
      await tester.pumpAndSettle();
      expect(c.background.active, true);
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('Keep connection active'), findsNothing);
      expect(c.background.active, true);
      expect(tester.takeException(), null);
    },
  );
}
