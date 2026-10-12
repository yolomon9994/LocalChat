import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'models.dart';
import 'chat_backup.dart';
import 'group_models.dart';
import 'chat_image.dart';

class LocalStore {
  LocalStore({DateTime Function()? now, FlutterSecureStorage? vault})
    : _now = now ?? DateTime.now,
      _vault = vault ?? const FlutterSecureStorage();
  final DateTime Function() _now;
  final FlutterSecureStorage _vault;
  late Database _database;
  late SecretKey _historyKey;
  late SimpleKeyPair identity;
  String name = 'LocalChat user';
  bool identityRecoveryRequired = false;
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
      version: 8,
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
        await _createDraftTable(db);
        await _addManagementColumns(db);
        await db.execute('CREATE TABLE backup_receipt (id TEXT PRIMARY KEY)');
        await _createOutboxIndex(db);
        await _createGroups(db);
        await _createImages(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Old installations have no read state. Keep existing history read.
          await db.execute(
            'ALTER TABLE messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 1',
          );
          await _createSummaryIndexes(db);
        }
        if (oldVersion < 3) await _createDraftTable(db);
        if (oldVersion < 4) await _addManagementColumns(db);
        if (oldVersion < 5) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS backup_receipt (id TEXT PRIMARY KEY)',
          );
        }
        if (oldVersion < 6) await _createOutboxIndex(db);
        if (oldVersion < 7) await _createGroups(db);
        if (oldVersion < 8) await _createImages(db);
      },
    );
    await _recoverIdentity();
    // A process termination leaves delivery unknown, never silently "delivered".
    await _database.update('messages', {
      'status': 'unconfirmed',
    }, where: "status = 'sending'");
  }

  /// SQLite commit receipts resolve crashes between database and vault writes.
  Future<void> _recoverIdentity() async {
    final pending = await _vault.read(key: 'identity_import_pending_v1');
    if (pending == null) {
      identityRecoveryRequired = false;
      await _database.delete('backup_receipt');
      return;
    }
    identityRecoveryRequired = true;
    final record = jsonDecode(pending) as Map;
    final committed = (await _database.query(
      'backup_receipt',
      where: 'id = ?',
      whereArgs: [record['id']],
    )).isNotEmpty;
    final seed = record[committed ? 'new' : 'old'] as String;
    if (await _vault.read(key: 'identity_seed_v1') != seed) {
      await _vault.write(key: 'identity_seed_v1', value: seed);
    }
    identity = await Ed25519().newKeyPairFromSeed(base64Decode(seed));
    identityRecoveryRequired = false;
    // Cleanup is optional. Never remove a receipt before its vault journal.
    try {
      await _vault.delete(key: 'identity_import_pending_v1');
      await _database.delete('backup_receipt');
    } catch (_) {
      /* A later open repeats the same committed recovery. */
    }
  }

  Future<BackupData> _snapshot(DatabaseExecutor db) async {
    final peers = await db.query('peers', orderBy: 'rowid ASC');
    final messages = await db.query('messages', orderBy: 'rowid ASC');
    final drafts = await db.query('drafts');
    final seed = base64Encode(await identity.extractPrivateKeyBytes());
    final owner = (await Sha256().hash(
      (await identity.extractPublicKey()).bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final result = <Map<String, Object?>>[];
    for (final row in messages) {
      final m = await _decodeMessage(row);
      result.add({
        'id': m.id,
        'peer': m.peerId,
        'text': m.text,
        'timestamp': m.timestamp,
        'outgoing': m.outgoing,
        'status': m.status,
        'read': row['is_read'] == 1,
        if (m.image != null)
          'image': {
            ...m.image!.toJson(),
            'data': base64Encode(await _imageBytes(db, m)),
          },
      });
    }
    final draftResult = <Map<String, Object?>>[];
    for (final d in drafts) {
      draftResult.add({'peer': d['peer'], 'text': await _decodeDraft(d)});
    }
    return BackupData(
      seed: seed,
      owner: owner,
      name: name,
      created: _now().millisecondsSinceEpoch,
      demo: false,
      peers: peers
          .map(
            (p) => <String, Object?>{
              'id': p['id'],
              'name': p['name'],
              'updated': p['updated'],
              'pinned': p['pinned'] == 1,
              'archived': p['archived'] == 1,
            },
          )
          .toList(),
      messages: result,
      drafts: draftResult,
      groups: (await _groupHistories(db)).map((g) => g.toJson()).toList(),
    );
  }

  Future<BackupData> exportBackup() => _database.transaction(_snapshot);

  Future<BackupMerge> importBackup(
    BackupData data, {
    bool moveIdentity = false,
  }) async {
    // Validate even callers that bypass the file decoder.
    data = await BackupData.parse(data.toJson());
    await _recoverIdentity();
    if (moveIdentity) {
      final current = await exportBackup();
      if (current.peers.isNotEmpty ||
          current.messages.isNotEmpty ||
          current.drafts.isNotEmpty ||
          current.groups.isNotEmpty) {
        throw const FormatException(
          'Identity transfer requires an empty destination phone.',
        );
      }
      final token = base64Encode(
        await (await _cipher.newSecretKey()).extractBytes(),
      );
      identityRecoveryRequired = true;
      await _vault.write(
        key: 'identity_import_pending_v1',
        value: jsonEncode({'id': token, 'old': current.seed, 'new': data.seed}),
      );
    }
    late BackupMerge result;
    try {
      result = await _database.transaction((txn) async {
        final current = await _snapshot(txn);
        if (moveIdentity &&
            (current.peers.isNotEmpty ||
                current.messages.isNotEmpty ||
                current.drafts.isNotEmpty ||
                current.groups.isNotEmpty)) {
          throw const FormatException(
            'Identity transfer requires an empty destination phone.',
          );
        }
        final plan = planBackup(current, data);
        for (final g in plan.data.groups) {
          await _writeGroup(txn, await GroupHistory.parse(g));
        }
        for (final p in plan.data.peers) {
          await txn.insert('peers', {
            'id': p['id'],
            'name': p['name'],
            'updated': p['updated'],
            'pinned': p['pinned'] == true ? 1 : 0,
            'archived': p['archived'] == true ? 1 : 0,
          });
        }
        final peerActivity = {
          for (final p in data.peers) p['id']: p['updated'] as int,
        };
        for (final m in plan.data.messages) {
          final direction = m['outgoing'] == true ? 1 : 0;
          final box = await _cipher.encrypt(
            utf8.encode(
              m['image'] == null
                  ? m['text'] as String
                  : jsonEncode(ChatImage.parse(m['image']).toJson()),
            ),
            secretKey: _historyKey,
            aad: utf8.encode(
              _messageAad(
                m['peer'] as String,
                m['id'] as String,
                direction,
                image: m['image'] != null,
              ),
            ),
          );
          await txn.insert('messages', {
            'id': m['id'],
            'peer': m['peer'],
            'body': base64Encode([
              ...box.nonce,
              ...box.mac.bytes,
              ...box.cipherText,
            ]),
            'timestamp': m['timestamp'],
            'outgoing': direction,
            'status': m['status'],
            'is_read': direction == 1 || m['read'] == true ? 1 : 0,
            'kind': m['image'] == null ? 'text' : 'image',
          });
          if (m['image'] != null) {
            final message = ChatMessage(
              id: m['id'] as String,
              peerId: m['peer'] as String,
              text: 'Image',
              timestamp: m['timestamp'] as int,
              outgoing: direction == 1,
              status: m['status'] as String,
              image: ChatImage.parse(m['image']),
            );
            await _writeImage(
              txn,
              message,
              base64Decode((m['image'] as Map)['data'] as String),
            );
          }
          await txn.rawUpdate(
            'UPDATE peers SET updated = MAX(updated, ?) WHERE id = ?',
            [peerActivity[m['peer']], m['peer']],
          );
        }
        for (final d in plan.data.drafts) {
          final box = await _cipher.encrypt(
            utf8.encode(d['text'] as String),
            secretKey: _historyKey,
            aad: utf8.encode(jsonEncode(['LocalChat/draft/1', d['peer']])),
          );
          await txn.insert('drafts', {
            'peer': d['peer'],
            'body': base64Encode([
              ...box.nonce,
              ...box.mac.bytes,
              ...box.cipherText,
            ]),
          });
        }
        if (moveIdentity) {
          final pending =
              jsonDecode(
                    (await _vault.read(key: 'identity_import_pending_v1'))!,
                  )
                  as Map;
          await txn.insert('backup_receipt', {'id': pending['id']});
        }
        return plan;
      });
    } finally {
      if (moveIdentity) await _recoverIdentity();
    }
    return result;
  }

  static Future<void> _createSummaryIndexes(Database db) async {
    await db.execute('CREATE INDEX message_peer_latest ON messages(peer)');
    await db.execute(
      'CREATE INDEX message_peer_unread ON messages(peer, outgoing, is_read)',
    );
  }

  static Future<void> _createGroups(Database db) => db.execute(
    'CREATE TABLE IF NOT EXISTS group_history (id TEXT PRIMARY KEY, body TEXT NOT NULL)',
  );

  static Future<void> _createImages(Database db) async {
    if (!(await db.rawQuery(
      'PRAGMA table_info(messages)',
    )).any((c) => c['name'] == 'kind')) {
      await db.execute(
        "ALTER TABLE messages ADD COLUMN kind TEXT NOT NULL DEFAULT 'text'",
      );
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS images (peer TEXT NOT NULL, id TEXT NOT NULL, outgoing INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(peer, id, outgoing))',
    );
  }

  String _imageAad(ChatMessage m) =>
      'LocalChat/image/1/${m.peerId}/${m.id}/${m.outgoing ? 1 : 0}';
  String _messageAad(
    String peer,
    String id,
    int direction, {
    bool image = false,
  }) => '${image ? 'LocalChat/image-message/1/' : ''}$peer/$id/$direction';
  Future<void> _writeImage(
    DatabaseExecutor db,
    ChatMessage m,
    Uint8List bytes,
  ) async {
    await m.image!.verify(bytes);
    final box = await _cipher.encrypt(
      bytes,
      secretKey: _historyKey,
      aad: utf8.encode(_imageAad(m)),
    );
    await db.insert('images', {
      'peer': m.peerId,
      'id': m.id,
      'outgoing': m.outgoing ? 1 : 0,
      'body': base64Encode([...box.nonce, ...box.mac.bytes, ...box.cipherText]),
    });
  }

  Future<Uint8List> _imageBytes(DatabaseExecutor db, ChatMessage m) async {
    if (m.image == null) {
      throw const FormatException('This message has no image.');
    }
    final rows = await db.query(
      'images',
      where: 'peer = ? AND id = ? AND outgoing = ?',
      whereArgs: [m.peerId, m.id, m.outgoing ? 1 : 0],
      limit: 1,
    );
    if (rows.isEmpty) throw const FormatException('Image is unavailable.');
    final bytes = base64Decode(rows.single['body'] as String);
    final clear = Uint8List.fromList(
      await _cipher.decrypt(
        SecretBox(
          bytes.sublist(40),
          nonce: bytes.sublist(0, 24),
          mac: Mac(bytes.sublist(24, 40)),
        ),
        secretKey: _historyKey,
        aad: utf8.encode(_imageAad(m)),
      ),
    );
    await m.image!.verify(clear);
    return clear;
  }

  Future<Uint8List> imageBytes(ChatMessage message) =>
      _imageBytes(_database, message);
  Future<bool> saveImageMessage(ChatMessage message, Uint8List bytes) =>
      _saveMessage(message, imageBytes: bytes);

  Future<List<GroupHistory>> _groupHistories(DatabaseExecutor db) async {
    final result = <GroupHistory>[];
    for (final row in await db.query('group_history')) {
      final bytes = base64Decode(row['body'] as String);
      final clear = await _cipher.decrypt(
        SecretBox(
          bytes.sublist(40),
          nonce: bytes.sublist(0, 24),
          mac: Mac(bytes.sublist(24, 40)),
        ),
        secretKey: _historyKey,
        aad: utf8.encode('LocalChat/group-history/1/${row['id']}'),
      );
      // Received/imported authors were checked before this authenticated local write.
      result.add(
        await GroupHistory.parse(
          jsonDecode(utf8.decode(clear)) as Map,
          verifySignatures: false,
        ),
      );
    }
    return result..sort((a, b) => b.updated.compareTo(a.updated));
  }

  Future<List<GroupHistory>> groupHistories() => _groupHistories(_database);
  Future<void> _writeGroup(DatabaseExecutor db, GroupHistory group) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(group.toJson())),
      secretKey: _historyKey,
      aad: utf8.encode('LocalChat/group-history/1/${group.id}'),
    );
    await db.insert('group_history', {
      'id': group.id,
      'body': base64Encode([...box.nonce, ...box.mac.bytes, ...box.cipherText]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveGroupHistory(GroupHistory group) =>
      _writeGroup(_database, group);
  Future<void> deleteGroupHistory(String id) =>
      _database.delete('group_history', where: 'id = ?', whereArgs: [id]);

  static Future<void> _createOutboxIndex(Database db) => db.execute(
    'CREATE INDEX IF NOT EXISTS message_outbox ON messages(peer, outgoing, status)',
  );

  static Future<void> _createDraftTable(Database db) => db.execute(
    'CREATE TABLE drafts (peer TEXT PRIMARY KEY, body TEXT NOT NULL)',
  );

  static Future<void> _addManagementColumns(Database db) async {
    await db.execute(
      'ALTER TABLE peers ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE peers ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<bool> setPinned(String peer, bool pinned) async =>
      await _database.update(
        'peers',
        {'pinned': pinned ? 1 : 0},
        where: 'id = ?',
        whereArgs: [peer],
      ) ==
      1;

  Future<bool> setArchived(String peer, bool archived) async =>
      await _database.update(
        'peers',
        {'archived': archived ? 1 : 0},
        where: 'id = ?',
        whereArgs: [peer],
      ) ==
      1;

  Future<void> deleteConversation(String peer) =>
      _database.transaction((txn) async {
        await txn.delete('images', where: 'peer = ?', whereArgs: [peer]);
        await txn.delete('messages', where: 'peer = ?', whereArgs: [peer]);
        await txn.delete('drafts', where: 'peer = ?', whereArgs: [peer]);
        await txn.delete('peers', where: 'id = ?', whereArgs: [peer]);
      });

  Future<String> draft(String peer) async {
    final rows = await _database.query(
      'drafts',
      where: 'peer = ?',
      whereArgs: [peer],
      limit: 1,
    );
    if (rows.isEmpty) return '';
    return _decodeDraft(rows.single);
  }

  Future<String> _decodeDraft(Map<String, Object?> row) async {
    final bytes = base64Decode(row['body'] as String);
    final clear = await _cipher.decrypt(
      SecretBox(
        bytes.sublist(40),
        nonce: bytes.sublist(0, 24),
        mac: Mac(bytes.sublist(24, 40)),
      ),
      secretKey: _historyKey,
      aad: utf8.encode(jsonEncode(['LocalChat/draft/1', row['peer']])),
    );
    return utf8.decode(clear);
  }

  Future<void> saveDraft(String peer, String text) async {
    if (text.isEmpty) {
      await _database.delete('drafts', where: 'peer = ?', whereArgs: [peer]);
      return;
    }
    final box = await _cipher.encrypt(
      utf8.encode(text),
      secretKey: _historyKey,
      aad: utf8.encode(jsonEncode(['LocalChat/draft/1', peer])),
    );
    await _database.insert('drafts', {
      'peer': peer,
      'body': base64Encode([...box.nonce, ...box.mac.bytes, ...box.cipherText]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      SELECT p.id AS peer_id, p.name, p.updated, p.pinned, p.archived,
             m.id, m.peer, m.body, m.timestamp, m.outgoing, m.status, m.kind,
             (SELECT COUNT(*) FROM messages u
              WHERE u.peer = p.id AND u.outgoing = 0 AND u.is_read = 0) AS unread_count,
             (SELECT COUNT(*) FROM messages q
              WHERE q.peer = p.id AND q.outgoing = 1 AND q.status = 'queued') AS queued_count
      FROM peers p
      LEFT JOIN messages m ON m.rowid =
        (SELECT rowid FROM messages WHERE peer = p.id ORDER BY rowid DESC LIMIT 1)
      ORDER BY p.pinned DESC, (m.id IS NOT NULL) DESC, p.updated DESC, p.id ASC
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
          pinned: row['pinned'] == 1,
          archived: row['archived'] == 1,
          queuedCount: row['queued_count'] as int,
        ),
      );
    }
    return result;
  }

  /// True only for a new committed row; duplicate retries return false.
  Future<bool> saveMessage(ChatMessage message) => _saveMessage(message);

  /// Message acceptance and removal of its composer draft commit together.
  Future<void> saveOutgoingMessage(
    ChatMessage message, {
    bool clearDraft = false,
  }) {
    if (!message.outgoing || message.status != 'queued') {
      throw ArgumentError('Expected a queued outgoing message');
    }
    return _saveMessage(message, clearDraft: clearDraft).then((_) {});
  }

  Future<bool> _saveMessage(
    ChatMessage message, {
    bool clearDraft = false,
    Uint8List? imageBytes,
  }) async {
    if (message.image != null) {
      if (imageBytes == null) {
        throw const FormatException('Missing image contents.');
      }
      await message.image!.verify(imageBytes);
    }
    final box = await _cipher.encrypt(
      utf8.encode(
        message.image == null
            ? message.text
            : jsonEncode(message.image!.toJson()),
      ),
      secretKey: _historyKey,
      aad: utf8.encode(
        _messageAad(
          message.peerId,
          message.id,
          message.outgoing ? 1 : 0,
          image: message.image != null,
        ),
      ),
    );
    return _database.transaction((txn) async {
      final existing = await txn.query(
        'messages',
        where: 'peer = ? AND id = ? AND outgoing = ?',
        whereArgs: [message.peerId, message.id, message.outgoing ? 1 : 0],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final previous = await _decodeMessage(existing.single);
        if (previous.text != message.text ||
            jsonEncode(previous.image?.toJson()) !=
                jsonEncode(message.image?.toJson()) ||
            previous.timestamp != message.timestamp) {
          throw const FormatException('Conflicting message ID');
        }
        return false;
      }
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
        'kind': message.image == null ? 'text' : 'image',
      });
      if (message.image != null) await _writeImage(txn, message, imageBytes!);
      await txn.update(
        'peers',
        {'updated': _now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [message.peerId],
      );
      if (clearDraft) {
        await txn.delete(
          'drafts',
          where: 'peer = ?',
          whereArgs: [message.peerId],
        );
      }
      return true;
    });
  }

  Future<List<ChatMessage>> queuedMessages(String peer, {int limit = 1}) async {
    final rows = await _database.query(
      'messages',
      where: "peer = ? AND outgoing = 1 AND status = 'queued'",
      whereArgs: [peer],
      orderBy: 'rowid ASC',
      limit: limit,
    );
    final result = <ChatMessage>[];
    for (final row in rows) {
      result.add(await _decodeMessage(row));
    }
    return result;
  }

  Future<bool> changeOutgoingStatus(
    String id,
    String peer,
    List<String> from,
    String to,
  ) async {
    if (from.isEmpty) return false;
    return await _database.update(
          'messages',
          {'status': to},
          where:
              'id = ? AND peer = ? AND outgoing = 1 AND status IN (${List.filled(from.length, '?').join(',')})',
          whereArgs: [id, peer, ...from],
        ) ==
        1;
  }

  Future<bool> deleteQueuedMessage(String id, String peer) async =>
      await _database.delete(
        'messages',
        where: "id = ? AND peer = ? AND outgoing = 1 AND status = 'queued'",
        whereArgs: [id, peer],
      ) ==
      1;

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
      aad: utf8.encode(
        _messageAad(
          peer,
          r['id'] as String,
          r['outgoing'] as int,
          image: r['kind'] == 'image',
        ),
      ),
    );
    return ChatMessage(
      id: r['id'] as String,
      peerId: peer,
      text: r['kind'] == 'image' ? 'Image' : utf8.decode(clear),
      image: r['kind'] == 'image'
          ? ChatImage.parse(jsonDecode(utf8.decode(clear)))
          : null,
      timestamp: r['timestamp'] as int,
      outgoing: r['outgoing'] == 1,
      status: r['status'] as String,
    );
  }

  Future<LocalSearchResults> search(
    String query, {
    bool Function()? isCancelled,
    int limit = 100,
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty || isCancelled?.call() == true) {
      return const LocalSearchResults();
    }
    final people = await _database.query(
      'peers',
      orderBy: 'updated DESC, id ASC',
    );
    final names = people
        .where((p) => (p['name'] as String).toLowerCase().contains(needle))
        .map(
          (p) => Conversation(
            p['id'] as String,
            p['name'] as String,
            p['updated'] as int,
            pinned: p['pinned'] == 1,
            archived: p['archived'] == 1,
          ),
        )
        .toList();
    final hits = <MessageSearchHit>[];
    int? before;
    while (true) {
      if (isCancelled?.call() == true) return const LocalSearchResults();
      // Scan ciphertext in small batches. No plaintext index or duplicate body.
      final rows = await _database.rawQuery('''
        SELECT m.rowid AS search_rowid, m.*, p.name AS peer_name, p.updated AS peer_updated,
               p.pinned AS peer_pinned, p.archived AS peer_archived
        FROM messages m JOIN peers p ON p.id = m.peer
        ${before == null ? '' : 'WHERE m.rowid < ?'}
        ORDER BY m.rowid DESC LIMIT 100
      ''', before == null ? [] : [before]);
      if (rows.isEmpty) break;
      for (final row in rows) {
        if (isCancelled?.call() == true) return const LocalSearchResults();
        final message = await _decodeMessage(row);
        if (message.image != null ||
            !message.text.toLowerCase().contains(needle)) {
          continue;
        }
        if (hits.length == limit) {
          return LocalSearchResults(
            conversations: names,
            messages: hits,
            hasMoreMessages: true,
          );
        }
        hits.add(
          MessageSearchHit(
            Conversation(
              message.peerId,
              row['peer_name'] as String,
              row['peer_updated'] as int,
              pinned: row['peer_pinned'] == 1,
              archived: row['peer_archived'] == 1,
            ),
            message,
          ),
        );
      }
      before = rows.last['search_rowid'] as int;
      // Give UI, new queries and live chat writes time between batches.
      await Future<void>.delayed(Duration.zero);
    }
    if (isCancelled?.call() == true) return const LocalSearchResults();
    return LocalSearchResults(conversations: names, messages: hits);
  }

  Future<void> clearHistory() async {
    await _database.transaction((txn) async {
      await txn.delete('group_history');
      await txn.delete('images');
      await txn.delete('messages');
      await txn.delete('drafts');
      await txn.delete('peers');
    });
  }

  Future<void> close() => _database.close();
}
