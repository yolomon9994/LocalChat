import 'dart:convert';

/// A local bookmark. Group authors and direct directions disambiguate IDs.
class StarredMessage {
  const StarredMessage({
    required this.target,
    required this.id,
    this.outgoing,
    this.author,
  });
  final String target, id;
  final bool? outgoing;
  final String? author;
  bool get group => author != null;
  String get key => jsonEncode(toJson());
  Map<String, Object?> toJson() => {
    'target': target,
    'id': id,
    if (group) 'author': author else 'outgoing': outgoing,
  };
  static StarredMessage parse(Object? raw) {
    if (raw is! Map ||
        raw.length != 3 ||
        raw['target'] is! String ||
        (raw['target'] as String).isEmpty ||
        utf8.encode(raw['target'] as String).length > 128 ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        utf8.encode(raw['id'] as String).length > 128 ||
        (raw.containsKey('author')
            ? raw['author'] is! String ||
                  !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['author'] as String)
            : raw['outgoing'] is! bool)) {
      throw const FormatException('Invalid starred message.');
    }
    return StarredMessage(
      target: raw['target'] as String,
      id: raw['id'] as String,
      outgoing: raw['outgoing'] as bool?,
      author: raw['author'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StarredMessage &&
      target == other.target &&
      id == other.id &&
      outgoing == other.outgoing &&
      author == other.author;
  @override
  int get hashCode => Object.hash(target, id, outgoing, author);
}
