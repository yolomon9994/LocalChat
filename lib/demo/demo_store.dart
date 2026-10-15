import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../core/chat_backup.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/group_models.dart';
import '../core/chat_image.dart';
import '../core/chat_file.dart';
import '../core/message_reply.dart';
import '../core/starred_message.dart';

/// Preview-only state. Never opens SQLite or platform secure storage.
class DemoStore extends LocalStore {
  final _stars = <StarredMessage>{};
  @override
  Future<List<StarredMessage>> starredMessages() async => _stars.toList();
  @override
  Future<bool> setMessageStarred(StarredMessage s, bool value) async {
    StarredMessage.parse(s.toJson());
    if (!value) {
      _stars.remove(s);
      return true;
    }
    final exists = s.group
        ? _groups[s.target]?.messages.any(
                (m) => m.id == s.id && m.author == s.author,
              ) ==
              true
        : _messages.containsKey((s.target, s.id, s.outgoing!));
    if (!exists) return false;
    if (!_stars.contains(s) && _stars.length >= 5000) {
      throw const FormatException('Starred message limit exceeded.');
    }
    _stars.add(s);
    return true;
  }

  final _people = <String, Conversation>{};
  final _messages = <(String, String, bool), ChatMessage>{};
  final _unread = <(String, String, bool)>{};
  final _drafts = <String, String>{};
  final _groupDrafts = <String, String>{};
  final _replyDrafts = <(String, bool), MessageReply>{};
  final _groups = <String, GroupHistory>{};
  final _images = <(String, String, bool), Uint8List>{};
  @override
  Future<Uint8List> imageBytes(ChatMessage message) async {
    final m = message;
    final bytes = _images[(m.peerId, m.id, m.outgoing)];
    if (bytes == null || m.image == null) {
      throw const FormatException('Image is unavailable.');
    }
    await m.image!.verify(bytes);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<bool> saveImageMessage(ChatMessage message, Uint8List bytes) async {
    final m = message;
    await m.image!.verify(bytes);
    final inserted = await saveMessage(m);
    if (inserted) {
      _images[(m.peerId, m.id, m.outgoing)] = Uint8List.fromList(bytes);
    }
    return inserted;
  }

  final _files = <(String, String, bool), Uint8List>{};
  @override
  Future<Uint8List> fileBytes(ChatMessage message) async {
    final m = message;
    final bytes = _files[(m.peerId, m.id, m.outgoing)];
    if (bytes == null || m.file == null) {
      throw const FormatException('File is unavailable.');
    }
    await m.file!.verify(bytes);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<bool> saveFileMessage(ChatMessage message, Uint8List bytes) async {
    final m = message;
    await m.file!.verify(bytes);
    final inserted = await saveMessage(m);
    if (inserted) {
      _files[(m.peerId, m.id, m.outgoing)] = Uint8List.fromList(bytes);
    }
    return inserted;
  }

  @override
  Future<List<GroupHistory>> groupHistories() async =>
      _groups.values.toList()..sort(compareGroupHistories);
  @override
  Future<void> saveGroupHistory(GroupHistory group) async =>
      _groups[group.id] = _withGroupChoices(group);
  GroupHistory _withGroupChoices(GroupHistory group) => group.copy(
    pinned: _groups[group.id]?.pinned ?? group.pinned,
    archived: _groups[group.id]?.archived ?? group.archived,
  );

  @override
  Future<bool> setGroupPinned(String id, bool pinned) async {
    final old = _groups[id];
    if (old == null) return false;
    _groups[id] = old.copy(pinned: pinned);
    return true;
  }

  @override
  Future<bool> setGroupArchived(String id, bool archived) async {
    final old = _groups[id];
    if (old == null) return false;
    _groups[id] = old.copy(archived: archived);
    return true;
  }

  @override
  Future<void> deleteGroupHistory(String id) async {
    _stars.removeWhere((s) => s.group && s.target == id);
    _groups.remove(id);
    _groupDrafts.remove(id);
    _replyDrafts.remove((id, true));
  }

  @override
  Future<String> groupDraft(String id) async => _groupDrafts[id] ?? '';
  @override
  Future<void> saveGroupDraft(String id, String text) async {
    if (utf8.encode(text).length > 1024 * 1024) {
      throw const FormatException('Draft exceeds the 1 MiB limit.');
    }
    if (text.isEmpty) {
      _groupDrafts.remove(id);
      return;
    }
    if (!_groups.containsKey(id)) {
      throw const FormatException('This group has been deleted.');
    }
    _groupDrafts[id] = text;
  }

  @override
  Future<void> saveOutgoingGroupHistory(
    GroupHistory group, {
    bool clearDraft = false,
  }) async {
    await saveGroupHistory(group);
    if (clearDraft) {
      _groupDrafts.remove(group.id);
      _replyDrafts.remove((group.id, true));
    }
  }

  @override
  Future<BackupData> exportBackup() async {
    final seed = base64Encode(await identity.extractPrivateKeyBytes());
    final owner = (await Sha256().hash(
      (await identity.extractPublicKey()).bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return BackupData(
      seed: seed,
      owner: owner,
      name: name,
      created: DateTime.now().millisecondsSinceEpoch,
      demo: true,
      groups: _groups.values.map((g) => g.toJson()).toList(),
      peers: _people.values
          .map(
            (p) => <String, Object?>{
              'id': p.id,
              'name': p.name,
              'updated': p.updated,
              'pinned': p.pinned,
              'archived': p.archived,
            },
          )
          .toList(),
      messages: _messages.entries
          .map(
            (e) => <String, Object?>{
              'id': e.value.id,
              'peer': e.value.peerId,
              'text': e.value.text,
              'timestamp': e.value.timestamp,
              'outgoing': e.value.outgoing,
              'status': e.value.status,
              'read': !_unread.contains(e.key),
              if (e.value.reply != null) 'reply': e.value.reply!.toJson(),
              if (e.value.file != null)
                'file': {
                  ...e.value.file!.toJson(),
                  'data': base64Encode(_files[e.key]!),
                },
              if (e.value.image != null)
                'image': {
                  ...e.value.image!.toJson(),
                  'data': base64Encode(_images[e.key]!),
                },
            },
          )
          .toList(),
      stars: _stars.map((s) => s.toJson()).toList(),
      groupDrafts: [
        for (final id in {
          ..._groupDrafts.keys,
          ..._replyDrafts.keys.where((k) => k.$2).map((k) => k.$1),
        })
          {
            'group': id,
            'text': _groupDrafts[id] ?? '',
            if (_replyDrafts[(id, true)] != null)
              'reply': _replyDrafts[(id, true)]!.toJson(),
          },
      ],
      drafts: [
        for (final id in {
          ..._drafts.keys,
          ..._replyDrafts.keys.where((k) => !k.$2).map((k) => k.$1),
        })
          {
            'peer': id,
            'text': _drafts[id] ?? '',
            if (_replyDrafts[(id, false)] != null)
              'reply': _replyDrafts[(id, false)]!.toJson(),
          },
      ],
    );
  }

  @override
  Future<BackupMerge> importBackup(
    BackupData data, {
    bool moveIdentity = false,
  }) async {
    data = await BackupData.parse(data.toJson());
    final current = await exportBackup();
    if (moveIdentity &&
        (current.peers.isNotEmpty ||
            current.messages.isNotEmpty ||
            current.drafts.isNotEmpty ||
            current.groupDrafts.isNotEmpty ||
            current.groups.isNotEmpty)) {
      throw const FormatException(
        'Identity transfer requires an empty destination phone.',
      );
    }
    final plan = planBackup(current, data);
    final groupPlan = [
      for (final g in plan.data.groups) await GroupHistory.parse(g),
    ];
    final pair = moveIdentity
        ? await Ed25519().newKeyPairFromSeed(base64Decode(data.seed))
        : identity;
    for (final p in plan.data.peers) {
      _people[p['id'] as String] = Conversation(
        p['id'] as String,
        p['name'] as String,
        p['updated'] as int,
        pinned: p['pinned'] as bool,
        archived: p['archived'] as bool,
      );
    }
    final activityByPeer = {
      for (final p in data.peers) p['id']: p['updated'] as int,
    };
    for (final m in plan.data.messages) {
      final key = (
        m['peer'] as String,
        m['id'] as String,
        m['outgoing'] as bool,
      );
      _messages[key] = ChatMessage(
        id: key.$2,
        peerId: key.$1,
        text: m['text'] as String,
        timestamp: m['timestamp'] as int,
        outgoing: key.$3,
        status: m['status'] as String,
        image: m['image'] == null ? null : ChatImage.parse(m['image']),
        file: m['file'] == null ? null : ChatFile.parse(m['file']),
        reply: m['reply'] == null
            ? null
            : MessageReply.parse(m['reply'], group: false),
      );
      if (m['file'] != null) {
        _files[key] = base64Decode((m['file'] as Map)['data'] as String);
      }
      if (m['image'] != null) {
        _images[key] = base64Decode((m['image'] as Map)['data'] as String);
      }
      if (!key.$3 && m['read'] == false) _unread.add(key);
      final p = _people[key.$1]!;
      final activity = activityByPeer[key.$1]!;
      if (activity > p.updated) {
        _people[p.id] = Conversation(
          p.id,
          p.name,
          activity,
          pinned: p.pinned,
          archived: p.archived,
        );
      }
    }
    for (final d in plan.data.drafts) {
      _drafts[d['peer'] as String] = d['text'] as String;
      if (d['reply'] != null) {
        _replyDrafts[(d['peer'] as String, false)] = MessageReply.parse(
          d['reply'],
          group: false,
        );
      }
    }
    identity = pair;
    for (final g in groupPlan) {
      _groups[g.id] = _withGroupChoices(g);
    }
    for (final d in plan.data.groupDrafts) {
      _groupDrafts[d['group'] as String] = d['text'] as String;
      if (d['reply'] != null) {
        _replyDrafts[(d['group'] as String, true)] = MessageReply.parse(
          d['reply'],
          group: true,
        );
      }
    }
    _stars.addAll(plan.data.stars.map(StarredMessage.parse));
    return plan;
  }

  @override
  Future<String> draft(String peer) async => _drafts[peer] ?? '';

  @override
  Future<void> saveDraft(String peer, String text) async {
    if (text.isEmpty) {
      _drafts.remove(peer);
    } else {
      _drafts[peer] = text;
    }
  }

  @override
  Future<MessageReply?> draftReply(String id, {bool group = false}) async =>
      _replyDrafts[(id, group)];

  @override
  Future<void> saveDraftState(
    String id,
    String text,
    MessageReply? reply, {
    bool group = false,
  }) async {
    if (!(group ? _groups.containsKey(id) : _people.containsKey(id))) {
      throw const FormatException('This conversation has been deleted.');
    }
    if (utf8.encode(text).length > 1024 * 1024) {
      throw const FormatException('Draft exceeds the 1 MiB limit.');
    }
    if (reply != null) MessageReply.parse(reply.toJson(), group: group);
    final drafts = group ? _groupDrafts : _drafts;
    if (text.isEmpty) {
      drafts.remove(id);
    } else {
      drafts[id] = text;
    }
    if (reply == null) {
      _replyDrafts.remove((id, group));
    } else {
      _replyDrafts[(id, group)] = reply;
    }
  }

  @override
  Future<void> open() async {
    identity = await Ed25519().newKeyPair();
    name = 'You (Demo)';
  }

  @override
  Future<void> rename(String value) async => name = value;

  @override
  Future<void> savePeer(String id, String name) async {
    _people[id] = Conversation(
      id,
      name,
      _people[id]?.updated ?? DateTime.now().millisecondsSinceEpoch,
      pinned: _people[id]?.pinned ?? false,
      archived: _people[id]?.archived ?? false,
    );
  }

  @override
  Future<List<Conversation>> conversations() async {
    final result = <Conversation>[];
    for (final peer in _people.values) {
      final history = _messages.values
          .where((m) => m.peerId == peer.id)
          .toList();
      result.add(
        Conversation(
          peer.id,
          peer.name,
          peer.updated,
          latestMessage: history.isEmpty ? null : history.last,
          unreadCount: _unread.where((key) => key.$1 == peer.id).length,
          pinned: peer.pinned,
          archived: peer.archived,
          queuedCount: history
              .where((m) => m.outgoing && m.status == 'queued')
              .length,
        ),
      );
    }
    return result..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if ((a.latestMessage == null) != (b.latestMessage == null)) {
        return a.latestMessage == null ? 1 : -1;
      }
      final activity = b.updated.compareTo(a.updated);
      return activity != 0 ? activity : a.id.compareTo(b.id);
    });
  }

  @override
  Future<bool> saveMessage(ChatMessage message) async {
    if (message.reply != null) {
      MessageReply.parse(message.reply!.toJson(), group: false);
      if (message.image != null || message.file != null) {
        throw const FormatException('Replies are text only');
      }
    }
    final key = (message.peerId, message.id, message.outgoing);
    final previous = _messages[key];
    if (previous != null) {
      if (previous.text != message.text ||
          previous.reply != message.reply ||
          jsonEncode(previous.file?.toJson()) !=
              jsonEncode(message.file?.toJson()) ||
          jsonEncode(previous.image?.toJson()) !=
              jsonEncode(message.image?.toJson()) ||
          previous.timestamp != message.timestamp) {
        throw const FormatException('Conflicting message ID');
      }
      return false;
    }
    _messages[key] = message;
    if (!message.outgoing) _unread.add(key);
    final peer = _people[message.peerId];
    if (peer != null) {
      _people[peer.id] = Conversation(
        peer.id,
        peer.name,
        DateTime.now().millisecondsSinceEpoch,
        pinned: peer.pinned,
        archived: peer.archived,
      );
    }
    return true;
  }

  @override
  Future<void> markRead(String peer) async =>
      _unread.removeWhere((key) => key.$1 == peer);

  @override
  Future<void> saveOutgoingMessage(
    ChatMessage message, {
    bool clearDraft = false,
  }) async {
    await saveMessage(message);
    if (clearDraft) {
      _drafts.remove(message.peerId);
      _replyDrafts.remove((message.peerId, false));
    }
  }

  @override
  Future<List<ChatMessage>> queuedMessages(
    String peer, {
    int limit = 1,
  }) async => _messages.values
      .where((m) => m.peerId == peer && m.outgoing && m.status == 'queued')
      .take(limit)
      .toList();

  @override
  Future<bool> changeOutgoingStatus(
    String id,
    String peer,
    List<String> from,
    String to,
  ) async {
    final message = _messages[(peer, id, true)];
    if (message == null || !from.contains(message.status)) return false;
    await setStatus(id, peer, to);
    return true;
  }

  @override
  Future<bool> deleteQueuedMessage(String id, String peer) async {
    final key = (peer, id, true);
    if (_messages[key]?.status != 'queued') return false;
    _messages.remove(key);
    _stars.removeWhere(
      (s) => !s.group && s.target == peer && s.id == id && s.outgoing == true,
    );
    return true;
  }

  @override
  Future<List<ChatMessage>> messages(String peer) async =>
      _messages.values.where((message) => message.peerId == peer).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<void> setStatus(String id, String peer, String status) async {
    final key = (peer, id, true);
    final message = _messages[key];
    if (message == null) return;
    _messages[key] = ChatMessage(
      id: id,
      peerId: peer,
      text: message.text,
      timestamp: message.timestamp,
      outgoing: true,
      status: status,
      image: message.image,
      file: message.file,
      reply: message.reply,
    );
  }

  @override
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
    final people = await conversations();
    final names = people
        .where((p) => p.name.toLowerCase().contains(needle))
        .toList();
    final hits = <MessageSearchHit>[];
    var scanned = 0;
    for (final message in _messages.values.toList().reversed) {
      if (isCancelled?.call() == true) return const LocalSearchResults();
      final peer = _people[message.peerId];
      if (peer != null &&
          message.image == null &&
          message.file == null &&
          message.text.toLowerCase().contains(needle)) {
        if (hits.length == limit) {
          return LocalSearchResults(
            conversations: names,
            messages: hits,
            hasMoreMessages: true,
          );
        }
        hits.add(MessageSearchHit(peer, message));
      }
      if (++scanned % 100 == 0) await Future<void>.delayed(Duration.zero);
    }
    return isCancelled?.call() == true
        ? const LocalSearchResults()
        : LocalSearchResults(conversations: names, messages: hits);
  }

  @override
  Future<bool> setPinned(String peer, bool pinned) async {
    final old = _people[peer];
    if (old == null) return false;
    _people[peer] = Conversation(
      peer,
      old.name,
      old.updated,
      pinned: pinned,
      archived: old.archived,
    );
    return true;
  }

  @override
  Future<bool> setArchived(String peer, bool archived) async {
    final old = _people[peer];
    if (old == null) return false;
    _people[peer] = Conversation(
      peer,
      old.name,
      old.updated,
      pinned: old.pinned,
      archived: archived,
    );
    return true;
  }

  @override
  Future<void> deleteConversation(String peer) async {
    _stars.removeWhere((s) => !s.group && s.target == peer);
    _people.remove(peer);
    _messages.removeWhere((key, _) => key.$1 == peer);
    _images.removeWhere((key, _) => key.$1 == peer);
    _files.removeWhere((key, _) => key.$1 == peer);
    _unread.removeWhere((key) => key.$1 == peer);
    _drafts.remove(peer);
    _replyDrafts.remove((peer, false));
  }

  @override
  Future<void> clearHistory() async {
    _stars.clear();
    _replyDrafts.clear();
    _groups.clear();
    _images.clear();
    _files.clear();
    _people.clear();
    _messages.clear();
    _unread.clear();
    _drafts.clear();
    _groupDrafts.clear();
  }

  @override
  Future<void> close() => clearHistory();
}
