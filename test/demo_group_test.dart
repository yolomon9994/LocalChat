import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_group_transport.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_search_controller.dart';
import 'package:local_chat/services/group_controller.dart';
import 'package:local_chat/services/chat_files.dart';
import 'package:local_chat/services/background_connection.dart';
import 'image_test_support.dart';

Future<void> demoTurn(GroupController group, {int turns = 30}) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await group.idle;
  }
}

Future<void> confirmDemo(GroupController group) async {
  await demoTurn(group);
  for (final link in group.links.values.toList()) {
    if (!link.localVerified) await group.confirm(link.id);
  }
  await demoTurn(group);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatController c;
  setUp(() async {
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
  tearDown(() => c.dispose());

  test(
    'browser factory supplies simulated groups and ordinary test/demo controllers retain their fallback',
    () async {
      final browser = createDemoController();
      addTearDown(browser.dispose);
      expect(browser.simulatedGroups && browser.canUseGroups, isTrue);
      await browser.initialize();
      final fallback = ChatController(
        DemoTransport(),
        DemoStore(),
        isDemo: true,
      );
      addTearDown(fallback.dispose);
      expect(fallback.simulatedGroups || fallback.canUseGroups, isFalse);
    },
  );

  test(
    'hosting creates two independent simulated handshakes without bypassing local confirmation',
    () async {
      expect(await c.groups.host('My demo room'), isTrue);
      await demoTurn(c.groups);
      expect(c.groups.links.length, 2);
      expect(c.groups.members.length, 1);
      expect(c.groups.active!.messages, isEmpty);
      expect(
        c.groups.links.values.every(
          (l) => l.remoteVerified && !l.localVerified && !l.admitted,
        ),
        isTrue,
      );
      expect(
        c.groups.links.values
            .map((l) => l.session.verificationCode)
            .toSet()
            .length,
        2,
      );
      expect(c.groups.transportGeneration, isNegative);
      expect(await c.groups.sendText('Not yet'), isFalse);
      await confirmDemo(c.groups);
      expect(c.groups.members.length, 3);
      expect(
        c.groups.active!.messages.where((m) => m.author != c.groups.selfId),
        isNotEmpty,
      );
      for (final m in c.groups.active!.messages) {
        expect((await GroupText.parse(m.toJson())).key, m.key);
      }
    },
  );

  test(
    'host text has per-member receipts and distinct signed simulated replies',
    () async {
      await c.groups.host('Room');
      await confirmDemo(c.groups);
      expect(await c.groups.sendText('Hello group سلام 👋'), isTrue);
      await demoTurn(c.groups);
      final outgoing = c.groups.active!.messages.singleWhere(
        (m) => m.text == 'Hello group سلام 👋',
      );
      expect(outgoing.receipts.values.every((s) => s == 'received'), isTrue);
      final replies = c.groups.active!.messages.where(
        (m) => m.text.startsWith('Got it!'),
      );
      expect(replies.map((m) => m.author).toSet().length, 2);
      expect(replies.every((m) => m.author != c.groups.selfId), isTrue);
      expect(c.groups.error, isNull);
    },
  );

  test(
    'finding and joining a simulated host still requires local verification and exercises host relay',
    () async {
      await c.groups.discover();
      await demoTurn(c.groups);
      expect(c.groups.nearby.single['title'], 'Weekend plans (Demo)');
      expect(await c.groups.join('not-a-demo-host'), isFalse);
      expect(await c.groups.join('demo-group'), isTrue);
      await demoTurn(c.groups);
      expect(c.groups.active, isNull);
      expect(c.groups.links.values.single.remoteVerified, isTrue);
      await confirmDemo(c.groups);
      expect(c.groups.hosting, isFalse);
      expect(c.groups.members.length, 3);
      expect(await c.groups.sendText('Relayed by the demo host'), isTrue);
      await demoTurn(c.groups);
      final sent = c.groups.active!.messages.singleWhere(
        (m) => m.text == 'Relayed by the demo host',
      );
      expect(sent.receipts.values.every((s) => s == 'received'), isTrue);
      expect(
        c.groups.active!.messages
            .where((m) => m.text.startsWith('Got it!'))
            .length,
        2,
      );
      expect(c.groups.error, isNull);
    },
  );

  test(
    'rejecting/removing simulated members closes only their link and preserves the rest of the group',
    () async {
      await c.groups.host('Room');
      await demoTurn(c.groups);
      final rejected = c.groups.links.values.first.id;
      await c.groups.reject(rejected);
      await demoTurn(c.groups);
      expect(c.groups.links.length, 1);
      await confirmDemo(c.groups);
      expect(c.groups.members.length, 2);
      expect(await c.groups.sendText('One recipient'), isTrue);
      await demoTurn(c.groups);
      final message = c.groups.active!.messages.singleWhere(
        (m) => m.text == 'One recipient',
      );
      expect(message.targets.length, 2);
      expect(message.receipts.values.every((s) => s == 'received'), isTrue);
      await c.groups.reject(c.groups.links.keys.single);
      await demoTurn(c.groups);
      expect(c.groups.members.length, 1);
      expect(c.groups.histories.single.messages, isNotEmpty);
    },
  );

  test(
    'lock/background gates local sends and admission without losing drafts or simulated incoming unread',
    () async {
      await c.groups.host('Room');
      await demoTurn(c.groups);
      final id = c.groups.active!.id;
      await c.drafts.load(id, group: true);
      c.drafts.setText(id, 'Private draft', group: true);
      await c.drafts.settled;
      c.setAppAccess(false);
      c.setAppForeground(false);
      await confirmDemo(c.groups);
      expect(c.groups.members.length, 1);
      expect(c.groups.active!.messages, isEmpty);
      expect(await c.groups.sendText('Blocked'), isFalse);
      c.setAppForeground(true);
      c.setAppAccess(true);
      await confirmDemo(c.groups);
      expect(c.groups.members.length, 3);
      expect(await c.store.groupDraft(id), 'Private draft');
      c.groups.setVisible(Object(), id, true);
      await demoTurn(c.groups);
      await c.groups.sendText('Reply while away');
      c.setAppAccess(false);
      c.setAppForeground(false);
      await demoTurn(c.groups);
      expect(c.groups.active!.unread, greaterThan(0));
      expect(c.groups.images.canSend || c.groups.files.canSend, isFalse);
    },
  );

  test(
    'ending a room cancels queued replies and saved history remains offline',
    () async {
      c.dispose();
      c = ChatController(
        DemoTransport(),
        DemoStore(),
        isDemo: true,
        groupTransport: DemoGroupTransport(
          replyDelay: const Duration(milliseconds: 400),
        ),
      );
      await c.initialize();
      await c.groups.host('Room');
      await confirmDemo(c.groups);
      await c.groups.sendText('Stop before replies');
      await c.groups.stop();
      final saved = c.groups.histories.single;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await c.groups.refreshHistory();
      expect(c.groups.active, isNull);
      expect(
        c.groups.histories.single.messages.map((m) => m.key),
        saved.messages.map((m) => m.key),
      );
      expect(
        c.groups.histories.single.messages.any(
          (m) => m.text == 'Stop before replies',
        ),
        isTrue,
      );
    },
  );

  test(
    'rehosting retains the room ID/history but creates a new epoch and fresh local confirmations',
    () async {
      await c.groups.host('Room');
      await confirmDemo(c.groups);
      await c.groups.sendText('Keep my history');
      await demoTurn(c.groups);
      final history = c.groups.active!, epoch = c.groups.epoch;
      await c.groups.setArchived(history.id, true);
      await c.groups.setPinned(history.id, true);
      await c.groups.stop();
      expect(await c.groups.host(history.title, previous: history), isTrue);
      await demoTurn(c.groups);
      expect(c.groups.active!.id, history.id);
      expect(c.groups.epoch, isNot(epoch));
      expect(c.groups.members.length, 1);
      expect(c.groups.links.values.every((l) => !l.localVerified), isTrue);
      expect(c.groups.active!.archived && c.groups.active!.pinned, isTrue);
      await confirmDemo(c.groups);
      await demoTurn(c.groups);
      expect(
        c.groups.active!.messages
            .where((m) => m.text == 'Keep my history')
            .length,
        1,
      );
      expect(c.groups.error, isNull);
    },
  );

  test(
    'rediscovery retains the simulated host identity and saved room within one tab',
    () async {
      await c.groups.discover();
      await demoTurn(c.groups);
      await c.groups.join('demo-group');
      await confirmDemo(c.groups);
      final first = c.groups.active!, epoch = c.groups.epoch;
      await c.groups.stop();
      await c.groups.discover();
      await demoTurn(c.groups);
      await c.groups.join('demo-group');
      await demoTurn(c.groups);
      expect(c.groups.active, isNull);
      await confirmDemo(c.groups);
      expect(c.groups.active!.id, first.id);
      expect(c.groups.active!.host, first.host);
      expect(c.groups.epoch, isNot(epoch));
      expect(c.groups.histories.length, 1);
    },
  );

  test(
    'archived demo history remains searchable with drafts and survives validated demo backup imports',
    () async {
      await c.groups.host('Room');
      await confirmDemo(c.groups);
      await c.groups.sendText('Find my demo needle');
      await demoTurn(c.groups);
      final id = c.groups.active!.id;
      await c.drafts.load(id, group: true);
      c.drafts.setText(id, 'Unfinished', group: true);
      await c.drafts.settled;
      await c.groups.setPinned(id, true);
      await c.groups.setArchived(id, true);
      final search = ChatSearchController(c, debounce: Duration.zero);
      addTearDown(search.dispose);
      search.setQuery('needle');
      await demoTurn(c.groups);
      expect(search.groupResults.messages.single.group.archived, isTrue);
      final archive = await BackupData.parse(
        (await c.backupSnapshot()).toJson(),
      );
      expect(archive.demo, isTrue);
      expect(archive.toJson()['version'], 8);
      final destination = DemoStore();
      await destination.open();
      await destination.importBackup(archive);
      final imported = (await destination.groupHistories()).single;
      expect(imported.pinned && imported.archived, isTrue);
      expect(await destination.groupDraft(id), 'Unfinished');
      expect(
        imported.messages.any((m) => m.text == 'Find my demo needle'),
        isTrue,
      );
      await c.groups.delete(id);
      await demoTurn(c.groups);
      expect(search.groupResults.messages, isEmpty);
    },
  );

  test(
    'independent demo tabs have separate worlds, identities and data; a new demo starts empty',
    () async {
      await c.groups.host('Private room');
      await confirmDemo(c.groups);
      final second = createDemoController();
      addTearDown(second.dispose);
      await second.initialize();
      expect(second.groups.histories, isEmpty);
      expect(second.groups.selfId, isNot(c.groups.selfId));
      await second.groups.discover();
      await demoTurn(second.groups);
      expect(second.groups.nearby.single['title'], isNot('Private room'));
      expect(second.groups.active, isNull);
    },
  );

  test(
    'switching to direct chats ends the demo room and cannot emit old group replies',
    () async {
      await c.groups.host('Room');
      await confirmDemo(c.groups);
      await c.groups.sendText('Before switching');
      await c.start();
      await demoTurn(c.groups);
      expect(c.groups.running, isFalse);
      expect(await c.connect(const Peer('demo-ava', 'Ava')), isTrue);
      await demoTurn(c.groups);
      await c.confirmCode();
      await demoTurn(c.groups);
      expect(c.ready, isTrue);
      expect(c.groups.active, isNull);
      expect(await c.groups.host('New room'), isTrue);
      await demoTurn(c.groups);
      expect(c.ready, isFalse);
      expect(c.groups.active!.messages, isEmpty);
      expect(c.groups.members.length, 1);
    },
  );

  test(
    'images and files use the existing signed transfer and per-member completion receipts',
    () async {
      await c.groups.host('Attachments');
      await confirmDemo(c.groups);
      expect(c.groups.images.available && c.groups.files.available, isTrue);
      final png = await testImage(size: 8);
      expect(await c.groups.images.send(png), isTrue);
      await demoTurn(c.groups, turns: 70);
      final image = c.groups.active!.messages.singleWhere(
        (m) => m.image != null,
      );
      expect(image.imageBytes, png);
      expect(image.receipts.values.every((s) => s == 'received'), isTrue);
      expect(
        await c.groups.files.send(
          SelectedFile('demo-notes.txt', Uint8List.fromList([1, 2, 3])),
        ),
        isTrue,
      );
      await demoTurn(c.groups, turns: 70);
      final file = c.groups.active!.messages.singleWhere((m) => m.file != null);
      expect(file.fileBytes, [1, 2, 3]);
      expect(file.receipts.values.every((s) => s == 'received'), isTrue);
      expect(c.groups.error, isNull);
    },
  );

  test(
    'background controls stay simulated and releasing a demo room clears their active state',
    () async {
      await c.background.initialize();
      await c.setBackgroundEnabled(true);
      expect(c.background.isDemo, isTrue);
      expect(c.background.platform, isA<MemoryBackgroundPlatform>());
      await c.groups.host('Room');
      await confirmDemo(c.groups);
      expect(c.background.active, isTrue);
      await c.groups.stop();
      await demoTurn(c.groups);
      expect(c.background.active, isFalse);
    },
  );

  test(
    'transport disposal cancels initialization and forbids new demo sessions',
    () async {
      final transport = DemoGroupTransport();
      final work = transport.host('You', 'Room');
      await transport.dispose();
      await work;
      await expectLater(transport.discover('You'), throwsStateError);
      await expectLater(transport.send('missing', 'frame'), throwsStateError);
    },
  );
}
