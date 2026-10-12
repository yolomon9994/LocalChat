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
  testWidgets('saved group opens offline; deletion requires confirmation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      late String id;
      await c.groups.host('Saved');
      final guest = await network.phone('Guest');
      await network.join(guest);
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
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
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
        await guest.sendText('hidden group text');
        await network.settle();
        id = c.groups.active!.id;
        await c.groups.stop();
        await network.settle();
      });
      final platform = c.notifications.platform as MemoryNotificationPlatform;
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
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('hidden group text'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
