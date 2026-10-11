import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';

import 'lock_test_support.dart';

class GatedHistoryStore extends DemoStore {
  Completer<void>? gate;
  @override
  Future<List<ChatMessage>> messages(String peer) async {
    await gate?.future;
    return super.messages(peer);
  }
}

void main() {
  Future<void> seed(DemoStore store) async {
    await store.open();
    for (final peer in ['alice', 'bob']) {
      await store.savePeer(peer, peer == 'alice' ? 'Alice' : 'Bob');
      await store.saveMessage(
        ChatMessage(
          id: '$peer-message',
          peerId: peer,
          text: '$peer private history',
          timestamp: 1,
          outgoing: false,
          status: 'received',
        ),
      );
    }
  }

  testWidgets('Cold tap waits for PIN; correct history opens after unlock', (
    tester,
  ) async {
    final store = DemoStore();
    await seed(store);
    final platform = MemoryNotificationPlatform()..launchPeer = 'bob';
    final c = ChatController(
      DemoTransport(),
      store,
      isDemo: true,
      notifications: ChatNotifications(platform, isDemo: true),
    );
    final lock = testLock();
    await lock.initialize();
    await lock.enable('123456');
    lock.lock();
    addTearDown(c.dispose);
    addTearDown(lock.dispose);
    await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
    await tester.pumpAndSettle();
    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.text('bob private history'), findsNothing);
    expect(c.notifications.pendingPeer, 'bob');
    await tester.enterText(find.widgetWithText(TextField, 'App PIN'), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('bob private history'), findsOneWidget);
    expect(find.text('alice private history'), findsNothing);
    expect(c.notifications.pendingPeer, null);
    expect(c.conversations.singleWhere((p) => p.id == 'bob').unreadCount, 0);
    expect(c.conversations.singleWhere((p) => p.id == 'alice').unreadCount, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets(
    'Warm taps replace routes; latest target wins and back returns to Chats',
    (tester) async {
      final store = DemoStore();
      await seed(store);
      final platform = MemoryNotificationPlatform();
      final c = ChatController(
        DemoTransport(),
        store,
        isDemo: true,
        notifications: ChatNotifications(platform, isDemo: true),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      platform.tapEvents.add('alice');
      platform.tapEvents.add('bob');
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('bob private history'), findsOneWidget);
      expect(find.text('alice private history'), findsNothing);
      platform.tapEvents.add('alice');
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('alice private history'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );

  testWidgets('Lock during history load retains tap without exposing content', (
    tester,
  ) async {
    final store = GatedHistoryStore();
    await seed(store);
    final platform = MemoryNotificationPlatform();
    final c = ChatController(
      DemoTransport(),
      store,
      isDemo: true,
      notifications: ChatNotifications(platform, isDemo: true),
    );
    final lock = testLock();
    await lock.initialize();
    await lock.enable('123456');
    addTearDown(c.dispose);
    addTearDown(lock.dispose);
    await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'App PIN'), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    store.gate = Completer<void>();
    platform.tapEvents.add('bob');
    await tester.pump();
    await tester.pump();
    lock.lock();
    await tester.pumpAndSettle();
    store.gate!.complete();
    store.gate = null;
    await tester.pumpAndSettle();
    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.text('bob private history'), findsNothing);
    expect(c.selectedPeer, null);
    expect(c.notifications.pendingPeer, 'bob');
    await tester.enterText(find.widgetWithText(TextField, 'App PIN'), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('bob private history'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets(
    'Stale tap gives a safe notice and does not recreate deleted history',
    (tester) async {
      final platform = MemoryNotificationPlatform()..launchPeer = 'deleted';
      final c = ChatController(
        DemoTransport(),
        DemoStore(),
        isDemo: true,
        notifications: ChatNotifications(platform, isDemo: true),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(
        find.text('This conversation is no longer available.'),
        findsOneWidget,
      );
      expect(c.notifications.pendingPeer, null);
      expect(c.conversations, isEmpty);
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'Settings exposes opt-in notification and preview switches in demo',
    (tester) async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Message notifications'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Message notifications'));
      await tester.pumpAndSettle();
      expect(c.notifications.enabled, true);
      expect(c.notifications.previews, false);
      await tester.ensureVisible(find.text('Show message previews'));
      await tester.tap(find.text('Show message previews'));
      await tester.pumpAndSettle();
      expect(c.notifications.previews, true);
      expect(tester.takeException(), null);
    },
  );
}
