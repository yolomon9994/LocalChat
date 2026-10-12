import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/services/group_controller.dart';
import 'package:local_chat/services/chat_files.dart';
import 'group_test_support.dart';
import 'group_controller_test.dart' show FailingGroupStore;
import 'group_file_test_support.dart';
import 'image_test_support.dart';
import 'package:local_chat/demo/demo_store.dart';

class DelayedGroupStore extends DemoStore {
  Completer<void>? gate;
  @override
  Future<List<GroupHistory>> groupHistories() async {
    await gate?.future;
    return super.groupHistories();
  }
}

class GroupPicker implements ChatFiles {
  final result = Completer<SelectedFile?>();
  @override
  Future<SelectedFile?> pick() => result.future;
  @override
  Future<bool> save(Uint8List bytes, String name) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupNetwork net;
  late GroupController host, alice, bob;
  late Uint8List bytes;
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await net.settle();
    }
    expect(done(), isTrue);
  }

  Future<GroupText> signed(GroupController author) => GroupText.create(
    author.store.identity,
    author.store.name,
    group: host.active!.id,
    host: host.selfPublic!,
    epoch: host.epoch!,
    view: host.view,
    text: 'File',
    targets: host.members.map((m) => m.id).toList(),
    fileBytes: bytes,
    fileName: '../../report?.pdf',
  );
  Future<void> offer(GroupController sender, GroupText message) async {
    final link = sender.links.values.single;
    await sender.transport.send(
      link.id,
      jsonEncode(
        await link.session.encrypt({
          'type': 'groupFileOffer',
          'id': message.id,
          'timestamp': message.timestamp,
          'message': message.envelope,
        }),
      ),
    );
    await net.settle();
  }

  setUp(() async {
    bytes = Uint8List.fromList(List.generate(32000, (i) => i % 251));
    net = GroupNetwork();
    host = await net.phone('Host');
    alice = await net.phone('Alice');
    bob = await net.phone('Bob');
    await host.host('Files');
    await net.join(alice);
    await net.join(bob);
  });
  tearDown(() => net.close());
  test(
    'signed guest upload stores before host relay and completes each recipient, alongside text',
    () async {
      expect(alice.files.canSend, isTrue);
      expect(
        await alice.files.send(SelectedFile('../../report?.pdf', bytes)),
        isTrue,
      );
      await alice.sendText('Text beside a file');
      await until(
        () => alice.active!.messages
            .where((m) => m.file != null)
            .single
            .receipts
            .values
            .every((s) => s == 'received'),
      );
      for (final c in [host, alice, bob]) {
        final m = c.active!.messages.singleWhere((m) => m.file != null);
        expect(m.author, alice.selfId);
        expect(m.fileBytes, bytes);
        expect(m.file!.name, ChatFile.safeName('../../report?.pdf'));
        expect(m.file!.length, bytes.length);
        await GroupText.parse(m.toJson());
        expect(
          c.active!.messages.any((m) => m.text == 'Text beside a file'),
          isTrue,
        );
        final frames = (c.transport as FakeGroupTransport).frames;
        expect(frames.every((f) => utf8.encode(f).length <= 65536), isTrue);
        expect(frames.join(), isNot(contains('application/octet-stream')));
      }
      expect(bob.active!.unread, 2);
    },
  );
  test(
    'host file has individual received receipts and retained offline bytes',
    () async {
      await host.files.send(SelectedFile('../../report?.pdf', bytes));
      await until(
        () => host.active!.messages.single.receipts.values.every(
          (s) => s == 'received',
        ),
      );
      final id = host.active!.id;
      await host.stop();
      await net.settle();
      for (final c in [host, alice, bob]) {
        final history = (await c.store.groupHistories()).singleWhere(
          (g) => g.id == id,
        );
        expect(history.messages.single.fileBytes, bytes);
      }
    },
  );
  test(
    'locking a recipient declines its file while other phones receive it',
    () async {
      await net.close();
      net = GroupNetwork();
      var accessible = true;
      host = await net.phone('Host');
      alice = await net.phone('Alice');
      bob = await net.phone('Bob', canAct: () => accessible);
      await host.host('Privacy');
      await net.join(alice);
      await net.join(bob);
      accessible = false;
      await bob.accessChanged();
      await alice.files.send(SelectedFile('../../report?.pdf', bytes));
      await until(
        () =>
            alice.active!.messages.single.receipts[bob.selfId] == 'unconfirmed',
      );
      expect(host.active!.messages.single.fileBytes, bytes);
      expect(alice.active!.messages.single.receipts[host.selfId], 'received');
      expect(bob.active!.messages, isEmpty);
    },
  );
  test(
    'sender cancellation discards upload, leaves source saved and never resumes',
    () async {
      (host.transport as FakeGroupTransport).dropOutgoing = true;
      await alice.files.send(SelectedFile('../../report?.pdf', bytes));
      await net.settle();
      expect(host.files.progress, isNotEmpty);
      await alice.files.cancelByUser();
      await net.settle();
      expect(host.active!.messages, isEmpty);
      expect(bob.active!.messages, isEmpty);
      expect(
        alice.active!.messages.single.receipts[host.selfId],
        'unconfirmed',
      );
      expect(alice.files.progress, isEmpty);
      (host.transport as FakeGroupTransport).dropOutgoing = false;
      await net.settle();
      expect(host.active!.messages, isEmpty);
    },
  );
  test(
    'membership changes cancel an active file and new members receive no old file',
    () async {
      await host.files.send(SelectedFile('../../report?.pdf', bytes));
      await until(
        () => host.active!.messages.single.receipts.values.every(
          (s) => s == 'received',
        ),
      );
      final newcomer = await net.phone('Newcomer');
      await net.join(newcomer);
      expect(newcomer.active!.messages, isEmpty);
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await host.files.send(SelectedFile('../../report?.pdf', bytes));
      await net.settle();
      await bob.stop();
      await net.settle();
      expect(host.files.progress, isEmpty);
      expect(host.active!.messages.last.receipts[bob.selfId], 'unconfirmed');
      expect(host.connected && alice.connected, isTrue);
    },
  );
  test(
    'host storage failure never acknowledges or forwards an upload',
    () async {
      await net.close();
      net = GroupNetwork();
      final store = FailingGroupStore();
      host = await net.phone('Host', store: store);
      alice = await net.phone('Alice');
      bob = await net.phone('Bob');
      await host.host('Storage');
      await net.join(alice);
      await net.join(bob);
      store.fail = true;
      await alice.files.send(SelectedFile('../../report?.pdf', bytes));
      await net.settle();
      expect(host.active!.messages, isEmpty);
      expect(bob.active!.messages, isEmpty);
      expect(
        alice.histories.single.messages.single.receipts[host.selfId],
        'unconfirmed',
      );
    },
  );
  test(
    'missing recipient receipts time out without marking it received',
    () async {
      await net.close();
      net = GroupNetwork();
      host = await net.phone(
        'Host',
        fileTimeout: const Duration(milliseconds: 300),
      );
      alice = await net.phone(
        'Alice',
        receiptTimeout: const Duration(milliseconds: 300),
      );
      bob = await net.phone('Bob');
      await host.host('Timeout');
      await net.join(alice);
      await net.join(bob);
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await alice.files.send(SelectedFile('../../report?.pdf', bytes));
      await until(
        () =>
            alice.active!.messages.single.receipts[bob.selfId] == 'unconfirmed',
      );
      expect(alice.active!.messages.single.receipts[host.selfId], 'received');
      expect(bob.active!.messages, isEmpty);
    },
  );
  test('legacy group members keep text but disable group files', () async {
    final legacy = await net.phone('Legacy', supportsFiles: false);
    await net.join(legacy);
    for (final c in [host, alice, bob, legacy]) {
      expect(c.files.canSend, isFalse);
    }
    expect(
      await alice.files.send(SelectedFile('../../report?.pdf', bytes)),
      isFalse,
    );
    expect(await legacy.sendText('Legacy text'), isTrue);
    await net.settle();
    expect(host.active!.messages.single.text, 'Legacy text');
  });
  test(
    'author impersonation and modified file signatures close only the bad link',
    () async {
      final forged = await signed(bob);
      await offer(alice, forged);
      expect(alice.connected, isFalse);
      expect(host.connected && bob.connected, isTrue);
      expect(host.active!.messages, isEmpty);
      final altered = await signed(bob);
      (altered.envelope['file'] as Map)['digest'] = '0' * 64;
      await offer(bob, altered);
      expect(bob.connected, isFalse);
      expect(host.active!.messages, isEmpty);
    },
  );
  test('replay from an old epoch cannot persist', () async {
    final old = await signed(alice);
    final history = host.active!;
    await host.stop();
    await net.settle();
    await host.host(history.title, previous: history);
    await net.join(alice);
    await net.join(bob);
    await offer(alice, old);
    expect(host.active!.messages, isEmpty);
    expect(alice.connected, isFalse);
  });
  test(
    'picker returning locked stays sealed and requires explicit send after unlock',
    () async {
      await net.close();
      net = GroupNetwork();
      var accessible = true;
      final picker = GroupPicker();
      host = await net.phone('Host');
      alice = await net.phone(
        'Alice',
        canAct: () => accessible,
        chatFiles: picker,
      );
      await host.host('Picker');
      await net.join(alice);
      final picking = alice.files.pick();
      accessible = false;
      await alice.accessChanged();
      picker.result.complete(SelectedFile('report.pdf', bytes));
      await picking;
      expect(alice.files.pendingGroup, alice.active!.id);
      expect(await alice.files.review(alice.active!.id), isNull);
      accessible = true;
      await alice.accessChanged();
      final prepared = await alice.files.review(alice.active!.id);
      expect(prepared, isNotNull);
      expect(host.active!.messages, isEmpty);
      await alice.files.send(prepared!);
      await until(() => host.active!.messages.isNotEmpty);
    },
  );
  test('signed incomplete recipient list is rejected', () async {
    final m = await GroupText.create(
      alice.store.identity,
      alice.store.name,
      group: host.active!.id,
      host: host.selfPublic!,
      epoch: host.epoch!,
      view: host.view,
      text: 'File',
      targets: [host.selfId!, alice.selfId!],
      fileBytes: bytes,
      fileName: '../../report?.pdf',
    );
    await offer(alice, m);
    expect(host.active!.messages, isEmpty);
    expect(alice.connected, isFalse);
    expect(bob.connected, isTrue);
  });
  test(
    'corrupt chunk content cannot persist or relay despite a valid signed offer',
    () async {
      final m = await signed(alice);
      // This manual sender does not run a transfer engine to consume ready/ACKs.
      (host.transport as FakeGroupTransport).dropOutgoing = true;
      await offer(alice, m);
      final corrupt = Uint8List.fromList(bytes)..[40] ^= 1;
      final link = alice.links.values.single;
      for (
        var offset = 0, index = 0;
        offset < corrupt.length;
        offset += 12288, index++
      ) {
        final end = (offset + 12288).clamp(0, corrupt.length);
        await alice.transport.send(
          link.id,
          jsonEncode(
            await link.session.encrypt({
              'type': 'groupFileChunk',
              'id': m.id,
              'index': index,
              'data': base64Encode(corrupt.sublist(offset, end)),
            }),
          ),
        );
        await net.settle();
      }
      await alice.transport.send(
        link.id,
        jsonEncode(
          await link.session.encrypt({'type': 'groupFileComplete', 'id': m.id}),
        ),
      );
      await net.settle();
      expect(host.active!.messages, isEmpty);
      expect(bob.active!.messages, isEmpty);
    },
  );
  test(
    'background author aborts unfinished relays after host upload receipt',
    () async {
      await net.close();
      net = GroupNetwork();
      var accessible = true;
      host = await net.phone('Host');
      alice = await net.phone('Alice', canAct: () => accessible);
      bob = await net.phone('Bob');
      await host.host('Background');
      await net.join(alice);
      await net.join(bob);
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await alice.files.send(SelectedFile('../../report?.pdf', bytes));
      await until(
        () => alice.active!.messages.single.receipts[host.selfId] == 'received',
      );
      expect(alice.files.waiting, isTrue);
      accessible = false;
      await alice.accessChanged();
      await net.settle();
      expect(host.files.progress, isEmpty);
      expect(bob.files.progress, isEmpty);
      expect(alice.active!.messages.single.receipts[bob.selfId], 'unconfirmed');
      accessible = true;
      await alice.accessChanged();
      await net.settle();
      expect(host.active!.messages.single.fileBytes, bytes);
      expect(bob.active!.messages, isEmpty);
    },
  );
  test(
    'file and image transfers can interleave on the same encrypted links',
    () async {
      final image = await testImage();
      await alice.files.send(SelectedFile('report.pdf', bytes));
      await alice.images.send(image);
      await until(
        () =>
            alice.active!.messages.length == 2 &&
            alice.active!.messages.every(
              (m) => m.receipts.values.every((s) => s == 'received'),
            ),
      );
      for (final c in [host, alice, bob]) {
        expect(
          c.active!.messages.singleWhere((m) => m.file != null).fileBytes,
          bytes,
        );
        expect(
          c.active!.messages.singleWhere((m) => m.image != null).imageBytes,
          image,
        );
      }
    },
  );
  test(
    'image-capable older members disable files but keep images and text',
    () async {
      final legacy = await net.phone('Older image build', supportsFiles: false);
      await net.join(legacy);
      expect(alice.files.available, isFalse);
      expect(alice.images.canSend, isTrue);
      await alice.images.send(await testImage());
      await until(() => legacy.active!.messages.isNotEmpty);
      expect(legacy.active!.messages.single.image, isNotNull);
    },
  );
  test(
    'offline export verifies stored bytes, respects lock, cancellation and provider errors',
    () async {
      await net.close();
      net = GroupNetwork();
      var accessible = true;
      final picker = MemoryGroupFiles(null);
      host = await net.phone('Host');
      alice = await net.phone(
        'Alice',
        chatFiles: picker,
        canAct: () => accessible,
      );
      await host.host('Export');
      await net.join(alice);
      await host.files.send(SelectedFile('../report?.pdf', bytes));
      await until(() => alice.active!.messages.isNotEmpty);
      final id = alice.active!.id, m = alice.active!.messages.single;
      expect(picker.saved, isEmpty);
      await alice.stop();
      await net.settle();
      expect(await alice.files.saveToPhone(id, m), isTrue);
      expect(picker.saved.single.name, ChatFile.safeName('../report?.pdf'));
      expect(picker.saved.single.bytes, bytes);
      accessible = false;
      await alice.accessChanged();
      expect(await alice.files.saveToPhone(id, m), isFalse);
      expect(picker.saved.length, 1);
      accessible = true;
      await alice.accessChanged();
      picker.result = false;
      expect(await alice.files.saveToPhone(id, m), isFalse);
      expect(picker.saved.length, 1);
      picker.fail = true;
      expect(await alice.files.saveToPhone(id, m), isFalse);
      expect(alice.error, contains('Could not save'));
      await alice.delete(id);
      picker.fail = false;
      picker.result = true;
      expect(await alice.files.saveToPhone(id, m), isFalse);
    },
  );
  test(
    'recipient storage failure keeps its receipt unconfirmed after host storage',
    () async {
      await net.close();
      net = GroupNetwork();
      final store = FailingGroupStore();
      host = await net.phone('Host');
      alice = await net.phone('Alice');
      bob = await net.phone('Bob', store: store);
      await host.host('Recipient storage');
      await net.join(alice);
      await net.join(bob);
      store.fail = true;
      await alice.files.send(SelectedFile('report.pdf', bytes));
      await net.settle();
      expect(alice.active!.messages.single.receipts[host.selfId], 'received');
      expect(alice.active!.messages.single.receipts[bob.selfId], 'unconfirmed');
      expect(bob.histories.single.messages, isEmpty);
    },
  );
  test(
    'locking while export reads history prevents invoking the destination picker',
    () async {
      await net.close();
      net = GroupNetwork();
      var accessible = true;
      final store = DelayedGroupStore(), picker = MemoryGroupFiles(null);
      host = await net.phone('Host');
      alice = await net.phone(
        'Alice',
        store: store,
        chatFiles: picker,
        canAct: () => accessible,
      );
      await host.host('Export gate');
      await net.join(alice);
      await host.files.send(SelectedFile('report.pdf', bytes));
      await until(() => alice.active!.messages.isNotEmpty);
      final id = alice.active!.id, message = alice.active!.messages.single;
      await alice.stop();
      await net.settle();
      store.gate = Completer<void>();
      final saving = alice.files.saveToPhone(id, message);
      accessible = false;
      await alice.accessChanged();
      store.gate!.complete();
      expect(await saving, isFalse);
      expect(picker.saved, isEmpty);
      store.gate = null;
    },
  );
  test('delete while picker is open ignores its late result', () async {
    await net.close();
    net = GroupNetwork();
    final picker = GroupPicker();
    host = await net.phone('Host', chatFiles: picker);
    alice = await net.phone('Alice');
    await host.host('Deleted');
    await net.join(alice);
    final picking = host.files.pick();
    await host.delete(host.active!.id);
    picker.result.complete(SelectedFile('report.pdf', bytes));
    await picking;
    expect(host.files.pendingGroup, isNull);
    expect(host.histories, isEmpty);
  });
  test(
    'files cannot send before both fresh confirmations or beyond byte bounds',
    () async {
      final guest = await net.phone('Guest');
      await net.join(guest, verify: false);
      expect(
        await guest.files.send(SelectedFile('../../report?.pdf', bytes)),
        isFalse,
      );
      expect(
        await alice.files.send(
          SelectedFile('large.bin', Uint8List(fileMaxBytes + 1)),
        ),
        isFalse,
      );
      expect(
        await alice.files.send(SelectedFile('empty.bin', Uint8List(0))),
        isFalse,
      );
      expect(host.active!.messages, isEmpty);
    },
  );
}
