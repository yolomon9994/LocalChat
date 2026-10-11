import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'draft_controller_test.dart' show ControlledDraftStore;
import 'lock_test_support.dart';

final composer = find.byKey(const ValueKey('message-composer'));
String composerText(WidgetTester tester) =>
    tester.widget<TextField>(composer).controller!.text;

void main() {
  testWidgets(
    'Offline drafts restore per chat through navigation, locking and history deletion',
    (tester) async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await store.savePeer('alice', 'Alice');
      await store.savePeer('bob', 'Bob');
      c.conversations = await store.conversations();
      final lock = testLock();
      addTearDown(lock.dispose);
      await lock.initialize();
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).enabled, isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Send',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(composer, '  Alice draft سلام 👋\nline two  ');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-bob')));
      await tester.pumpAndSettle();
      expect(composerText(tester), '');
      await tester.enterText(composer, 'Bob draft');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      expect(composerText(tester), '  Alice draft سلام 👋\nline two  ');
      lock.lock();
      await tester.pumpAndSettle();
      expect(composer, findsNothing);
      expect(find.textContaining('Alice draft'), findsNothing);
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      expect(composerText(tester), '  Alice draft سلام 👋\nline two  ');
      await c.clearHistory();
      await tester.pumpAndSettle();
      expect(composerText(tester), '');
      expect(await store.draft('alice'), '');
      expect(await store.draft('bob'), '');
      expect(tester.widget<TextField>(composer).enabled, isFalse);
      expect(c.selectedPeer, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Draft loading and save failures offer retry and preserve edits on a small phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = ControlledDraftStore();
      await store.savePeer('alice', 'Alice');
      await store.saveDraft('alice', 'Stored draft');
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await c.viewHistory(const Conversation('alice', 'Alice', 0));
      store.failRead = true;
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
      expect(tester.widget<TextField>(composer).enabled, isFalse);
      expect(
        find.text('Could not load this draft. Please retry.'),
        findsOneWidget,
      );
      store.failRead = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(composerText(tester), 'Stored draft');
      store.failWrite = true;
      await tester.enterText(composer, 'Unwritten\nسلام 👋');
      await tester.pumpAndSettle();
      expect(
        find.text('Draft not saved on this device. Please retry.'),
        findsOneWidget,
      );
      expect(composerText(tester), 'Unwritten\nسلام 👋');
      expect(await store.draft('alice'), 'Stored draft');
      store.failWrite = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(await store.draft('alice'), 'Unwritten\nسلام 👋');
      expect(
        find.text('Draft not saved on this device. Please retry.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A pending send clears its draft even when the chat route is closed',
    (tester) async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nearby-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go nearby'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Ava (Demo)'), 100);
      await tester.ensureVisible(find.text('Ava (Demo)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ava (Demo)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Codes match'));
      await tester.pumpAndSettle();
      final peer = c.selectedPeer!;
      await tester.enterText(composer, 'Send after leaving');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(
        c.messages.any((m) => m.outgoing && m.text == 'Send after leaving'),
        isTrue,
      );
      expect(c.drafts.textFor(peer), '');
      expect(await store.draft(peer), '');
      await tester.tap(find.byKey(const ValueKey('chats-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('conversation-$peer')));
      await tester.pumpAndSettle();
      expect(composerText(tester), '');
      expect(tester.takeException(), isNull);
    },
  );
}
