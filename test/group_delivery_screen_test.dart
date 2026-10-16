import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/group_controller.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'group_test_support.dart';
import 'lock_test_support.dart';

void main() {
  late GroupNetwork net;
  late ChatController c;
  late GroupController alice, bob;
  late String id;
  setUp(() async {
    net = GroupNetwork();
    c = ChatController(
      DemoTransport(),
      DemoStore(),
      groupTransport: FakeGroupTransport(net),
    );
    await c.initialize();
    net.controllers.add(c.groups);
    await c.groups.host('Delivery room');
    id = c.groups.active!.id;
    alice = await net.phone('Alice');
    bob = await net.phone('Bob');
    await net.join(alice);
    await net.join(bob);
  });
  tearDown(() {
    net.controllers.remove(c.groups);
    for (final phone in net.controllers) {
      phone.dispose();
    }
    c.dispose();
  });

  Future<void> turn(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 30));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t, {bool large = false}) async {
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(large ? 2.34 : 1)),
          child: child!,
        ),
        home: GroupChatScreen(controller: c, id: id),
      ),
    );
    await turn(t);
  }

  Future<void> visible(WidgetTester t, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
  }

  Future<void> becomeOfflineGuest() async {
    await c.groups.stop();
    await net.settle();
    await alice.host('Guest room');
    await net.join(c.groups);
    id = c.groups.active!.id;
    await c.groups.sendText('Saved outgoing');
    await net.settle();
    await c.store.saveGroupDraft(id, 'Keep draft');
    await alice.stop();
    await net.settle();
  }

  testWidgets(
    'Departed member keeps its name and an accessible uncertainty explanation',
    (t) async {
      await t.runAsync(() async {
        (bob.transport as FakeGroupTransport).dropOutgoing = true;
        await c.groups.sendText('Receipt example');
        await net.settle();
        await bob.stop();
        await net.settle();
      });
      await open(t);
      final row = find.text('Bob: Unconfirmed: member disconnected or left');
      await visible(t, row);
      expect(row, findsOneWidget);
      expect(find.text('Alice: Received'), findsOneWidget);
      final semantics = t.ensureSemantics();
      expect(
        t.getSemantics(row).toStringDeep(),
        contains('member disconnected or left'),
      );
      semantics.dispose();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Guest host-loss guidance opens the finder without sending or joining',
    (t) async {
      await t.runAsync(becomeOfflineGuest);
      await open(t);
      final finder = find.byKey(const ValueKey('group-delivery-find-host'));
      await visible(t, finder);
      expect(
        find.textContaining('Ask the original host to reopen it'),
        findsOneWidget,
      );
      expect(
        find.text('Session ended: host connection ended.'),
        findsOneWidget,
      );
      await t.tap(finder);
      await turn(t);
      expect(find.byType(GroupHubScreen), findsOneWidget);
      expect(c.groups.running, isFalse);
      expect(c.groups.links, isEmpty);
      expect(
        c.groups.histories.firstWhere((h) => h.id == id).messages.length,
        1,
      );
      expect(await c.store.groupDraft(id), 'Keep draft');
    },
  );

  testWidgets(
    'Original host receives reopening guidance and existing host action',
    (t) async {
      await t.runAsync(() async {
        await c.groups.sendText('Keep this history');
        await net.settle();
        await c.groups.stop();
        await net.settle();
      });
      await open(t);
      await visible(t, find.text('Host this group again'));
      expect(
        find.textContaining('Hosting has ended on this phone'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-delivery-find-host')),
        findsNothing,
      );
      expect(
        find.textContaining('Sending it again creates a new message'),
        findsOneWidget,
      );
      expect(c.groups.running, isFalse);
    },
  );

  testWidgets(
    'Captured finder callback cannot navigate after background and return',
    (t) async {
      await t.runAsync(becomeOfflineGuest);
      await open(t);
      final finder = find.byKey(const ValueKey('group-delivery-find-host'));
      await visible(t, finder);
      final callback = t.widget<TextButton>(finder).onPressed!;
      await t.runAsync(() async {
        c.setAppForeground(false);
        await c.groups.idle;
        c.setAppForeground(true);
        await c.groups.idle;
      });
      callback();
      await turn(t);
      expect(find.byType(GroupHubScreen), findsNothing);
      expect(c.groups.running, isFalse);
    },
  );

  testWidgets(
    'Offline recovery guidance is scrollable on narrow screens at enlarged text',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(becomeOfflineGuest);
      await open(t, large: true);
      final finder = find.byKey(const ValueKey('group-delivery-find-host'));
      await visible(t, finder);
      expect(finder.hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(finder);
      await turn(t);
      expect(find.byType(GroupHubScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'App lock removes delivery details and rejects a saved finder callback',
    (t) async {
      await t.runAsync(becomeOfflineGuest);
      final lock = testLock();
      await t.runAsync(() async {
        await lock.initialize();
        await lock.enable('123456');
        lock.lock();
      });
      final appearance = AppearanceController(MemoryAppearanceStorage());
      addTearDown(lock.dispose);
      addTearDown(appearance.dispose);
      (c.notifications.platform as MemoryNotificationPlatform).launchPeer =
          'group:$id';
      // The app consumes launch taps while creating its navigation state.
      await t.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await turn(t);
      await t.runAsync(() => lock.unlockPin('123456'));
      await turn(t);
      final finder = find.byKey(const ValueKey('group-delivery-find-host'));
      await visible(t, finder);
      final callback = t.widget<TextButton>(finder).onPressed!;
      lock.lock();
      await turn(t);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(GroupChatScreen), findsNothing);
      callback();
      await turn(t);
      expect(find.byType(GroupHubScreen), findsNothing);
      expect(find.textContaining('Session ended:'), findsNothing);
    },
  );
}
