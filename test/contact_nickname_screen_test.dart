import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/starred_message.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/chats_tab.dart';
import 'package:local_chat/features/starred_messages_screen.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'contact_nickname_test.dart' show NicknameStore;

void main() {
  late NicknameStore store;
  late ChatController c;
  setUp(() async {
    store = NicknameStore();
    c = ChatController(DemoTransport(), store, isDemo: true);
    await c.initialize();
    await store.savePeer('alice', 'Alice phone');
    await store.saveDraft('alice', 'Unsent draft');
    c.conversations = await store.conversations();
  });
  tearDown(() => c.dispose());
  Future<void> turn(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 30));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await t.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester t, {
    bool chat = false,
    TextScaler? scaler,
  }) async {
    if (chat) {
      await t.runAsync(() async {
        await c.viewHistory(c.conversations.single);
        await c.drafts.load('alice');
      });
    }
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final child = chat
                ? ChatScreen(controller: c)
                : Scaffold(
                    body: ChatsTab(
                      controller: c,
                      onFindDevices: () {},
                      onOpenConnected: () {},
                      onOpenHistory: (_) {},
                    ),
                  );
            return child;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t, {bool existing = false}) async {
    final menu = find.byKey(const ValueKey('conversation-menu-alice'));
    if (menu.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        menu,
        150,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(menu);
    await t.tap(menu);
    await t.pumpAndSettle();
    await t.tap(find.text(existing ? 'Edit nickname' : 'Set nickname'));
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await turn(t);
  }

  Future<void> waitForSave(WidgetTester t) async {
    for (var i = 0; i < 20 && !store.entered!.isCompleted; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(store.entered!.isCompleted, isTrue);
  }

  testWidgets('Covered or disposed editor cannot complete a delayed save', (
    t,
  ) async {
    await show(t);
    await open(t);
    await t.enterText(
      find.byKey(const ValueKey('contact-nickname')),
      'Discard',
    );
    store.entered = Completer<void>();
    store.release = Completer<void>();
    await t.tap(find.text('Save'));
    await t.pump();
    await waitForSave(t);
    final nav = Navigator.of(t.element(find.byType(AlertDialog)));
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Cover')),
        ),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    store.release!.complete();
    await turn(t);
    expect((await store.conversations()).single.nickname, isNull);
    expect(find.text('Cover'), findsOneWidget);
    nav.pop();
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await open(t);
    await t.enterText(
      find.byKey(const ValueKey('contact-nickname')),
      'Discard again',
    );
    store.entered = Completer<void>();
    store.release = Completer<void>();
    await t.tap(find.text('Save'));
    await t.pump();
    await waitForSave(t);
    await t.pumpWidget(const SizedBox());
    store.release!.complete();
    await turn(t);
    expect((await store.conversations()).single.nickname, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Starred-message labels refresh when a contact nickname changes',
    (t) async {
      await t.runAsync(() async {
        await store.saveMessage(
          const ChatMessage(
            id: 'm',
            peerId: 'alice',
            text: 'Saved text',
            timestamp: 1,
            outgoing: false,
            status: 'received',
          ),
        );
        await store.setMessageStarred(
          const StarredMessage(target: 'alice', id: 'm', outgoing: false),
          true,
        );
        await c.refreshStars();
      });
      await t.pumpWidget(
        MaterialApp(home: StarredMessagesScreen(controller: c)),
      );
      await turn(t);
      expect(find.text('Alice phone'), findsOneWidget);
      final pending = c.setNickname('alice', 'Friend');
      await turn(t);
      expect(await pending, isTrue);
      expect(find.text('Friend'), findsOneWidget);
      expect(find.textContaining('Alice phone'), findsNothing);
    },
  );

  testWidgets('Chat options set/edit/remove nicknames and preserve drafts', (
    t,
  ) async {
    await show(t);
    await open(t);
    expect(find.text('Phone name: Alice phone'), findsOneWidget);
    expect(
      find.text('Private in this demo tab. Resets on reload.'),
      findsOneWidget,
    );
    await t.enterText(
      find.byKey(const ValueKey('contact-nickname')),
      'Friend سلام 👋',
    );
    await save(t);
    expect(find.text('Friend سلام 👋'), findsOneWidget);
    expect(c.conversations.single.originalName, 'Alice phone');
    expect(await store.draft('alice'), 'Unsent draft');
    await open(t, existing: true);
    await t.enterText(
      find.byKey(const ValueKey('contact-nickname')),
      'Best friend',
    );
    await save(t);
    expect(find.text('Best friend'), findsOneWidget);
    await open(t, existing: true);
    await t.tap(find.text('Remove nickname'));
    await t.pumpAndSettle();
    expect(find.text('Alice phone'), findsOneWidget);
    expect(c.conversations.single.nickname, isNull);
  });

  testWidgets(
    'Nickname validation, cancellation, failed save and retry retain input',
    (t) async {
      await show(t);
      await open(t);
      await t.enterText(
        find.byKey(const ValueKey('contact-nickname')),
        '👋' * 33,
      );
      await save(t);
      expect(find.textContaining('128 UTF-8 bytes'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('contact-nickname')),
        'Friend',
      );
      store.fail = true;
      await save(t);
      expect(
        find.text('Could not save the nickname. Please try again.'),
        findsOneWidget,
      );
      expect(c.conversations.single.nickname, isNull);
      expect(find.text('Friend'), findsOneWidget);
      store.fail = false;
      await save(t);
      expect(find.text('Friend'), findsOneWidget);
      await open(t, existing: true);
      await t.enterText(
        find.byKey(const ValueKey('contact-nickname')),
        'Discard',
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.conversations.single.name, 'Friend');
    },
  );

  testWidgets(
    'Lock and background dismiss editor and cannot retain unsaved nickname',
    (t) async {
      await show(t);
      await open(t);
      await t.enterText(
        find.byKey(const ValueKey('contact-nickname')),
        'Discard',
      );
      c.setAppAccess(false);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      c.setAppAccess(true);
      await t.pumpAndSettle();
      await open(t);
      expect(find.text('Discard'), findsNothing);
      c.setAppForeground(false);
      c.setAppForeground(true);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.conversations.single.nickname, isNull);
    },
  );

  testWidgets(
    'Saved chat title updates live and blank input restores phone name',
    (t) async {
      await show(t, chat: true);
      await open(t);
      await t.enterText(
        find.byKey(const ValueKey('contact-nickname')),
        'Friend',
      );
      await save(t);
      expect(find.text('Friend'), findsOneWidget);
      expect(c.selectedName, 'Alice phone');
      expect(c.drafts.textFor('alice'), 'Unsent draft');
      await open(t, existing: true);
      await t.enterText(find.byKey(const ValueKey('contact-nickname')), '  ');
      await save(t);
      expect(find.text('Alice phone'), findsOneWidget);
    },
  );

  testWidgets('Nickname dialog fits a narrow display at enlarged text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await show(t, scaler: TextScaler.linear(2.34));
    await open(t);
    await t.enterText(find.byKey(const ValueKey('contact-nickname')), 'Friend');
    await save(t);
    expect(c.conversations.single.name, 'Friend');
    expect(t.takeException(), isNull);
  });
}
