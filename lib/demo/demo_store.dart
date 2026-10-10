import 'package:cryptography/cryptography.dart';
import '../core/local_store.dart';
import '../core/models.dart';

/// Preview-only state. Never opens SQLite or platform secure storage.
class DemoStore extends LocalStore {
  final _people = <String, Conversation>{};
  final _messages = <(String, String, bool), ChatMessage>{};
  final _unread = <(String, String, bool)>{};

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
        ),
      );
    }
    return result..sort((a, b) {
      if ((a.latestMessage == null) != (b.latestMessage == null)) {
        return a.latestMessage == null ? 1 : -1;
      }
      final activity = b.updated.compareTo(a.updated);
      return activity != 0 ? activity : a.id.compareTo(b.id);
    });
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    final key = (message.peerId, message.id, message.outgoing);
    if (_messages.containsKey(key)) return;
    _messages[key] = message;
    if (!message.outgoing) _unread.add(key);
    final peer = _people[message.peerId];
    if (peer != null) {
      _people[peer.id] = Conversation(
        peer.id,
        peer.name,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<void> markRead(String peer) async =>
      _unread.removeWhere((key) => key.$1 == peer);

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
  Future<void> clearHistory() async {
    _people.clear();
    _messages.clear();
    _unread.clear();
  }

  @override
  Future<void> close() => clearHistory();
}
