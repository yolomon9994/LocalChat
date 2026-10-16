import '../core/group_models.dart';

/// Local observations, never transmitted or included in saved history/backups.
enum GroupDeliveryReason {
  memberLeft('member disconnected or left'),
  memberRemoved('member removed from the group'),
  membershipChanged('group membership changed'),
  hostDisconnected('host connection ended'),
  connectionEnded('group connection ended'),
  stopped('this phone left or ended the group'),
  timeout('confirmation timed out'),
  interrupted('sending was interrupted'),
  transferStopped('attachment transfer stopped');

  const GroupDeliveryReason(this.label);
  final String label;
}

/// Reasons describe only pending -> unconfirmed transitions observed this run.
/// Receipt values remain authoritative, including late valid confirmations.
class GroupDeliveryDetails {
  final _reasons = <(String, String, String), GroupDeliveryReason>{};
  final _names = <(String, String), String>{};
  final _endings = <String, GroupDeliveryReason>{};

  void remember(String group, List<GroupMember> members) {
    for (final member in members) {
      _names[(group, member.id)] = member.name;
    }
  }

  void record(
    GroupHistory before,
    GroupHistory after,
    GroupDeliveryReason reason,
  ) {
    final old = {for (final m in before.messages) m.key: m};
    for (final m in after.messages) {
      for (final entry in m.receipts.entries) {
        if (entry.value == 'unconfirmed' &&
            old[m.key]?.receipts[entry.key] == 'pending') {
          _reasons[(after.id, m.key, entry.key)] = reason;
        }
      }
    }
  }

  void ended(String group, GroupDeliveryReason reason) =>
      _endings[group] = reason;
  void joined(String group) => _endings.remove(group);
  GroupDeliveryReason? ending(String group) => _endings[group];

  String name(String group, String member) =>
      _names[(group, member)] ?? member.substring(0, 8);

  String status(String group, GroupText message, String member) {
    switch (message.receipts[member]) {
      case 'received':
        return 'Received';
      case 'pending':
        return 'Pending confirmation';
      default:
        final reason = _reasons[(group, message.key, member)];
        return 'Unconfirmed: ${reason?.label ?? 'no receipt available'}';
    }
  }

  void prune(List<GroupHistory> histories) {
    final groups = {for (final h in histories) h.id: h};
    if (_reasons.isNotEmpty) {
      final messages = {
        for (final h in histories)
          for (final m in h.messages) (h.id, m.key): m,
      };
      _reasons.removeWhere(
        (key, _) =>
            messages[(key.$1, key.$2)]?.receipts[key.$3] != 'unconfirmed',
      );
    }
    _names.removeWhere((key, _) => !groups.containsKey(key.$1));
    _endings.removeWhere((key, _) => !groups.containsKey(key));
  }

  void clear() {
    _reasons.clear();
    _names.clear();
    _endings.clear();
  }
}
