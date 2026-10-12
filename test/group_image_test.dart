import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/chat_image.dart';
import 'package:local_chat/services/group_controller.dart';
import 'package:local_chat/services/image_files.dart';
import 'group_test_support.dart';
import 'group_controller_test.dart' show FailingGroupStore;
import 'image_test_support.dart';

class GroupPicker implements ImageFiles {
  final result = Completer<Uint8List?>();
  @override
  Future<Uint8List?> pick() => result.future;
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
    text: 'Image',
    targets: host.members.map((m) => m.id).toList(),
    imageBytes: bytes,
  );
  Future<void> offer(GroupController sender, GroupText message) async {
    final link = sender.links.values.single;
    await sender.transport.send(
      link.id,
      jsonEncode(
        await link.session.encrypt({
          'type': 'groupImageOffer',
          'id': message.id,
          'timestamp': message.timestamp,
          'message': message.envelope,
        }),
      ),
    );
    await net.settle();
  }

  setUp(() async {
    bytes = await testImage();
    net = GroupNetwork();
    host = await net.phone('Host');
    alice = await net.phone('Alice');
    bob = await net.phone('Bob');
    await host.host('Images');
    await net.join(alice);
    await net.join(bob);
  });
  tearDown(() => net.close());
  test(
    'signed guest upload stores before host relay and completes each recipient, alongside text',
    () async {
      expect(alice.images.canSend, isTrue);
      expect(await alice.images.send(bytes), isTrue);
      await alice.sendText('Text beside an image');
      await until(
        () => alice.active!.messages
            .where((m) => m.image != null)
            .single
            .receipts
            .values
            .every((s) => s == 'received'),
      );
      for (final c in [host, alice, bob]) {
        final m = c.active!.messages.singleWhere((m) => m.image != null);
        expect(m.author, alice.selfId);
        expect(m.imageBytes, bytes);
        await GroupText.parse(m.toJson());
        expect(
          c.active!.messages.any((m) => m.text == 'Text beside an image'),
          isTrue,
        );
        final frames = (c.transport as FakeGroupTransport).frames;
        expect(frames.every((f) => utf8.encode(f).length <= 65536), isTrue);
        expect(frames.join(), isNot(contains('image/png')));
      }
      expect(bob.active!.unread, 2);
    },
  );
  test(
    'host image has individual received receipts and retained offline bytes',
    () async {
      await host.images.send(bytes);
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
        expect(history.messages.single.imageBytes, bytes);
      }
    },
  );
  test(
    'locking a recipient declines its image while other phones receive it',
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
      await alice.images.send(bytes);
      await until(
        () =>
            alice.active!.messages.single.receipts[bob.selfId] == 'unconfirmed',
      );
      expect(host.active!.messages.single.imageBytes, bytes);
      expect(alice.active!.messages.single.receipts[host.selfId], 'received');
      expect(bob.active!.messages, isEmpty);
    },
  );
  test(
    'sender cancellation discards upload, leaves source saved and never resumes',
    () async {
      (host.transport as FakeGroupTransport).dropOutgoing = true;
      await alice.images.send(bytes);
      await net.settle();
      expect(host.images.progress, isNotEmpty);
      await alice.images.cancelByUser();
      await net.settle();
      expect(host.active!.messages, isEmpty);
      expect(bob.active!.messages, isEmpty);
      expect(
        alice.active!.messages.single.receipts[host.selfId],
        'unconfirmed',
      );
      expect(alice.images.progress, isEmpty);
      (host.transport as FakeGroupTransport).dropOutgoing = false;
      await net.settle();
      expect(host.active!.messages, isEmpty);
    },
  );
  test(
    'membership changes cancel an active image and new members receive no old image',
    () async {
      await host.images.send(bytes);
      await until(
        () => host.active!.messages.single.receipts.values.every(
          (s) => s == 'received',
        ),
      );
      final newcomer = await net.phone('Newcomer');
      await net.join(newcomer);
      expect(newcomer.active!.messages, isEmpty);
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await host.images.send(bytes);
      await net.settle();
      await bob.stop();
      await net.settle();
      expect(host.images.progress, isEmpty);
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
      await alice.images.send(bytes);
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
        imageTimeout: const Duration(milliseconds: 300),
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
      await alice.images.send(bytes);
      await until(
        () =>
            alice.active!.messages.single.receipts[bob.selfId] == 'unconfirmed',
      );
      expect(alice.active!.messages.single.receipts[host.selfId], 'received');
      expect(bob.active!.messages, isEmpty);
    },
  );
  test('legacy group members keep text but disable group images', () async {
    final legacy = await net.phone('Legacy', supportsImages: false);
    await net.join(legacy);
    for (final c in [host, alice, bob, legacy]) {
      expect(c.images.canSend, isFalse);
    }
    expect(await alice.images.send(bytes), isFalse);
    expect(await legacy.sendText('Legacy text'), isTrue);
    await net.settle();
    expect(host.active!.messages.single.text, 'Legacy text');
  });
  test(
    'author impersonation and modified image signatures close only the bad link',
    () async {
      final forged = await signed(bob);
      await offer(alice, forged);
      expect(alice.connected, isFalse);
      expect(host.connected && bob.connected, isTrue);
      expect(host.active!.messages, isEmpty);
      final altered = await signed(bob);
      (altered.envelope['image'] as Map)['digest'] = '0' * 64;
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
        imageFiles: picker,
      );
      await host.host('Picker');
      await net.join(alice);
      final picking = alice.images.pick();
      accessible = false;
      await alice.accessChanged();
      picker.result.complete(bytes);
      await picking;
      expect(alice.images.pendingGroup, alice.active!.id);
      expect(await alice.images.review(alice.active!.id), isNull);
      accessible = true;
      await alice.accessChanged();
      final prepared = await alice.images.review(alice.active!.id);
      expect(prepared, isNotNull);
      expect(host.active!.messages, isEmpty);
      await alice.images.send(prepared!);
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
      text: 'Image',
      targets: [host.selfId!, alice.selfId!],
      imageBytes: bytes,
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
              'type': 'groupImageChunk',
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
          await link.session.encrypt({
            'type': 'groupImageComplete',
            'id': m.id,
          }),
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
      await alice.images.send(bytes);
      await until(
        () => alice.active!.messages.single.receipts[host.selfId] == 'received',
      );
      expect(alice.images.waiting, isTrue);
      accessible = false;
      await alice.accessChanged();
      await net.settle();
      expect(host.images.progress, isEmpty);
      expect(bob.images.progress, isEmpty);
      expect(alice.active!.messages.single.receipts[bob.selfId], 'unconfirmed');
      accessible = true;
      await alice.accessChanged();
      await net.settle();
      expect(host.active!.messages.single.imageBytes, bytes);
      expect(bob.active!.messages, isEmpty);
    },
  );
  test('delete while picker is open ignores its late result', () async {
    await net.close();
    net = GroupNetwork();
    final picker = GroupPicker();
    host = await net.phone('Host', imageFiles: picker);
    alice = await net.phone('Alice');
    await host.host('Deleted');
    await net.join(alice);
    final picking = host.images.pick();
    await host.delete(host.active!.id);
    picker.result.complete(bytes);
    await picking;
    expect(host.images.pendingGroup, isNull);
    expect(host.histories, isEmpty);
  });
  test(
    'images cannot send before both fresh confirmations or beyond byte bounds',
    () async {
      final guest = await net.phone('Guest');
      await net.join(guest, verify: false);
      expect(await guest.images.send(bytes), isFalse);
      expect(await alice.images.send(Uint8List(imageMaxBytes + 1)), isFalse);
      expect(host.active!.messages, isEmpty);
    },
  );
}
