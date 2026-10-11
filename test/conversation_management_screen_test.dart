import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/archived_chats_screen.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'chats_list_test.dart' show incoming;
import 'conversation_management_test.dart' show FailingManagementStore;
import 'lock_test_support.dart';

Future<void> option(WidgetTester tester, String peer, String label) async {
  final menu = find.byKey(ValueKey('conversation-menu-$peer'));
  if (menu.evaluate().isEmpty) {
    final list = find.byKey(
      PageStorageKey(
        find.byType(ArchivedChatsScreen).evaluate().isNotEmpty
            ? 'archived-chats-list'
            : 'chats-list',
      ),
    );
    await tester.scrollUntilVisible(
      menu,
      100,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Pin, archive, search archived history, unarchive, cancel and confirm deletion',
    (tester) async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      for (final p in ['alice', 'bob']) {
        await store.savePeer(p, p);
        await store.saveMessage(incoming('first', p));
        await store.saveDraft(p, '$p draft');
      }
      c.conversations = await store.conversations();
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await option(tester, 'bob', 'Pin chat');
      expect(c.conversations.first.id, 'bob');
      await option(tester, 'bob', 'Archive chat');
      expect(find.byKey(const ValueKey('conversation-bob')), findsNothing);
      expect(find.text('1 chat · 1 unread message'), findsOneWidget);
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'bob',
      );
      await tester.pumpAndSettle();
      expect(find.text('Archived chat'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-conversation-bob')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('message-composer')))
            .controller!
            .text,
        'bob draft',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-archived-chats')));
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedChatsScreen), findsOneWidget);
      await option(tester, 'bob', 'Unarchive chat');
      expect(find.text('No archived chats'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(c.conversations.first.pinned, isTrue);
      await option(tester, 'bob', 'Unpin chat');
      await option(tester, 'bob', 'Delete chat');
      expect(find.text('Delete chat?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await store.draft('bob'), 'bob draft');
      await option(tester, 'bob', 'Delete chat');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(c.conversations.single.id, 'alice');
      expect(await store.draft('bob'), '');
      expect(await store.draft('alice'), 'alice draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Archive routes and delete confirmations disappear while locked',
    (tester) async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await store.savePeer('alice', 'Alice');
      await store.setArchived('alice', true);
      c.conversations = await store.conversations();
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-archived-chats')));
      await tester.pumpAndSettle();
      await option(tester, 'alice', 'Delete chat');
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedChatsScreen), findsNothing);
      expect(find.text('Delete chat?'), findsNothing);
      expect((await store.conversations()).single.id, 'alice');
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedChatsScreen), findsNothing);
      expect(find.byKey(const ValueKey('open-archived-chats')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Long names, unread badges and failed actions fit large phone text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = FailingManagementStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await store.savePeer('alice', 'A very long name سلام 👋 with more words');
      for (var i = 0; i < 120; i++) {
        await store.saveMessage(incoming('$i', 'alice'));
      }
      c.conversations = await store.conversations();
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await option(tester, 'alice', 'Pin chat');
      expect(c.conversations.single.pinned, isFalse);
      expect(
        find.text('Could not update this chat. Please try again.'),
        findsWidgets,
      );
      // Let the temporary error snackbar leave before using the list again.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await option(tester, 'alice', 'Delete chat');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(c.conversations.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
