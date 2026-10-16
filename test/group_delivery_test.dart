import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/services/group_controller.dart';
import 'package:local_chat/services/group_delivery.dart';
import 'package:local_chat/services/chat_files.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/core/group_models.dart' show GroupHistory;
import 'group_test_support.dart';
import 'group_controller_test.dart' show FailingGroupStore;
import 'image_test_support.dart';

class DeliverySaveStore extends DemoStore {
  void Function()? afterSave;
  @override
  Future<void> saveGroupHistory(GroupHistory group) async {
    await super.saveGroupHistory(group);
    afterSave?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupNetwork net;
  late GroupController host, alice, bob;
  setUp(() async {
    net = GroupNetwork();
    host = await net.phone('Host');
    alice = await net.phone('Alice');
    bob = await net.phone('Bob');
    await host.host('Delivery');
    await net.join(alice);
    await net.join(bob);
  });
  tearDown(() => net.close());

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await net.settle();
    }
    expect(done(), isTrue);
  }

  test(
    'Departing recipient resolves immediately on host and guest author without losing confirmed receipts',
    () async {
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await alice.sendText('May already have arrived');
      await net.settle();
      await alice.store.saveGroupDraft(alice.active!.id, 'Keep my draft');
      final before = alice.active!.messages.single;
      final updated = alice.active!.updated;
      expect(before.receipts[bob.selfId], 'pending');
      expect(bob.active!.messages.single.text, before.text);
      await bob.stop();
      await net.settle();
      for (final c in [host, alice]) {
        final m = c.active!.messages.single;
        expect(m.receipts[bob.selfId], 'unconfirmed');
        expect(m.receipts[host.selfId], 'received');
        expect(m.receipts[alice.selfId], 'received');
        expect(
          c.delivery.status(c.active!.id, m, bob.selfId!),
          contains('member disconnected or left'),
        );
        expect(c.delivery.name(c.active!.id, bob.selfId!), 'Bob');
        expect(m.envelope, before.envelope);
      }
      expect(alice.active!.updated, updated);
      expect(await alice.store.groupDraft(alice.active!.id), 'Keep my draft');
      expect(alice.canSend, isTrue);
    },
  );

  test(
    'Departure frees all exhausted text receipt slots without resending earlier messages',
    () async {
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      for (var i = 0; i < 4; i++) {
        expect(await host.sendText('Pending $i'), isTrue);
        await net.settle();
      }
      expect(host.canSend, isFalse);
      await bob.stop();
      await net.settle();
      expect(host.canSend, isTrue);
      expect(await host.sendText('New message to remaining members'), isTrue);
      await net.settle();
      expect(host.active!.messages.length, 5);
      expect(alice.active!.messages.length, 5);
      expect(
        host.active!.messages.take(4).map((m) => m.receipts[bob.selfId]),
        everyElement('unconfirmed'),
      );
    },
  );
  test(
    'Host removal has a local explanation and preserves another pending recipient',
    () async {
      (alice.transport as FakeGroupTransport).dropOutgoing = true;
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await host.sendText('Two pending recipients');
      await net.settle();
      await host.reject(
        host.links.values.firstWhere((l) => l.session.peerId == bob.selfId).id,
      );
      await net.settle();
      final m = host.active!.messages.single;
      expect(m.receipts[bob.selfId], 'unconfirmed');
      expect(m.receipts[alice.selfId], 'pending');
      expect(
        host.delivery.status(host.active!.id, m, bob.selfId!),
        contains('member removed'),
      );
      expect(
        host.delivery.status(host.active!.id, m, alice.selfId!),
        'Pending confirmation',
      );
      expect(host.links.values.single.session.peerId, alice.selfId);
      expect(host.canSend, isTrue);
    },
  );

  test(
    'Host loss keeps receipt evidence, history and drafts and rejoining requires fresh confirmation',
    () async {
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await alice.sendText('Partly confirmed');
      await net.settle();
      final id = alice.active!.id;
      final previous = host.active!;
      await alice.store.saveGroupDraft(id, 'Still here');
      await host.stop();
      await net.settle();
      final saved = alice.histories.single.messages.single;
      expect(saved.receipts[host.selfId], 'received');
      expect(saved.receipts[bob.selfId], 'unconfirmed');
      expect(
        alice.delivery.status(id, saved, bob.selfId!),
        contains('host connection ended'),
      );
      expect(alice.delivery.ending(id), GroupDeliveryReason.hostDisconnected);
      expect(await alice.store.groupDraft(id), 'Still here');
      expect(await alice.sendText('Offline'), isFalse);
      await host.host(previous.title, previous: host.histories.single);
      await net.join(alice, verify: false);
      expect(alice.connected, isFalse);
      expect(alice.links.values.single.localVerified, isFalse);
      expect(alice.histories.single.messages.length, 1);
      expect(host.active!.messages.length, 1);
    },
  );

  test(
    'Saved statuses survive controller restart; session explanations never enter backup or signed records',
    () async {
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await host.sendText('Saved receipt state');
      await net.settle();
      await bob.stop();
      await net.settle();
      await host.stop();
      await net.settle();
      final original = host.histories.single;
      final store = host.store as DemoStore;
      final archive = await store.exportBackup();
      expect(
        jsonEncode(archive.toJson()),
        isNot(contains('member disconnected or left')),
      );
      expect(
        original.messages.single.toJson().keys,
        unorderedEquals(['envelope', 'receipts', 'read']),
      );
      net.controllers.remove(host);
      host.dispose();
      host = await net.phone('Host', store: store);
      final restored = host.histories.single.messages.single;
      expect(restored.receipts[bob.selfId], 'unconfirmed');
      expect(restored.receipts[alice.selfId], 'received');
      expect(
        host.delivery.status(original.id, restored, bob.selfId!),
        'Unconfirmed: no receipt available',
      );
      expect(host.delivery.ending(original.id), isNull);
    },
  );

  test(
    'Timeout explains uncertainty and a later authenticated receipt replaces it',
    () async {
      await net.close();
      net = GroupNetwork();
      host = await net.phone(
        'Host',
        receiptTimeout: const Duration(milliseconds: 250),
      );
      alice = await net.phone('Alice');
      await host.host('Timeout');
      await net.join(alice);
      (alice.transport as FakeGroupTransport).dropOutgoing = true;
      await host.sendText('Receipt delayed');
      await until(
        () =>
            host.active!.messages.single.receipts[alice.selfId] ==
            'unconfirmed',
      );
      final m = host.active!.messages.single;
      expect(
        host.delivery.status(host.active!.id, m, alice.selfId!),
        contains('confirmation timed out'),
      );
      (alice.transport as FakeGroupTransport).dropOutgoing = false;
      // Deliver the original delayed encrypted ACK. Creating a second one would
      // skip a frame sequence, which the live session correctly rejects.
      final hostTransport = host.transport as FakeGroupTransport;
      hostTransport.bus.add({
        'type': 'frame',
        'link': host.links.keys.single,
        'frame': (alice.transport as FakeGroupTransport).frames.last,
        'generation': hostTransport.generation,
      });
      await net.settle();
      expect(
        host.delivery.status(
          host.active!.id,
          host.active!.messages.single,
          alice.selfId!,
        ),
        'Received',
      );
      await alice.stop();
      await net.settle();
      expect(host.active!.messages.single.receipts[alice.selfId], 'received');
    },
  );

  test(
    'A failed departure-status save cannot keep a removed link or fabricate delivery evidence',
    () async {
      await net.close();
      net = GroupNetwork();
      final store = FailingGroupStore();
      host = await net.phone('Host', store: store);
      alice = await net.phone('Alice');
      await host.host('Storage failure');
      await net.join(alice);
      (alice.transport as FakeGroupTransport).dropOutgoing = true;
      await host.sendText('Uncertain');
      await net.settle();
      store.fail = true;
      await host.reject(host.links.keys.single);
      await net.settle();
      expect(host.links, isEmpty);
      expect(host.members.length, 1);
      expect(alice.connected, isFalse);
      expect((host.transport as FakeGroupTransport).links, isEmpty);
      expect(host.active!.messages.single.receipts[alice.selfId], 'pending');
      expect(
        host.delivery.status(
          host.active!.id,
          host.active!.messages.single,
          alice.selfId!,
        ),
        'Pending confirmation',
      );
      expect(host.error, contains('could not save delivery status'));
    },
  );

  for (final file in [false, true]) {
    final kind = file ? 'file' : 'image';
    test(
      '$kind interrupted at local acceptance does not claim a timeout or transmit',
      () async {
        await net.close();
        net = GroupNetwork();
        var accessible = true;
        final store = DeliverySaveStore();
        host = await net.phone('Host', store: store, canAct: () => accessible);
        alice = await net.phone('Alice');
        await host.host('Interrupted acceptance');
        await net.join(alice);
        final bytes = file ? Uint8List.fromList([4, 5, 6]) : await testImage();
        store.afterSave = () => accessible = false;
        final accepted = file
            ? await host.files.send(SelectedFile('kept.bin', bytes))
            : await host.images.send(bytes);
        store.afterSave = null;
        await net.settle();
        expect(accepted, isTrue);
        final m = host.active!.messages.single;
        expect(m.receipts[alice.selfId], 'unconfirmed');
        expect(
          host.delivery.status(host.active!.id, m, alice.selfId!),
          'Unconfirmed: sending was interrupted',
        );
        expect(file ? m.fileBytes : m.imageBytes, bytes);
        expect(alice.active!.messages, isEmpty);
        expect(file ? host.files.progress : host.images.progress, isEmpty);
      },
    );
    test(
      '$kind departure keeps completed copies and receipts and cancels remaining transfer',
      () async {
        final bytes = file
            ? Uint8List.fromList(List.generate(32000, (i) => i % 251))
            : await testImage();
        Future<bool> send(GroupController c) => file
            ? c.files.send(SelectedFile('report.pdf', bytes))
            : c.images.send(bytes);
        await send(host);
        await until(
          () => host.active!.messages.single.receipts.values.every(
            (s) => s == 'received',
          ),
        );
        final complete = host.active!.messages.single;
        (bob.transport as FakeGroupTransport).dropOutgoing = true;
        await send(host);
        await until(
          () => host.active!.messages.last.receipts[alice.selfId] == 'received',
        );
        expect(host.active!.messages.last.receipts[bob.selfId], 'pending');
        await bob.stop();
        await net.settle();
        final m = host.active!.messages.last;
        expect(m.receipts[alice.selfId], 'received');
        expect(m.receipts[bob.selfId], 'unconfirmed');
        expect(
          host.delivery.status(host.active!.id, m, bob.selfId!),
          contains('member disconnected or left'),
        );
        expect(host.active!.messages.first.receipts, complete.receipts);
        expect(file ? m.fileBytes : m.imageBytes, bytes);
        expect(file ? host.files.progress : host.images.progress, isEmpty);
        expect(
          file
              ? alice.active!.messages.last.fileBytes
              : alice.active!.messages.last.imageBytes,
          bytes,
        );
        final newcomer = await net.phone('Newcomer');
        await net.join(newcomer);
        expect(newcomer.active!.messages, isEmpty);
      },
    );
    test(
      '$kind host loss preserves a confirmed host copy and leaves missing recipient uncertain',
      () async {
        final bytes = file
            ? Uint8List.fromList([1, 2, 3, 4])
            : await testImage();
        (bob.transport as FakeGroupTransport).dropOutgoing = true;
        if (file) {
          await alice.files.send(SelectedFile('saved.bin', bytes));
        } else {
          await alice.images.send(bytes);
        }
        await until(
          () =>
              alice.active!.messages.single.receipts[host.selfId] == 'received',
        );
        await host.stop();
        await net.settle();
        final m = alice.histories.single.messages.single;
        expect(m.receipts[host.selfId], 'received');
        expect(m.receipts[bob.selfId], 'unconfirmed');
        expect(
          alice.delivery.status(alice.histories.single.id, m, bob.selfId!),
          contains('host connection ended'),
        );
        expect(file ? m.fileBytes : m.imageBytes, bytes);
        expect(file ? alice.files.progress : alice.images.progress, isEmpty);
        expect(alice.connected, isFalse);
      },
    );
  }
}
