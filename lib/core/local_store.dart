import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'models.dart';

class LocalStore {
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
      },
    );
    // A process termination leaves delivery unknown, never silently "delivered".
    await _database.update('messages', {
      'status': 'unconfirmed',
    }, where: "status = 'sending'");
  }

  Future<void> rename(String value) async {
    await _vault.write(key: 'profile_name', value: value);
    name = value;
  }

  Future<void> savePeer(String id, String name) => _database
      .insert('peers', {
        'id': id,
        'name': name,
        'updated': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
  Future<List<Conversation>> conversations() async =>
      (await _database.query('peers', orderBy: 'updated DESC'))
          .map(
            (r) => Conversation(
              r['id'] as String,
              r['name'] as String,
              r['updated'] as int,
            ),
          )
          .toList();

  Future<void> saveMessage(ChatMessage message) async {
    final box = await _cipher.encrypt(
      utf8.encode(message.text),
      secretKey: _historyKey,
      aad: utf8.encode(
        '${message.peerId}/${message.id}/${message.outgoing ? 1 : 0}',
      ),
    );
    await _database.insert('messages', {
      'id': message.id,
      'peer': message.peerId,
      'body': base64Encode([...box.nonce, ...box.mac.bytes, ...box.cipherText]),
      'timestamp': message.timestamp,
      'outgoing': message.outgoing ? 1 : 0,
      'status': message.status,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _database.update(
      'peers',
      {'updated': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [message.peerId],
    );
  }

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
      result.add(
        ChatMessage(
          id: r['id'] as String,
          peerId: peer,
          text: utf8.decode(clear),
          timestamp: r['timestamp'] as int,
          outgoing: r['outgoing'] == 1,
          status: r['status'] as String,
        ),
      );
    }
    return result;
  }

  Future<void> clearHistory() async {
    await _database.transaction((txn) async {
      await txn.delete('messages');
      await txn.delete('peers');
    });
  }

  Future<void> close() => _database.close();
}
