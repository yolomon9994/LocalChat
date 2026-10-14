import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/message_reply.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/text_message_actions.dart';
import 'package:local_chat/features/message_reply_card.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/demo/demo_transport.dart';

import 'group_draft_test.dart' show emptyGroup;
import 'group_search_test.dart' show searchText;
import 'lock_test_support.dart';
import 'message_reply_test.dart' show ReplyStore;
import 'group_test_support.dart';

void main() {
  late ReplyStore store;
  late ChatController c;
  late ChatMessage incoming, outgoing;
  late GroupHistory group;
  setUp(() async {
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.contextMenu,
            (_) async => null,
          );
      await BrowserContextMenu.disableContextMenu();
    }
    store = ReplyStore();
    c = ChatController(DemoTransport(), store, isDemo: true);
    await c.initialize();
    await store.savePeer('alice', 'Alice');
    incoming = ChatMessage(
      id: 'a' * 24,
      peerId: 'alice',
      text: 'Older سلام 👋',
      timestamp: 1,
      outgoing: false,
      status: 'received',
    );
    outgoing = ChatMessage(
      id: incoming.id,
      peerId: 'alice',
      text: 'Same ID from me',
      timestamp: 2,
      outgoing: true,
      status: 'delivered',
    );
    await store.saveMessage(incoming);
    await store.saveMessage(outgoing);
    c.conversations = await store.conversations();
    c.messages = await store.messages('alice');
    c.selectedPeer = 'alice';
    c.selectedName = 'Alice';
    await c.drafts.load('alice');
    group = (await emptyGroup(store)).copy(
      pinned: true,
      archived: true,
      messages: [
        searchText('a' * 24, 'Bob old message', 1, author: 'b' * 64),
        searchText(
          'a' * 24,
          'Own group message with same ID',
          2,
          author: c.groups.selfId,
        ),
      ],
    );
    for (final m in group.messages) {
      m.envelope['targets'] = [c.groups.selfId!, 'b' * 64];
    }
    await store.saveGroupHistory(group);
    await c.groups.refreshHistory();
    await c.drafts.load(group.id, group: true);
  });
  tearDown(() {
    c.dispose();
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    }
  });

  Future<void> settleUi(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDirect(WidgetTester tester) async {
    await tester.pumpWidget(LocalChatApp(controller: c));
    await settleUi(tester);
    await tester.tap(find.byKey(const ValueKey('conversation-alice')));
    await settleUi(tester);
  }

  Finder directBubble(ChatMessage m) => find.descendant(
    of: find.byKey(ValueKey((m.peerId, m.id, m.outgoing))),
    matching: find.byType(TextMessageActions),
  );
  Finder groupBubble(GroupText m) => find.descendant(
    of: find.byKey(ValueKey(('group-message', group.id, m.key))),
    matching: find.byType(TextMessageActions),
  );
  Future<void> replyMenu(WidgetTester tester, Finder bubble) async {
    await tester.longPressAt(tester.getTopLeft(bubble) + const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await settleUi(tester);
  }

  testWidgets(
    'direct Reply previews, queues a quote, and jumps to the exact older direction',
    (tester) async {
      await openDirect(tester);
      await replyMenu(tester, directBubble(incoming));
      expect(
        find.byKey(const ValueKey('reply-composer-preview')),
        findsOneWidget,
      );
      expect(c.drafts.replyFor('alice')!.outgoing, isFalse);
      final composer = find.byKey(const ValueKey('message-composer'));
      await tester.enterText(composer, 'My answer');
      await settleUi(tester);
      await tester.tap(find.byTooltip('Queue message'));
      await settleUi(tester);
      expect(c.messages.last.reply!.text, incoming.text);
      expect(
        find.byKey(const ValueKey('reply-composer-preview')),
        findsNothing,
      );
      await tester.enterText(composer, 'New draft stays');
      await settleUi(tester);
      final sent = c.messages.last;
      await tester.tap(
        find.byKey(ValueKey(('message-quote', 'alice', sent.id, true))),
      );
      await settleUi(tester);
      expect(find.text('Original message'), findsOneWidget);
      final target = find.byKey(ValueKey(('alice', incoming.id, false)));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('search-message-history')))
            .overlaps(tester.getRect(target)),
        isTrue,
      );
      expect(c.drafts.textFor('alice'), 'New draft stays');
      await tester.tap(find.byTooltip('Jump to latest'));
      await settleUi(tester);
      expect(find.text('Original message'), findsNothing);
      expect(find.text('My answer'), findsOneWidget);
    },
  );

  testWidgets(
    'cancel and navigation keep answer text and independent reply drafts',
    (tester) async {
      await openDirect(tester);
      final composer = find.byKey(const ValueKey('message-composer'));
      await tester.enterText(composer, 'Keep this answer');
      await settleUi(tester);
      await replyMenu(tester, directBubble(outgoing));
      expect(c.drafts.textFor('alice'), 'Keep this answer');
      await tester.pageBack();
      await settleUi(tester);
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await settleUi(tester);
      expect(
        find.byKey(const ValueKey('reply-composer-preview')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Keep this answer',
      );
      await tester.tap(find.byTooltip('Cancel reply'));
      await settleUi(tester);
      expect(c.drafts.replyFor('alice'), isNull);
      expect(await tester.runAsync(() => store.draftReply('alice')), isNull);
      expect(c.drafts.textFor('alice'), 'Keep this answer');
    },
  );

  testWidgets(
    'text-selection toolbar offers Reply while retaining Copy actions',
    (tester) async {
      await openDirect(tester);
      final text = find.descendant(
        of: directBubble(incoming),
        matching: find.byType(SelectableText),
      );
      await tester.longPress(text);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy message'), findsOneWidget);
      expect(find.text('Copy selection'), findsOneWidget);
      await tester.tap(find.text('Reply'));
      await settleUi(tester);
      expect(c.drafts.replyFor('alice')!.id, incoming.id);
      expect(
        find.byKey(const ValueKey('reply-composer-preview')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'archived saved group reply preview anchors author keys and keeps text and organization',
    (tester) async {
      final original = group.messages.first;
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(
            controller: c,
            id: group.id,
            focusMessageKey: original.key,
            searchQuery: 'old',
          ),
        ),
      );
      await settleUi(tester);
      final composer = find.byKey(const ValueKey('group-message-composer'));
      await tester.enterText(composer, 'Group draft');
      await settleUi(tester);
      await replyMenu(tester, groupBubble(original));
      final preview = find.byKey(
        const ValueKey('group-reply-composer-preview'),
      );
      expect(preview, findsOneWidget);
      expect(c.drafts.replyFor(group.id, group: true)!.author, original.author);
      await tester.tap(preview);
      await settleUi(tester);
      expect(find.text('Original message'), findsOneWidget);
      expect(c.drafts.textFor(group.id, group: true), 'Group draft');
      expect(
        c.groups.histories.single.pinned && c.groups.histories.single.archived,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Send group message',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Cancel reply'));
      await settleUi(tester);
      expect(c.drafts.replyFor(group.id, group: true), isNull);
      expect(c.drafts.textFor(group.id, group: true), 'Group draft');
    },
  );

  testWidgets(
    'group quote taps jump to the quoted author rather than a colliding ID',
    (tester) async {
      final original = group.messages.first;
      final reference = MessageReply(
        id: original.id,
        author: original.author,
        name: original.name,
        text: original.text,
      );
      final answer = searchText('c' * 24, 'Answer', 3, author: c.groups.selfId);
      answer.envelope['reply'] = reference.toJson();
      answer.envelope['targets'] = [c.groups.selfId!, original.author];
      await store.saveGroupHistory(
        group.copy(messages: [...group.messages, answer]),
      );
      await tester.runAsync(c.groups.refreshHistory);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(
            controller: c,
            id: group.id,
            focusMessageKey: answer.key,
          ),
        ),
      );
      await settleUi(tester);
      await tester.tap(
        find.byKey(ValueKey(('group-quote', group.id, answer.key))),
      );
      await settleUi(tester);
      final target = find.byKey(
        ValueKey(('group-message', group.id, original.key)),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('group-search-message-history')))
            .overlaps(tester.getRect(target)),
        isTrue,
      );
      expect(find.text('Original message'), findsOneWidget);
    },
  );

  testWidgets(
    'live group Reply sends the signed quote and atomically clears its composer draft',
    (tester) async {
      final net = GroupNetwork();
      late String room;
      await tester.runAsync(() async {
        c.dispose();
        c = ChatController(
          DemoTransport(),
          store,
          groupTransport: FakeGroupTransport(net),
        );
        await c.initialize();
        net.controllers.add(c.groups);
        await c.groups.host('Live reply room');
        room = c.groups.active!.id;
        final guest = await net.phone('Guest');
        await net.join(guest);
        await guest.sendText('Original from guest');
        await net.settle();
      });
      try {
        final original = c.groups.active!.messages.single;
        await tester.pumpWidget(
          MaterialApp(
            home: GroupChatScreen(
              controller: c,
              id: room,
              focusMessageKey: original.key,
            ),
          ),
        );
        await settleUi(tester);
        final bubble = find.descendant(
          of: find.byKey(ValueKey(('group-message', room, original.key))),
          matching: find.byType(TextMessageActions),
        );
        await replyMenu(tester, bubble);
        final composer = find.byKey(const ValueKey('group-message-composer'));
        await tester.enterText(composer, 'Answer from host');
        await settleUi(tester);
        await tester.tap(find.byTooltip('Send group message'));
        final guest = net.controllers.firstWhere((p) => p != c.groups);
        // The UI owns fake-clock draft/visibility work while crypto and peer
        // queues progress in real time. Awaiting net.idle without pumping can
        // deadlock the fixture; drive both clocks until delivery completes.
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          if (guest.active!.messages.length == 2 &&
              c.groups.active!.messages.last.receipts.values.every(
                (s) => s == 'received',
              )) {
            break;
          }
        }
        await settleUi(tester);
        expect(guest.active!.messages.last.reply!.id, original.id);
        expect(guest.active!.messages.last.reply!.author, original.author);
        expect(guest.active!.messages.last.text, 'Answer from host');
        expect(c.drafts.replyFor(room, group: true), isNull);
        expect(c.drafts.textFor(room, group: true), '');
        expect(
          find.byKey(const ValueKey('group-reply-composer-preview')),
          findsNothing,
        );
      } finally {
        await tester.runAsync(() async {
          await c.groups.stop();
          net.controllers.remove(c.groups);
          await net.close();
        });
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  for (final missing in [true, false]) {
    testWidgets(
      '${missing ? 'missing original' : 'conflicting original text'} retains quote and reports unavailable',
      (tester) async {
        final reference = MessageReply(
          id: missing ? 'missing' : incoming.id,
          outgoing: false,
          name: 'Alice',
          text: 'Quoted content not saved here',
        );
        final answer = ChatMessage(
          id: 'c' * 24,
          peerId: 'alice',
          text: 'Answer',
          timestamp: 3,
          outgoing: true,
          status: 'delivered',
          reply: reference,
        );
        await store.saveMessage(answer);
        c.messages = await store.messages('alice');
        await openDirect(tester);
        await tester.tap(
          find.byKey(ValueKey(('message-quote', 'alice', answer.id, true))),
        );
        await settleUi(tester);
        expect(find.text('Original message unavailable.'), findsOneWidget);
        expect(c.messages.last.reply, reference);
        expect(find.text('Original message'), findsNothing);
      },
    );
  }

  testWidgets(
    'PIN removes reply menus and callbacks cannot choose a quote after unlock',
    (tester) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await settleUi(tester);
      await tester.runAsync(() => lock.enable('123456'));
      await settleUi(tester);
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await settleUi(tester);
      await tester.longPressAt(
        tester.getTopLeft(directBubble(incoming)) + const Offset(5, 5),
      );
      await tester.pumpAndSettle();
      final callback = tester
          .widget<SimpleDialogOption>(
            find.ancestor(
              of: find.text('Reply'),
              matching: find.byType(SimpleDialogOption),
            ),
          )
          .onPressed!;
      lock.lock();
      await settleUi(tester);
      expect(find.text('LocalChat locked'), findsOneWidget);
      expect(find.text('Reply'), findsNothing);
      await tester.runAsync(() => lock.unlockPin('123456'));
      await settleUi(tester);
      callback();
      await settleUi(tester);
      expect(c.drafts.replyFor('alice'), isNull);
    },
  );

  testWidgets(
    'small-screen enlarged group reply preview and cancel stay usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = group.messages.first;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: GroupChatScreen(
            controller: c,
            id: group.id,
            focusMessageKey: original.key,
          ),
        ),
      );
      await settleUi(tester);
      await replyMenu(tester, groupBubble(original));
      expect(find.byTooltip('Cancel reply'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel reply'));
      await settleUi(tester);
      expect(
        find.byKey(const ValueKey('group-reply-composer-preview')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final isGroup in [false, true]) {
    testWidgets(
      'background hides ${isGroup ? 'group' : 'direct'} preview and rejects an obsolete cancel callback',
      (tester) async {
        if (isGroup) {
          await tester.runAsync(
            () => c.groups.replyTo(group.id, group.messages.first),
          );
          c.drafts.setText(group.id, 'Answer kept', group: true);
          await tester.pumpWidget(
            MaterialApp(
              home: GroupChatScreen(controller: c, id: group.id),
            ),
          );
        } else {
          await tester.runAsync(() => c.replyTo(incoming));
          c.drafts.setText('alice', 'Answer kept');
          await openDirect(tester);
        }
        await settleUi(tester);
        final preview = find.byKey(
          ValueKey(
            isGroup ? 'group-reply-composer-preview' : 'reply-composer-preview',
          ),
        );
        final oldCancel = tester.widget<MessageReplyCard>(preview).onCancel!;
        c.setAppForeground(false);
        await settleUi(tester);
        expect(preview, findsNothing);
        c.setAppForeground(true);
        await settleUi(tester);
        oldCancel();
        await settleUi(tester);
        expect(
          c.drafts.replyFor(isGroup ? group.id : 'alice', group: isGroup),
          isNotNull,
        );
        await tester.tap(find.byTooltip('Cancel reply'));
        await settleUi(tester);
        expect(
          c.drafts.replyFor(isGroup ? group.id : 'alice', group: isGroup),
          isNull,
        );
        expect(
          c.drafts.textFor(isGroup ? group.id : 'alice', group: isGroup),
          'Answer kept',
        );
      },
    );
  }
}
