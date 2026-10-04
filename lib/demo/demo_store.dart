import 'package:cryptography/cryptography.dart';
import '../core/local_store.dart';
import '../core/models.dart';

/// Preview-only state. Never opens SQLite or platform secure storage.
class DemoStore extends LocalStore {
  final _people = <String, Conversation>{};
  final _messages = <(String, String, bool), ChatMessage>{};

  @override
  Future<void> open() async {
    identity = await Ed25519().newKeyPair();
    name = 'You (Demo)';
  }

  @override
  Future<void> rename(String value) async => name = value;

  @override
  Future<void> savePeer(String id, String name) async {
    _people[id] = Conversation(id, name, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Future<List<Conversation>> conversations() async =>
      _people.values.toList()..sort((a, b) => b.updated.compareTo(a.updated));

  @override
  Future<void> saveMessage(ChatMessage message) async {
    _messages.putIfAbsent((
      message.peerId,
      message.id,
      message.outgoing,
    ), () => message);
    final peer = _people[message.peerId];
    if (peer != null) await savePeer(peer.id, peer.name);
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
  Future<void> clearHistory() async {
    _people.clear();
    _messages.clear();
  }

  @override
  Future<void> close() => clearHistory();
}
