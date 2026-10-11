import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Version one fixes the KDF cost; files cannot request arbitrary work.
const backupMaxPlaintext = 20 * 1024 * 1024;
const backupMaxFile = backupMaxPlaintext + 65;
const _magic = [76, 67, 66, 65, 67, 75, 85, 80, 1]; // LCBACKUP + version

class BackupData {
  BackupData({
    required this.seed,
    required this.owner,
    required this.name,
    required this.created,
    required this.demo,
    required this.peers,
    required this.messages,
    required this.drafts,
  });
  final String seed, owner, name;
  final int created;
  final bool demo;
  final List<Map<String, Object?>> peers, messages, drafts;
  Map<String, Object?> toJson() => {
    'version': 1,
    'seed': seed,
    'owner': owner,
    'name': name,
    'created': created,
    'demo': demo,
    'peers': peers,
    'messages': messages,
    'drafts': drafts,
  };

  static Future<BackupData> parse(Object? raw) async {
    const invalid = FormatException('Invalid backup contents.');
    if (raw is! Map || raw['version'] != 1) throw invalid;
    String string(Map row, String key, int max, {bool empty = false}) {
      final value = row[key];
      if (value is! String ||
          (!empty && value.isEmpty) ||
          utf8.encode(value).length > max) {
        throw invalid;
      }
      return value;
    }

    int number(Map row, String key) {
      final value = row[key];
      if (value is! int || value < 0 || value > 8640000000000000) throw invalid;
      return value;
    }

    bool boolean(Map row, String key) {
      final value = row[key];
      if (value is! bool) throw invalid;
      return value;
    }

    List<Map<String, Object?>> rows(String key, int max) {
      final value = raw[key];
      if (value is! List || value.length > max) throw invalid;
      return value.map((r) {
        if (r is! Map || r.keys.any((k) => k is! String)) throw invalid;
        return Map<String, Object?>.from(r);
      }).toList();
    }

    final seed = string(raw, 'seed', 64);
    final bytes = base64Decode(seed);
    if (bytes.length != 32) throw invalid;
    final pair = await Ed25519().newKeyPairFromSeed(bytes);
    final owner = (await Sha256().hash(
      (await pair.extractPublicKey()).bytes,
    )).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    if (raw['owner'] != owner) throw invalid;
    final peers = rows('peers', 5000),
        messages = rows('messages', 100000),
        drafts = rows('drafts', 5000);
    final ids = <String>{};
    for (final p in peers) {
      if (!ids.add(string(p, 'id', 128))) throw invalid;
      string(p, 'name', 256);
      number(p, 'updated');
      boolean(p, 'pinned');
      boolean(p, 'archived');
    }
    final keys = <(String, String, bool)>{};
    for (final m in messages) {
      final peer = string(m, 'peer', 128), id = string(m, 'id', 128);
      final outgoing = boolean(m, 'outgoing');
      if (!ids.contains(peer) || !keys.add((peer, id, outgoing))) throw invalid;
      string(m, 'text', 4096);
      number(m, 'timestamp');
      boolean(m, 'read');
      if (!{
        'sending',
        'delivered',
        'unconfirmed',
        'received',
      }.contains(m['status'])) {
        throw invalid;
      }
    }
    final draftPeers = <String>{};
    for (final d in drafts) {
      final peer = string(d, 'peer', 128);
      if (!ids.contains(peer) || !draftPeers.add(peer)) throw invalid;
      // The composer counts graphemes; one grapheme may contain many code points.
      string(d, 'text', 1024 * 1024);
    }
    return BackupData(
      seed: seed,
      owner: owner,
      name: string(raw, 'name', 256),
      created: number(raw, 'created'),
      demo: boolean(raw, 'demo'),
      peers: peers,
      messages: messages,
      drafts: drafts,
    );
  }
}

class BackupMerge {
  BackupMerge(
    this.data,
    this.newChats,
    this.newMessages,
    this.duplicates,
    this.conflicts,
    this.newDrafts,
    this.keptDrafts,
  );
  final BackupData data;
  final int newChats, newMessages, duplicates, conflicts, newDrafts, keptDrafts;
}

/// The same plan drives preview and the transaction. Existing records win.
BackupMerge planBackup(BackupData current, BackupData incoming) {
  if (current.demo != incoming.demo) {
    throw const FormatException(
      'Browser demo backups and phone backups cannot be mixed.',
    );
  }
  final peers = {for (final p in current.peers) p['id']: p};
  final messages = {
    for (final m in current.messages) (m['peer'], m['id'], m['outgoing']): m,
  };
  final drafts = {for (final d in current.drafts) d['peer']: d};
  final newPeers = <Map<String, Object?>>[],
      newMessages = <Map<String, Object?>>[],
      newDrafts = <Map<String, Object?>>[];
  var duplicates = 0, conflicts = 0, keptDrafts = 0;
  for (final p in incoming.peers) {
    if (!peers.containsKey(p['id'])) newPeers.add(p);
  }
  for (final m in incoming.messages) {
    final old = messages[(m['peer'], m['id'], m['outgoing'])];
    if (old == null) {
      newMessages.add({
        ...m,
        'status': m['status'] == 'sending' ? 'unconfirmed' : m['status'],
      });
    } else if (old['text'] == m['text'] && old['timestamp'] == m['timestamp']) {
      duplicates++;
    } else {
      conflicts++;
    }
  }
  for (final d in incoming.drafts) {
    if (!drafts.containsKey(d['peer'])) {
      newDrafts.add(d);
    } else if (drafts[d['peer']]!['text'] != d['text']) {
      keptDrafts++;
    }
  }
  final data = BackupData(
    seed: incoming.seed,
    owner: incoming.owner,
    name: incoming.name,
    created: incoming.created,
    demo: incoming.demo,
    peers: newPeers,
    messages: newMessages,
    drafts: newDrafts,
  );
  return BackupMerge(
    data,
    newPeers.length,
    newMessages.length,
    duplicates,
    conflicts,
    newDrafts.length,
    keptDrafts,
  );
}

typedef BackupKeyDeriver = Future<Uint8List> Function(String, Uint8List);

Future<Uint8List> _derive(Map<String, Object> arguments) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 600000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(arguments['password'] as String)),
        nonce: arguments['salt'] as Uint8List,
      );
  return Uint8List.fromList(await key.extractBytes());
}

class BackupCodec {
  BackupCodec({BackupKeyDeriver? deriveKey})
    : _key =
          deriveKey ??
          ((password, salt) =>
              compute(_derive, {'password': password, 'salt': salt}));
  final BackupKeyDeriver _key;
  final _cipher = Xchacha20.poly1305Aead();
  static void checkPassword(String password) {
    if (password.runes.length < 12 || utf8.encode(password).length > 1024) {
      throw const FormatException(
        'Use a backup password of at least 12 characters (up to 1024 bytes).',
      );
    }
  }

  Future<Uint8List> encrypt(BackupData data, String password) async {
    checkPassword(password);
    data = await BackupData.parse(data.toJson());
    final clear = utf8.encode(jsonEncode(data.toJson()));
    if (clear.length > backupMaxPlaintext) {
      throw const FormatException('Backup exceeds the 20 MB limit.');
    }
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    final header = [..._magic, ...salt];
    final key = await _key(password, salt);
    try {
      final box = await _cipher.encrypt(
        clear,
        secretKey: SecretKey(key),
        aad: header,
      );
      return Uint8List.fromList([
        ...header,
        ...box.nonce,
        ...box.mac.bytes,
        ...box.cipherText,
      ]);
    } finally {
      key.fillRange(0, key.length, 0);
      clear.fillRange(0, clear.length, 0);
    }
  }

  Future<BackupData> decrypt(Uint8List bytes, String password) async {
    checkPassword(password);
    if (bytes.length <= 65 || bytes.length > backupMaxFile) {
      throw const FormatException('Invalid backup size (maximum 20 MB).');
    }
    if (!listEquals(bytes.sublist(0, 8), _magic.sublist(0, 8))) {
      throw const FormatException('Choose a LocalChat .lcbackup file.');
    }
    if (bytes[8] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    final key = await _key(password, bytes.sublist(9, 25));
    try {
      final clear = await _cipher.decrypt(
        SecretBox(
          bytes.sublist(65),
          nonce: bytes.sublist(25, 49),
          mac: Mac(bytes.sublist(49, 65)),
        ),
        secretKey: SecretKey(key),
        aad: bytes.sublist(0, 25),
      );
      try {
        return await BackupData.parse(jsonDecode(utf8.decode(clear)));
      } finally {
        clear.fillRange(0, clear.length, 0);
      }
    } catch (_) {
      throw const FormatException(
        'Could not open backup. Check the password and file.',
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}
