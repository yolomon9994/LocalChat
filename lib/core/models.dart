class Peer {
  const Peer(this.address, this.name);
  final String address;
  final String name;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerId,
    required this.text,
    required this.timestamp,
    required this.outgoing,
    required this.status,
  });
  final String id;
  final String peerId;
  final String text;
  final int timestamp;
  final bool outgoing;
  final String status;
}

class Conversation {
  const Conversation(
    this.id,
    this.name,
    this.updated, {
    this.latestMessage,
    this.unreadCount = 0,
  });
  final String id;
  final String name;
  final int updated;
  final ChatMessage? latestMessage;
  final int unreadCount;
}
