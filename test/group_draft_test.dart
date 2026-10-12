import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/draft_controller.dart';
import 'group_test_support.dart';

class DraftGroupStore extends DemoStore {
  bool failRead = false,
      failWrite = false,
      failMessage = false,
      failDelete = false;
  Completer<void>? writeGate, messageGate, importGate;
  @override
  Future<String> groupDraft(String id) async {
    if (failRead) throw StateError('Private storage detail');
    return super.groupDraft(id);
  }

  @override
  Future<void> saveGroupDraft(String id, String text) async {
    await writeGate?.future;
    if (failWrite) throw StateError('Private storage detail');
    await super.saveGroupDraft(id, text);
  }

  @override
  Future<void> saveOutgoingGroupHistory(
    GroupHistory group, {
    bool clearDraft = false,
  }) async {
    await messageGate?.future;
    if (failMessage) throw StateError('Private storage detail');
    await super.saveOutgoingGroupHistory(group, clearDraft: clearDraft);
  }

  @override
  Future<void> deleteGroupHistory(String id) async {
    if (failDelete) throw StateError('Private storage detail');
    await super.deleteGroupHistory(id);
  }

  @override
  Future<BackupMerge> importBackup(
    BackupData data, {
    bool moveIdentity = false,
  }) async {
    await importGate?.future;
    return super.importBackup(data, moveIdentity: moveIdentity);
  }
}

Future<GroupHistory> emptyGroup(DemoStore store, {String? id}) async =>
    GroupHistory(
      id: id ?? randomId(),
      title: 'Friends',
      host: base64Encode((await store.identity.extractPublicKey()).bytes),
      messages: [],
      updated: 1,
    );

void main() {
  late DraftGroupStore store;
  late DraftController drafts;
  late GroupHistory group;
  setUp(() async {
    store = DraftGroupStore();
    await store.open();
    group = await emptyGroup(store);
    await store.saveGroupHistory(group);
    drafts = DraftController(store);
  });
  tearDown(() => drafts.dispose());

  test(
    'group drafts restore exact text and isolate rooms and direct IDs',
    () async {
      final other = await emptyGroup(store);
      await store.saveGroupHistory(other);
      await drafts.load(group.id, group: true);
      await drafts.load(other.id, group: true);
      await drafts.load(group.id);
      const text = '  سلام 👋\nunfinished  ';
      drafts.setText(group.id, text, group: true);
      drafts.setText(other.id, 'Other room', group: true);
      drafts.setText(group.id, 'Direct chat');
      await drafts.settled;
      final restored = DraftController(store);
      addTearDown(restored.dispose);
      await restored.load(group.id, group: true);
      expect(restored.textFor(group.id, group: true), text);
      expect(await store.groupDraft(other.id), 'Other room');
      expect(await store.draft(group.id), 'Direct chat');
    },
  );

  test(
    'group load and save failures preserve text, retry and block backups',
    () async {
      await store.saveGroupDraft(group.id, 'Saved');
      store.failRead = true;
      await drafts.load(group.id, group: true);
      expect(drafts.isLoaded(group.id, group: true), isFalse);
      expect(
        drafts.errorFor(group.id, group: true),
        isNot(contains('Private')),
      );
      await expectLater(drafts.exportBackup(), throwsFormatException);
      store.failRead = false;
      await drafts.retry(group.id, group: true);
      expect(drafts.textFor(group.id, group: true), 'Saved');
      store.failWrite = true;
      drafts.setText(group.id, 'New text', group: true);
      await drafts.settled;
      expect(await store.groupDraft(group.id), 'Saved');
      expect(drafts.errorFor(group.id, group: true), contains('not saved'));
      await expectLater(
        drafts.importBackup(await store.exportBackup()),
        throwsFormatException,
      );
      store.failWrite = false;
      await drafts.retry(group.id, group: true);
      expect(await store.groupDraft(group.id), 'New text');
      expect(drafts.errorFor(group.id, group: true), isNull);
    },
  );

  test('atomic acceptance clears only the captured group draft', () async {
    await drafts.load(group.id, group: true);
    drafts.setText(group.id, 'Sent text', group: true);
    await drafts.settled;
    await drafts.acceptGroupOutgoing(
      group,
      draftRevision: drafts.revisionFor(group.id, group: true),
      draftText: 'Sent text',
    );
    expect(drafts.textFor(group.id, group: true), '');
    expect(await store.groupDraft(group.id), '');
  });

  test('edits during local acceptance survive its atomic cleanup', () async {
    await drafts.load(group.id, group: true);
    drafts.setText(group.id, 'First text', group: true);
    await drafts.settled;
    store.messageGate = Completer<void>();
    final send = drafts.acceptGroupOutgoing(
      group,
      draftRevision: drafts.revisionFor(group.id, group: true),
      draftText: 'First text',
    );
    await Future<void>.delayed(Duration.zero);
    drafts.setText(group.id, 'Next message', group: true);
    store.messageGate!.complete();
    await send;
    await drafts.settled;
    expect(drafts.textFor(group.id, group: true), 'Next message');
    expect(await store.groupDraft(group.id), 'Next message');
  });

  test('failed message persistence and access rejection keep draft', () async {
    await drafts.load(group.id, group: true);
    drafts.setText(group.id, 'Keep me', group: true);
    await drafts.settled;
    final revision = drafts.revisionFor(group.id, group: true);
    store.failMessage = true;
    await expectLater(
      drafts.acceptGroupOutgoing(
        group,
        draftRevision: revision,
        draftText: 'Keep me',
      ),
      throwsStateError,
    );
    store.failMessage = false;
    await expectLater(
      drafts.acceptGroupOutgoing(
        group,
        draftRevision: revision,
        draftText: 'Keep me',
        canAccept: () => false,
      ),
      throwsFormatException,
    );
    expect(drafts.textFor(group.id, group: true), 'Keep me');
    expect(await store.groupDraft(group.id), 'Keep me');
  });

  test(
    'deletion invalidates queued edits and keeps same-ID direct draft',
    () async {
      await drafts.load(group.id, group: true);
      await drafts.load(group.id);
      drafts.setText(group.id, 'Direct');
      await drafts.settled;
      store.writeGate = Completer<void>();
      drafts.setText(group.id, 'Old draft', group: true);
      await Future<void>.delayed(Duration.zero);
      final deletion = drafts.deleteGroupHistory(group.id);
      drafts.setText(group.id, 'Must not return', group: true);
      final staleSend = drafts.acceptGroupOutgoing(group);
      final rejected = expectLater(staleSend, throwsFormatException);
      store.writeGate!.complete();
      await deletion;
      await rejected;
      await drafts.settled;
      expect(await store.groupHistories(), isEmpty);
      expect(await store.groupDraft(group.id), '');
      expect(await store.draft(group.id), 'Direct');
      expect(drafts.isLoaded(group.id, group: true), isFalse);
    },
  );

  test('failed group deletion preserves its draft and history', () async {
    await drafts.load(group.id, group: true);
    drafts.setText(group.id, 'Keep', group: true);
    await drafts.settled;
    store.failDelete = true;
    await expectLater(drafts.deleteGroupHistory(group.id), throwsStateError);
    expect(drafts.textFor(group.id, group: true), 'Keep');
    expect(await store.groupDraft(group.id), 'Keep');
    expect(await store.groupHistories(), hasLength(1));
  });

  test('delete all invalidates both kinds of pending edits', () async {
    await drafts.load(group.id, group: true);
    await drafts.load('direct');
    store.writeGate = Completer<void>();
    drafts.setText(group.id, 'Old', group: true);
    await Future<void>.delayed(Duration.zero);
    final clear = drafts.clearHistory();
    drafts.setText(group.id, 'Late group', group: true);
    drafts.setText('direct', 'Late direct');
    store.writeGate!.complete();
    await clear;
    await drafts.settled;
    expect(await store.groupDraft(group.id), '');
    expect(await store.draft('direct'), '');
    expect(drafts.textFor(group.id, group: true), '');
  });

  test(
    'export waits for pending group saves; empty drafts remove rows',
    () async {
      await drafts.load(group.id, group: true);
      store.writeGate = Completer<void>();
      drafts.setText(group.id, 'For backup', group: true);
      final export = drafts.exportBackup();
      store.writeGate!.complete();
      expect((await export).groupDrafts.single['text'], 'For backup');
      drafts.setText(group.id, '', group: true);
      expect((await drafts.exportBackup()).groupDrafts, isEmpty);
    },
  );

  test('import retains edits made while the import is pending', () async {
    final source = DemoStore();
    await source.open();
    await source.saveGroupHistory(group);
    await source.saveGroupDraft(group.id, 'Imported');
    await drafts.load(group.id, group: true);
    store.importGate = Completer<void>();
    final importing = drafts.importBackup(await source.exportBackup());
    await Future<void>.delayed(Duration.zero);
    drafts.setText(group.id, 'New local edit', group: true);
    store.importGate!.complete();
    await importing;
    await drafts.settled;
    expect(drafts.textFor(group.id, group: true), 'New local edit');
    expect(await store.groupDraft(group.id), 'New local edit');
  });

  test(
    'v7 encrypted archive transfers drafts and identity to an empty phone',
    () async {
      await store.saveGroupDraft(group.id, 'Backup secret سلام');
      final data = await store.exportBackup();
      expect(data.toJson()['version'], 7);
      final codec = BackupCodec(
        deriveKey: (password, salt) async => Uint8List.fromList(
          (await Sha256().hash([...utf8.encode(password), ...salt])).bytes,
        ),
      );
      final bytes = await codec.encrypt(data, 'test backup password');
      final decoded = await codec.decrypt(bytes, 'test backup password');
      final target = DemoStore();
      await target.open();
      final result = await target.importBackup(decoded, moveIdentity: true);
      expect(result.newDrafts, 1);
      expect(await target.groupDraft(group.id), 'Backup secret سلام');
      expect((await target.exportBackup()).owner, data.owner);
    },
  );

  test(
    'history-only merge keeps local draft and imports absent draft without new messages',
    () async {
      await store.saveGroupDraft(group.id, 'Imported');
      final data = await store.exportBackup();
      final target = DemoStore();
      await target.open();
      await target.saveGroupHistory(group);
      final owner = (await target.exportBackup()).owner;
      expect((await target.importBackup(data)).newDrafts, 1);
      expect((await target.importBackup(data)).newDrafts, 0);
      await target.saveGroupDraft(group.id, 'Local');
      expect((await target.importBackup(data)).keptDrafts, 1);
      expect(await target.groupDraft(group.id), 'Local');
      expect((await target.exportBackup()).owner, owner);
    },
  );

  test('conflicting host cannot receive imported group draft', () async {
    await store.saveGroupDraft(group.id, 'Wrong host');
    final target = DemoStore();
    await target.open();
    await target.saveGroupHistory(await emptyGroup(target, id: group.id));
    final result = await target.importBackup(await store.exportBackup());
    expect(result.conflicts, 1);
    expect(result.newDrafts, 0);
    expect(await target.groupDraft(group.id), '');
  });

  test(
    'v7 rejects missing references, duplicates, empty/oversize drafts and old version fields',
    () async {
      await store.saveGroupDraft(group.id, 'Valid');
      final raw = (await store.exportBackup()).toJson();
      for (final bad in [
        {...raw, 'version': 6},
        {...raw, 'groups': <Object>[]},
        {
          ...raw,
          'groupDrafts': [raw['groupDrafts'] as List, {}],
        },
        {
          ...raw,
          'groupDrafts': [
            ...raw['groupDrafts'] as List,
            ...raw['groupDrafts'] as List,
          ],
        },
        {
          ...raw,
          'groupDrafts': [
            {'group': group.id, 'text': ''},
          ],
        },
        {
          ...raw,
          'groupDrafts': [
            {'group': group.id, 'text': 'a' * (1024 * 1024 + 1)},
          ],
        },
      ]) {
        await expectLater(BackupData.parse(bad), throwsFormatException);
      }
      await expectLater(
        store.saveGroupDraft(randomId(), 'Orphan'),
        throwsFormatException,
      );
      await expectLater(
        store.saveGroupDraft(group.id, 'a' * (1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );

  test(
    'group sends clear locally accepted draft and preserve rejected text',
    () async {
      final net = GroupNetwork();
      addTearDown(net.close);
      final host = await net.phone('Host', store: store);
      await host.host('Room');
      final id = host.active!.id;
      await host.drafts.load(id, group: true);
      host.drafts.setText(id, '  send me  ', group: true);
      await host.drafts.settled;
      // A host without another verified member cannot accept a message.
      expect(
        await host.sendText(
          '  send me  ',
          draftText: '  send me  ',
          draftRevision: host.drafts.revisionFor(id, group: true),
        ),
        isFalse,
      );
      expect(await store.groupDraft(id), '  send me  ');
      final guest = await net.phone('Guest');
      await net.join(guest);
      expect(
        await host.sendText(
          '  send me  ',
          draftText: '  send me  ',
          draftRevision: host.drafts.revisionFor(id, group: true),
        ),
        isTrue,
      );
      await net.settle();
      expect(await store.groupDraft(id), '');
      expect(host.active!.messages.single.text, 'send me');
      expect(guest.active!.messages.single.text, 'send me');
    },
  );

  test(
    'failed group send and lock preserve drafts; rehosting preserves offline text',
    () async {
      final net = GroupNetwork();
      addTearDown(net.close);
      var unlocked = true;
      final host = await net.phone(
        'Host',
        store: store,
        canAct: () => unlocked,
      );
      await host.host('Room');
      final guest = await net.phone('Guest');
      await net.join(guest);
      final history = host.active!;
      await host.drafts.load(history.id, group: true);
      host.drafts.setText(history.id, 'Keep', group: true);
      await host.drafts.settled;
      store.failMessage = true;
      expect(
        await host.sendText(
          'Keep',
          draftText: 'Keep',
          draftRevision: host.drafts.revisionFor(history.id, group: true),
        ),
        isFalse,
      );
      expect(host.active!.messages, isEmpty);
      expect(await store.groupDraft(history.id), 'Keep');
      store.failMessage = false;
      unlocked = false;
      expect(await host.sendText('Keep'), isFalse);
      unlocked = true;
      await host.stop();
      host.drafts.setText(history.id, 'Offline edit', group: true);
      await host.drafts.settled;
      await host.host(history.title, previous: history);
      expect(await store.groupDraft(history.id), 'Offline edit');
    },
  );
}
