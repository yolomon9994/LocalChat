import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/features/background_settings.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'group_background_test.dart';
import 'lock_test_support.dart';

Future<void> backgroundUiTurn(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late GroupBackgroundRig rig;
  late ChatController host;
  setUp(() async {
    rig = GroupBackgroundRig();
    host = await rig.phone('Host');
    final guest = await rig.phone('Guest');
    await host.groups.host('Room');
    await rig.net.join(guest.groups);
    await rig.settle();
  });
  // UI continuations use Flutter's fake clock. Dispose directly rather than
  // await another protocol turn after that clock has been torn down.
  tearDown(() => rig.close(stopGroups: false));

  testWidgets(
    'group-only service failures offer reachable Retry and preserve foreground messaging',
    (tester) async {
      await tester.runAsync(() async {
        await host.setBackgroundEnabled(false);
        await rig.settle();
      });
      rig.platforms[0].fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackgroundSettings(controller: host),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep connection active'));
      await backgroundUiTurn(tester);
      expect(host.ready, isFalse);
      expect(host.groups.backgroundReady, isTrue);
      expect(find.text('Retry connection protection'), findsOneWidget);
      expect(find.textContaining('Could not protect'), findsOneWidget);
      rig.platforms[0].fail = false;
      await tester.ensureVisible(find.text('Retry connection protection'));
      await tester.tap(find.text('Retry connection protection'));
      await backgroundUiTurn(tester);
      expect(host.background.active, isTrue);
      expect(find.text('Connection protection active'), findsOneWidget);
      expect(find.text('Retry connection protection'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'group controls and foreground-only attachment guidance fit large text on a narrow phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: BackgroundSettings(controller: host),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Groups can receive and relay text'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Connection protection active'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.textContaining('member approval, images and files'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'PIN covers Settings while the existing group protection stays active',
    (tester) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: host, appLock: lock));
      await backgroundUiTurn(tester);
      await lock.enable('123456');
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Keep connection active'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(host.background.active, isTrue);
      lock.lock();
      await backgroundUiTurn(tester);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('Keep connection active'), findsNothing);
      expect(host.background.active && host.groups.connected, isTrue);
      expect(rig.platforms[0].starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
