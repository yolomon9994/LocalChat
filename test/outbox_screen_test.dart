import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'draft_screen_test.dart' show composer, composerText;
import 'lock_test_support.dart';

void main() {
  testWidgets(
    'Offline queue clears composer, shows counts and supports keeping or cancelling a message',
    (tester) async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await c.store.savePeer('alice', 'Alice');
      c.conversations = await c.store.conversations();
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      await tester.enterText(composer, '  Offline سلام 👋  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Queue message'));
      await tester.pumpAndSettle();
      expect(composerText(tester), '');
      expect(c.messages.single.status, 'queued');
      expect(find.text('Cancel queued'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queued-alice')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel queued'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep message'));
      await tester.pumpAndSettle();
      expect(c.messages.length, 1);
      await tester.tap(find.text('Cancel queued'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel queued message'));
      await tester.pumpAndSettle();
      expect(c.messages, isEmpty);
      expect(c.conversations.single.queuedCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retry requires confirmation, preserves the draft, and its dialog disappears on lock',
    (tester) async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await c.store.savePeer('alice', 'Alice');
      await c.store.saveMessage(
        ChatMessage(
          id: 'a' * 24,
          peerId: 'alice',
          text: 'May already be delivered',
          timestamp: 1,
          outgoing: true,
          status: 'unconfirmed',
        ),
      );
      c.conversations = await c.store.conversations();
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      await tester.enterText(composer, 'A different draft');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry message?'), findsOneWidget);
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('Retry message?'), findsNothing);
      expect((await c.store.messages('alice')).single.status, 'unconfirmed');
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Queue retry'));
      await tester.pumpAndSettle();
      expect(c.messages.single.status, 'queued');
      expect(c.messages.single.id, 'a' * 24);
      expect(composerText(tester), 'A different draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Queued and retry controls fit a small phone with keyboard, long text and storage feedback',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = ChatController(DemoTransport(), DemoStore());
      addTearDown(c.dispose);
      await c.initialize();
      await c.store.savePeer('alice', 'A long nearby name');
      await c.store.saveMessage(
        ChatMessage(
          id: 'a' * 24,
          peerId: 'alice',
          text: 'A long message\nسلام 👋\n${'words ' * 35}',
          timestamp: 1,
          outgoing: true,
          status: 'unconfirmed',
        ),
      );
      await c.viewHistory((await c.store.conversations()).single);
      c.error =
          'Could not save this message. Your draft is kept; please retry.';
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.5),
              viewInsets: EdgeInsets.only(bottom: 160),
            ),
            child: ChatScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(composer, 'Two lines\ndraft');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry message?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
