import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'group_models.dart';
import 'contact_nickname.dart';
import 'chat_image.dart';
import 'chat_file.dart';
import 'message_reply.dart';
import 'starred_message.dart';

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
    this.groups = const [],
    this.groupDrafts = const [],
    this.stars = const [],
  });
  final String seed, owner, name;
  final int created;
  final bool demo;
  final List<Map<String, Object?>> peers, messages, drafts;
  final List<Map<String, Object?>> groups, groupDrafts, stars;
  Map<String, Object?> toJson() => {
    'version': peers.any((p) => p.containsKey('nickname'))
        ? 11
        : stars.isNotEmpty
        ? 10
        : messages.any((m) => m.containsKey('reply')) ||
              drafts.any((d) => d.containsKey('reply')) ||
              groupDrafts.any((d) => d.containsKey('reply')) ||
              groups.any(
                (g) => (g['messages'] as List).any(
                  (m) =>
                      (m as Map)['envelope'] is Map &&
                      ((m['envelope']) as Map).containsKey('reply'),
                ),
              )
        ? 9
        : groups.any(
            (g) => g.containsKey('pinned') || g.containsKey('archived'),
          )
        ? 8
        : groupDrafts.isNotEmpty
        ? 7
        : groups.any(
            (g) => (g['messages'] as List).any(
              (m) => (m as Map)['fileData'] != null,
            ),
          )
        ? 6
        : groups.any(
            (g) => (g['messages'] as List).any(
              (m) => (m as Map)['imageData'] != null,
            ),
          )
        ? 5
        : messages.any((m) => m['file'] != null)
        ? 4
        : messages.any((m) => m['image'] != null)
        ? 3
        : groups.isEmpty
        ? 1
        : 2,
    'seed': seed,
    'owner': owner,
    'name': name,
    'created': created,
    'demo': demo,
    'peers': peers,
    'messages': messages,
    'drafts': drafts,
    if (groups.isNotEmpty) 'groups': groups,
    if (groupDrafts.isNotEmpty) 'groupDrafts': groupDrafts,
    if (stars.isNotEmpty) 'stars': stars,
  };

  static Future<BackupData> parse(Object? raw) async {
    const invalid = FormatException('Invalid backup contents.');
    if (raw is! Map ||
        !{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}.contains(raw['version'])) {
      throw invalid;
    }
    if (raw['version'] == 1 && raw.containsKey('groups')) throw invalid;
    if (raw.containsKey('groupDrafts') && (raw['version'] as int) < 7) {
      throw invalid;
    }
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
      if (p.containsKey('nickname')) {
        if (raw['version'] != 11 ||
            p['nickname'] is! String ||
            normalizeContactNickname(p['nickname'] as String) !=
                p['nickname'] ||
            (p['nickname'] as String).isEmpty) {
          throw invalid;
        }
      }
      number(p, 'updated');
      boolean(p, 'pinned');
      boolean(p, 'archived');
    }
    final keys = <(String, String, bool)>{};
    final starSources = <String>{};
    for (final m in messages) {
      final peer = string(m, 'peer', 128), id = string(m, 'id', 128);
      final outgoing = boolean(m, 'outgoing');
      if (!ids.contains(peer) || !keys.add((peer, id, outgoing))) throw invalid;
      starSources.add(
        StarredMessage(target: peer, id: id, outgoing: outgoing).key,
      );
      string(m, 'text', 4096);
      if (m.containsKey('reply')) {
        if ((raw['version'] as int) < 9 ||
            m.containsKey('image') ||
            m.containsKey('file')) {
          throw invalid;
        }
        m['reply'] = MessageReply.parse(m['reply'], group: false).toJson();
      }
      if (m.containsKey('file')) {
        if ((raw['version'] as int) < 4 ||
            m.containsKey('image') ||
            m['file'] is! Map ||
            m['text'] != 'File') {
          throw invalid;
        }
        final file = ChatFile.parse(m['file']);
        final encoded = (m['file'] as Map)['data'];
        if (encoded is! String ||
            encoded.length > ((fileMaxBytes + 2) ~/ 3) * 4) {
          throw invalid;
        }
        await file.verify(base64Decode(encoded));
        m['file'] = {...file.toJson(), 'data': encoded};
      }
      if (m.containsKey('image')) {
        if ((raw['version'] as int) < 3 ||
            m['image'] is! Map ||
            m['text'] != 'Image') {
          throw invalid;
        }
        final image = ChatImage.parse(m['image']);
        final encoded = (m['image'] as Map)['data'];
        if (encoded is! String ||
            encoded.length > ((imageMaxBytes + 2) ~/ 3) * 4) {
          throw invalid;
        }
        await image.verify(base64Decode(encoded));
        m['image'] = {...image.toJson(), 'data': encoded};
      }
      number(m, 'timestamp');
      boolean(m, 'read');
      if (!{
        'sending',
        'queued',
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
      string(d, 'text', 1024 * 1024, empty: d.containsKey('reply'));
      if (d.containsKey('reply')) {
        if ((raw['version'] as int) < 9) throw invalid;
        d['reply'] = MessageReply.parse(d['reply'], group: false).toJson();
      }
    }
    final groups = <Map<String, Object?>>[];
    final groupIds = <String>{};
    var groupMessages = 0;
    if (raw['version'] == 2 || raw.containsKey('groups')) {
      for (final row in rows('groups', 500)) {
        if ((row.containsKey('pinned') || row.containsKey('archived')) &&
            (raw['version'] as int) < 8) {
          throw invalid;
        }
        final group = await GroupHistory.parse(row);
        if (group.messages.any((m) => m.reply != null) &&
            (raw['version'] as int) < 9) {
          throw invalid;
        }
        if (group.messages.any((m) => m.image != null) &&
                (raw['version'] as int) < 5 ||
            group.messages.any((m) => m.file != null) &&
                (raw['version'] as int) < 6) {
          throw invalid;
        }
        groupMessages += group.messages.length;
        if (!groupIds.add(group.id) || groupMessages > 100000) throw invalid;
        groups.add(group.toJson());
        starSources.addAll(
          group.messages.map(
            (m) => StarredMessage(
              target: group.id,
              id: m.id,
              author: m.author,
            ).key,
          ),
        );
      }
    }
    final groupDrafts = <Map<String, Object?>>[];
    final draftGroups = <String>{};
    if (raw.containsKey('groupDrafts')) {
      for (final d in rows('groupDrafts', 500)) {
        final group = string(d, 'group', 128);
        if (!groupIds.contains(group) || !draftGroups.add(group)) throw invalid;
        groupDrafts.add({
          'group': group,
          'text': string(d, 'text', 1024 * 1024, empty: d.containsKey('reply')),
          if (d.containsKey('reply'))
            'reply': (raw['version'] as int) >= 9
                ? MessageReply.parse(d['reply'], group: true).toJson()
                : throw invalid,
        });
      }
    }
    final stars = <Map<String, Object?>>[];
    final starKeys = <String>{};
    if (raw.containsKey('stars')) {
      if ((raw['version'] as int) < 10) throw invalid;
      for (final row in rows('stars', 5000)) {
        final star = StarredMessage.parse(row);
        if (!starKeys.add(star.key) || !starSources.contains(star.key)) {
          throw invalid;
        }
        stars.add(star.toJson());
      }
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
      groups: groups,
      groupDrafts: groupDrafts,
      stars: stars,
    );
  }
}

bool _sameStarOriginal(Map a, Map b) => [
  'text',
  'timestamp',
  'image',
  'file',
  'reply',
].every((k) => jsonEncode(a[k]) == jsonEncode(b[k]));
Map<(Object?, Object?, Object?), Map> _groupStarIndex(
  List<Map<String, Object?>> groups,
) => {
  for (final g in groups)
    for (final raw in g['messages'] as List)
      (
        g['id'],
        (raw['envelope'] as Map)['authorId'],
        (raw['envelope'] as Map)['id'],
      ): raw as Map,
};

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
  final groupDrafts = {for (final d in current.groupDrafts) d['group']: d};
  final newGroupDrafts = <Map<String, Object?>>[];
  final incomingGroups = {for (final g in incoming.groups) g['id']: g};
  final newPeers = <Map<String, Object?>>[],
      newMessages = <Map<String, Object?>>[],
      newDrafts = <Map<String, Object?>>[];
  var duplicates = 0, conflicts = 0, keptDrafts = 0;
  final groupChanges = <Map<String, Object?>>[];
  final oldGroups = {for (final g in current.groups) g['id']: g};
  var newGroups = 0, newGroupMessages = 0;
  for (final group in incoming.groups) {
    final old = oldGroups[group['id']];
    if (old == null) {
      newGroups++;
      newGroupMessages += (group['messages'] as List).length;
      groupChanges.add(_restoredGroup(group));
      continue;
    }
    if (old['host'] != group['host']) {
      conflicts++;
      continue;
    }
    String key(Map m) =>
        '${(m['envelope'] as Map)['authorId']}/${(m['envelope'] as Map)['id']}';
    final records = {for (final m in old['messages'] as List) key(m as Map): m};
    final additions = <Object?>[];
    for (final m in group['messages'] as List) {
      final previous = records[key(m as Map)];
      if (previous == null) {
        additions.add(m);
        newGroupMessages++;
      } else if ((previous['envelope'] as Map)['signature'] ==
          (m['envelope'] as Map)['signature']) {
        duplicates++;
      } else {
        conflicts++;
      }
    }
    if (additions.isNotEmpty) {
      if (records.length + additions.length > 10000) {
        throw const FormatException('Group history limit exceeded.');
      }
      groupChanges.add(
        _restoredGroup({
          ...old,
          'messages': [...records.values, ...additions],
          'updated': max(old['updated'] as int, group['updated'] as int),
        }),
      );
    }
  }
  for (final p in incoming.peers) {
    if (!peers.containsKey(p['id'])) newPeers.add(p);
  }
  for (final m in incoming.messages) {
    final old = messages[(m['peer'], m['id'], m['outgoing'])];
    if (old == null) {
      newMessages.add({
        ...m,
        // Restoring an archive never silently schedules a transmission.
        'status': m['status'] == 'sending' || m['status'] == 'queued'
            ? 'unconfirmed'
            : m['status'],
      });
    } else if (old['text'] == m['text'] &&
        old['timestamp'] == m['timestamp'] &&
        jsonEncode(old['image']) == jsonEncode(m['image']) &&
        jsonEncode(old['file']) == jsonEncode(m['file']) &&
        jsonEncode(old['reply']) == jsonEncode(m['reply'])) {
      duplicates++;
    } else {
      conflicts++;
    }
  }
  for (final d in incoming.drafts) {
    if (!drafts.containsKey(d['peer'])) {
      newDrafts.add(d);
    } else if (drafts[d['peer']]!['text'] != d['text'] ||
        jsonEncode(drafts[d['peer']]!['reply']) != jsonEncode(d['reply'])) {
      keptDrafts++;
    }
  }
  for (final d in incoming.groupDrafts) {
    final old = oldGroups[d['group']];
    // A conflicting group ID must never receive another host's draft.
    if (old != null && old['host'] != incomingGroups[d['group']]?['host']) {
      continue;
    }
    if (!groupDrafts.containsKey(d['group'])) {
      newGroupDrafts.add(d);
    } else if (groupDrafts[d['group']]!['text'] != d['text'] ||
        jsonEncode(groupDrafts[d['group']]!['reply']) !=
            jsonEncode(d['reply'])) {
      keptDrafts++;
    }
  }
  final oldStars = current.stars
      .map((s) => StarredMessage.parse(s).key)
      .toSet();
  final newStars = <Map<String, Object?>>[];
  final currentGroupMessages = _groupStarIndex(current.groups);
  final incomingGroupMessages = _groupStarIndex(incoming.groups);
  final incomingMessages = {
    for (final m in incoming.messages) (m['peer'], m['id'], m['outgoing']): m,
  };
  for (final row in incoming.stars) {
    final star = StarredMessage.parse(row);
    if (oldStars.contains(star.key)) continue;
    if (star.group) {
      final old = oldGroups[star.target];
      final source = incomingGroups[star.target];
      if (old != null && old['host'] != source?['host']) continue;
      final previous =
          currentGroupMessages[(star.target, star.author, star.id)];
      final original =
          incomingGroupMessages[(star.target, star.author, star.id)];
      if (previous != null &&
          (previous['envelope'] as Map)['signature'] !=
              (original!['envelope'] as Map)['signature']) {
        continue;
      }
    } else {
      final old = messages[(star.target, star.id, star.outgoing)];
      final original = incomingMessages[(star.target, star.id, star.outgoing)]!;
      if (old != null && !_sameStarOriginal(old, original)) continue;
    }
    newStars.add(row);
  }
  if (current.stars.length + newStars.length > 5000) {
    throw const FormatException('Starred message limit exceeded.');
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
    groups: groupChanges,
    groupDrafts: newGroupDrafts,
    stars: newStars,
  );
  return BackupMerge(
    data,
    newPeers.length + newGroups,
    newMessages.length + newGroupMessages,
    duplicates,
    conflicts,
    newDrafts.length + newGroupDrafts.length,
    keptDrafts,
  );
}

Map<String, Object?> _restoredGroup(Map<String, Object?> group) => {
  ...group,
  'messages': [
    for (final raw in group['messages'] as List)
      {
        ...raw as Map,
        'receipts': {
          for (final e in (raw['receipts'] as Map).entries)
            e.key: e.value == 'pending' ? 'unconfirmed' : e.value,
        },
      },
  ],
};

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
