import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../core/chat_backup.dart';
import '../core/local_store.dart';
import '../core/models.dart';

/// Preview-only state. Never opens SQLite or platform secure storage.
class DemoStore extends LocalStore {
  final _people = <String, Conversation>{};
  final _messages = <(String, String, bool), ChatMessage>{};
  final _unread = <(String, String, bool)>{};
  final _drafts = <String, String>{};

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
            },
          )
          .toList(),
      drafts: _drafts.entries
          .map((e) => <String, Object?>{'peer': e.key, 'text': e.value})
          .toList(),
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
            current.drafts.isNotEmpty)) {
      throw const FormatException(
        'Identity transfer requires an empty destination phone.',
      );
    }
    final plan = planBackup(current, data);
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
      );
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
    }
    identity = pair;
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
    final key = (message.peerId, message.id, message.outgoing);
    final previous = _messages[key];
    if (previous != null) {
      if (previous.text != message.text ||
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
    if (clearDraft) _drafts.remove(message.peerId);
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
      if (peer != null && message.text.toLowerCase().contains(needle)) {
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
    _people.remove(peer);
    _messages.removeWhere((key, _) => key.$1 == peer);
    _unread.removeWhere((key) => key.$1 == peer);
    _drafts.remove(peer);
  }

  @override
  Future<void> clearHistory() async {
    _people.clear();
    _messages.clear();
    _unread.clear();
    _drafts.clear();
  }

  @override
  Future<void> close() => clearHistory();
}
