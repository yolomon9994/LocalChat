import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/group_controller.dart';
import 'group_test_support.dart';

class FailingGroupStore extends DemoStore {
  bool fail = false;
  @override
  Future<void> saveGroupHistory(GroupHistory group) async {
    if (fail) {
      fail = false;
      throw StateError('Disk full');
    }
    await super.saveGroupHistory(group);
  }
}

void main() {
  late GroupNetwork network;
  late GroupController host, alice, bob;
  setUp(() async {
    network = GroupNetwork();
    host = await network.phone('Host');
    alice = await network.phone('Alice');
    bob = await network.phone('Bob');
    await host.host('Friends');
  });
  tearDown(() => network.close());
  test(
    'eight-member cap refuses an additional guest without dropping admitted peers',
    () async {
      await network.join(alice);
      await network.join(bob);
      for (var i = 0; i < 5; i++) {
        await network.join(await network.phone('Guest $i'));
      }
      expect(host.members.length, groupLimit);
      final extra = await network.phone('Extra');
      await network.join(extra, verify: false);
      expect(extra.connected, false);
      expect(host.members.length, groupLimit);
      expect(alice.connected, true);
      expect(bob.connected, true);
    },
  );
  test(
    'unverified guests cannot send text and cannot join without both confirmations',
    () async {
      await network.join(alice);
      await network.join(bob, verify: false);
      final message = await GroupText.create(
        bob.store.identity,
        'Bob',
        group: host.active!.id,
        host: host.active!.host,
        epoch: host.epoch!,
        view: host.view,
        text: 'not verified',
        targets: [...host.members.map((m) => m.id), bob.selfId!],
      );
      final link = bob.links.values.single;
      await bob.transport.send(
        link.id,
        jsonEncode(
          await link.session.encrypt({
            'type': 'groupText',
            'message': message.envelope,
          }),
        ),
      );
      await network.settle();
      expect(host.active!.messages, isEmpty);
      expect(bob.connected, false);
      expect(alice.connected, true);
      expect(host.members.length, 2);
    },
  );
  test(
    'membership race rejects stale recipients without closing the verified link',
    () async {
      await network.join(alice);
      final stale = await GroupText.create(
        alice.store.identity,
        'Alice',
        group: host.active!.id,
        host: host.active!.host,
        epoch: host.epoch!,
        view: host.view,
        text: 'old roster',
        targets: host.members.map((m) => m.id).toList(),
      );
      await network.join(bob);
      final link = alice.links.values.single;
      await alice.transport.send(
        link.id,
        jsonEncode(
          await link.session.encrypt({
            'type': 'groupText',
            'message': stale.envelope,
          }),
        ),
      );
      await network.settle();
      expect(host.active!.messages, isEmpty);
      expect(alice.connected, true);
      expect(alice.error, contains('Membership changed'));
    },
  );
  test(
    'stop closes all links even if saving delivery uncertainty fails',
    () async {
      await network.close();
      network = GroupNetwork();
      final store = FailingGroupStore();
      host = await network.phone('Host', store: store);
      alice = await network.phone('Alice');
      await host.host('Stop');
      await network.join(alice);
      store.fail = true;
      await host.stop();
      await network.settle();
      expect(host.connected, false);
      expect(alice.connected, false);
      expect((host.transport as FakeGroupTransport).links, isEmpty);
      expect(host.histories.length, 1);
    },
  );
  test(
    'three phones require both codes, relay encrypted signed text and receipt per member',
    () async {
      await network.join(alice, verify: false);
      final h = host.links.values.single, a = alice.links.values.single;
      expect(h.session.verificationCode, a.session.verificationCode);
      expect(await alice.sendText('before verification'), false);
      await host.confirm(h.id);
      await network.settle();
      expect(host.members.length, 1);
      await alice.confirm(a.id);
      await network.settle();
      await network.join(bob);
      expect(host.members.length, 3);
      expect(alice.members.length, 3);
      expect(bob.members.length, 3);
      expect(await alice.sendText('Private سلام group text'), true);
      await network.settle();
      for (final c in [host, alice, bob]) {
        expect(c.active!.messages.single.text, 'Private سلام group text');
        expect(c.active!.messages.single.author, alice.selfId);
      }
      expect(
        alice.active!.messages.single.receipts.values,
        everyElement('received'),
      );
      expect(
        (host.transport as FakeGroupTransport).frames.join(),
        isNot(contains('Private سلام')),
      );
      expect(await host.sendText('Host message'), true);
      await network.settle();
      expect(
        host.active!.messages.last.receipts.values,
        everyElement('received'),
      );
      expect(bob.active!.messages.length, 2);
    },
  );
  test(
    'new members receive no old history; leaving changes roster and rejoining needs fresh code',
    () async {
      await network.join(alice);
      await host.sendText('before Bob');
      await network.settle();
      await network.join(bob);
      expect(bob.active!.messages, isEmpty);
      await bob.stop();
      await network.settle();
      expect(host.members.length, 2);
      expect(alice.members.length, 2);
      await host.sendText('after Bob');
      await network.settle();
      expect(bob.histories.single.messages, isEmpty);
      await network.join(bob, verify: false);
      expect(bob.connected, false);
      expect(host.members.length, 2);
      expect(bob.links.values.single.localVerified, false);
      await host.confirm(
        host.links.values.firstWhere((l) => l.session.peerId == bob.selfId).id,
      );
      await bob.confirm(bob.links.keys.single);
      await network.settle();
      await host.sendText('new for Bob');
      await network.settle();
      expect(bob.active!.messages.single.text, 'new for Bob');
    },
  );
  test(
    'a verified guest cannot impersonate another member; only offending link closes',
    () async {
      await network.join(alice);
      await network.join(bob);
      final forged = await GroupText.create(
        bob.store.identity,
        'Bob',
        group: host.active!.id,
        host: host.active!.host,
        epoch: host.epoch!,
        view: host.view,
        text: 'impersonated',
        targets: host.members.map((m) => m.id).toList(),
      );
      final link = alice.links.values.single;
      await alice.transport.send(
        link.id,
        jsonEncode(
          await link.session.encrypt({
            'type': 'groupText',
            'message': forged.envelope,
          }),
        ),
      );
      await network.settle();
      expect(host.active!.messages, isEmpty);
      expect(bob.connected, true);
      expect(host.members.length, 2);
      expect(alice.connected, false);
    },
  );
  test('unsigned modification and cross-session replay are rejected', () async {
    await network.join(alice);
    await network.join(bob);
    final message = await GroupText.create(
      alice.store.identity,
      'Alice',
      group: host.active!.id,
      host: host.active!.host,
      epoch: randomId(),
      view: host.view,
      text: 'old session',
      targets: host.members.map((m) => m.id).toList(),
    );
    final modified = {
      ...message.toJson(),
      'envelope': {...message.envelope, 'text': 'modified'},
    };
    await expectLater(GroupText.parse(modified), throwsFormatException);
    final link = alice.links.values.single;
    await alice.transport.send(
      link.id,
      jsonEncode(
        await link.session.encrypt({
          'type': 'groupText',
          'message': message.envelope,
        }),
      ),
    );
    await network.settle();
    expect(host.active!.messages, isEmpty);
    expect(bob.connected, true);
    expect(alice.connected, false);
  });
  test(
    'locked host cannot admit or originate text; admitted receiving remains unread until visible',
    () async {
      var access = true;
      await network.close();
      network = GroupNetwork();
      host = await network.phone('Host', canAct: () => access);
      alice = await network.phone('Alice');
      await host.host('Locked');
      await network.join(alice, verify: false);
      final h = host.links.values.single;
      await host.confirm(h.id);
      access = false;
      await alice.confirm(alice.links.keys.single);
      await network.settle();
      expect(host.members.length, 1);
      expect(await host.sendText('locked'), false);
      access = true;
      await host.accessChanged();
      await network.settle();
      expect(alice.connected, true);
      access = false;
      await alice.sendText('received while locked');
      await network.settle();
      expect(host.active!.unread, 1);
      expect(
        alice.active!.messages.single.receipts.values,
        everyElement('received'),
      );
      final screen = Object();
      host.setVisible(screen, host.active!.id, true);
      await host.idle;
      expect(host.active!.unread, 1);
      access = true;
      await host.accessChanged();
      expect(host.active!.unread, 0);
    },
  );
  test(
    'missing receipts become unconfirmed and host departure pauses every guest without deleting history',
    () async {
      await network.close();
      network = GroupNetwork();
      host = await network.phone('Host');
      alice = await network.phone(
        'Alice',
        receiptTimeout: const Duration(milliseconds: 250),
      );
      bob = await network.phone('Bob');
      await host.host('Receipts');
      await network.join(alice);
      await network.join(bob);
      (bob.transport as FakeGroupTransport).dropOutgoing = true;
      await alice.sendText('uncertain delivery');
      await network.settle();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await network.settle();
      expect(alice.active!.messages.single.receipts[host.selfId], 'received');
      expect(alice.active!.messages.single.receipts[bob.selfId], 'unconfirmed');
      await host.stop();
      await network.settle();
      expect(alice.connected, false);
      expect(bob.connected, false);
      expect(await alice.sendText('offline'), false);
      expect(alice.histories.single.messages.length, 1);
    },
  );
  test(
    'disk failure on host prevents ACK and relay; saved sender message becomes unconfirmed',
    () async {
      await network.close();
      network = GroupNetwork();
      final store = FailingGroupStore();
      host = await network.phone('Host', store: store);
      alice = await network.phone('Alice');
      bob = await network.phone('Bob');
      await host.host('Disk');
      await network.join(alice);
      await network.join(bob);
      store.fail = true;
      await alice.sendText('not persisted on host');
      await network.settle();
      expect(host.histories.single.messages, isEmpty);
      expect(bob.active!.messages, isEmpty);
      expect(
        alice.histories.single.messages.single.receipts[host.selfId],
        'unconfirmed',
      );
    },
  );
  test(
    'duplicate signed IDs do not add history, unread or relay twice',
    () async {
      await network.join(alice);
      await network.join(bob);
      await alice.sendText('once');
      await network.settle();
      final m = alice.active!.messages.single, link = alice.links.values.single;
      await alice.transport.send(
        link.id,
        jsonEncode(
          await link.session.encrypt({
            'type': 'groupText',
            'message': m.envelope,
          }),
        ),
      );
      await network.settle();
      expect(host.active!.messages.length, 1);
      expect(bob.active!.messages.length, 1);
      expect(host.active!.unread, 1);
    },
  );
  test(
    'reopening original group uses new epoch; an imported archive cannot silently host',
    () async {
      await network.join(alice);
      await host.sendText('history');
      await network.settle();
      final previous = host.active!, epoch = host.epoch;
      await host.stop();
      await network.settle();
      expect(await alice.host(previous.title, previous: previous), false);
      expect(await host.host(previous.title, previous: previous), true);
      expect(host.epoch, isNot(epoch));
      expect(host.active!.messages.single.text, 'history');
      expect(host.members.length, 1);
      expect(host.links, isEmpty);
    },
  );
}
