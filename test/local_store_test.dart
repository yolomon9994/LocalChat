import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/local_store.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/message_reply.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/group_search.dart';
import 'package:local_chat/core/chat_image.dart';
import 'package:local_chat/core/chat_file.dart';
import 'dart:typed_data';
import 'image_test_support.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  databaseFactory = createDatabaseFactoryFfi(noIsolate: true);
  late LocalStore store;
  late String databasePath;
  late DateTime clock;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    databasePath = path.join(await getDatabasesPath(), 'localchat.db');
    await deleteDatabase(databasePath);
    clock = DateTime(2026, 10, 10, 9);
    store = LocalStore(now: () => clock);
    await store.open();
    await store.savePeer('alice', 'Alice');
  });
  tearDown(() async {
    await store.close();
    await deleteDatabase(databasePath);
  });
  ChatMessage message({String peer = 'alice', bool outgoing = true}) =>
      ChatMessage(
        id: 'id-1',
        peerId: peer,
        text: 'Private text سلام 👋',
        timestamp: 1000,
        outgoing: outgoing,
        status: 'sending',
      );
  Future<GroupHistory> draftGroup() async => GroupHistory(
    id: randomId(),
    title: 'Draft room',
    host: base64Encode((await store.identity.extractPublicKey()).bytes),
    messages: [],
    updated: 1,
  );

  const reply = MessageReply(
    id: 'original',
    outgoing: false,
    name: 'Alice',
    text: 'Quoted secret reply',
  );
  ChatMessage answer({MessageReply? quote = reply}) => ChatMessage(
    id: 'reply-answer',
    peerId: 'alice',
    text: 'Private reply body',
    timestamp: 2000,
    outgoing: true,
    status: 'queued',
    reply: quote,
  );

  test(
    'schema 11 upgrade preserves ciphertext and adds encrypted reply drafts',
    () async {
      await store.saveMessage(message());
      await store.saveDraft('alice', 'Old draft');
      await store.close();
      final old = await openDatabase(databasePath);
      final body = (await old.query('messages')).single['body'];
      await old.execute('DROP TABLE reply_drafts');
      await old.setVersion(11);
      await old.close();
      store = LocalStore(now: () => clock);
      await store.open();
      final upgraded = await openDatabase(databasePath);
      expect(await upgraded.getVersion(), 12);
      expect((await upgraded.query('messages')).single['body'], body);
      expect(await store.draft('alice'), 'Old draft');
      expect(await store.draftReply('alice'), isNull);
      await store.saveDraftState('alice', '', reply);
      final encrypted =
          (await upgraded.query('reply_drafts')).single['body'] as String;
      expect(
        utf8.decode(base64Decode(encrypted), allowMalformed: true),
        isNot(contains(reply.text)),
      );
      expect(await store.draftReply('alice'), reply);
      expect((await store.exportBackup()).drafts.single['text'], '');
    },
  );

  test(
    'reply body uses authenticated kind and survives restart without interpreting plain JSON',
    () async {
      await store.saveMessage(answer());
      await store.saveMessage(
        const ChatMessage(
          id: 'literal',
          peerId: 'alice',
          text: '{"text":"ordinary","reply":{"id":"fake"}}',
          timestamp: 3000,
          outgoing: false,
          status: 'received',
        ),
      );
      final db = await openDatabase(databasePath);
      final row = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['reply-answer'],
      )).single;
      expect(row['kind'], 'reply');
      expect(
        utf8.decode(base64Decode(row['body'] as String), allowMalformed: true),
        isNot(contains(reply.text)),
      );
      await store.close();
      store = LocalStore(now: () => clock);
      await store.open();
      final history = await store.messages('alice');
      expect(history.first.reply, reply);
      expect(history.last.reply, isNull);
      expect(history.last.text, '{"text":"ordinary","reply":{"id":"fake"}}');
      final reopened = await openDatabase(databasePath);
      await reopened.update(
        'messages',
        {'kind': 'text'},
        where: 'id = ?',
        whereArgs: ['reply-answer'],
      );
      await expectLater(
        store.messages('alice'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await reopened.update(
        'messages',
        {'kind': 'reply'},
        where: 'id = ?',
        whereArgs: ['reply-answer'],
      );
    },
  );

  test(
    'reply draft updates and cancellation are atomic on a storage failure',
    () async {
      await store.saveDraftState('alice', 'Kept answer', reply);
      final db = await openDatabase(databasePath);
      final before = (await db.query('drafts')).single['body'];
      await db.execute(
        "CREATE TRIGGER fail_reply_state BEFORE INSERT ON reply_drafts BEGIN SELECT RAISE(ABORT, 'blocked'); END",
      );
      await expectLater(
        store.saveDraftState(
          'alice',
          'Wrong newer answer',
          const MessageReply(
            id: 'new',
            outgoing: true,
            name: 'Me',
            text: 'New quote',
          ),
        ),
        throwsA(anything),
      );
      expect(await store.draft('alice'), 'Kept answer');
      expect(await store.draftReply('alice'), reply);
      expect((await db.query('drafts')).single['body'], before);
      await db.execute('DROP TRIGGER fail_reply_state');
      await store.saveDraftState('alice', 'Kept answer', null);
      expect(await store.draftReply('alice'), isNull);
      expect(await store.draft('alice'), 'Kept answer');
    },
  );

  test(
    'failed reply draft cleanup rolls back outgoing message and preserves both draft parts',
    () async {
      await store.saveDraftState('alice', 'Private reply body', reply);
      final db = await openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_reply_cleanup BEFORE DELETE ON reply_drafts BEGIN SELECT RAISE(ABORT, 'blocked'); END",
      );
      await expectLater(
        store.saveOutgoingMessage(answer(), clearDraft: true),
        throwsA(anything),
      );
      expect(await store.messages('alice'), isEmpty);
      expect(await store.draft('alice'), 'Private reply body');
      expect(await store.draftReply('alice'), reply);
      await db.execute('DROP TRIGGER fail_reply_cleanup');
      await store.saveOutgoingMessage(answer(), clearDraft: true);
      expect((await store.messages('alice')).single.reply, reply);
      expect(await store.draft('alice'), '');
      expect(await store.draftReply('alice'), isNull);
      expect(await store.saveMessage(answer()), isFalse);
      await expectLater(
        store.saveMessage(answer(quote: null)),
        throwsFormatException,
      );
    },
  );

  test(
    'v9 import re-encrypts quotes and quote-only drafts with destination keys',
    () async {
      await store.saveMessage(answer());
      await store.saveDraftState('alice', '', reply);
      final source = await store.exportBackup();
      final db = await openDatabase(databasePath);
      final original = (await db.query('messages')).single['body'];
      await store.close();
      await deleteDatabase(databasePath);
      FlutterSecureStorage.setMockInitialValues({});
      store = LocalStore(now: () => clock);
      await store.open();
      await store.importBackup(await BackupData.parse(source.toJson()));
      expect((await store.messages('alice')).single.reply, reply);
      expect((await store.messages('alice')).single.status, 'unconfirmed');
      expect(await store.draftReply('alice'), reply);
      final destination = await openDatabase(databasePath);
      expect(
        (await destination.query('messages')).single['body'],
        isNot(original),
      );
      await store.deleteConversation('alice');
      expect(await destination.query('reply_drafts'), isEmpty);
    },
  );

  test(
    'native signed group quotes and quote-only drafts survive restart and deletion',
    () async {
      final group = await draftGroup();
      final self = await identityId(group.host);
      final reference = MessageReply(
        id: randomId(),
        author: self,
        name: 'Host',
        text: 'Quoted group text',
      );
      final m = await GroupText.create(
        store.identity,
        'Host',
        group: group.id,
        host: group.host,
        epoch: randomId(),
        view: 1,
        text: 'Group reply',
        targets: [self],
        reply: reference,
      );
      await store.saveGroupHistory(group.copy(messages: [m]));
      await store.saveDraftState(group.id, '', reference, group: true);
      await store.close();
      store = LocalStore(now: () => clock);
      await store.open();
      expect(
        (await store.groupHistories()).single.messages.single.reply,
        reference,
      );
      expect(await store.draftReply(group.id, group: true), reference);
      final backup = await store.exportBackup();
      expect(backup.toJson()['version'], 9);
      expect(backup.groupDrafts.single['text'], '');
      final history = (await store.groupHistories()).single;
      await store.saveOutgoingGroupHistory(history, clearDraft: true);
      expect(await store.draftReply(group.id, group: true), isNull);
      await store.saveDraftState(group.id, '', reference, group: true);
      await store.deleteGroupHistory(group.id);
      expect(await store.draftReply(group.id, group: true), isNull);
    },
  );

  test(
    'group search after reopening uses encrypted histories and preserves metadata and drafts',
    () async {
      final group = (await draftGroup()).copy(pinned: true, archived: true);
      final m = await GroupText.create(
        store.identity,
        store.name,
        group: group.id,
        host: group.host,
        epoch: randomId(),
        view: 1,
        text: 'Offline NEEDLE سلام 👋 %_',
        targets: [await identityId(group.host)],
      );
      await store.saveGroupHistory(group.copy(messages: [m.copy(read: false)]));
      await store.saveGroupDraft(group.id, 'Secret unsearched draft');
      final db = await openDatabase(databasePath);
      final before = (await db.query('group_history')).single;
      expect(before['body'], isNot(contains('NEEDLE')));
      await store.close();
      store = LocalStore(now: () => clock);
      await store.open();
      final histories = await store.groupHistories();
      final result = await searchGroupHistories(histories, ' needle ');
      expect(result.messages.single.key, m.key);
      expect(result.messages.single.group.archived, isTrue);
      expect(
        (await searchGroupHistories(histories, 'سلام 👋')).messages.length,
        1,
      );
      expect((await searchGroupHistories(histories, '%_')).messages.length, 1);
      expect(
        (await searchGroupHistories(histories, 'unsearched')).messages,
        isEmpty,
      );
      expect(histories.single.unread, 1);
      expect(histories.single.pinned, isTrue);
      expect(await store.groupDraft(group.id), 'Secret unsearched draft');
      final afterDb = await openDatabase(databasePath);
      expect((await afterDb.query('group_history')).single, before);
      expect(await afterDb.getVersion(), 12);
      expect(
        await afterDb.query(
          'sqlite_master',
          where: 'name LIKE ?',
          whereArgs: ['%search%'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'schema 10 upgrades preserve ciphertext, messages and drafts with default group choices',
    () async {
      final group = await draftGroup();
      await store.saveGroupHistory(group);
      await store.saveGroupDraft(group.id, 'Group draft');
      await store.saveDraft('alice', 'Direct draft');
      await store.saveMessage(message());
      final db = await openDatabase(databasePath);
      final body = (await db.query('group_history')).single['body'];
      await store.close();
      final old = await openDatabase(databasePath);
      await old.transaction((txn) async {
        await txn.execute('ALTER TABLE group_history RENAME TO group_new');
        await txn.execute(
          'CREATE TABLE group_history (id TEXT PRIMARY KEY, body TEXT NOT NULL)',
        );
        await txn.execute(
          'INSERT INTO group_history(id, body) SELECT id, body FROM group_new',
        );
        await txn.execute('DROP TABLE group_new');
        await txn.execute('PRAGMA user_version = 10');
      });
      await old.close();
      store = LocalStore();
      await store.open();
      final upgraded = await openDatabase(databasePath);
      expect(await upgraded.getVersion(), 12);
      expect((await upgraded.query('group_history')).single['body'], body);
      final restored = (await store.groupHistories()).single;
      expect(restored.pinned || restored.archived, isFalse);
      expect(await store.groupDraft(group.id), 'Group draft');
      expect(await store.draft('alice'), 'Direct draft');
      expect((await store.messages('alice')).single.text, message().text);
    },
  );

  test(
    'group choices persist, avoid rewriting ciphertext, and survive stale and atomic history writes',
    () async {
      final group = await draftGroup(), newer = await draftGroup();
      await store.saveGroupHistory(group);
      await store.saveGroupHistory(newer.copy(updated: 10));
      await store.saveGroupDraft(group.id, 'Keep');
      final db = await openDatabase(databasePath);
      final body = (await db.query(
        'group_history',
        where: 'id = ?',
        whereArgs: [group.id],
      )).single['body'];
      expect(await store.setGroupPinned(group.id, true), isTrue);
      expect(await store.setGroupArchived(group.id, true), isTrue);
      final metadata = (await db.query(
        'group_history',
        where: 'id = ?',
        whereArgs: [group.id],
      )).single;
      expect(metadata['body'], body);
      expect(metadata['pinned'], 1);
      expect(metadata['archived'], 1);
      await store.saveGroupHistory(group.copy(updated: 2));
      await store.saveOutgoingGroupHistory(group.copy(updated: 3));
      await store.close();
      store = LocalStore();
      await store.open();
      final all = await store.groupHistories();
      expect(all.first.id, group.id);
      expect(all.first.pinned && all.first.archived, isTrue);
      expect(all.first.updated, 3);
      expect(await store.groupDraft(group.id), 'Keep');
      expect(await store.setGroupPinned(group.id, false), isTrue);
      expect((await store.groupHistories()).first.id, newer.id);
      await store.deleteGroupHistory(group.id);
      expect(await store.setGroupPinned(group.id, true), isFalse);
      expect(await store.setGroupArchived(group.id, true), isFalse);
      expect(await store.groupDraft(group.id), '');
    },
  );

  test(
    'failed group metadata writes preserve choices, content and drafts',
    () async {
      final group = await draftGroup();
      await store.saveGroupHistory(group.copy(pinned: true));
      await store.saveGroupDraft(group.id, 'Keep');
      final db = await openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_group_flags BEFORE UPDATE ON group_history BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        store.setGroupPinned(group.id, false),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        store.setGroupArchived(group.id, true),
        throwsA(isA<DatabaseException>()),
      );
      final saved = (await store.groupHistories()).single;
      expect(saved.pinned, isTrue);
      expect(saved.archived, isFalse);
      expect(saved.updated, group.updated);
      expect(await store.groupDraft(group.id), 'Keep');
      await db.execute('DROP TRIGGER fail_group_flags');
    },
  );

  test(
    'v8 SQLite import inherits new group choices and keeps existing choices while merging messages',
    () async {
      final group = await draftGroup();
      await store.saveGroupHistory(group);
      final source = DemoStore();
      await source.open();
      final m = await GroupText.create(
        store.identity,
        store.name,
        group: group.id,
        host: group.host,
        epoch: randomId(),
        view: 1,
        text: 'New record',
        targets: [await identityId(group.host)],
      );
      await source.saveGroupHistory(
        group.copy(messages: [m], pinned: true, archived: true),
      );
      final fresh = await draftGroup();
      await source.saveGroupHistory(fresh.copy(archived: true));
      await source.saveGroupDraft(fresh.id, 'Imported draft');
      final data = await source.exportBackup();
      final phone = BackupData(
        seed: data.seed,
        owner: data.owner,
        name: data.name,
        created: data.created,
        demo: false,
        peers: data.peers,
        messages: data.messages,
        drafts: data.drafts,
        groups: data.groups,
        groupDrafts: data.groupDrafts,
      );
      expect(phone.toJson()['version'], 8);
      final result = await store.importBackup(phone);
      expect(result.newMessages, 1);
      expect(result.newChats, 1);
      final groups = await store.groupHistories();
      final kept = groups.firstWhere((g) => g.id == group.id);
      expect(kept.pinned || kept.archived, isFalse);
      expect(kept.messages.single.text, 'New record');
      expect(groups.firstWhere((g) => g.id == fresh.id).archived, isTrue);
      expect(await store.groupDraft(fresh.id), 'Imported draft');
      expect((await store.importBackup(phone)).newChats, 0);
    },
  );

  test(
    'concurrent group history and metadata writes keep the newest choices',
    () async {
      final group = await draftGroup();
      await store.saveGroupHistory(group);
      await Future.wait([
        store.saveGroupHistory(group.copy(updated: 10)),
        store.setGroupPinned(group.id, true),
        store.setGroupArchived(group.id, true),
      ]);
      final saved = (await store.groupHistories()).single;
      expect(saved.updated, 10);
      expect(saved.pinned && saved.archived, isTrue);
    },
  );

  test(
    'schema 9 upgrades without changing existing text, direct drafts or group history',
    () async {
      final group = await draftGroup();
      await store.saveGroupHistory(group);
      await store.saveDraft('alice', 'Direct draft');
      await store.saveMessage(message());
      await store.close();
      final old = await openDatabase(databasePath);
      await old.execute('DROP TABLE group_drafts');
      await old.execute('PRAGMA user_version = 9');
      await old.close();
      store = LocalStore();
      await store.open();
      expect(await (await openDatabase(databasePath)).getVersion(), 12);
      expect((await store.messages('alice')).single.text, message().text);
      expect(await store.draft('alice'), 'Direct draft');
      expect((await store.groupHistories()).single.id, group.id);
      await store.saveGroupDraft(group.id, 'New group draft');
      expect(await store.groupDraft(group.id), 'New group draft');
    },
  );

  test(
    'group drafts encrypt exact text, authenticate room binding, reopen and merge',
    () async {
      final group = await draftGroup(), other = await draftGroup();
      await store.saveGroupHistory(group);
      await store.saveGroupHistory(other);
      const text = '  private draft سلام 👋\nline two  ';
      await store.saveGroupDraft(group.id, text);
      final db = await openDatabase(databasePath);
      final body = (await db.query('group_drafts')).single['body'];
      expect(
        utf8.decode(base64Decode(body as String), allowMalformed: true),
        isNot(contains('private draft')),
      );
      await db.insert('group_drafts', {'id': other.id, 'body': body});
      await expectLater(
        store.groupDraft(other.id),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await db.delete('group_drafts', where: 'id = ?', whereArgs: [other.id]);
      await store.close();
      store = LocalStore();
      await store.open();
      expect(await store.groupDraft(group.id), text);
      final backup = await store.exportBackup();
      expect(backup.toJson()['version'], 7);
      await store.clearHistory();
      expect(
        await (await openDatabase(databasePath)).query('group_drafts'),
        isEmpty,
      );
      expect((await store.importBackup(backup)).newDrafts, 1);
      expect(await store.groupDraft(group.id), text);
      expect((await store.importBackup(backup)).newDrafts, 0);
      await store.deleteGroupHistory(group.id);
      expect(await store.groupDraft(group.id), '');
      await expectLater(
        store.saveGroupDraft(group.id, 'Orphan'),
        throwsFormatException,
      );
    },
  );

  test(
    'failed atomic group draft cleanup rolls back message and keeps the draft',
    () async {
      final group = await draftGroup();
      await store.saveGroupHistory(group);
      await store.saveGroupDraft(group.id, 'Keep me');
      final m = await GroupText.create(
        store.identity,
        store.name,
        group: group.id,
        host: group.host,
        epoch: randomId(),
        view: 1,
        text: 'Keep me',
        targets: [await identityId(group.host)],
      );
      final next = group.copy(messages: [m]);
      final db = await openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_draft_delete BEFORE DELETE ON group_drafts BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        store.saveOutgoingGroupHistory(next, clearDraft: true),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.groupHistories()).single.messages, isEmpty);
      expect(await store.groupDraft(group.id), 'Keep me');
      await expectLater(
        store.deleteGroupHistory(group.id),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.groupHistories(), hasLength(1));
      await db.execute('DROP TRIGGER fail_draft_delete');
      await store.saveOutgoingGroupHistory(next, clearDraft: true);
      expect(
        (await store.groupHistories()).single.messages.single.text,
        'Keep me',
      );
      expect(await store.groupDraft(group.id), '');
    },
  );

  test(
    'failed draft import rolls back its mixed direct and group history',
    () async {
      final source = DemoStore();
      await source.open();
      final group = await draftGroup();
      await source.saveGroupHistory(group);
      await source.saveGroupDraft(group.id, 'Incoming group');
      await source.savePeer('new-peer', 'New peer');
      await source.saveMessage(message(peer: 'new-peer'));
      final data = await source.exportBackup();
      final phone = BackupData(
        seed: data.seed,
        owner: data.owner,
        name: data.name,
        created: data.created,
        demo: false,
        peers: data.peers,
        messages: data.messages,
        drafts: data.drafts,
        groups: data.groups,
        groupDrafts: data.groupDrafts,
      );
      final db = await openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_draft_insert BEFORE INSERT ON group_drafts BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        store.importBackup(phone),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.groupHistories(), isEmpty);
      expect(
        await (await openDatabase(databasePath)).query('group_drafts'),
        isEmpty,
      );
      expect(await store.messages('new-peer'), isEmpty);
      expect((await store.conversations()).map((p) => p.id), ['alice']);
      await db.execute('DROP TRIGGER fail_draft_insert');
    },
  );
  test(
    'image bytes and metadata encrypted, atomic dedupe, reopen, backup and deletion',
    () async {
      final bytes = await testImage();
      final m = ChatMessage(
        id: 'image',
        peerId: 'alice',
        text: 'Image',
        timestamp: 2,
        outgoing: false,
        status: 'received',
        image: await ChatImage.fromBytes(bytes),
      );
      expect(await store.saveImageMessage(m, bytes), isTrue);
      expect(await store.saveImageMessage(m, bytes), isFalse);
      final db = await openDatabase(databasePath);
      final row = (await db.query('images')).single;
      expect(row['body'], isNot(base64Encode(bytes)));
      expect(
        (await db.query('messages')).single['body'],
        isNot(contains(m.image!.digest)),
      );
      expect((await store.conversations()).single.unreadCount, 1);
      await store.close();
      store = LocalStore();
      await store.open();
      final saved = (await store.messages('alice')).single;
      expect(await store.imageBytes(saved), bytes);
      final backup = await store.exportBackup();
      expect(backup.toJson()['version'], 3);
      await store.clearHistory();
      await store.importBackup(backup);
      expect(
        await store.imageBytes((await store.messages('alice')).single),
        bytes,
      );
      await store.deleteConversation('alice');
      expect(await (await openDatabase(databasePath)).query('images'), isEmpty);
    },
  );
  test(
    'schema 7 upgrades preserve encrypted text and add image storage',
    () async {
      await store.saveMessage(message());
      await store.close();
      final db = await openDatabase(databasePath);
      await db.execute('DROP TABLE images');
      await db.execute('ALTER TABLE messages DROP COLUMN kind');
      await db.execute('PRAGMA user_version = 7');
      await db.close();
      store = LocalStore();
      await store.open();
      expect((await store.messages('alice')).single.text, message().text);
      final upgraded = await openDatabase(databasePath);
      expect(await upgraded.getVersion(), 12);
      expect(await upgraded.query('images'), isEmpty);
    },
  );
  test(
    'file bytes and metadata encrypted, atomic dedupe, reopen, backup and deletion',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('Private document body'));
      final m = ChatMessage(
        id: 'file',
        peerId: 'alice',
        text: 'File',
        timestamp: 2,
        outgoing: false,
        status: 'received',
        file: await ChatFile.fromBytes('private-report.pdf', bytes),
      );
      expect(await store.saveFileMessage(m, bytes), isTrue);
      expect(await store.saveFileMessage(m, bytes), isFalse);
      final db = await openDatabase(databasePath);
      final row = (await db.query('files')).single;
      expect(row['body'], isNot(base64Encode(bytes)));
      expect(
        (await db.query('messages')).single['body'],
        isNot(contains(m.file!.digest)),
      );
      expect(
        (await db.query('messages')).single['body'],
        isNot(contains('private-report.pdf')),
      );
      await db.update('messages', {'kind': 'image'});
      await expectLater(store.messages('alice'), throwsA(anything));
      await db.update('messages', {'kind': 'file'});
      expect((await store.conversations()).single.unreadCount, 1);
      await store.close();
      store = LocalStore();
      await store.open();
      final saved = (await store.messages('alice')).single;
      expect(await store.fileBytes(saved), bytes);
      final backup = await store.exportBackup();
      expect(backup.toJson()['version'], 4);
      await store.clearHistory();
      await store.importBackup(backup);
      expect(
        await store.fileBytes((await store.messages('alice')).single),
        bytes,
      );
      await store.deleteConversation('alice');
      expect(await (await openDatabase(databasePath)).query('files'), isEmpty);
    },
  );
  test(
    'schema 8 upgrades preserve encrypted text/images and add file storage',
    () async {
      await store.saveMessage(message());
      final bytes = await testImage();
      await store.saveImageMessage(
        ChatMessage(
          id: 'old-image',
          peerId: 'alice',
          text: 'Image',
          timestamp: 1,
          outgoing: false,
          status: 'received',
          image: await ChatImage.fromBytes(bytes),
        ),
        bytes,
      );
      final seed = (await store.exportBackup()).seed;
      await store.close();
      final db = await openDatabase(databasePath);
      await db.execute('DROP TABLE files');
      await db.execute('PRAGMA user_version = 8');
      await db.close();
      store = LocalStore();
      await store.open();
      final records = await store.messages('alice');
      expect(records.singleWhere((m) => m.image == null).text, message().text);
      expect(
        await store.imageBytes(records.singleWhere((m) => m.image != null)),
        bytes,
      );
      expect((await store.exportBackup()).seed, seed);
      final upgraded = await openDatabase(databasePath);
      expect(await upgraded.getVersion(), 12);
      expect(await upgraded.query('files'), isEmpty);
    },
  );
  test('file write failure rolls back metadata and activity', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final m = ChatMessage(
      id: 'file-atomic',
      peerId: 'alice',
      text: 'File',
      timestamp: 1,
      outgoing: false,
      status: 'received',
      file: await ChatFile.fromBytes('a.bin', bytes),
    );
    final db = await openDatabase(databasePath);
    await db.execute(
      "CREATE TRIGGER fail_file BEFORE INSERT ON files BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    final activity = (await store.conversations()).single.updated;
    await expectLater(store.saveFileMessage(m, bytes), throwsA(anything));
    expect(await store.messages('alice'), isEmpty);
    expect(await db.query('files'), isEmpty);
    expect((await store.conversations()).single.updated, activity);
  });
  test('file backup insert failure rolls back the entire import', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await store.saveFileMessage(
      ChatMessage(
        id: 'archive-file',
        peerId: 'alice',
        text: 'File',
        timestamp: 1,
        outgoing: false,
        status: 'received',
        file: await ChatFile.fromBytes('a.bin', bytes),
      ),
      bytes,
    );
    final archive = await store.exportBackup();
    await store.clearHistory();
    await store.savePeer('bob', 'Bob');
    await store.saveMessage(message(peer: 'bob'));
    final db = await openDatabase(databasePath);
    await db.execute(
      "CREATE TRIGGER fail_file BEFORE INSERT ON files BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(store.importBackup(archive), throwsA(anything));
    expect((await store.conversations()).single.id, 'bob');
    expect(await store.messages('alice'), isEmpty);
    expect((await store.messages('bob')).single.text, message().text);
    expect(await db.query('files'), isEmpty);
  });
  test(
    'group image bytes stay encrypted across reopen, v5 backup, dedupe and deletion',
    () async {
      final public = base64Encode(
            (await store.identity.extractPublicKey()).bytes,
          ),
          id = randomId();
      final bytes = await testImage();
      final m = await GroupText.create(
        store.identity,
        'Private image author',
        group: id,
        host: public,
        epoch: randomId(),
        view: 1,
        text: 'Image',
        targets: [await identityId(public)],
        imageBytes: bytes,
      );
      await store.saveGroupHistory(
        GroupHistory(
          id: id,
          title: 'Private image group',
          host: public,
          messages: [m],
          updated: 1000,
        ),
      );
      final db = await openDatabase(databasePath);
      final ciphertext =
          (await db.query('group_history')).single['body'] as String;
      expect(ciphertext, isNot(contains(base64Encode(bytes))));
      expect(
        utf8.decode(base64Decode(ciphertext), allowMalformed: true),
        isNot(contains(m.image!.digest)),
      );
      expect(await db.getVersion(), 12);
      await store.close();
      store = LocalStore();
      await store.open();
      expect(
        (await store.groupHistories()).single.messages.single.imageBytes,
        bytes,
      );
      final backup = await store.exportBackup();
      expect(backup.toJson()['version'], 5);
      await store.clearHistory();
      await store.importBackup(backup);
      expect(
        (await store.groupHistories()).single.messages.single.imageBytes,
        bytes,
      );
      expect((await store.importBackup(backup)).duplicates, 1);
      await store.deleteGroupHistory(id);
      expect(
        await (await openDatabase(databasePath)).query('group_history'),
        isEmpty,
      );
    },
  );
  test(
    'group files remain encrypted with safe signed names across reopen and v6 import',
    () async {
      final public = base64Encode(
            (await store.identity.extractPublicKey()).bytes,
          ),
          id = randomId();
      final bytes = Uint8List.fromList(List.generate(40000, (i) => i % 251));
      final m = await GroupText.create(
        store.identity,
        'Private file author',
        group: id,
        host: public,
        epoch: randomId(),
        view: 1,
        text: 'File',
        targets: [await identityId(public)],
        fileBytes: bytes,
        fileName: '../private?.pdf',
      );
      await store.saveGroupHistory(
        GroupHistory(
          id: id,
          title: 'Private file group',
          host: public,
          messages: [m],
          updated: 1000,
        ),
      );
      final db = await openDatabase(databasePath);
      final ciphertext =
          (await db.query('group_history')).single['body'] as String;
      expect(ciphertext, isNot(contains(base64Encode(bytes))));
      final raw = utf8.decode(base64Decode(ciphertext), allowMalformed: true);
      expect(raw, isNot(contains(m.file!.name)));
      expect(raw, isNot(contains(m.file!.digest)));
      expect(await db.getVersion(), 12);
      await store.close();
      store = LocalStore();
      await store.open();
      final saved = (await store.groupHistories()).single.messages.single;
      expect(saved.fileBytes, bytes);
      expect(saved.file!.name, ChatFile.safeName('../private?.pdf'));
      expect(saved.envelope['signature'], m.envelope['signature']);
      final backup = await store.exportBackup();
      expect(backup.toJson()['version'], 6);
      await store.clearHistory();
      await store.importBackup(backup);
      expect(
        (await store.groupHistories()).single.messages.single.fileBytes,
        bytes,
      );
      expect((await store.importBackup(backup)).duplicates, 1);
      await store.deleteGroupHistory(id);
      expect(
        await (await openDatabase(databasePath)).query('group_history'),
        isEmpty,
      );
    },
  );
  test(
    'failed group-file backup write rolls back direct and group records together',
    () async {
      final source = DemoStore();
      await source.open();
      final public = base64Encode(
            (await source.identity.extractPublicKey()).bytes,
          ),
          id = randomId();
      final m = await GroupText.create(
        source.identity,
        'Author',
        group: id,
        host: public,
        epoch: randomId(),
        view: 1,
        text: 'File',
        targets: [await identityId(public)],
        fileBytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'report.pdf',
      );
      await source.saveGroupHistory(
        GroupHistory(
          id: id,
          title: 'Incoming',
          host: public,
          messages: [m],
          updated: 1,
        ),
      );
      await source.savePeer('new-peer', 'New peer');
      await source.saveMessage(
        ChatMessage(
          id: 'direct',
          peerId: 'new-peer',
          text: 'Imported direct text',
          timestamp: 1,
          outgoing: false,
          status: 'received',
        ),
      );
      await store.saveMessage(message());
      final db = await openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_group_file BEFORE INSERT ON group_history BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        store.importBackup(await source.exportBackup()),
        throwsA(anything),
      );
      expect(await store.groupHistories(), isEmpty);
      expect(await store.messages('new-peer'), isEmpty);
      expect((await store.messages('alice')).single.text, message().text);
      expect(
        (await store.conversations()).map((p) => p.id),
        isNot(contains('new-peer')),
      );
    },
  );
  test(
    'group titles/authors/text/receipts are encrypted and preserved across reopen',
    () async {
      final public = base64Encode(
        (await store.identity.extractPublicKey()).bytes,
      );
      final id = randomId();
      final text = await GroupText.create(
        store.identity,
        'Private author',
        group: id,
        host: public,
        epoch: randomId(),
        view: 1,
        text: 'Private group body سلام',
        targets: [await identityId(public)],
      );
      await store.saveGroupHistory(
        GroupHistory(
          id: id,
          title: 'Private group title',
          host: public,
          messages: [text],
          updated: 1000,
        ),
      );
      final db = await openDatabase(databasePath);
      final ciphertext =
          (await db.query('group_history')).single['body'] as String;
      final bytes = utf8.decode(base64Decode(ciphertext), allowMalformed: true);
      expect(bytes, isNot(contains('Private group')));
      expect(bytes, isNot(contains('Private author')));
      await store.close();
      store = LocalStore();
      await store.open();
      final saved = (await store.groupHistories()).single;
      expect(saved.title, 'Private group title');
      expect(saved.messages.single.text, text.text);
      expect(
        saved.messages.single.envelope['signature'],
        text.envelope['signature'],
      );
      final backup = await store.exportBackup();
      expect(backup.groups.length, 1);
      await store.clearHistory();
      expect(await store.groupHistories(), isEmpty);
      await store.importBackup(backup);
      expect(
        (await store.groupHistories()).single.messages.single.receipts.values,
        everyElement('unconfirmed'),
      );
    },
  );
  test(
    'schema six upgrades without losing existing direct history and creates group storage',
    () async {
      await store.saveMessage(message());
      final db = await openDatabase(databasePath);
      await db.execute('DROP TABLE group_history');
      await db.execute('PRAGMA user_version = 6');
      await store.close();
      store = LocalStore();
      await store.open();
      expect((await store.messages('alice')).single.text, message().text);
      expect(await store.groupHistories(), isEmpty);
      final public = base64Encode(
        (await store.identity.extractPublicKey()).bytes,
      );
      await store.saveGroupHistory(
        GroupHistory(id: randomId(), title: 'Upgraded', host: public),
      );
      expect((await store.groupHistories()).single.title, 'Upgraded');
    },
  );
  test(
    'SQLite contains ciphertext; reopening preserves identity, text and delivery uncertainty',
    () async {
      final identity = base64Encode(
        (await store.identity.extractPublicKey()).bytes,
      );
      await store.saveMessage(message());
      final db = await openDatabase(databasePath);
      final row = (await db.query('messages')).single;
      expect(row['body'], isNot(contains('Private text')));
      expect(base64Decode(row['body'] as String).length, greaterThan(40));
      await store.close();
      store = LocalStore();
      await store.open();
      expect(
        base64Encode((await store.identity.extractPublicKey()).bytes),
        identity,
      );
      expect(
        (await store.messages('alice')).single.text,
        'Private text سلام 👋',
      );
      expect((await store.messages('alice')).single.status, 'unconfirmed');
    },
  );
  test(
    'Message IDs are scoped by peer and direction; acknowledgements only affect outbound message',
    () async {
      await store.savePeer('bob', 'Bob');
      await store.saveMessage(message());
      expect(await store.saveMessage(message(outgoing: false)), true);
      await store.saveMessage(message(peer: 'bob'));
      expect(await store.saveMessage(message(outgoing: false)), false);
      await store.setStatus('id-1', 'alice', 'delivered');
      final alice = await store.messages('alice');
      expect(alice.length, 2);
      expect(alice.singleWhere((m) => m.outgoing).status, 'delivered');
      expect(alice.singleWhere((m) => !m.outgoing).status, 'sending');
      expect((await store.messages('bob')).single.status, 'sending');
    },
  );
  test('Modified stored ciphertext fails authentication', () async {
    await store.saveMessage(message());
    final db = await openDatabase(databasePath);
    final row = (await db.query('messages')).single;
    final bytes = base64Decode(row['body'] as String);
    bytes[24] ^= 1;
    await db.update('messages', {'body': base64Encode(bytes)});
    await expectLater(
      store.messages('alice'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      store.conversations(),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      store.search('Private'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test(
    'Local search finds literal Unicode text across peers and directions without marking read',
    () async {
      await store.savePeer('bob', 'BÓB سلام');
      await store.saveMessage(message());
      await store.saveMessage(message(outgoing: false));
      await store.saveMessage(message(peer: 'bob', outgoing: false));
      final hits = await store.search('  PRIVATE  ');
      expect(hits.messages.map((h) => (h.message.peerId, h.message.outgoing)), [
        ('bob', false),
        ('alice', false),
        ('alice', true),
      ]);
      expect((await store.search('ALICE')).conversations.single.name, 'Alice');
      final unicode = await store.search('سلام');
      expect(unicode.messages.length, 3);
      expect(unicode.conversations.single.id, 'bob');
      await store.saveMessage(
        const ChatMessage(
          id: 'literal',
          peerId: 'alice',
          text: 'Literal %_ characters',
          timestamp: 1,
          outgoing: true,
          status: 'delivered',
        ),
      );
      expect((await store.search('%_')).messages.single.message.id, 'literal');
      expect(
        (await store.conversations()).map((p) => p.unreadCount),
        everyElement(1),
      );
      expect((await store.search('   ')).messages, isEmpty);
      expect((await store.search('absent')).messages, isEmpty);
      final db = await openDatabase(databasePath);
      expect(
        (await db.query(
          'messages',
        )).every((r) => !(r['body'] as String).contains('Private text')),
        isTrue,
      );
      await store.clearHistory();
      expect((await store.search('Private')).messages, isEmpty);
    },
  );

  test(
    'Search scans beyond a batch, bounds newest matches and cancels obsolete work',
    () async {
      for (var i = 0; i < 106; i++) {
        await store.saveMessage(
          ChatMessage(
            id: 'search-$i',
            peerId: 'alice',
            text: i % 52 == 0 ? 'Needle $i' : 'Other $i',
            timestamp: i,
            outgoing: false,
            status: 'received',
          ),
        );
      }
      final all = await store.search('needle');
      expect(all.messages.map((h) => h.message.id), [
        'search-104',
        'search-52',
        'search-0',
      ]);
      expect(all.hasMoreMessages, isFalse);
      final limited = await store.search('needle', limit: 2);
      expect(limited.messages.map((h) => h.message.id), [
        'search-104',
        'search-52',
      ]);
      expect(limited.hasMoreMessages, isTrue);
      var checks = 0;
      final cancelled = await store.search(
        'needle',
        isCancelled: () => ++checks > 7,
      );
      expect(cancelled.messages, isEmpty);
      expect(checks, 8);
      expect((await store.conversations()).single.unreadCount, 106);
    },
  );

  test(
    'Unread summaries persist, deduplicate and clear only the opened peer',
    () async {
      await store.savePeer('bob', 'Bob');
      await store.saveMessage(message(outgoing: false));
      await store.saveMessage(message());
      await store.saveMessage(message(peer: 'bob', outgoing: false));
      await store.saveMessage(message(outgoing: false));
      var summaries = await store.conversations();
      expect(summaries.singleWhere((p) => p.id == 'alice').unreadCount, 1);
      expect(
        summaries.singleWhere((p) => p.id == 'alice').latestMessage!.outgoing,
        isTrue,
      );
      expect(summaries.singleWhere((p) => p.id == 'bob').unreadCount, 1);
      final db = await openDatabase(databasePath);
      expect(
        (await db.query(
          'messages',
        )).every((row) => !(row['body'] as String).contains('Private text')),
        isTrue,
      );
      expect(
        (await db.rawQuery('PRAGMA table_info(peers)')).map((r) => r['name']),
        isNot(contains('preview')),
      );
      await store.close();
      store = LocalStore(now: () => clock);
      await store.open();
      summaries = await store.conversations();
      expect(summaries.map((p) => p.unreadCount), everyElement(1));
      expect(
        summaries.singleWhere((p) => p.id == 'alice').latestMessage!.text,
        'Private text سلام 👋',
      );
      await store.markRead('alice');
      await store.saveMessage(message(outgoing: false)); // Must remain read.
      await store.close();
      store = LocalStore(now: () => clock);
      await store.open();
      summaries = await store.conversations();
      expect(summaries.singleWhere((p) => p.id == 'alice').unreadCount, 0);
      expect(summaries.singleWhere((p) => p.id == 'bob').unreadCount, 1);
    },
  );

  test(
    'Latest local message activity orders chats; names, acknowledgements and duplicates do not',
    () async {
      await store.saveMessage(message());
      final aliceTime = (await store.conversations()).single.updated;
      clock = clock.add(const Duration(minutes: 1));
      await store.savePeer('bob', 'Bob');
      await store.saveMessage(message(peer: 'bob', outgoing: false));
      clock = clock.add(const Duration(minutes: 1));
      await store.savePeer('alice', 'Renamed Alice');
      await store.savePeer('empty', 'No messages');
      await store.setStatus('id-1', 'alice', 'delivered');
      await store.markRead('bob');
      await store.saveMessage(message());
      var summaries = await store.conversations();
      expect(summaries.map((p) => p.id), ['bob', 'alice', 'empty']);
      expect(summaries[1].updated, aliceTime);
      expect(summaries[1].name, 'Renamed Alice');
      expect(summaries[2].latestMessage, isNull);
      // Sender timestamps may be wrong. The last saved message is still latest.
      await store.saveMessage(
        ChatMessage(
          id: 'new',
          peerId: 'alice',
          text: 'New arrival',
          timestamp: 0,
          outgoing: false,
          status: 'received',
        ),
      );
      summaries = await store.conversations();
      expect(summaries.first.id, 'alice');
      expect(summaries.first.latestMessage!.text, 'New arrival');
      expect(summaries.first.updated, clock.millisecondsSinceEpoch);
    },
  );

  test(
    'Version 1 upgrade preserves encrypted history and initializes old messages as read',
    () async {
      await store.saveMessage(message(outgoing: false));
      final db = await openDatabase(databasePath);
      final oldMessage =
          Map<String, Object?>.from((await db.query('messages')).single)
            ..remove('is_read')
            ..remove('kind');
      final oldPeer =
          Map<String, Object?>.from((await db.query('peers')).single)
            ..remove('pinned')
            ..remove('archived');
      final key = (await store.identity.extractPublicKey()).bytes;
      await store.close();
      await deleteDatabase(databasePath);
      final legacy = await openDatabase(
        databasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE peers (id TEXT PRIMARY KEY, name TEXT NOT NULL, updated INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE messages (id TEXT NOT NULL, peer TEXT NOT NULL, body TEXT NOT NULL, timestamp INTEGER NOT NULL, outgoing INTEGER NOT NULL, status TEXT NOT NULL, PRIMARY KEY(peer, id, outgoing))',
          );
          await db.execute(
            'CREATE INDEX message_peer_time ON messages(peer, timestamp)',
          );
          await db.insert('peers', oldPeer);
          await db.insert('messages', oldMessage);
        },
      );
      await legacy.close();
      store = LocalStore(now: () => clock);
      await store.open();
      expect((await store.identity.extractPublicKey()).bytes, key);
      expect(
        (await store.messages('alice')).single.text,
        'Private text سلام 👋',
      );
      expect((await store.conversations()).single.unreadCount, 0);
      final upgraded = await openDatabase(databasePath);
      expect(await upgraded.getVersion(), 12);
      await store.saveMessage(
        ChatMessage(
          id: 'after-upgrade',
          peerId: 'alice',
          text: 'New unread',
          timestamp: 2,
          outgoing: false,
          status: 'received',
        ),
      );
      expect((await store.conversations()).single.unreadCount, 1);
    },
  );
  test(
    'History deletion removes conversations and messages but keeps identity',
    () async {
      await store.saveMessage(message());
      await store.saveDraft('alice', 'Unsent text');
      final key = (await store.identity.extractPublicKey()).bytes;
      await store.clearHistory();
      expect(await store.conversations(), isEmpty);
      expect(await store.messages('alice'), isEmpty);
      expect(await store.draft('alice'), '');
      expect((await store.identity.extractPublicKey()).bytes, key);
    },
  );

  test(
    'Drafts encrypt exact per-peer text and survive reopening without affecting chats',
    () async {
      const text = '  Private draft سلام 👋\nsecond line  ';
      await store.saveMessage(message(outgoing: false));
      final before = (await store.conversations()).single;
      await store.saveDraft('alice', text);
      await store.saveDraft('bob', 'A different draft');
      expect(await store.draft('missing'), '');
      final db = await openDatabase(databasePath);
      final rows = await db.query('drafts');
      expect(rows.length, 2);
      expect(
        rows.map((r) => r['body']),
        everyElement(isNot(contains('draft'))),
      );
      final firstBody = rows.first['body'];
      await store.saveDraft('alice', text);
      expect(
        (await db.query(
          'drafts',
          where: 'peer = ?',
          whereArgs: ['alice'],
        )).single['body'],
        isNot(firstBody),
      );
      await store.close();
      store = LocalStore();
      await store.open();
      expect(await store.draft('alice'), text);
      expect(await store.draft('bob'), 'A different draft');
      // The composer counts characters, while send validation counts bytes.
      // Even an oversized-to-send Unicode draft must remain recoverable.
      await store.saveDraft('bob', '👋' * 2500);
      expect(await store.draft('bob'), '👋' * 2500);
      final after = (await store.conversations()).single;
      expect(after.updated, before.updated);
      expect(after.unreadCount, 1);
      expect((await store.search('Private draft')).messages, isEmpty);
      await store.saveDraft('alice', '');
      expect(await store.draft('alice'), '');
      expect(await store.draft('bob'), '👋' * 2500);
    },
  );

  test(
    'Draft authentication rejects tampering and ciphertext moved between peers',
    () async {
      await store.saveDraft('alice', 'Secret draft');
      final db = await openDatabase(databasePath);
      final body = (await db.query('drafts')).single['body'] as String;
      await db.insert('drafts', {'peer': 'bob', 'body': body});
      await expectLater(
        store.draft('bob'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final bytes = base64Decode(body)..[24] ^= 1;
      await db.update(
        'drafts',
        {'body': base64Encode(bytes)},
        where: 'peer = ?',
        whereArgs: ['alice'],
      );
      await expectLater(
        store.draft('alice'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );

  test(
    'Version 2 upgrade adds drafts and preserves encrypted history and read state',
    () async {
      await store.saveMessage(message(outgoing: false));
      final db = await openDatabase(databasePath);
      await db.execute('DROP TABLE drafts');
      await legacyPeerTable(db);
      await db.setVersion(2);
      await store.close();
      store = LocalStore();
      await store.open();
      expect((await store.messages('alice')).single.text, message().text);
      expect((await store.conversations()).single.unreadCount, 1);
      expect(await store.draft('alice'), '');
      await store.saveDraft('alice', 'After upgrade');
      expect(await store.draft('alice'), 'After upgrade');
    },
  );

  test(
    'Pinned ordering and archived metadata persist across activity, names, reads and restarts',
    () async {
      await store.saveMessage(message(outgoing: false));
      final aliceTime = (await store.conversations()).single.updated;
      clock = clock.add(const Duration(minutes: 1));
      await store.savePeer('bob', 'Bob');
      await store.saveMessage(message(peer: 'bob', outgoing: false));
      await store.saveDraft('alice', 'A draft');
      expect(await store.setPinned('alice', true), isTrue);
      expect(await store.setArchived('alice', true), isTrue);
      expect(await store.setPinned('missing', true), isFalse);
      expect(await store.setArchived('missing', true), isFalse);
      var all = await store.conversations();
      expect(all.map((p) => p.id), ['alice', 'bob']);
      expect(all.first.updated, aliceTime);
      expect(all.first.unreadCount, 1);
      expect(await store.draft('alice'), 'A draft');
      await store.savePeer('alice', 'Renamed Alice');
      await store.setStatus('id-1', 'alice', 'delivered');
      await store.saveMessage(message(outgoing: false)); // Duplicate.
      await store.close();
      store = LocalStore(now: () => clock);
      await store.open();
      all = await store.conversations();
      expect(all.first.pinned, isTrue);
      expect(all.first.archived, isTrue);
      expect(all.first.updated, aliceTime);
      await store.saveMessage(
        const ChatMessage(
          id: 'new-arrival',
          peerId: 'alice',
          text: 'New private arrival',
          timestamp: 2,
          outgoing: false,
          status: 'received',
        ),
      );
      expect((await store.conversations()).first.archived, isTrue);
      expect(
        (await store.search('Renamed')).conversations.single.archived,
        isTrue,
      );
      expect(
        (await store.search('arrival')).messages.single.conversation.pinned,
        isTrue,
      );
      await store.markRead('alice');
      await store.setArchived('alice', false);
      await store.setPinned('alice', false);
      all = await store.conversations();
      expect(all.singleWhere((p) => p.id == 'alice').unreadCount, 0);
      expect(all.every((p) => !p.archived && !p.pinned), isTrue);
    },
  );

  test(
    'Deleting one conversation removes its encrypted records and draft but preserves others and identity',
    () async {
      await store.savePeer('bob', 'Bob');
      await store.saveMessage(message());
      await store.saveMessage(message(outgoing: false));
      await store.saveMessage(message(peer: 'bob', outgoing: false));
      await store.saveDraft('alice', 'Alice draft');
      await store.saveDraft('bob', 'Bob draft');
      await store.setPinned('alice', true);
      await store.setArchived('alice', true);
      final identity = (await store.identity.extractPublicKey()).bytes;
      await store.deleteConversation('alice');
      await store.deleteConversation(
        'alice',
      ); // Idempotent, no other peer touched.
      expect((await store.conversations()).single.id, 'bob');
      expect((await store.conversations()).single.unreadCount, 1);
      expect(await store.messages('alice'), isEmpty);
      expect(await store.draft('alice'), '');
      expect(await store.draft('bob'), 'Bob draft');
      expect(
        (await store.search('Private')).messages.single.message.peerId,
        'bob',
      );
      expect((await store.identity.extractPublicKey()).bytes, identity);
      await store.close();
      store = LocalStore();
      await store.open();
      expect(await store.messages('alice'), isEmpty);
      expect((await store.conversations()).single.id, 'bob');
    },
  );

  test(
    'Version 3 upgrade preserves drafts, encrypted messages, identity and unread state',
    () async {
      await store.saveMessage(message(outgoing: false));
      await store.saveDraft('alice', 'Older draft');
      final identity = (await store.identity.extractPublicKey()).bytes;
      final db = await openDatabase(databasePath);
      await legacyPeerTable(db);
      await db.setVersion(3);
      await store.close();
      store = LocalStore();
      await store.open();
      final peer = (await store.conversations()).single;
      expect(peer.pinned, isFalse);
      expect(peer.archived, isFalse);
      expect(peer.unreadCount, 1);
      expect(peer.latestMessage!.text, message().text);
      expect(await store.draft('alice'), 'Older draft');
      expect((await store.identity.extractPublicKey()).bytes, identity);
      expect(await store.setPinned('alice', true), isTrue);
      expect(await store.setArchived('alice', true), isTrue);
    },
  );
  Future<BackupData> incomingBackup() async {
    final demo = DemoStore();
    await demo.open();
    await demo.savePeer('alice', 'Backup Alice');
    await demo.savePeer('bob', 'Backup Bob');
    await demo.setPinned('alice', true);
    await demo.setArchived('bob', true);
    await demo.saveMessage(message());
    await demo.saveMessage(message(outgoing: false));
    await demo.saveMessage(message(peer: 'bob', outgoing: false));
    await demo.saveDraft('alice', 'Imported draft');
    await demo.saveDraft('bob', 'Other imported draft سلام 👋');
    final data = await demo.exportBackup();
    return BackupData.parse({...data.toJson(), 'demo': false});
  }

  test(
    'Backup merges by peer/id/direction, retains existing state and re-encrypts bodies',
    () async {
      await store.saveMessage(message());
      await store.setStatus('id-1', 'alice', 'delivered');
      await store.saveDraft('alice', 'Existing draft');
      final seed = (await store.exportBackup()).seed;
      final incoming = await incomingBackup();
      final result = await store.importBackup(incoming);
      expect(result.newChats, 1);
      expect(result.newMessages, 2);
      expect(result.duplicates, 1);
      expect(result.keptDrafts, 1);
      expect((await store.exportBackup()).seed, seed);
      expect(await store.draft('alice'), 'Existing draft');
      expect(await store.draft('bob'), 'Other imported draft سلام 👋');
      final peers = await store.conversations();
      expect(peers.singleWhere((p) => p.id == 'alice').pinned, isFalse);
      expect(peers.singleWhere((p) => p.id == 'alice').name, 'Alice');
      expect(peers.singleWhere((p) => p.id == 'bob').archived, isTrue);
      expect(peers.singleWhere((p) => p.id == 'bob').unreadCount, 1);
      expect((await store.messages('alice')).first.status, 'delivered');
      final db = await openDatabase(databasePath);
      expect(
        (await db.query(
          'messages',
        )).every((r) => !(r['body'] as String).contains('Private')),
        isTrue,
      );
      final repeat = await store.importBackup(incoming);
      expect(repeat.newMessages, 0);
      expect(repeat.duplicates, 3);
      await store.close();
      store = LocalStore();
      await store.open();
      expect((await store.exportBackup()).seed, seed);
      expect(await store.draft('bob'), 'Other imported draft سلام 👋');
    },
  );

  test(
    'Import rolls back every record on an insert failure; invalid contents never mutate',
    () async {
      final incoming = await incomingBackup();
      final db = await openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_import BEFORE INSERT ON messages BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(store.importBackup(incoming), throwsA(anything));
      expect((await store.conversations()).single.id, 'alice');
      expect(await store.messages('alice'), isEmpty);
      expect(await store.draft('bob'), '');
      final originalIdentity = (await store.exportBackup()).seed;
      await store.clearHistory();
      await expectLater(
        store.importBackup(incoming, moveIdentity: true),
        throwsA(anything),
      );
      expect(await store.conversations(), isEmpty);
      expect((await store.exportBackup()).seed, originalIdentity);
      expect(
        await const FlutterSecureStorage().read(
          key: 'identity_import_pending_v1',
        ),
        isNull,
      );
      await store.savePeer('alice', 'Alice');
      await db.execute('DROP TRIGGER fail_import');
      final invalid = BackupData(
        seed: incoming.seed,
        owner: incoming.owner,
        name: incoming.name,
        created: incoming.created,
        demo: false,
        peers: incoming.peers,
        messages: [
          {...incoming.messages.first, 'peer': 'missing'},
        ],
        drafts: [],
      );
      await expectLater(store.importBackup(invalid), throwsFormatException);
      expect((await store.conversations()).single.id, 'alice');
    },
  );

  test(
    'Identity migration requires an empty store and survives restart with destination history key',
    () async {
      final incoming = await incomingBackup();
      await expectLater(
        store.importBackup(incoming, moveIdentity: true),
        throwsFormatException,
      );
      expect((await store.conversations()).single.id, 'alice');
      await store.clearHistory();
      const vault = FlutterSecureStorage();
      final historyKey = await vault.read(key: 'history_key_v1');
      await store.importBackup(incoming, moveIdentity: true);
      expect((await store.exportBackup()).seed, incoming.seed);
      expect(await vault.read(key: 'identity_import_pending_v1'), isNull);
      expect(await vault.read(key: 'history_key_v1'), historyKey);
      await store.close();
      store = LocalStore();
      await store.open();
      expect((await store.exportBackup()).seed, incoming.seed);
      expect((await store.messages('bob')).single.text, message().text);
      expect(await store.draft('bob'), 'Other imported draft سلام 👋');
    },
  );

  test(
    'Crash journal uses committed identity or rolls back an uncommitted identity',
    () async {
      final incoming = await incomingBackup();
      final old = (await store.exportBackup()).seed;
      const vault = FlutterSecureStorage();
      for (final committed in [false, true]) {
        await vault.write(key: 'identity_seed_v1', value: old);
        await vault.write(
          key: 'identity_import_pending_v1',
          value: jsonEncode({
            'id': 'migration-test',
            'old': old,
            'new': incoming.seed,
          }),
        );
        final db = await openDatabase(databasePath);
        if (committed) {
          await db.insert('backup_receipt', {'id': 'migration-test'});
        }
        await store.close();
        store = LocalStore();
        await store.open();
        expect(
          (await store.exportBackup()).seed,
          committed ? incoming.seed : old,
        );
        expect(await vault.read(key: 'identity_import_pending_v1'), isNull);
        expect(
          await (await openDatabase(databasePath)).query('backup_receipt'),
          isEmpty,
        );
      }
    },
  );

  test(
    'Version 4 upgrade preserves encrypted chats, flags and drafts',
    () async {
      await store.saveMessage(message(outgoing: false));
      await store.saveDraft('alice', 'Version four draft');
      await store.setArchived('alice', true);
      await store.setPinned('alice', true);
      final seed = (await store.exportBackup()).seed;
      final db = await openDatabase(databasePath);
      await db.execute('DROP TABLE backup_receipt');
      await db.setVersion(4);
      await store.close();
      store = LocalStore();
      await store.open();
      final p = (await store.conversations()).single;
      expect(p.pinned && p.archived, isTrue);
      expect(p.unreadCount, 1);
      expect(await store.draft('alice'), 'Version four draft');
      expect((await store.exportBackup()).seed, seed);
      expect(await (await openDatabase(databasePath)).getVersion(), 12);
    },
  );
  test(
    'A failed final vault write leaves a committed migration recoverable on restart',
    () async {
      final incoming = await incomingBackup();
      await store.clearHistory();
      await store.close();
      store = LocalStore(vault: FailIdentityWrite(incoming.seed));
      await store.open();
      await expectLater(
        store.importBackup(incoming, moveIdentity: true),
        throwsStateError,
      );
      expect(store.identityRecoveryRequired, isTrue);
      expect((await store.conversations()).length, 2);
      expect(
        await const FlutterSecureStorage().read(
          key: 'identity_import_pending_v1',
        ),
        isNotNull,
      );
      await store.close();
      store = LocalStore();
      await store.open();
      expect(store.identityRecoveryRequired, isFalse);
      expect((await store.exportBackup()).seed, incoming.seed);
      expect((await store.messages('bob')).single.text, message().text);
    },
  );
  ChatMessage queued(String id, {int timestamp = 1000}) => ChatMessage(
    id: id,
    peerId: 'alice',
    text: 'Queued private سلام 👋',
    timestamp: timestamp,
    outgoing: true,
    status: 'queued',
  );

  test(
    'Outbox acceptance encrypts text, atomically clears the draft and survives schema-5 restart',
    () async {
      await store.saveDraft('alice', 'Composer draft');
      await store.setPinned('alice', true);
      await store.setArchived('alice', true);
      final identity = (await store.exportBackup()).seed;
      await store.saveOutgoingMessage(
        queued('a' * 24, timestamp: 3000),
        clearDraft: true,
      );
      await store.saveOutgoingMessage(queued('b' * 24, timestamp: 1000));
      await store.changeOutgoingStatus('b' * 24, 'alice', [
        'queued',
      ], 'sending');
      expect(await store.draft('alice'), '');
      expect((await store.conversations()).single.queuedCount, 1);
      final db = await openDatabase(databasePath);
      expect(
        (await db.query(
          'messages',
        )).every((r) => !(r['body'] as String).contains('Queued private')),
        isTrue,
      );
      await db.execute('DROP INDEX message_outbox');
      await db.setVersion(5);
      await store.close();
      store = LocalStore();
      await store.open();
      final messages = await store.messages('alice');
      expect(messages.singleWhere((m) => m.id == 'a' * 24).status, 'queued');
      expect(
        messages.singleWhere((m) => m.id == 'b' * 24).status,
        'unconfirmed',
      );
      final peer = (await store.conversations()).single;
      expect(peer.pinned && peer.archived, isTrue);
      expect(peer.queuedCount, 1);
      expect((await store.exportBackup()).seed, identity);
      expect(await (await openDatabase(databasePath)).getVersion(), 12);
    },
  );

  test(
    'Draft cleanup failure rolls back outgoing acceptance and its activity update',
    () async {
      await store.saveDraft('alice', 'Keep this draft');
      final activity = (await store.conversations()).single.updated;
      clock = clock.add(const Duration(minutes: 1));
      final db = await openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_draft_delete BEFORE DELETE ON drafts BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        store.saveOutgoingMessage(queued('a' * 24), clearDraft: true),
        throwsA(anything),
      );
      expect(await store.messages('alice'), isEmpty);
      expect(await store.draft('alice'), 'Keep this draft');
      expect((await store.conversations()).single.updated, activity);
    },
  );

  test(
    'FIFO uses insertion order; status and cancel operations are scoped and cannot undo delivery',
    () async {
      await store.savePeer('bob', 'Bob');
      await store.saveOutgoingMessage(queued('a' * 24, timestamp: 3000));
      await store.saveOutgoingMessage(queued('b' * 24, timestamp: 1000));
      await store.saveMessage(
        ChatMessage(
          id: 'a' * 24,
          peerId: 'alice',
          text: 'Incoming same ID',
          timestamp: 3000,
          outgoing: false,
          status: 'received',
        ),
      );
      await store.saveMessage(
        ChatMessage(
          id: 'a' * 24,
          peerId: 'bob',
          text: 'Other peer',
          timestamp: 3000,
          outgoing: true,
          status: 'queued',
        ),
      );
      expect(
        (await store.queuedMessages('alice', limit: 10)).map((m) => m.id),
        ['a' * 24, 'b' * 24],
      );
      await store.changeOutgoingStatus('a' * 24, 'alice', [
        'queued',
      ], 'sending');
      await store.changeOutgoingStatus('a' * 24, 'alice', [
        'sending',
      ], 'delivered');
      expect(await store.deleteQueuedMessage('a' * 24, 'alice'), isFalse);
      expect(
        await store.changeOutgoingStatus('a' * 24, 'alice', [
          'unconfirmed',
        ], 'queued'),
        isFalse,
      );
      expect(await store.deleteQueuedMessage('b' * 24, 'alice'), isTrue);
      final alice = await store.messages('alice');
      expect(alice.length, 2);
      expect(alice.singleWhere((m) => !m.outgoing).status, 'received');
      expect((await store.messages('bob')).single.status, 'queued');
    },
  );

  test(
    'Backups retain queued status in exports but imports never schedule its transmission',
    () async {
      await store.saveOutgoingMessage(queued('a' * 24));
      final backup = await store.exportBackup();
      expect(backup.messages.single['status'], 'queued');
      await BackupData.parse(backup.toJson());
      await store.clearHistory();
      await store.importBackup(backup);
      expect((await store.messages('alice')).single.status, 'unconfirmed');
      expect((await store.conversations()).single.queuedCount, 0);
      expect(await store.queuedMessages('alice'), isEmpty);
    },
  );
}

class FailIdentityWrite extends FlutterSecureStorage {
  FailIdentityWrite(this.seed);
  final String seed;
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == 'identity_seed_v1' && value == seed) {
      throw StateError('Test vault write failure');
    }
    await super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

Future<void> legacyPeerTable(Database db) => db.transaction((txn) async {
  await txn.execute(
    'CREATE TABLE legacy_peers (id TEXT PRIMARY KEY, name TEXT NOT NULL, updated INTEGER NOT NULL)',
  );
  await txn.execute(
    'INSERT INTO legacy_peers SELECT id, name, updated FROM peers',
  );
  await txn.execute('DROP TABLE peers');
  await txn.execute('ALTER TABLE legacy_peers RENAME TO peers');
});
