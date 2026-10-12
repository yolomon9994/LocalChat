import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/group_controller.dart';
import 'group_test_support.dart';
import 'lock_test_support.dart';
import 'image_test_support.dart';
import 'image_screen_test.dart' show FixedPicker;
import 'package:local_chat/features/group_image_bubble.dart';
import 'package:local_chat/features/chat_image_view.dart';
import 'package:local_chat/features/group_file_bubble.dart';
import 'package:local_chat/services/chat_files.dart';
import 'group_file_test_support.dart';
import 'package:local_chat/core/chat_file.dart';
import 'group_draft_test.dart' show DraftGroupStore;

void main() {
  late GroupNetwork network;
  late ChatController c;
  setUp(() async {
    network = GroupNetwork();
    c = ChatController(
      DemoTransport(),
      DemoStore(),
      groupTransport: FakeGroupTransport(network),
    );
    await c.initialize();
    network.controllers.add(c.groups);
  });
  tearDown(() {
    network.controllers.remove(c.groups);
    for (final guest in network.controllers) {
      guest.dispose();
    }
    c.dispose();
  });
  testWidgets(
    'offline group drafts restore after navigation and remain isolated',
    (tester) async {
      late String first, second;
      await tester.runAsync(() async {
        await c.groups.host('First room');
        first = c.groups.active!.id;
        await c.groups.host('Second room');
        second = c.groups.active!.id;
        await c.groups.stop();
        await c.drafts.load(first, group: true);
        await c.drafts.load(second, group: true);
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      void open(String id) => navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => GroupChatScreen(controller: c, id: id),
        ),
      );
      final composer = find.byKey(const ValueKey('group-message-composer'));
      open(first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).enabled, isTrue);
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
      await tester.runAsync(() async {
        await tester.enterText(composer, '  first سلام 👋\nline two  ');
        await c.drafts.settled;
      });
      await tester.pageBack();
      await tester.pumpAndSettle();
      open(second);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).controller!.text, '');
      await tester.runAsync(() async {
        await tester.enterText(composer, 'Second draft');
        await c.drafts.settled;
      });
      await tester.pageBack();
      await tester.pumpAndSettle();
      open(first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        '  first سلام 👋\nline two  ',
      );
      expect(await c.store.groupDraft(second), 'Second draft');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed group draft load disables editing; failed saves retain text with retry',
    (tester) async {
      late DraftGroupStore store;
      late String id;
      await tester.runAsync(() async {
        network.controllers.remove(c.groups);
        c.dispose();
        store = DraftGroupStore();
        c = ChatController(
          DemoTransport(),
          store,
          groupTransport: FakeGroupTransport(network),
        );
        await c.initialize();
        network.controllers.add(c.groups);
        await c.groups.host('Errors');
        id = c.groups.active!.id;
        await c.groups.stop();
        await store.saveGroupDraft(id, 'Saved text');
        store.failRead = true;
        await c.drafts.load(id, group: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(controller: c, id: id),
        ),
      );
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('group-message-composer'));
      expect(tester.widget<TextField>(composer).enabled, isFalse);
      expect(find.textContaining('Could not load'), findsOneWidget);
      store.failRead = false;
      await tester.runAsync(() async {
        await tester.tap(find.text('Retry draft'));
        await c.drafts.settled;
      });
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).controller!.text, 'Saved text');
      store.failWrite = true;
      await tester.runAsync(() async {
        await tester.enterText(composer, 'Keep unsaved text');
        await c.drafts.settled;
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Draft not saved'), findsOneWidget);
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Keep unsaved text',
      );
      store.failWrite = false;
      await tester.runAsync(() async {
        await tester.tap(find.text('Retry draft'));
        await c.drafts.settled;
      });
      await tester.pumpAndSettle();
      expect(await store.groupDraft(id), 'Keep unsaved text');
      expect(find.text('Retry draft'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('accepted group text clears its composer and stored draft', (
    tester,
  ) async {
    late String id;
    await tester.runAsync(() async {
      await c.groups.host('Send draft');
      final guest = await network.phone('Guest');
      await network.join(guest);
      await c.drafts.load(c.groups.active!.id, group: true);
      id = c.groups.active!.id;
      await c.drafts.load(id, group: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: GroupChatScreen(controller: c, id: id),
      ),
    );
    await tester.pumpAndSettle();
    final composer = find.byKey(const ValueKey('group-message-composer'));
    await tester.enterText(composer, '  Accepted draft  ');
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Send group message',
            ),
          )
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    // Pump the widget zone between real crypto turns; awaiting its protocol
    // queue inside runAsync would prevent fake-zone continuations from running.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(composer).controller!.text, '');
    expect(await c.store.groupDraft(id), '');
    expect(c.groups.active!.messages.single.text, 'Accepted draft');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'small screen and large text keep verification and member controls usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late GroupController guest;
      await tester.runAsync(() async {
        await c.groups.host('Friends');
        guest = await network.phone('Guest');
        await network.join(guest, verify: false);
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: GroupHubScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Codes match'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Codes match'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Codes match'),
      );
      await tester.runAsync(() async {
        button.onPressed!();
        await network.settle();
        expect(c.groups.members.length, 1);
        await guest.confirm(guest.links.keys.single);
        await network.settle();
      });
      await tester.pumpAndSettle();
      expect(c.groups.members.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(controller: c, id: c.groups.active!.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove member'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'small screen group image review can discard without clearing text or sending',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        network.controllers.remove(c.groups);
        c.dispose();
        c = ChatController(
          DemoTransport(),
          DemoStore(),
          groupTransport: FakeGroupTransport(network),
          imageFiles: FixedPicker(await testImage()),
        );
        await c.initialize();
        network.controllers.add(c.groups);
      });
      await tester.runAsync(() async {
        await c.groups.host('Pictures');
        final guest = await network.phone('Guest');
        await network.join(guest);
        await c.drafts.load(c.groups.active!.id, group: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
            ),
            child: GroupChatScreen(controller: c, id: c.groups.active!.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keep this draft');
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Attach group image'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Send group image?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Discard'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(c.groups.active!.messages, isEmpty);
      expect(c.groups.images.pendingGroup, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep this draft',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'offline group image opens zoom and PIN lock removes both image routes',
    (tester) async {
      late String id;
      await tester.runAsync(() async {
        await c.groups.host('Private pictures');
        final guest = await network.phone('Guest');
        await network.join(guest);
        await c.drafts.load(c.groups.active!.id, group: true);
        await guest.images.send(await testImage());
        await network.settle();
        id = c.groups.active!.id;
        await c.groups.stop();
        await network.settle();
      });
      (c.notifications.platform as MemoryNotificationPlatform).launchPeer =
          'group:$id';
      final lock = testLock();
      await lock.initialize();
      await lock.enable('123456');
      lock.lock();
      final appearance = AppearanceController(MemoryAppearanceStorage());
      addTearDown(lock.dispose);
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => lock.unlockPin('123456'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupImageBubble), findsOneWidget);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      expect(find.byType(ChatImageViewer), findsOneWidget);
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(ChatImageViewer), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'small screen group file preview discards safely and keeps composer text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        network.controllers.remove(c.groups);
        c.dispose();
        c = ChatController(
          DemoTransport(),
          DemoStore(),
          groupTransport: FakeGroupTransport(network),
          chatFiles: MemoryGroupFiles(
            SelectedFile('../report?.pdf', Uint8List.fromList([1, 2, 3])),
          ),
        );
        await c.initialize();
        network.controllers.add(c.groups);
        await c.groups.host('Documents');
        final guest = await network.phone('Guest');
        await network.join(guest);
        await c.drafts.load(c.groups.active!.id, group: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
            ),
            child: GroupChatScreen(controller: c, id: c.groups.active!.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keep this draft');
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Attach group file'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Send group file?'), findsOneWidget);
      expect(find.text(ChatFile.safeName('../report?.pdf')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Discard'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(c.groups.active!.messages, isEmpty);
      expect(c.groups.files.pendingGroup, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep this draft',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'offline group file export needs confirmation and PIN removes its dialog',
    (tester) async {
      late String id;
      late MemoryGroupFiles files;
      final bytes = Uint8List.fromList([1, 2, 3]);
      await tester.runAsync(() async {
        network.controllers.remove(c.groups);
        c.dispose();
        files = MemoryGroupFiles(null);
        c = ChatController(
          DemoTransport(),
          DemoStore(),
          groupTransport: FakeGroupTransport(network),
          chatFiles: files,
        );
        await c.initialize();
        network.controllers.add(c.groups);
        await c.groups.host('Private files');
        final guest = await network.phone('Guest');
        await network.join(guest);
        await c.drafts.load(c.groups.active!.id, group: true);
        await guest.files.send(SelectedFile('report.pdf', bytes));
        await network.settle();
        id = c.groups.active!.id;
        await c.groups.stop();
        await network.settle();
      });
      (c.notifications.platform as MemoryNotificationPlatform).launchPeer =
          'group:$id';
      final lock = testLock();
      await lock.initialize();
      await lock.enable('123456');
      lock.lock();
      final appearance = AppearanceController(MemoryAppearanceStorage());
      addTearDown(lock.dispose);
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => lock.unlockPin('123456'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupFileBubble), findsOneWidget);
      await tester.ensureVisible(find.text('Save to phone'));
      await tester.tap(find.text('Save to phone'));
      await tester.pumpAndSettle();
      expect(files.saved, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(files.saved, isEmpty);
      await tester.tap(find.text('Save to phone'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Save file'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(files.saved.single.bytes, bytes);
      expect(files.saved.single.name, 'report.pdf');
      await tester.tap(find.text('Save to phone'));
      await tester.pumpAndSettle();
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('Save file to phone?'), findsNothing);
      expect(find.text('report.pdf'), findsNothing);
      expect(files.saved.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('saved group opens offline; deletion requires confirmation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      late String id;
      await c.groups.host('Saved');
      final guest = await network.phone('Guest');
      await network.join(guest);
      await c.drafts.load(c.groups.active!.id, group: true);
      await guest.sendText('saved private group text');
      await network.settle();
      id = c.groups.active!.id;
      await c.groups.stop();
      await network.settle();
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(controller: c, id: id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('saved private group text'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
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
      await tester.tap(find.byTooltip('Delete group history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.groups.histories.length, 1);
      await tester.tap(find.byTooltip('Delete group history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      await network.settle();
      await tester.pumpAndSettle();
      expect(c.groups.histories, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
  testWidgets(
    'notification group tap waits for PIN; lock covers group history',
    (tester) async {
      late String id;
      await tester.runAsync(() async {
        await c.groups.host('Private group');
        final guest = await network.phone('Guest');
        await network.join(guest);
        await c.drafts.load(c.groups.active!.id, group: true);
        await guest.sendText('hidden group text');
        await network.settle();
        id = c.groups.active!.id;
        await c.groups.stop();
        await network.settle();
      });
      final platform = c.notifications.platform as MemoryNotificationPlatform;
      await tester.runAsync(() async {
        await c.drafts.load(id, group: true);
        c.drafts.setText(id, 'hidden group draft', group: true);
        await c.drafts.settled;
      });
      platform.launchPeer = 'group:$id';
      final lock = testLock();
      await lock.initialize();
      await lock.enable('123456');
      lock.lock();
      final appearance = AppearanceController(MemoryAppearanceStorage());
      addTearDown(lock.dispose);
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('hidden group text'), findsNothing);
      await tester.runAsync(() => lock.unlockPin('123456'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupChatScreen), findsOneWidget);
      expect(find.text('hidden group text'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('group-message-composer')),
            )
            .controller!
            .text,
        'hidden group draft',
      );
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('hidden group text'), findsNothing);
      expect(find.text('hidden group draft'), findsNothing);
      await tester.runAsync(() => lock.unlockPin('123456'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        platform.tapEvents.add('group:$id');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('group-message-composer')),
            )
            .controller!
            .text,
        'hidden group draft',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
