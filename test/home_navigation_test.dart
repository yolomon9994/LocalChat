import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';

import 'lock_test_support.dart';

Finder destination(String name) => find.byKey(ValueKey('$name-destination'));

void main() {
  testWidgets(
    'Empty Chats opens Nearby without starting discovery; Settings works on both',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('No chats yet'), findsOneWidget);
      expect(find.text('Go nearby'), findsNothing);
      expect(c.started, isFalse);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Find nearby devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find nearby devices'));
      await tester.pumpAndSettle();
      expect(find.text('Find someone nearby'), findsOneWidget);
      expect(find.text('No chats yet'), findsNothing);
      expect(c.started, isFalse);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tabs retain separate scroll positions and hide inactive content from semantics',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      c.conversations = List.generate(
        20,
        (i) => Conversation('saved-$i', 'Saved friend $i', i),
      );
      c.peers = List.generate(
        20,
        (i) => Peer('device-$i', 'Discovered friend $i'),
      );
      c.started = true;
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      final chats = find.byKey(const PageStorageKey('chats-list'));
      await tester.drag(chats, const Offset(0, -500));
      await tester.pumpAndSettle();
      final chatsPosition = tester
          .state<ScrollableState>(
            find.descendant(of: chats, matching: find.byType(Scrollable)),
          )
          .position
          .pixels;
      expect(chatsPosition, greaterThan(0));
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('Discovered friend')), findsNothing);
      await tester.tap(destination('nearby'));
      await tester.pumpAndSettle();
      final nearby = find.byKey(const PageStorageKey('nearby-list'));
      await tester.drag(nearby, const Offset(0, -350));
      await tester.pumpAndSettle();
      final nearbyPosition = tester
          .state<ScrollableState>(
            find.descendant(of: nearby, matching: find.byType(Scrollable)),
          )
          .position
          .pixels;
      expect(nearbyPosition, greaterThan(0));
      expect(find.bySemanticsLabel(RegExp('Saved friend')), findsNothing);
      await tester.tap(destination('chats'));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(of: chats, matching: find.byType(Scrollable)),
            )
            .position
            .pixels,
        chatsPosition,
      );
      await tester.tap(destination('nearby'));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(of: nearby, matching: find.byType(Scrollable)),
            )
            .position
            .pixels,
        nearbyPosition,
      );
      expect(c.started, isTrue);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Locking from Nearby hides navigation and unlock returns to Chats',
    (tester) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.tap(destination('nearby'));
      await tester.pumpAndSettle();
      lock.lifecycle(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Find someone nearby'), findsNothing);
      lock.lifecycle(AppLifecycleState.resumed);
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.text('Your chats'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
