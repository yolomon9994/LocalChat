import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/text_message_actions.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';

import 'group_draft_test.dart' show emptyGroup;
import 'group_search_test.dart' show searchText;
import 'lock_test_support.dart';

const incoming = ChatMessage(
  id: 'same-id',
  peerId: 'alice',
  text: '  Incoming سلام 👋\nSecond line  ',
  timestamp: 1,
  outgoing: false,
  status: 'received',
);
const outgoing = ChatMessage(
  id: 'same-id',
  peerId: 'alice',
  text: 'Outgoing full message',
  timestamp: 2,
  outgoing: true,
  status: 'queued',
);

Future<void> openBubbleMenu(WidgetTester tester, Finder bubble) async {
  await tester.longPressAt(tester.getTopLeft(bubble) + const Offset(5, 5));
  await tester.pumpAndSettle();
  expect(find.text('Message actions'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatController c;
  late DemoStore store;
  late GroupHistory group;
  final writes = <String>[];
  Completer<void>? gate;
  bool failCopy = false;

  setUp(() async {
    if (kIsWeb) {
      // Automated widget bindings do not dispatch this engine-only channel.
      // Acknowledge it so Flutter's custom selection toolbar can be exercised.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.contextMenu,
            (_) async => null,
          );
      await BrowserContextMenu.disableContextMenu();
    }
    writes.clear();
    gate = null;
    failCopy = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            writes.add((call.arguments as Map)['text'] as String);
            await gate?.future;
            if (failCopy) {
              throw PlatformException(code: 'Private platform detail');
            }
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': writes.isEmpty ? '' : writes.last};
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': writes.isNotEmpty};
          }
          return null;
        });
    store = DemoStore();
    c = ChatController(DemoTransport(), store, isDemo: true);
    await c.initialize();
    await store.savePeer('alice', 'Alice');
    await store.saveMessage(incoming);
    await store.saveMessage(outgoing);
    await store.saveDraft('alice', 'Untouched direct draft');
    c.conversations = await store.conversations();
    c.selectedPeer = 'alice';
    c.selectedName = 'Alice';
    c.messages = await store.messages('alice');
    await c.drafts.load('alice');
    group = (await emptyGroup(store, id: 'group-copy')).copy(
      pinned: true,
      archived: true,
      messages: [
        searchText('same-id', 'Group NEEDLE سلام 👋\nFull body', 1),
        searchText(
          'same-id',
          'Other author same id',
          2,
          author: c.groups.selfId,
        ),
      ],
    );
    await store.saveGroupHistory(group);
    await store.saveGroupDraft(group.id, 'Untouched group draft');
    await c.groups.refreshHistory();
    await c.drafts.load(group.id, group: true);
  });

  tearDown(() {
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    }
    gate?.complete();
    c.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> direct(WidgetTester tester, {ChatMessage? focus}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: c, focusMessage: focus),
      ),
    );
    await tester.pumpAndSettle();
    // Opening the visible chat queues its normal read-state update. Let it
    // finish before taking a snapshot to isolate the subsequent copy action.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Finder directBubble(ChatMessage m) => find.descendant(
    of: find.byKey(ValueKey((m.peerId, m.id, m.outgoing))),
    matching: find.byType(TextMessageActions),
  );

  for (final message in [incoming, outgoing]) {
    testWidgets(
      'copy exact ${message.outgoing ? 'queued outgoing' : 'incoming'} text offline',
      (tester) async {
        await direct(tester);
        final before = (await tester.runAsync(store.exportBackup))!;
        await openBubbleMenu(tester, directBubble(message));
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(writes, [message.text]);
        expect(find.text('Message copied.'), findsOneWidget);
        expect(find.text('Message actions'), findsNothing);
        expect(
          (await tester.runAsync(store.exportBackup))!.messages,
          before.messages,
        );
        expect(c.drafts.textFor('alice'), 'Untouched direct draft');
        expect(find.text('Cancel queued'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'text selection keeps full-message and selected-text copy actions',
    (tester) async {
      await direct(tester);
      final selectable = find.descendant(
        of: directBubble(outgoing),
        matching: find.byType(SelectableText),
      );
      await tester.longPress(selectable);
      await tester.pumpAndSettle();
      expect(find.text('Copy message'), findsOneWidget);
      expect(find.text('Copy selection'), findsOneWidget);
      final editable = tester.state<EditableTextState>(
        find.descendant(of: selectable, matching: find.byType(EditableText)),
      );
      final selected = editable.textEditingValue.selection.textInside(
        outgoing.text,
      );
      expect(selected, isNotEmpty);
      await tester.tap(find.text('Copy selection'));
      await tester.pumpAndSettle();
      expect(writes, [selected]);
      await tester.longPress(selectable);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy message'));
      await tester.pumpAndSettle();
      expect(writes.last, outgoing.text);
    },
  );

  testWidgets(
    'highlighted saved group uses exact author key and preserves metadata and draft',
    (tester) async {
      final message = group.messages.first;
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(
            controller: c,
            id: group.id,
            focusMessageKey: message.key,
            searchQuery: 'needle',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bubble = find.descendant(
        of: find.byKey(ValueKey(('group-message', group.id, message.key))),
        matching: find.byType(TextMessageActions),
      );
      final selectable = find.descendant(
        of: bubble,
        matching: find.byType(SelectableText),
      );
      expect(
        tester.widget<SelectableText>(selectable).textSpan!.toPlainText(),
        message.text,
      );
      await tester.longPress(selectable);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy message'));
      await tester.pumpAndSettle();
      expect(writes, [message.text]);
      expect(c.drafts.textFor(group.id, group: true), 'Untouched group draft');
      final history = c.groups.histories.single;
      expect(history.pinned && history.archived, isTrue);
      expect(history.messages.length, 2);
      expect(history.messages.first.receipts, isEmpty);
    },
  );

  testWidgets(
    'saved group bubble long-press copies the other colliding author',
    (tester) async {
      final message = group.messages.last;
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(
            controller: c,
            id: group.id,
            focusMessageKey: message.key,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openBubbleMenu(
        tester,
        find.descendant(
          of: find.byKey(ValueKey(('group-message', group.id, message.key))),
          matching: find.byType(TextMessageActions),
        ),
      );
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(writes, [message.text]);
    },
  );

  testWidgets(
    'background invalidates an open menu and its captured callback after return',
    (tester) async {
      await direct(tester);
      await openBubbleMenu(tester, directBubble(incoming));
      final callback = tester
          .widget<SimpleDialogOption>(
            find.ancestor(
              of: find.text('Copy'),
              matching: find.byType(SimpleDialogOption),
            ),
          )
          .onPressed!;
      c.setAppForeground(false);
      await tester.pumpAndSettle();
      expect(find.text('Message actions'), findsNothing);
      c.setAppForeground(true);
      callback();
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await openBubbleMenu(tester, directBubble(incoming));
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(writes, [incoming.text]);
    },
  );

  testWidgets('deletion rejects retained menu actions', (tester) async {
    await direct(tester);
    await openBubbleMenu(tester, directBubble(incoming));
    final callback = tester
        .widget<SimpleDialogOption>(
          find.ancestor(
            of: find.text('Copy'),
            matching: find.byType(SimpleDialogOption),
          ),
        )
        .onPressed!;
    await tester.runAsync(() => c.deleteConversation('alice'));
    await tester.pumpAndSettle();
    callback();
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.text('Message actions'), findsNothing);
  });

  testWidgets(
    'PIN removes clipboard dialog and stale callbacks cannot copy after unlock',
    (tester) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await tester.runAsync(() => lock.enable('123456'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conversation-alice')));
      await tester.pumpAndSettle();
      await openBubbleMenu(tester, directBubble(incoming));
      final callback = tester
          .widget<SimpleDialogOption>(
            find.ancestor(
              of: find.text('Copy'),
              matching: find.byType(SimpleDialogOption),
            ),
          )
          .onPressed!;
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('LocalChat locked'), findsOneWidget);
      expect(find.text('Message actions'), findsNothing);
      await tester.runAsync(() => lock.unlockPin('123456'));
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clipboard failure is generic and can be retried', (
    tester,
  ) async {
    await direct(tester);
    failCopy = true;
    await openBubbleMenu(tester, directBubble(incoming));
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Could not copy. Try again.'), findsOneWidget);
    expect(find.textContaining('Private platform detail'), findsNothing);
    failCopy = false;
    await openBubbleMenu(tester, directBubble(incoming));
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Message copied.'), findsOneWidget);
    expect(writes.length, 2);
  });

  testWidgets(
    'late clipboard completion is not repeated and gives no background confirmation',
    (tester) async {
      await direct(tester);
      gate = Completer<void>();
      await openBubbleMenu(tester, directBubble(incoming));
      final callback = tester
          .widget<SimpleDialogOption>(
            find.ancestor(
              of: find.text('Copy'),
              matching: find.byType(SimpleDialogOption),
            ),
          )
          .onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(writes, [incoming.text]);
      c.setAppForeground(false);
      await tester.pumpAndSettle();
      gate!.complete();
      gate = null;
      await tester.pumpAndSettle();
      c.setAppForeground(true);
      await tester.pumpAndSettle();
      expect(find.text('Message copied.'), findsNothing);
      expect(writes, [incoming.text]);
    },
  );

  testWidgets(
    'copy UI fits small screens at enlarged text and exposes an accessibility action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: ChatScreen(controller: c, focusMessage: incoming),
        ),
      );
      await tester.pumpAndSettle();
      final copySemantics = find.descendant(
        of: directBubble(incoming),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.customSemanticsActions?.keys.any(
                    (a) => a.label == 'Copy message',
                  ) ==
                  true,
        ),
      );
      expect(copySemantics, findsOneWidget);
      await openBubbleMenu(tester, directBubble(incoming));
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(writes, [incoming.text]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'secondary mouse click opens Copy and dismissing it leaves clipboard untouched',
    (tester) async {
      await direct(tester);
      await tester.tapAt(
        tester.getTopLeft(directBubble(incoming)) + const Offset(5, 5),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(find.text('Message actions'), findsNothing);
    },
  );

  testWidgets('file bubbles do not gain text-message copy controls', (
    tester,
  ) async {
    await tester.runAsync(() => c.deleteConversation('alice'));
    await store.savePeer('alice', 'Alice');
    final fileMessage = ChatMessage(
      id: 'file',
      peerId: 'alice',
      text: 'File',
      timestamp: 3,
      outgoing: false,
      status: 'received',
      file: ChatFile('report.txt', 4, 'a' * 64),
    );
    await store.saveMessage(fileMessage);
    c.selectedPeer = 'alice';
    c.messages = [fileMessage];
    await direct(tester);
    expect(find.byType(TextMessageActions), findsNothing);
    expect(find.text('Save to phone'), findsOneWidget);
  });
}
