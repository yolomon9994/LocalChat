import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/nearby_support.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/app_lock_controller.dart';
import 'lock_test_support.dart';
import 'nearby_support_test.dart' show TestNearbyTools, RecoveryTransport;

Widget recoveryApp(ChatController c, {AppLockController? appLock}) {
  final appearance = AppearanceController(MemoryAppearanceStorage());
  final lock = appLock ?? testLock();
  addTearDown(appearance.dispose);
  if (appLock == null) addTearDown(lock.dispose);
  return LocalChatApp(controller: c, appLock: lock, appearance: appearance);
}

void main() {
  testWidgets(
    'Wi-Fi recovery offers settings, rechecks access and distinguishes an empty completed scan',
    (tester) async {
      final tools = TestNearbyTools()
        ..status = const NearbyStatus(wifiEnabled: false);
      final t = RecoveryTransport();
      final c = ChatController(t, DemoStore(), nearbyTools: tools);
      addTearDown(() async {
        c.dispose();
        await t.bus.close();
      });
      await c.initialize();
      await tester.pumpWidget(recoveryApp(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nearby-destination')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Go nearby').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go nearby').last);
      await tester.pumpAndSettle();
      expect(find.text('Turn on Wi-Fi'), findsOneWidget);
      await tester.ensureVisible(find.text('Open Wi-Fi settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Wi-Fi settings'));
      await tester.pumpAndSettle();
      expect(tools.opened, [NearbySettings.wifi]);
      tools.status = const NearbyStatus();
      await tester.ensureVisible(find.text('Check access').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check access').first);
      await tester.pumpAndSettle();
      expect(find.text('Turn on Wi-Fi'), findsNothing);
      await tester.tap(find.text('Go nearby'));
      await tester.pumpAndSettle();
      expect(find.text('No LocalChat phones found'), findsOneWidget);
      expect(find.text('Looking for LocalChat phones'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed connect stays on Nearby; successful Reconnect opens the chat instead of a stale history route',
    (tester) async {
      final t = RecoveryTransport()..connectFailure = 'P2P_BUSY';
      final c = ChatController(t, DemoStore(), nearbyTools: TestNearbyTools());
      addTearDown(() async {
        c.dispose();
        await t.bus.close();
      });
      await c.initialize();
      await c.start();
      c.peers = [const Peer('nearby', 'Nearby friend')];
      await tester.pumpWidget(recoveryApp(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nearby-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nearby friend'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('Wi-Fi Direct is busy'), findsOneWidget);
      t.connectFailure = null;
      await tester.ensureVisible(find.text('Reconnect').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reconnect').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(c.state, 'Connecting');
      expect(c.selectedPeer, isNull);
      expect(tester.takeException(), isNull);
      await c.disconnect();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Permission recovery actions wrap and remain reachable on a small phone with enlarged text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tools = TestNearbyTools()
        ..status = const NearbyStatus(permissionGranted: false);
      final t = RecoveryTransport()..startFailure = 'PERMISSION_DENIED';
      final c = ChatController(t, DemoStore(), nearbyTools: tools);
      addTearDown(() async {
        c.dispose();
        await t.bus.close();
      });
      await c.initialize();
      await c.start();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
            ),
            child: HomeScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Open app settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open app settings'));
      await tester.pumpAndSettle();
      expect(tools.opened, [NearbySettings.permissions]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Queued help explains reconnect and disappears when locked without losing queued text',
    (tester) async {
      final t = RecoveryTransport(), tools = TestNearbyTools();
      final c = ChatController(t, DemoStore(), nearbyTools: tools);
      final lock = testLock();
      addTearDown(() async {
        c.dispose();
        lock.dispose();
        await t.bus.close();
      });
      await c.initialize();
      await c.store.savePeer('alice', 'Alice');
      await c.viewHistory((await c.store.conversations()).single);
      await c.sendText('Still queued', queueIfOffline: true);
      await tester.pumpWidget(recoveryApp(c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Why messages are queued'));
      await tester.pumpAndSettle();
      expect(
        find.text('Open Nearby and tap Go nearby, then connect to this phone.'),
        findsOneWidget,
      );
      lock.lock();
      await tester.pumpAndSettle();
      expect(
        find.text('Open Nearby and tap Go nearby, then connect to this phone.'),
        findsNothing,
      );
      expect((await c.store.messages('alice')).single.status, 'queued');
      expect(t.connects, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
