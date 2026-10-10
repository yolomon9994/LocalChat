import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'models.dart';

class LocalStore {
  LocalStore({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  static const _vault = FlutterSecureStorage();
  late Database _database;
  late SecretKey _historyKey;
  late SimpleKeyPair identity;
  String name = 'LocalChat user';
  final _cipher = Xchacha20.poly1305Aead();

  Future<void> open() async {
    var seed = await _vault.read(key: 'identity_seed_v1');
    if (seed == null) {
      seed = base64Encode(
        await (await Ed25519().newKeyPair()).extractPrivateKeyBytes(),
      );
      await _vault.write(key: 'identity_seed_v1', value: seed);
    }
    identity = await Ed25519().newKeyPairFromSeed(base64Decode(seed));
    var historyKey = await _vault.read(key: 'history_key_v1');
    if (historyKey == null) {
      historyKey = base64Encode(
        await (await _cipher.newSecretKey()).extractBytes(),
      );
      await _vault.write(key: 'history_key_v1', value: historyKey);
    }
    _historyKey = SecretKey(base64Decode(historyKey));
    name = await _vault.read(key: 'profile_name') ?? name;
    _database = await openDatabase(
      path.join(await getDatabasesPath(), 'localchat.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE peers (id TEXT PRIMARY KEY, name TEXT NOT NULL, updated INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE messages (id TEXT NOT NULL, peer TEXT NOT NULL, body TEXT NOT NULL, timestamp INTEGER NOT NULL, outgoing INTEGER NOT NULL, status TEXT NOT NULL, is_read INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(peer, id, outgoing))',
        );
        await db.execute(
          'CREATE INDEX message_peer_time ON messages(peer, timestamp)',
        );
        await _createSummaryIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Old installations have no read state. Keep existing history read.
          await db.execute(
            'ALTER TABLE messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 1',
          );
          await _createSummaryIndexes(db);
        }
      },
    );
    // A process termination leaves delivery unknown, never silently "delivered".
    await _database.update('messages', {
      'status': 'unconfirmed',
    }, where: "status = 'sending'");
  }

  static Future<void> _createSummaryIndexes(Database db) async {
    await db.execute('CREATE INDEX message_peer_latest ON messages(peer)');
    await db.execute(
      'CREATE INDEX message_peer_unread ON messages(peer, outgoing, is_read)',
    );
  }

  Future<void> rename(String value) async {
    await _vault.write(key: 'profile_name', value: value);
    name = value;
  }

  Future<void> savePeer(String id, String name) async {
    await _database.transaction((txn) async {
      await txn.insert('peers', {
        'id': id,
        'name': name,
        'updated': _now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // Learning the name again is not new message activity.
      await txn.update(
        'peers',
        {'name': name},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Conversation>> conversations() async {
    final rows = await _database.rawQuery('''
      SELECT p.id AS peer_id, p.name, p.updated,
             m.id, m.peer, m.body, m.timestamp, m.outgoing, m.status,
             (SELECT COUNT(*) FROM messages u
              WHERE u.peer = p.id AND u.outgoing = 0 AND u.is_read = 0) AS unread_count
      FROM peers p
      LEFT JOIN messages m ON m.rowid =
        (SELECT rowid FROM messages WHERE peer = p.id ORDER BY rowid DESC LIMIT 1)
      ORDER BY (m.id IS NOT NULL) DESC, p.updated DESC, p.id ASC
    ''');
    final result = <Conversation>[];
    for (final row in rows) {
      result.add(
        Conversation(
          row['peer_id'] as String,
          row['name'] as String,
          row['updated'] as int,
          latestMessage: row['id'] == null ? null : await _decodeMessage(row),
          unreadCount: row['unread_count'] as int,
        ),
      );
    }
    return result;
  }

  Future<void> saveMessage(ChatMessage message) async {
    final box = await _cipher.encrypt(
      utf8.encode(message.text),
      secretKey: _historyKey,
      aad: utf8.encode(
        '${message.peerId}/${message.id}/${message.outgoing ? 1 : 0}',
      ),
    );
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'messages',
        columns: ['id'],
        where: 'peer = ? AND id = ? AND outgoing = ?',
        whereArgs: [message.peerId, message.id, message.outgoing ? 1 : 0],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      await txn.insert('messages', {
        'id': message.id,
        'peer': message.peerId,
        'body': base64Encode([
          ...box.nonce,
          ...box.mac.bytes,
          ...box.cipherText,
        ]),
        'timestamp': message.timestamp,
        'outgoing': message.outgoing ? 1 : 0,
        'status': message.status,
        'is_read': message.outgoing ? 1 : 0,
      });
      await txn.update(
        'peers',
        {'updated': _now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [message.peerId],
      );
    });
  }

  Future<void> markRead(String peer) => _database
      .update(
        'messages',
        {'is_read': 1},
        where: 'peer = ? AND outgoing = 0 AND is_read = 0',
        whereArgs: [peer],
      )
      .then((_) {});

  Future<void> setStatus(String id, String peer, String status) async {
    await _database.update(
      'messages',
      {'status': status},
      where: 'id = ? AND peer = ? AND outgoing = 1',
      whereArgs: [id, peer],
    );
  }

  Future<List<ChatMessage>> messages(String peer) async {
    final rows = await _database.query(
      'messages',
      where: 'peer = ?',
      whereArgs: [peer],
      orderBy: 'timestamp ASC',
    );
    final result = <ChatMessage>[];
    for (final r in rows) {
      result.add(await _decodeMessage(r));
    }
    return result;
  }

  Future<ChatMessage> _decodeMessage(Map<String, Object?> r) async {
    final peer = r['peer'] as String;
    final bytes = base64Decode(r['body'] as String);
    final clear = await _cipher.decrypt(
      SecretBox(
        bytes.sublist(40),
        nonce: bytes.sublist(0, 24),
        mac: Mac(bytes.sublist(24, 40)),
      ),
      secretKey: _historyKey,
      aad: utf8.encode('$peer/${r['id']}/${r['outgoing']}'),
    );
    return ChatMessage(
      id: r['id'] as String,
      peerId: peer,
      text: utf8.decode(clear),
      timestamp: r['timestamp'] as int,
      outgoing: r['outgoing'] == 1,
      status: r['status'] as String,
    );
  }

  Future<void> clearHistory() async {
    await _database.transaction((txn) async {
      await txn.delete('messages');
      await txn.delete('peers');
    });
  }

  Future<void> close() => _database.close();
}
