import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/archived_chats_screen.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/features/group_file_bubble.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'group_draft_test.dart' show emptyGroup;
import 'group_management_test.dart' show GroupManagementStore;
import 'group_test_support.dart';
import 'lock_test_support.dart';

Future<void> groupOption(WidgetTester tester, String id, String label) async {
  final menu = find.byKey(ValueKey('group-menu-$id'));
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
      180,
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
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late GroupManagementStore store;
  late ChatController c;
  late GroupHistory first, second;
  setUp(() async {
    store = GroupManagementStore();
    c = ChatController(
      DemoTransport(),
      store,
      isDemo: true,
      groupTransport: FakeGroupTransport(GroupNetwork()),
    );
    await c.initialize();
    first = (await emptyGroup(store)).copy(updated: 5);
    second = (await emptyGroup(store)).copy(updated: 10);
    final public = first.host;
    final file = await GroupText.create(
      store.identity,
      store.name,
      group: first.id,
      host: public,
      epoch: randomId(),
      view: 1,
      text: 'File',
      targets: [await identityId(public)],
      fileBytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'report.txt',
    );
    final text = await GroupText.create(
      store.identity,
      store.name,
      group: first.id,
      host: public,
      epoch: randomId(),
      view: 1,
      text: 'Unseen text',
      targets: [await identityId(public)],
    );
    first = first.copy(
      messages: [file.copy(read: false), text.copy(read: false)],
    );
    await store.saveGroupHistory(first);
    await store.saveGroupHistory(second);
    await c.drafts.load(first.id, group: true);
    c.drafts.setText(first.id, 'Group draft', group: true);
    await c.drafts.settled;
    await store.savePeer('friend', 'Friend');
    await store.saveMessage(
      ChatMessage(
        id: 'message',
        peerId: 'friend',
        text: 'Unread direct text',
        timestamp: 7,
        outgoing: false,
        status: 'received',
      ),
    );
    await store.setArchived('friend', true);
    c.conversations = await store.conversations();
    await c.groups.refreshHistory();
  });
  tearDown(() => c.dispose());

  testWidgets(
    'open group menus survive activity reordering and keep their target',
    (tester) async {
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      final menu = find.byKey(ValueKey('group-menu-${first.id}'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await store.saveGroupHistory(first.copy(updated: 30));
        c.groups.refreshHistory();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text('Pin group'), findsOneWidget);
      await tester.tap(find.text('Pin group'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(c.groups.histories.first.id, first.id);
      expect(c.groups.histories.first.pinned, isTrue);
      expect(
        c.groups.histories.firstWhere((g) => g.id == second.id).pinned,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pin, archive and unarchive groups with combined counts and preserved files/drafts',
    (tester) async {
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await groupOption(tester, first.id, 'Pin group');
      expect(c.groups.histories.first.id, first.id);
      expect(c.groups.histories.first.pinned, isTrue);
      await groupOption(tester, first.id, 'Archive group');
      expect(find.byKey(ValueKey('group-${first.id}')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-archived-chats')),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('chats-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('2 chats · 3 unread messages'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-archived-chats')),
      );
      await tester.tap(find.byKey(const ValueKey('open-archived-chats')));
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedChatsScreen), findsOneWidget);
      final row = find.byKey(ValueKey('group-${first.id}'));
      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(GroupChatScreen), findsOneWidget);
      expect(find.byType(GroupFileBubble), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('group-message-composer')),
            )
            .controller!
            .text,
        'Group draft',
      );
      await groupOption(tester, first.id, 'Unarchive group');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('group-${first.id}')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(c.groups.histories.first.pinned, isTrue);
      expect(await store.groupDraft(first.id), 'Group draft');
      expect(c.groups.histories.first.messages.first.fileBytes, [1, 2, 3]);
      await groupOption(tester, first.id, 'Unpin group');
      expect(c.groups.histories.first.id, second.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'group hub hides archived saved rows and links to the shared archive screen',
    (tester) async {
      await tester.runAsync(() async {
        await c.groups.setArchived(first.id, true);
      });
      await tester.pumpWidget(MaterialApp(home: GroupHubScreen(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('group-${first.id}')), findsNothing);
      final open = find.byKey(const ValueKey('open-archived-groups'));
      await tester.scrollUntilVisible(
        open,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedChatsScreen), findsOneWidget);
      expect(find.byKey(ValueKey('group-${first.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('group-${second.id}')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'PIN removes group archive menus, rejects late actions and opens archived notification history',
    (tester) async {
      await tester.runAsync(() => c.groups.setArchived(first.id, true));
      final lock = testLock();
      addTearDown(lock.dispose);
      await lock.initialize();
      await lock.enable('123456');
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await tester.runAsync(() => lock.unlockPin('123456'));
      await tester.pumpAndSettle();
      final archive = find.byKey(const ValueKey('open-archived-chats'));
      await tester.scrollUntilVisible(
        archive,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('chats-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(archive);
      await tester.tap(archive);
      await tester.pumpAndSettle();
      final menu = find.byKey(ValueKey('group-menu-${first.id}'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final lateAction = tester
          .widget<PopupMenuButton<String>>(menu)
          .onSelected!;
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(ArchivedChatsScreen), findsNothing);
      expect(find.text('Pin group'), findsNothing);
      final platform = c.notifications.platform as MemoryNotificationPlatform;
      await tester.runAsync(() async {
        platform.tapEvents.add('group:${first.id}');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await lock.unlockPin('123456');
      });
      await tester.pumpAndSettle();
      lateAction('pin');
      await tester.pumpAndSettle();
      expect(find.byType(GroupChatScreen), findsOneWidget);
      expect(
        c.groups.histories.firstWhere((g) => g.id == first.id).archived,
        isTrue,
      );
      expect(
        c.groups.histories.firstWhere((g) => g.id == first.id).pinned,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('group-message-composer')),
            )
            .controller!
            .text,
        'Group draft',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'long group titles, large text and failed updates stay usable on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await store.saveGroupHistory(
          GroupHistory(
            id: first.id,
            title:
                'A long group title that should wrap without hiding its controls',
            host: first.host,
            messages: first.messages,
            updated: first.updated,
          ),
        );
        await c.groups.refreshHistory();
      });
      store.failPin = true;
      store.failArchive = true;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: HomeScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await groupOption(tester, first.id, 'Pin group');
      expect(
        find.text('Could not update this group. Please try again.'),
        findsOneWidget,
      );
      expect(
        c.groups.histories.firstWhere((g) => g.id == first.id).pinned,
        isFalse,
      );
      await groupOption(tester, first.id, 'Archive group');
      expect(
        c.groups.histories.firstWhere((g) => g.id == first.id).archived,
        isFalse,
      );
      expect(await store.groupDraft(first.id), 'Group draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
