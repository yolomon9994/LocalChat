import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/chat_search_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';

import 'lock_test_support.dart';

void main() {
  test('Snippets show matches near the end and preserve Unicode text', () {
    final text = '${'👋' * 50}Before\n NEEDLE سلام ${'tail ' * 30}';
    final snippet = searchSnippet(text, 'needle');
    expect(snippet, contains('NEEDLE سلام'));
    expect(snippet, isNot(contains('\n')));
    expect(snippet, isNot(contains('\ufffd')));
    expect(snippet.startsWith('…'), isTrue);
    expect(snippet.endsWith('…'), isTrue);
  });

  testWidgets(
    'Search names, jump to an older message by direction, and return to latest',
    (tester) async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await store.savePeer('alice', 'Alice');
      for (var i = 0; i < 180; i++) {
        await store.saveMessage(
          ChatMessage(
            id: 'm-$i',
            peerId: 'alice',
            text: i == 2
                ? 'An older needle message'
                : 'Message $i ${'variable height\n' * (i % 5)}',
            timestamp: 1000 + i,
            outgoing: false,
            status: 'received',
          ),
        );
      }
      await store.saveMessage(
        const ChatMessage(
          id: 'm-2',
          peerId: 'alice',
          text: 'Different direction needle',
          timestamp: 2000,
          outgoing: true,
          status: 'delivered',
        ),
      );
      c.conversations = await store.conversations();
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('chat-search-field'));
      await tester.enterText(field, 'ALICE');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('search-conversation-alice')),
        findsOneWidget,
      );
      expect(c.conversations.single.unreadCount, 180);
      await tester.tap(find.byKey(const ValueKey('search-conversation-alice')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Search result'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'ALICE');
      await tester.tap(find.byKey(const ValueKey('clear-chat-search')));
      await tester.pumpAndSettle();
      await tester.enterText(field, 'needle');
      await tester.pumpAndSettle();
      final hit = find.byKey(
        const ValueKey(('search-message', 'alice', 'm-2', false)),
      );
      await tester.ensureVisible(hit);
      await tester.pumpAndSettle();
      await tester.tap(hit);
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey(('alice', 'm-2', false)));
      expect(target, findsOneWidget);
      expect(find.text('Search result'), findsOneWidget);
      final history = find.byKey(const ValueKey('search-message-history'));
      expect(tester.getRect(history).overlaps(tester.getRect(target)), isTrue);
      // Both older and newer history remain reachable around the anchored result.
      await tester.drag(history, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.text('Message 0 '), findsOneWidget);
      await tester.tap(find.byTooltip('Jump to latest'));
      await tester.pumpAndSettle();
      expect(find.text('Different direction needle'), findsOneWidget);
      expect(find.text('Search result'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'needle');
      await tester.tap(hit);
      await tester.pumpAndSettle();
      await c.clearHistory();
      await tester.pumpAndSettle();
      expect(
        find.text('The matching message is no longer in this chat.'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No results for “needle”.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Locking removes search query and private results; unlocking starts fresh',
    (tester) async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await store.savePeer('private', 'Private friend');
      await store.saveMessage(
        const ChatMessage(
          id: 'private-message',
          peerId: 'private',
          text: 'Secret message text',
          timestamp: 1,
          outgoing: false,
          status: 'received',
        ),
      );
      c.conversations = await store.conversations();
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'secret',
      );
      await tester.pumpAndSettle();
      expect(find.text('Secret message text'), findsOneWidget);
      expect(c.conversations.single.unreadCount, 1);
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(ChatSearchScreen), findsNothing);
      expect(find.text('Secret message text'), findsNothing);
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      expect(c.conversations.single.unreadCount, 1);
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-search-field')))
            .controller!
            .text,
        '',
      );
      expect(find.text('Secret message text'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Search remains usable with large text, long queries and a phone keyboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.5),
              viewInsets: EdgeInsets.only(bottom: 160),
            ),
            child: ChatSearchScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('chat-search-field'));
      await tester.enterText(field, 'x' * 200);
      await tester.pumpAndSettle();
      expect(find.textContaining('No results'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('clear-chat-search')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '');
      expect(tester.takeException(), isNull);
      await tester.enterText(field, '   ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-chat-search')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '');
    },
  );
}
