import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_group_transport.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'demo_group_test.dart' show confirmDemo, demoTurn;
import 'lock_test_support.dart';

Future<void> demoUiTurn(WidgetTester tester) async {
  // Cryptographic work and peer queues must progress in real time before a
  // settling loop advances Flutter's fake clock past handshake deadlines.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  late ChatController c;
  bool cleaned = false;
  setUp(() async {
    cleaned = false;
    c = ChatController(
      DemoTransport(),
      DemoStore(),
      isDemo: true,
      groupTransport: DemoGroupTransport(
        replyDelay: const Duration(milliseconds: 20),
      ),
    );
    await c.initialize();
  });
  tearDown(() {
    if (!cleaned) c.dispose();
  });

  testWidgets(
    'browser group hub hosts a labeled demo and requires explicit local code confirmations',
    (tester) async {
      await tester.pumpWidget(LocalChatApp(controller: c));
      await demoUiTurn(tester);
      await tester.tap(find.byTooltip('Group chats'));
      await tester.pumpAndSettle();
      expect(find.text('Group chats (Demo)'), findsOneWidget);
      expect(
        find.textContaining('No other phones or browser tabs'),
        findsOneWidget,
      );
      await tester.tap(find.text('Create demo group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'My browser room',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await demoUiTurn(tester);
      expect(find.byType(GroupChatScreen), findsOneWidget);
      expect(find.text('Demo • My browser room'), findsOneWidget);
      expect(c.groups.members.length, 1);
      expect(
        find.textContaining('Demo verification:'),
        findsAtLeastNWidgets(1),
      );
      // Confirm through the same buttons the browser user sees, one member at a time.
      for (var i = 0; i < 2; i++) {
        final confirm = find.widgetWithText(FilledButton, 'Codes match').first;
        final list = find.byKey(const ValueKey('group-message-history'));
        await tester.scrollUntilVisible(
          confirm,
          200,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
        );
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await demoUiTurn(tester);
      }
      expect(c.groups.members.length, 3);
      final composer = find.byKey(const ValueKey('group-message-composer'));
      await tester.enterText(composer, 'From my browser');
      await tester.tap(find.byTooltip('Send group message'));
      await demoUiTurn(tester);
      final message = c.groups.active!.messages.singleWhere(
        (m) => m.text == 'From my browser',
      );
      expect(message.receipts.values.every((s) => s == 'received'), isTrue);
      expect(tester.widget<TextField>(composer).controller!.text, '');
      c.dispose();
      cleaned = true;
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'find and join demo groups uses the guest verification flow and clear simulation labels',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: GroupHubScreen(controller: c)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Find demo groups'));
        await demoTurn(c.groups);
      });
      await demoUiTurn(tester);
      await tester.ensureVisible(find.text('Weekend plans (Demo)'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Weekend plans (Demo)'));
        await demoTurn(c.groups);
      });
      await demoUiTurn(tester);
      expect(c.groups.active, isNull);
      final button = find.widgetWithText(FilledButton, 'Codes match');
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(button);
        await demoTurn(c.groups);
      });
      await demoUiTurn(tester);
      expect(c.groups.hosting, isFalse);
      expect(
        c.groups.members.length,
        3,
        reason: '${c.groups.state}: ${c.groups.error}',
      );
      expect(find.text('Weekend plans (Demo)'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
      c.dispose();
      cleaned = true;
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'saved browser drafts, archive and search coexist with demo rehosting',
    (tester) async {
      await tester.runAsync(() async {
        await c.groups.host('Saved room');
        await confirmDemo(c.groups);
        await c.groups.sendText('Demo needle');
        await demoTurn(c.groups);
        final id = c.groups.active!.id;
        await c.drafts.load(id, group: true);
        c.drafts.setText(id, 'Draft kept', group: true);
        await c.drafts.settled;
        await c.groups.setArchived(id, true);
        await c.groups.setPinned(id, true);
        await c.groups.stop();
      });
      final group = c.groups.histories.single;
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(controller: c, id: group.id),
        ),
      );
      await demoUiTurn(tester);
      final composer = find.byKey(const ValueKey('group-message-composer'));
      expect(tester.widget<TextField>(composer).controller!.text, 'Draft kept');
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Host this group again'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Search group messages'));
      await demoUiTurn(tester);
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'needle',
      );
      await demoUiTurn(tester);
      expect(find.text('Archived group'), findsOneWidget);
      await tester.pageBack();
      await demoUiTurn(tester);
      await tester.ensureVisible(find.text('Host this group again'));
      await tester.tap(find.text('Host this group again'));
      await demoUiTurn(tester);
      expect(c.groups.active!.id, group.id);
      expect(c.groups.members.length, 1);
      expect(c.groups.active!.archived && c.groups.active!.pinned, isTrue);
      expect(tester.widget<TextField>(composer).controller!.text, 'Draft kept');
      expect(tester.takeException(), isNull);
      c.dispose();
      cleaned = true;
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'PIN removes demo verification and a stale create-dialog confirmation cannot start a group',
    (tester) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await demoUiTurn(tester);
      await tester.runAsync(() => lock.enable('123456'));
      await tester.tap(find.byTooltip('Group chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create demo group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'Private draft name',
      );
      lock.lock();
      await demoUiTurn(tester);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(GroupHubScreen), findsNothing);
      expect(find.text('Private draft name'), findsNothing);
      expect(c.groups.running, isFalse);
      await tester.runAsync(() => lock.unlockPin('123456'));
      await demoUiTurn(tester);
      expect(c.groups.histories, isEmpty);
      c.dispose();
      cleaned = true;
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'demo controls remain reachable at narrow width with enlarged text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
            ),
            child: GroupHubScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('Create demo group');
      await tester.scrollUntilVisible(
        button,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'A long demo group name with larger text',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await demoUiTurn(tester);
      expect(find.byType(GroupChatScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      c.dispose();
      cleaned = true;
      await tester.pumpWidget(const SizedBox());
    },
  );
}
