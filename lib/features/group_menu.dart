import 'package:flutter/material.dart';
import '../core/group_models.dart';
import '../services/chat_controller.dart';

class GroupMenu extends StatefulWidget {
  const GroupMenu({super.key, required this.controller, required this.group});
  final ChatController controller;
  final GroupHistory group;
  @override
  State<GroupMenu> createState() => _GroupMenuState();
}

class _GroupMenuState extends State<GroupMenu> {
  bool _busy = false;
  int? _accessAtOpen;

  Future<void> _act(String action) async {
    if (!mounted || _busy) return;
    final c = widget.controller;
    if (!c.appAccessible ||
        !c.appForeground ||
        _accessAtOpen != c.accessRevision) {
      return;
    }
    setState(() => _busy = true);
    try {
      final success = switch (action) {
        'pin' => await c.groups.setPinned(widget.group.id, true),
        'unpin' => await c.groups.setPinned(widget.group.id, false),
        'archive' => await c.groups.setArchived(widget.group.id, true),
        'unarchive' => await c.groups.setArchived(widget.group.id, false),
        _ => false,
      };
      if (mounted && !success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              c.groups.error ??
                  'Could not update this group. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: ValueKey('group-menu-${widget.group.id}'),
    tooltip: 'Group options for ${widget.group.title}',
    enabled:
        !_busy &&
        widget.controller.appAccessible &&
        widget.controller.appForeground,
    onOpened: () => _accessAtOpen = widget.controller.accessRevision,
    onSelected: _act,
    itemBuilder: (_) => [
      PopupMenuItem(
        value: widget.group.pinned ? 'unpin' : 'pin',
        child: Text(widget.group.pinned ? 'Unpin group' : 'Pin group'),
      ),
      PopupMenuItem(
        value: widget.group.archived ? 'unarchive' : 'archive',
        child: Text(
          widget.group.archived ? 'Unarchive group' : 'Archive group',
        ),
      ),
    ],
  );
}
