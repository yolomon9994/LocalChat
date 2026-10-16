import 'contact_nickname_dialog.dart';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';

class ConversationMenu extends StatefulWidget {
  const ConversationMenu({
    super.key,
    required this.controller,
    required this.peer,
  });
  final ChatController controller;
  final Conversation peer;
  @override
  State<ConversationMenu> createState() => _ConversationMenuState();
}

class _ConversationMenuState extends State<ConversationMenu> {
  bool _busy = false;

  Future<void> _act(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final c = widget.controller;
    final peer = widget.peer;
    try {
      bool success;
      switch (action) {
        case 'nickname':
          await showDialog<void>(
            context: context,
            builder: (_) => ContactNicknameDialog(controller: c, peer: peer),
          );
          return;
        case 'pin':
          success = await c.setPinned(peer.id, !peer.pinned);
        case 'archive':
          success = await c.setArchived(peer.id, !peer.archived);
        case 'delete':
          final active = c.connectedPeer == peer.id;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete chat?'),
              scrollable: true,
              content: Text(
                'Delete “${peer.name}” and its saved messages and draft '
                '${c.isDemo ? 'in this demo tab' : 'on this phone'}? This cannot be undone. '
                '${active ? 'The active connection will be disconnected. ' : ''}'
                'The other person’s history is unaffected.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (!mounted || confirmed != true) return;
          success = await c.deleteConversation(peer.id);
        default:
          return;
      }
      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              c.error ?? 'Could not update this chat. Please try again.',
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
    key: ValueKey('conversation-menu-${widget.peer.id}'),
    tooltip: 'Chat options for ${widget.peer.name}',
    enabled: !_busy,
    onSelected: _act,
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'nickname',
        child: Text(
          widget.peer.nickname == null ? 'Set nickname' : 'Edit nickname',
        ),
      ),
      PopupMenuItem(
        value: 'pin',
        child: Text(widget.peer.pinned ? 'Unpin chat' : 'Pin chat'),
      ),
      PopupMenuItem(
        value: 'archive',
        child: Text(widget.peer.archived ? 'Unarchive chat' : 'Archive chat'),
      ),
      const PopupMenuItem(value: 'delete', child: Text('Delete chat')),
    ],
  );
}
