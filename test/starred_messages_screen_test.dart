import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/starred_message.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/starred_messages_screen.dart';
import 'package:local_chat/features/text_message_actions.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'starred_messages_test.dart';
import 'lock_test_support.dart';
import 'image_test_support.dart';

void main() {
  late StarStore store;
  late ChatController c;
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
    store = StarStore();
    await store.open();
    await store.savePeer('alice', 'Alice');
    await store.saveMessage(starMessage());
    await store.saveMessage(
      starMessage(outgoing: true, text: 'Same ID from me'),
    );
    await store.saveDraft('alice', 'Keep unsent text');
    group = await signedStarGroup(store);
    await store.saveGroupHistory(group);
    await store.saveGroupDraft(group.id, 'Group unsent text');
    c = ChatController(DemoTransport(), store, isDemo: true);
    await c.initialize();
    await c.refreshStars();
  });
  tearDown(() {
    c.dispose();
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    }
  });
  Future<void> settle(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpAndSettle();
  }

  Future<void> decodeVisibleImages(WidgetTester t) async {
    final images = t.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty);
    for (final image in images) {
      final ready = Completer<void>();
      Object? failure;
      late ImageStream stream;
      final listener = ImageStreamListener(
        (info, _) {
          info.dispose();
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object error, StackTrace? stack) {
          failure = error;
          if (!ready.isCompleted) ready.complete();
        },
      );
      await t.runAsync(() async {
        stream = image.image.resolve(ImageConfiguration.empty);
        stream.addListener(listener);
      });
      try {
        // Browser decoding uses real promises; ImageStream frame delivery also
        // needs the widget binding's fake frame clock to advance.
        for (var i = 0; i < 100 && !ready.isCompleted; i++) {
          await t.pump(const Duration(milliseconds: 20));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(
          ready.isCompleted,
          isTrue,
          reason:
              'The visible image must finish decoding before route disposal.',
        );
        expect(failure, isNull);
      } finally {
        stream.removeListener(listener);
      }
    }
    await t.pump();
  }

  Future<void> home(WidgetTester t) async {
    await t.pumpWidget(LocalChatApp(controller: c));
    await settle(t);
  }

  Future<void> direct(WidgetTester t) async {
    await home(t);
    await t.tap(find.byKey(const ValueKey('conversation-alice')));
    await settle(t);
  }

  Finder bubble({bool outgoing = false, String id = 'same'}) => find.descendant(
    of: find.byKey(ValueKey(('alice', id, outgoing))),
    matching: find.byType(TextMessageActions),
  );
  Future<void> menu(WidgetTester t, Finder bubble) async {
    await t.longPressAt(t.getTopLeft(bubble) + const Offset(5, 5));
    await t.pumpAndSettle();
  }

  Future<void> chooseStar(WidgetTester t, Finder bubble) async {
    await menu(t, bubble);
    await t.tap(find.text('Star'));
    await settle(t);
  }

  Future<void> openSaved(WidgetTester t) async {
    await t.tap(find.byTooltip('Starred messages'));
    await settle(t);
  }

  testWidgets(
    'star and unstar direct text then open its exact direction, preserving the draft',
    (t) async {
      await direct(t);
      await chooseStar(t, bubble());
      expect(c.starred, [incomingStar]);
      expect(await store.draft('alice'), 'Keep unsent text');
      await menu(t, bubble());
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Unstar'), findsOneWidget);
      await t.tap(find.text('Unstar'));
      await settle(t);
      expect(c.starred, isEmpty);
      await chooseStar(t, bubble(outgoing: true));
      await t.pageBack();
      await settle(t);
      await openSaved(t);
      expect(find.text('You: Same ID from me'), findsOneWidget);
      await t.tap(find.byKey(ValueKey(('starred', outgoingStar.key))));
      await settle(t);
      final screen = t.widget<ChatScreen>(find.byType(ChatScreen));
      expect(screen.focusMessage!.outgoing, isTrue);
      expect(screen.fromStar, isTrue);
      expect(
        find.byKey(const ValueKey('search-message-history')),
        findsOneWidget,
      );
      expect(await store.draft('alice'), 'Keep unsent text');
    },
  );
  testWidgets(
    'saved list combines archived group and direct stars, unstars without opening history',
    (t) async {
      final groupStar = StarredMessage(
        target: group.id,
        id: group.messages.single.id,
        author: group.messages.single.author,
      );
      await t.runAsync(() => c.setStarred(incomingStar, true));
      await t.runAsync(() => c.setStarred(groupStar, true));
      await home(t);
      await openSaved(t);
      expect(
        find.byKey(ValueKey(('starred', incomingStar.key))),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey(('starred', groupStar.key))), findsOneWidget);
      final unread = (await store.conversations()).single.unreadCount;
      await t.tap(
        find.descendant(
          of: find.byKey(ValueKey(('starred', incomingStar.key))),
          matching: find.byTooltip('Unstar message'),
        ),
      );
      await settle(t);
      expect(c.starred, [groupStar]);
      expect((await store.conversations()).single.unreadCount, unread);
      await t.tap(find.byKey(ValueKey(('starred', groupStar.key))));
      await settle(t);
      final screen = t.widget<GroupChatScreen>(find.byType(GroupChatScreen));
      expect(screen.id, group.id);
      expect(screen.focusMessageKey, group.messages.single.key);
      expect(screen.fromStar, isTrue);
      expect((await store.groupHistories()).single.archived, isTrue);
      expect((await store.groupHistories()).single.pinned, isTrue);
      expect(await store.groupDraft(group.id), 'Group unsent text');
    },
  );
  testWidgets('group bubble star and unstar use author-scoped references', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: GroupChatScreen(controller: c, id: group.id),
      ),
    );
    await settle(t);
    final target = find.descendant(
      of: find.byKey(
        ValueKey(('group-message', group.id, group.messages.single.key)),
      ),
      matching: find.byType(TextMessageActions),
    );
    await chooseStar(t, target);
    expect(c.starred.single.author, group.messages.single.author);
    expect(c.starred.single.target, group.id);
    await menu(t, target);
    await t.tap(find.text('Unstar'));
    await settle(t);
    expect(c.starred, isEmpty);
    expect(await store.groupDraft(group.id), 'Group unsent text');
  });
  testWidgets(
    'file star menu retains attachment controls and saved list opens its original bubble',
    (t) async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = (await t.runAsync(
        () => ChatFile.fromBytes('notes.bin', bytes),
      ))!;
      final message = ChatMessage(
        id: 'file',
        peerId: 'alice',
        text: 'File',
        timestamp: 20,
        outgoing: false,
        status: 'received',
        file: file,
      );
      await t.runAsync(() => store.saveFileMessage(message, bytes));
      await direct(t);
      await menu(t, bubble(id: 'file'));
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      await t.tap(find.text('Star'));
      await settle(t);
      expect(c.starred.single.id, 'file');
      await t.pageBack();
      await settle(t);
      await openSaved(t);
      expect(find.text('Alice: notes.bin'), findsOneWidget);
      await t.tap(find.byKey(ValueKey(('starred', c.starred.single.key))));
      await settle(t);
      expect(
        t.widget<ChatScreen>(find.byType(ChatScreen)).focusMessage!.file!.name,
        'notes.bin',
      );
    },
  );
  testWidgets(
    'stale star menu callback cannot act after foreground loss and return',
    (t) async {
      await direct(t);
      await menu(t, bubble());
      final option = t.widget<SimpleDialogOption>(
        find.ancestor(
          of: find.text('Star'),
          matching: find.byType(SimpleDialogOption),
        ),
      );
      c.setAppForeground(false);
      c.setAppForeground(true);
      option.onPressed!();
      await settle(t);
      expect(await store.starredMessages(), isEmpty);
      expect(find.byType(SimpleDialog), findsNothing);
    },
  );
  testWidgets(
    'saved list hides immediately on background and ignores delayed decrypted history',
    (t) async {
      await t.runAsync(() => c.setStarred(incomingStar, true));
      await home(t);
      store.historyGate = Completer<void>();
      await t.tap(find.byTooltip('Starred messages'));
      await t.pump();
      await t.runAsync(() => store.historyEntered.future);
      c.setAppForeground(false);
      await t.pump();
      expect(find.text('Alice: Saved message'), findsNothing);
      expect(find.textContaining('Return to the unlocked app'), findsOneWidget);
      store.historyGate!.complete();
      await settle(t);
      expect(find.text('Alice: Saved message'), findsNothing);
      store.historyGate = null;
      c.setAppForeground(true);
      await settle(t);
      expect(find.text('Alice: Saved message'), findsOneWidget);
    },
  );
  testWidgets(
    'generic star write and list load errors can retry without losing the draft',
    (t) async {
      await direct(t);
      store.failStarWrite = true;
      await chooseStar(t, bubble());
      expect(
        find.text('Could not update this starred message. Try again.'),
        findsOneWidget,
      );
      expect(c.starred, isEmpty);
      store.failStarWrite = false;
      await chooseStar(t, bubble());
      await t.pageBack();
      await settle(t);
      store.failStars = true;
      await t.runAsync(c.refreshStars);
      await openSaved(t);
      expect(
        find.text('Could not load starred messages. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Private storage'), findsNothing);
      store.failStars = false;
      await t.tap(find.text('Retry'));
      await settle(t);
      expect(find.text('Alice: Saved message'), findsOneWidget);
      expect(await store.draft('alice'), 'Keep unsent text');
    },
  );
  testWidgets(
    'starred list fits a small screen with enlarged text and shows its empty state',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() => c.setStarred(incomingStar, true));
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: StarredMessagesScreen(controller: c),
        ),
      );
      await settle(t);
      expect(t.takeException(), isNull);
      await t.tap(find.byTooltip('Unstar message'));
      await settle(t);
      expect(find.textContaining('No starred messages yet.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'PIN removes Star menus and obsolete callbacks cannot star after unlock',
    (t) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      await t.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await settle(t);
      await t.runAsync(() => lock.enable('123456'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('conversation-alice')));
      await settle(t);
      await menu(t, bubble());
      final callback = t
          .widget<SimpleDialogOption>(
            find.ancestor(
              of: find.text('Star'),
              matching: find.byType(SimpleDialogOption),
            ),
          )
          .onPressed!;
      lock.lock();
      await settle(t);
      expect(find.text('LocalChat locked'), findsOneWidget);
      expect(find.text('Star'), findsNothing);
      await t.runAsync(() => lock.unlockPin('123456'));
      await settle(t);
      callback();
      await settle(t);
      expect(await store.starredMessages(), isEmpty);
    },
  );
  testWidgets(
    'obsolete saved-list callbacks cannot open or unstar after foreground return',
    (t) async {
      await t.runAsync(() => c.setStarred(incomingStar, true));
      await home(t);
      await openSaved(t);
      final row = t.widget<ListTile>(
        find.byKey(ValueKey(('starred', incomingStar.key))),
      );
      final unstar = t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Unstar message',
            ),
          )
          .onPressed!;
      c.setAppForeground(false);
      c.setAppForeground(true);
      row.onTap!();
      unstar();
      await settle(t);
      expect(c.starred, [incomingStar]);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('Alice: Saved message'), findsOneWidget);
    },
  );
  testWidgets(
    'group images can be starred without text actions and open in their saved group',
    (t) async {
      final image = (await t.runAsync(() => testImage(size: 16)))!;
      final photo = (await t.runAsync(
        () => GroupText.create(
          store.identity,
          'Member',
          group: group.id,
          host: group.host,
          epoch: group.messages.single.envelope['epoch'] as String,
          view: 1,
          text: 'Image',
          targets: group.messages.single.targets,
          imageBytes: image,
        ),
      ))!;
      group = group.copy(messages: [photo]);
      await store.saveGroupHistory(group);
      await t.runAsync(c.groups.refreshHistory);
      await t.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(controller: c, id: group.id),
        ),
      );
      await settle(t);
      await decodeVisibleImages(t);
      final target = find.descendant(
        of: find.byKey(ValueKey(('group-message', group.id, photo.key))),
        matching: find.byType(TextMessageActions),
      );
      await menu(t, target);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Reply'), findsNothing);
      await t.tap(find.text('Star'));
      await settle(t);
      final star = c.starred.single;
      expect(star.author, photo.author);
      await t.pumpWidget(
        MaterialApp(home: StarredMessagesScreen(controller: c)),
      );
      await settle(t);
      expect(find.text('You: Image'), findsOneWidget);
      await t.tap(find.byKey(ValueKey(('starred', star.key))));
      await settle(t);
      expect(
        t.widget<GroupChatScreen>(find.byType(GroupChatScreen)).focusMessageKey,
        photo.key,
      );
      await decodeVisibleImages(t);
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
    },
  );
}
