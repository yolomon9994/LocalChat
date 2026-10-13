import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/group_controller.dart';
import 'group_test_support.dart';
import 'group_draft_test.dart' show emptyGroup;

class GroupManagementStore extends DemoStore {
  bool failPin = false, failArchive = false;
  Completer<void>? readGate;
  @override
  Future<List<GroupHistory>> groupHistories() async {
    await readGate?.future;
    return super.groupHistories();
  }

  @override
  Future<bool> setGroupPinned(String id, bool pinned) async {
    if (failPin) throw StateError('Private storage detail');
    return super.setGroupPinned(id, pinned);
  }

  @override
  Future<bool> setGroupArchived(String id, bool archived) async {
    if (failArchive) throw StateError('Private storage detail');
    return super.setGroupArchived(id, archived);
  }
}

void main() {
  late GroupManagementStore store;
  late GroupHistory history;
  setUp(() async {
    store = GroupManagementStore();
    await store.open();
    history = await emptyGroup(store);
    await store.saveGroupHistory(history);
  });

  test(
    'legacy groups default to normal placement; metadata validates and copies',
    () async {
      final legacy = await GroupHistory.parse(history.toJson());
      expect(legacy.pinned, isFalse);
      expect(legacy.archived, isFalse);
      final changed = legacy.copy(pinned: true, archived: true);
      final restored = await GroupHistory.parse(changed.toJson());
      expect(restored.pinned && restored.archived, isTrue);
      expect(restored.copy(messages: [], updated: 4).pinned, isTrue);
      for (final key in ['pinned', 'archived']) {
        await expectLater(
          GroupHistory.parse({...history.toJson(), key: 1}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'pins sort before activity and stable IDs; toggling does not change activity',
    () async {
      final second = (await emptyGroup(store)).copy(updated: 20);
      final third = (await emptyGroup(store)).copy(updated: 20);
      await store.saveGroupHistory(second);
      await store.saveGroupHistory(third);
      await store.setGroupPinned(history.id, true);
      final all = await store.groupHistories();
      expect(all.first.id, history.id);
      expect(all.first.updated, history.updated);
      expect(all.skip(1).map((g) => g.id), [second.id, third.id]..sort());
      await store.setGroupArchived(history.id, true);
      await store.setGroupPinned(history.id, false);
      final saved = (await store.groupHistories()).last;
      expect(saved.id, history.id);
      expect(saved.archived, isTrue);
      expect(saved.updated, history.updated);
    },
  );

  test(
    'stale history and outgoing writes preserve choices and separate same-ID direct chats',
    () async {
      await store.savePeer(history.id, 'Direct');
      await store.saveGroupDraft(history.id, 'Group draft');
      await store.setGroupPinned(history.id, true);
      await store.setGroupArchived(history.id, true);
      await store.saveGroupHistory(history.copy(updated: 2));
      await store.saveOutgoingGroupHistory(history.copy(updated: 3));
      final group = (await store.groupHistories()).single;
      expect(group.pinned && group.archived, isTrue);
      expect((await store.conversations()).single.pinned, isFalse);
      expect((await store.conversations()).single.archived, isFalse);
      expect(await store.groupDraft(history.id), 'Group draft');
      await store.deleteGroupHistory(history.id);
      expect(await store.setGroupPinned(history.id, true), isFalse);
      expect(await store.setGroupArchived(history.id, true), isFalse);
      expect(await store.groupDraft(history.id), '');
      expect(await store.conversations(), hasLength(1));
    },
  );

  test(
    'failed updates and missing groups preserve state with generic errors',
    () async {
      final net = GroupNetwork();
      final c = GroupController(
        FakeGroupTransport(net),
        store,
        prepare: () async => true,
        canAct: () => true,
      );
      addTearDown(c.dispose);
      await c.initialize();
      await store.saveGroupDraft(history.id, 'Keep');
      store.failPin = true;
      expect(await c.setPinned(history.id, true), isFalse);
      expect(c.histories.single.pinned, isFalse);
      expect(c.error, isNot(contains('Private')));
      store.failArchive = true;
      expect(await c.setArchived(history.id, true), isFalse);
      expect(c.histories.single.archived, isFalse);
      expect(await store.groupDraft(history.id), 'Keep');
      store.failPin = false;
      expect(await c.setPinned('missing', true), isFalse);
      expect(await c.setPinned(history.id, true), isTrue);
      expect(c.error, isNull);
    },
  );

  test(
    'queued updates reject old access revisions even after unlocking again',
    () async {
      var access = 0, unlocked = true;
      final c = GroupController(
        FakeGroupTransport(GroupNetwork()),
        store,
        prepare: () async => true,
        canAct: () => unlocked,
        accessRevision: () => access,
      );
      addTearDown(c.dispose);
      await c.initialize();
      store.readGate = Completer<void>();
      final refreshing = c.refreshHistory();
      await Future<void>.delayed(Duration.zero);
      final pinning = c.setPinned(history.id, true);
      final archiving = c.setArchived(history.id, true);
      unlocked = false;
      access++;
      unlocked = true;
      access++;
      store.readGate!.complete();
      await refreshing;
      expect(await pinning, isFalse);
      expect(await archiving, isFalse);
      expect(c.histories.single.pinned || c.histories.single.archived, isFalse);
      unlocked = false;
      expect(await c.setPinned(history.id, true), isFalse);
    },
  );

  test(
    'archived active groups still receive unread messages without changing remote choices or drafts',
    () async {
      final net = GroupNetwork();
      addTearDown(net.close);
      final host = await net.phone('Host');
      await host.host('Room');
      final guest = await net.phone('Guest');
      await net.join(guest);
      final id = host.active!.id, epoch = host.epoch;
      await host.drafts.load(id, group: true);
      host.drafts.setText(id, 'Unfinished', group: true);
      await host.drafts.settled;
      expect(await host.setArchived(id, true), isTrue);
      expect(await host.setPinned(id, true), isTrue);
      expect(host.connected, isTrue);
      expect(host.epoch, epoch);
      expect(host.members, hasLength(2));
      expect(await guest.sendText('New while archived'), isTrue);
      await net.settle();
      expect(host.active!.archived && host.active!.pinned, isTrue);
      expect(host.active!.unread, 1);
      expect(guest.active!.archived || guest.active!.pinned, isFalse);
      expect(await host.store.groupDraft(id), 'Unfinished');
      expect(await host.setArchived(id, false), isTrue);
      expect(host.active!.pinned, isTrue);
      expect(host.active!.unread, 1);
    },
  );

  test(
    'rehosting a stale snapshot keeps latest messages and local choices',
    () async {
      final net = GroupNetwork();
      addTearDown(net.close);
      final host = await net.phone('Host');
      await host.host('Room');
      final old = host.active!, epoch = host.epoch;
      final guest = await net.phone('Guest');
      await net.join(guest);
      await guest.sendText('Keep this message');
      await net.settle();
      await host.setPinned(old.id, true);
      await host.setArchived(old.id, true);
      expect(await host.host(old.title, previous: old), isTrue);
      expect(host.epoch, isNot(epoch));
      expect(host.active!.messages.single.text, 'Keep this message');
      expect(host.active!.pinned && host.active!.archived, isTrue);
      await host.delete(old.id);
      expect(await host.host(old.title, previous: old), isFalse);
      expect(await host.store.groupHistories(), isEmpty);
    },
  );

  test(
    'v8 backups restore choices and drafts on new groups; existing choices win',
    () async {
      await store.setGroupPinned(history.id, true);
      await store.setGroupArchived(history.id, true);
      await store.saveGroupDraft(history.id, 'Draft');
      final data = await store.exportBackup();
      expect(data.toJson()['version'], 8);
      final target = DemoStore();
      await target.open();
      final owner = (await target.exportBackup()).owner;
      await target.importBackup(await BackupData.parse(data.toJson()));
      final restored = (await target.groupHistories()).single;
      expect(restored.pinned && restored.archived, isTrue);
      expect(await target.groupDraft(history.id), 'Draft');
      await target.setGroupPinned(history.id, false);
      await target.setGroupArchived(history.id, false);
      final m = await GroupText.create(
        store.identity,
        store.name,
        group: history.id,
        host: history.host,
        epoch: randomId(),
        view: 1,
        text: 'Another message',
        targets: [await identityId(history.host)],
      );
      await store.saveGroupHistory(history.copy(messages: [m]));
      expect(
        (await target.importBackup(await store.exportBackup())).newMessages,
        1,
      );
      final kept = (await target.groupHistories()).single;
      expect(kept.pinned || kept.archived, isFalse);
      expect(kept.messages.single.text, 'Another message');
      expect((await target.exportBackup()).owner, owner);
    },
  );

  test(
    'legacy backups keep local choices, while invalid and older-version metadata is rejected',
    () async {
      final legacy = await store.exportBackup();
      await store.setGroupPinned(history.id, true);
      await store.setGroupArchived(history.id, true);
      await store.importBackup(legacy);
      expect((await store.groupHistories()).single.archived, isTrue);
      final managed = (await store.exportBackup()).toJson();
      for (final version in [2, 3, 4, 5, 6, 7]) {
        await expectLater(
          BackupData.parse({...managed, 'version': version}),
          throwsFormatException,
        );
      }
      for (final field in ['pinned', 'archived']) {
        final raw = (await store.exportBackup()).toJson();
        ((raw['groups'] as List).single as Map)[field] = 'yes';
        await expectLater(BackupData.parse(raw), throwsFormatException);
      }
    },
  );

  test('conflicting hosts cannot import archive or pin choices', () async {
    await store.setGroupPinned(history.id, true);
    await store.setGroupArchived(history.id, true);
    final target = DemoStore();
    await target.open();
    await target.saveGroupHistory(await emptyGroup(target, id: history.id));
    expect(
      (await target.importBackup(await store.exportBackup())).conflicts,
      1,
    );
    expect((await target.groupHistories()).single.archived, isFalse);
    expect((await target.groupHistories()).single.pinned, isFalse);
  });
}
