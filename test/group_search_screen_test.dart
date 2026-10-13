import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_search_screen.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'group_draft_test.dart' show emptyGroup;
import 'group_search_test.dart' show searchText;
import 'lock_test_support.dart';

Future<void> settleGroups(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'highlighting preserves literal regex characters, Unicode and selectable text',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                HighlightedSearchText('👋 %_[] سلام %_[]', '%_[]'),
                HighlightedSearchText(
                  'Older NEEDLE سلام',
                  'needle',
                  selectable: true,
                ),
              ],
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(HighlightedSearchText).first,
          matching: find.byType(Text),
        ),
      );
      final span = text.textSpan! as TextSpan;
      expect(span.toPlainText(), '👋 %_[] سلام %_[]');
      expect(
        span.children!
            .whereType<TextSpan>()
            .where((s) => s.style?.fontWeight == FontWeight.bold)
            .map((s) => s.text),
        ['%_[]', '%_[]'],
      );
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(
        selectable.textSpan!.children!
            .whereType<TextSpan>()
            .singleWhere((s) => s.style?.fontWeight == FontWeight.bold)
            .text,
        'NEEDLE',
      );
      expect(tester.takeException(), isNull);
    },
  );
  late DemoStore store;
  late ChatController c;
  late GroupHistory group;
  setUp(() async {
    store = DemoStore();
    c = ChatController(DemoTransport(), store, isDemo: true);
    await c.initialize();
    group = (await emptyGroup(store)).copy(
      archived: true,
      messages: List.generate(
        180,
        (i) => searchText(
          'm-$i',
          i == 2
              ? 'Older NEEDLE سلام 👋'
              : 'Message $i ${'variable height\n' * (i % 4)}',
          i,
        ),
      ),
    );
    // Same message ID from another author must open its own bubble.
    group = group.copy(
      messages: [
        ...group.messages,
        searchText('m-2', 'Newest needle', 200, author: c.groups.selfId),
      ],
    );
    await store.saveGroupHistory(group);
    await store.saveGroupDraft(group.id, 'Preserved draft');
    await c.groups.refreshHistory();
  });
  tearDown(() => c.dispose());

  testWidgets(
    'global archived group results anchor exact older key and preserve navigation and draft',
    (tester) async {
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('chat-search-field'));
      await tester.enterText(field, 'friends');
      await tester.pumpAndSettle();
      final name = find.byKey(ValueKey('search-group-${group.id}'));
      expect(name, findsOneWidget);
      expect(c.groups.histories.single.unread, 181);
      await tester.enterText(field, 'needle');
      await tester.pumpAndSettle();
      final old = group.messages[2];
      final hit = find.byKey(
        ValueKey(('search-group-message', group.id, old.key)),
      );
      expect(hit, findsOneWidget);
      expect(find.text('Archived group'), findsNWidgets(2));
      await tester.ensureVisible(hit);
      await tester.tap(hit);
      await settleGroups(tester);
      final target = find.byKey(ValueKey(('group-message', group.id, old.key)));
      final history = find.byKey(
        const ValueKey('group-search-message-history'),
      );
      expect(tester.getRect(history).overlaps(tester.getRect(target)), isTrue);
      expect(find.text('Search result'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('group-message-composer')),
            )
            .controller!
            .text,
        'Preserved draft',
      );
      expect(c.groups.histories.single.archived, isTrue);
      expect(c.groups.histories.single.unread, 0);
      await tester.drag(history, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.text('Message 0 '), findsOneWidget);
      await tester.tap(find.byTooltip('Jump to latest'));
      await tester.pumpAndSettle();
      expect(find.text('Newest needle'), findsOneWidget);
      expect(find.text('Search result'), findsNothing);
      await tester.pageBack();
      await settleGroups(tester);
      expect(tester.widget<TextField>(field).controller!.text, 'needle');
      final newestHit = find.byKey(
        ValueKey(('search-group-message', group.id, group.messages.last.key)),
      );
      await tester.ensureVisible(newestHit);
      await tester.tap(newestHit);
      await settleGroups(tester);
      expect(
        find.byKey(
          ValueKey(('group-message', group.id, group.messages.last.key)),
        ),
        findsOneWidget,
      );
      expect(find.text('Search result'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'group toolbar scopes search and covering the chat leaves new messages unread',
    (tester) async {
      await tester.runAsync(() async {
        final other = (await emptyGroup(
          store,
        )).copy(messages: [searchText('other', 'needle in other room', 500)]);
        await store.saveGroupHistory(other);
        await c.groups.refreshHistory();
      });
      final observer = RouteObserver<ModalRoute<dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: GroupChatScreen(
            controller: c,
            id: group.id,
            routeObserver: observer,
          ),
        ),
      );
      await settleGroups(tester);
      await tester.tap(find.byTooltip('Search group messages'));
      await tester.pumpAndSettle();
      expect(find.text('Search group'), findsOneWidget);
      final field = find.byKey(const ValueKey('chat-search-field'));
      await tester.enterText(field, 'needle');
      await tester.pumpAndSettle();
      expect(find.text('needle in other room'), findsNothing);
      expect(find.text('Group messages'), findsOneWidget);
      await tester.runAsync(() async {
        final latest = c.groups.histories.firstWhere((h) => h.id == group.id);
        await store.saveGroupHistory(
          latest.copy(
            messages: [
              ...latest.messages,
              searchText('incoming', 'needle while searching', 1000),
            ],
          ),
        );
        c.groups.refreshHistory();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await settleGroups(tester);
      expect(c.groups.histories.firstWhere((h) => h.id == group.id).unread, 1);
      expect(find.text('needle while searching'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear-chat-search')));
      await tester.pumpAndSettle();
      expect(find.text('Search saved messages in this group.'), findsOneWidget);
      expect(await store.groupDraft(group.id), 'Preserved draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'deleting an open target shows a missing notice and refreshes results',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatSearchScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();
      final hit = find.byKey(
        ValueKey(('search-group-message', group.id, group.messages[2].key)),
      );
      await tester.ensureVisible(hit);
      await tester.tap(hit);
      await settleGroups(tester);
      await tester.runAsync(() async {
        c.groups.delete(group.id);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await settleGroups(tester);
      expect(
        find.text('The matching message is no longer in this group.'),
        findsOneWidget,
      );
      expect(find.text('Search result'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('No results'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'PIN removes group search, stale taps cannot navigate, unlock starts empty',
    (tester) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'needle',
      );
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(
        find.byKey(
          ValueKey(('search-group-message', group.id, group.messages[2].key)),
        ),
      );
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(ChatSearchScreen), findsNothing);
      tile.onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(GroupChatScreen), findsNothing);
      await lock.unlockPin('123456');
      await settleGroups(tester);
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-search-field')))
            .controller!
            .text,
        '',
      );
      expect(c.groups.histories.single.unread, 181);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small screen large text keyboard and background hide group results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
              viewInsets: EdgeInsets.only(bottom: 160),
            ),
            child: ChatSearchScreen(controller: c, groupId: group.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('chat-search-field'));
      await tester.enterText(field, 'needle');
      await tester.pumpAndSettle();
      expect(find.text('Group messages'), findsOneWidget);
      c.setAppForeground(false);
      await tester.pumpAndSettle();
      expect(find.text('Group messages'), findsNothing);
      expect(
        find.text('Return to the unlocked app to search.'),
        findsOneWidget,
      );
      c.setAppForeground(true);
      await settleGroups(tester);
      expect(find.text('Group messages'), findsOneWidget);
      c.setAppAccess(false);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
