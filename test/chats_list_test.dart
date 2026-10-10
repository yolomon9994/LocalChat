import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/chats_tab.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';

import 'lock_test_support.dart';

ChatMessage incoming(String id, String peer) => ChatMessage(
  id: id,
  peerId: peer,
  text: 'Incoming $id',
  timestamp: 1,
  outgoing: false,
  status: 'received',
);

void main() {
  test('Activity labels distinguish today, yesterday and older years', () {
    final now = DateTime(2026, 1, 1, 12);
    String label(DateTime time) =>
        formatConversationTime(time.millisecondsSinceEpoch, now: now);
    expect(label(DateTime(2026, 1, 1, 9, 5)), '09:05');
    expect(label(DateTime(2025, 12, 31)), 'Yesterday');
    expect(label(DateTime(2025, 12, 30)), 'Dec 30, 2025');
    expect(label(DateTime(2026, 2, 3)), 'Feb 3');
  });

  testWidgets(
    'Opening, dialogs, backgrounding and locking track actual reading',
    (tester) async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      for (final peer in ['alice', 'bob']) {
        await store.savePeer(peer, peer);
        await store.saveMessage(incoming('first', peer));
      }
      c.conversations = await store.conversations();
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unread-alice')), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-bob')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      expect(
        c.conversations.singleWhere((p) => p.id == 'alice').unreadCount,
        0,
      );
      expect(c.conversations.singleWhere((p) => p.id == 'bob').unreadCount, 1);
      final dialog = showDialog<void>(
        context: tester.element(find.byType(ChatScreen)),
        builder: (_) => const AlertDialog(title: Text('Covering chat')),
      );
      await tester.pumpAndSettle();
      await store.saveMessage(incoming('during-dialog', 'alice'));
      await c.viewHistory(c.conversations.singleWhere((p) => p.id == 'alice'));
      await tester.pumpAndSettle();
      expect(
        c.conversations.singleWhere((p) => p.id == 'alice').unreadCount,
        1,
      );
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await dialog;
      await tester.pumpAndSettle();
      expect(
        c.conversations.singleWhere((p) => p.id == 'alice').unreadCount,
        0,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      await store.saveMessage(incoming('background', 'alice'));
      await c.viewHistory(c.conversations.singleWhere((p) => p.id == 'alice'));
      await tester.pumpAndSettle();
      expect(
        c.conversations.singleWhere((p) => p.id == 'alice').unreadCount,
        1,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        c.conversations.singleWhere((p) => p.id == 'alice').unreadCount,
        0,
      );
      await lock.enable('123456');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      await store.saveMessage(incoming('locked', 'alice'));
      await c.viewHistory(c.conversations.singleWhere((p) => p.id == 'alice'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('Incoming locked'), findsNothing);
      expect(
        c.conversations.singleWhere((p) => p.id == 'alice').unreadCount,
        1,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unread-alice')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unread-alice')), findsNothing);
      expect(find.byKey(const ValueKey('unread-bob')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Long previews, dates and large unread badges fit enlarged phone text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      c.conversations = [
        Conversation(
          'long',
          'A very long friend name that takes more than one line',
          DateTime(2025, 1, 1).millisecondsSinceEpoch,
          unreadCount: 120,
          latestMessage: ChatMessage(
            id: 'long',
            peerId: 'long',
            text: 'Hello\n  سلام 👋 ${'Long preview ' * 40}',
            timestamp: 1,
            outgoing: true,
            status: 'delivered',
          ),
        ),
        const Conversation('empty', 'No history yet', 1),
      ];
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: ChatsTab(
                controller: c,
                onFindDevices: () {},
                onOpenConnected: () {},
                onOpenHistory: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
      expect(find.textContaining('You: Hello سلام 👋'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('120 unread messages')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('No messages yet'), 100);
      await tester.pumpAndSettle();
      expect(find.text('No messages yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
