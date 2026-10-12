import 'chat_image.dart';

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
    this.image,
  });
  final String id;
  final String peerId;
  final String text;
  final int timestamp;
  final bool outgoing;
  final String status;
  final ChatImage? image;
}

class Conversation {
  const Conversation(
    this.id,
    this.name,
    this.updated, {
    this.latestMessage,
    this.unreadCount = 0,
    this.pinned = false,
    this.archived = false,
    this.queuedCount = 0,
  });
  final String id;
  final String name;
  final int updated;
  final ChatMessage? latestMessage;
  final int unreadCount;
  final bool pinned;
  final bool archived;
  final int queuedCount;
}

class MessageSearchHit {
  const MessageSearchHit(this.conversation, this.message);
  final Conversation conversation;
  final ChatMessage message;
}

class LocalSearchResults {
  const LocalSearchResults({
    this.conversations = const [],
    this.messages = const [],
    this.hasMoreMessages = false,
  });
  final List<Conversation> conversations;
  final List<MessageSearchHit> messages;
  final bool hasMoreMessages;
}
