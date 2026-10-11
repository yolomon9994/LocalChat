import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/local_store.dart';
import 'package:local_chat/core/models.dart';
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
      await store.saveMessage(message(outgoing: false));
      await store.saveMessage(message(peer: 'bob'));
      await store.saveMessage(message(outgoing: false)); // Duplicate receive.
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
      final oldMessage = Map<String, Object?>.from(
        (await db.query('messages')).single,
      )..remove('is_read');
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
      expect(await upgraded.getVersion(), 4);
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
