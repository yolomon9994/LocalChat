import 'dart:convert';

/// A bounded quotation supplied by the replying sender, not proof of authorship.
/// Direct direction is local to the storing phone; group authors are identity IDs.
class MessageReply {
  const MessageReply({
    required this.id,
    required this.name,
    required this.text,
    this.outgoing,
    this.author,
  });
  final String id, name, text;
  final bool? outgoing;
  final String? author;
  bool get isGroup => author != null;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'text': text,
    if (author != null) 'author': author else 'outgoing': outgoing,
  };

  static String preview(String text) {
    text = text.trim();
    final result = StringBuffer();
    var bytes = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      bytes += utf8.encode(char).length;
      if (bytes > 512) break;
      result.write(char);
    }
    return result.toString();
  }

  static MessageReply parse(Object? raw, {required bool group}) {
    const invalid = FormatException('Invalid message reply');
    if (raw is! Map ||
        raw.length != 4 ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        utf8.encode(raw['id'] as String).length > 128 ||
        raw['name'] is! String ||
        (raw['name'] as String).trim().isEmpty ||
        utf8.encode(raw['name'] as String).length > 256 ||
        raw['text'] is! String ||
        (raw['text'] as String).trim().isEmpty ||
        utf8.encode(raw['text'] as String).length > 512) {
      throw invalid;
    }
    if (group
        ? raw['author'] is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['author'] as String) ||
              !RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(raw['id'] as String)
        : raw['outgoing'] is! bool) {
      throw invalid;
    }
    return MessageReply(
      id: raw['id'] as String,
      name: raw['name'] as String,
      text: raw['text'] as String,
      author: group ? raw['author'] as String : null,
      outgoing: group ? null : raw['outgoing'] as bool,
    );
  }

  /// A direct receiver has the opposite local direction for the quoted message.
  MessageReply reversed() =>
      MessageReply(id: id, name: name, text: text, outgoing: !outgoing!);

  bool matchesText(String body) => preview(body) == text;
  @override
  bool operator ==(Object other) =>
      other is MessageReply &&
      id == other.id &&
      name == other.name &&
      text == other.text &&
      outgoing == other.outgoing &&
      author == other.author;
  @override
  int get hashCode => Object.hash(id, name, text, outgoing, author);
}
