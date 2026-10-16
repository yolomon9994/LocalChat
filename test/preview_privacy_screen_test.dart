import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/features/chats_tab.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'package:local_chat/services/preview_privacy.dart';
import 'preview_privacy_test.dart';
import 'starred_messages_test.dart' show signedStarGroup;

void main() {
  late ChatController c;
  late DemoStore store;
  late TestPreviewStorage storage;
  late TestPreviewNotifications platform;
  setUp(() async {
    storage = TestPreviewStorage();
    platform = TestPreviewNotifications();
    store = DemoStore();
    await store.open();
    await store.savePeer('alice', 'Alice');
    await store.saveMessage(
      const ChatMessage(
        id: 'm',
        peerId: 'alice',
        text: 'Private saved body',
        timestamp: 1,
        outgoing: false,
        status: 'received',
      ),
    );
    await store.saveDraft('alice', 'Private direct draft');
    final group = await signedStarGroup(store);
    await store.saveGroupHistory(group);
    await store.saveGroupDraft(group.id, 'Private group draft');
    c = ChatController(
      DemoTransport(),
      store,
      isDemo: true,
      previewPrivacy: PreviewPrivacy(storage),
      notifications: ChatNotifications(platform, isDemo: true),
    );
    await c.initialize();
    await c.notifications.initialize();
    await c.notifications.setEnabled(true);
  });
  tearDown(() => c.dispose());
  Future<void> turn(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 30));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await t.pumpAndSettle();
  }

  Future<void> show(WidgetTester t, Widget home, {bool large = false}) async {
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(large ? 2.34 : 1)),
          child: child!,
        ),
        home: home,
      ),
    );
    await turn(t);
  }

  Widget list({bool archived = false}) => ListenableBuilder(
    listenable: c,
    builder: (_, _) => Scaffold(
      body: ChatsTab(
        controller: c,
        archived: archived,
        onFindDevices: () {},
        onOpenConnected: () {},
        onOpenHistory: (_) {},
      ),
    ),
  );
  Future<void> tapVisible(WidgetTester t, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await t.tap(finder);
    await turn(t);
  }

  Future<void> mode(WidgetTester t, String label) async {
    await tapVisible(
      t,
      find.byKey(const ValueKey('notification-preview-mode')),
    );
    final option = find.text(label).last;
    await t.ensureVisible(option);
    await t.pumpAndSettle();
    expect(option.hitTestable(), findsOneWidget);
    await t.tap(option);
    await turn(t);
  }

  testWidgets(
    'Hidden chat rows omit text from widgets and semantics while retaining identity, unread and history',
    (t) async {
      final semantics = t.ensureSemantics();
      await show(t, list());
      expect(find.text('Private saved body'), findsOneWidget);
      final before = c.conversations.single;
      final revision = c.historyRevision;
      await c.previewPrivacy.setHidden(true);
      await turn(t);
      expect(find.text('Private saved body'), findsNothing);
      expect(find.text('Message preview hidden'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(
        t
            .getSemantics(find.byKey(const ValueKey('conversation-alice')))
            .toStringDeep(),
        isNot(contains('Private saved body')),
      );
      expect(c.conversations.single.unreadCount, before.unreadCount);
      expect(c.conversations.single.updated, before.updated);
      expect(c.historyRevision, revision);
      expect((await store.messages('alice')).single.text, 'Private saved body');
      expect(await store.draft('alice'), 'Private direct draft');
      // Browser WebCrypto completes outside the widget test's fake clock.
      final backup = await t.runAsync(store.exportBackup);
      expect(backup!.toJson().containsKey('previewPrivacy'), isFalse);
      semantics.dispose();
    },
  );
  testWidgets(
    'Archived direct/group lists never reveal hidden messages or draft text',
    (t) async {
      await t.runAsync(() => c.setArchived('alice', true));
      await c.previewPrivacy.setHidden(true);
      await show(t, list(archived: true));
      expect(find.text('Message preview hidden'), findsOneWidget);
      expect(find.text('Private saved body'), findsNothing);
      expect(find.textContaining('Group saved text'), findsNothing);
      expect(find.text('Private direct draft'), findsNothing);
      expect(find.text('Private group draft'), findsNothing);
      expect(
        find.byKey(ValueKey('group-${c.groups.histories.single.id}')),
        findsOneWidget,
      );
      await c.previewPrivacy.setHidden(false);
      await turn(t);
      expect(find.text('Private saved body'), findsOneWidget);
      expect(find.text('Private group draft'), findsNothing);
    },
  );
  testWidgets(
    'Hide setting saves, retains the old choice on error and supports retry',
    (t) async {
      await show(t, SettingsScreen(controller: c));
      storage.failWrite = true;
      await tapVisible(t, find.byKey(const ValueKey('hide-chat-previews')));
      expect(c.previewPrivacy.hidden, isFalse);
      expect(
        find.text('Could not save preview privacy. Please try again.'),
        findsOneWidget,
      );
      storage.failWrite = false;
      await tapVisible(t, find.byKey(const ValueKey('hide-chat-previews')));
      expect(c.previewPrivacy.hidden, isTrue);
      expect(storage.value, contains('"hidden":true'));
    },
  );
  testWidgets(
    'Notification selector controls hidden, sender and body independently of chat rows',
    (t) async {
      await show(t, SettingsScreen(controller: c));
      c.notifications.setAccessible(true);
      await mode(t, 'Sender only');
      expect(c.notifications.previewMode, NotificationPreview.sender);
      await c.notifications.incoming(
        'alice',
        'Alice',
        'Body secret',
        isReading: () => false,
      );
      expect(platform.payloads.last, (name: 'Alice', text: null));
      expect(c.previewPrivacy.hidden, isFalse);
      await mode(t, 'Sender and message');
      expect(c.notifications.previewMode, NotificationPreview.message);
      await mode(t, 'Hidden');
      expect(c.notifications.previewMode, NotificationPreview.hidden);
      expect(platform.alerts['alice'], (name: null, text: null));
    },
  );
  testWidgets('Opened conversations still show their content and saved draft', (
    t,
  ) async {
    await c.previewPrivacy.setHidden(true);
    await t.runAsync(() async {
      await c.viewHistory(c.conversations.single);
      await c.drafts.load('alice');
    });
    await show(t, ChatScreen(controller: c));
    expect(find.text('Private saved body'), findsOneWidget);
    expect(find.text('Private direct draft'), findsOneWidget);
  });
  testWidgets(
    'Both privacy controls remain usable on a narrow screen at enlarged text',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await show(t, SettingsScreen(controller: c), large: true);
      await tapVisible(t, find.byKey(const ValueKey('hide-chat-previews')));
      await mode(t, 'Sender only');
      expect(c.previewPrivacy.hidden, isTrue);
      expect(c.notifications.previewMode, NotificationPreview.sender);
      expect(t.takeException(), isNull);
    },
  );
}
