import 'group_models.dart';

/// Search snapshots contain display text and IDs, never attachment contents.
class GroupSearchGroup {
  const GroupSearchGroup(this.id, this.title, this.archived);
  final String id, title;
  final bool archived;
}

class GroupSearchHit {
  const GroupSearchHit(
    this.group,
    this.key,
    this.text,
    this.author,
    this.name,
    this.timestamp,
  );
  final GroupSearchGroup group;
  final String key, text, author, name;
  final int timestamp;
}

class GroupSearchResults {
  const GroupSearchResults({
    this.groups = const [],
    this.messages = const [],
    this.hasMoreMessages = false,
  });
  final List<GroupSearchGroup> groups;
  final List<GroupSearchHit> messages;
  final bool hasMoreMessages;
}

/// Scan already authenticated, decrypted saved histories. No disk index or
/// additional decryption is needed; yield regularly so edits/locking can cancel.
Future<GroupSearchResults> searchGroupHistories(
  List<GroupHistory> histories,
  String query, {
  String? groupId,
  int limit = 100,
  bool Function()? isCancelled,
}) async {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty || limit <= 0 || isCancelled?.call() == true) {
    return const GroupSearchResults();
  }
  final groups = <GroupSearchGroup>[];
  final hits = <GroupSearchHit>[];
  var seen = 0, matches = 0;
  int compare(GroupSearchHit a, GroupSearchHit b) {
    final time = b.timestamp.compareTo(a.timestamp);
    if (time != 0) return time;
    final group = a.group.id.compareTo(b.group.id);
    return group != 0 ? group : a.key.compareTo(b.key);
  }

  for (final history in histories) {
    if (isCancelled?.call() == true) return const GroupSearchResults();
    if (groupId != null && history.id != groupId) continue;
    final group = GroupSearchGroup(history.id, history.title, history.archived);
    if (groupId == null && history.title.toLowerCase().contains(needle)) {
      groups.add(group);
    }
    for (final message in history.messages) {
      // Attachment labels and filenames are searchable; bytes are never scanned.
      final file = message.file;
      final text = file == null
          ? message.text
          : '${message.text}: ${file.name}';
      if (text.toLowerCase().contains(needle)) {
        matches++;
        hits.add(
          GroupSearchHit(
            group,
            message.key,
            text,
            message.author,
            message.name,
            message.timestamp,
          ),
        );
        hits.sort(compare);
        if (hits.length > limit) hits.removeLast();
      }
      if (++seen % 128 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() == true) return const GroupSearchResults();
      }
    }
    // Also yield for many empty saved rooms.
    await Future<void>.delayed(Duration.zero);
  }
  if (isCancelled?.call() == true) return const GroupSearchResults();
  return GroupSearchResults(
    groups: groups,
    messages: hits,
    hasMoreMessages: matches > limit,
  );
}
