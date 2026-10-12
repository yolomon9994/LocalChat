import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/chat_controller.dart';
import 'conversation_menu.dart';
import 'group_screen.dart';

String formatConversationTime(int timestamp, {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  final today = now ?? DateTime.now();
  final date = DateTime(time.year, time.month, time.day);
  final currentDate = DateTime(today.year, today.month, today.day);
  if (date == currentDate) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  if (date == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final label = '${months[time.month - 1]} ${time.day}';
  return time.year == today.year ? label : '$label, ${time.year}';
}

class ChatsTab extends StatelessWidget {
  const ChatsTab({
    super.key,
    required this.controller,
    required this.onFindDevices,
    required this.onOpenConnected,
    required this.onOpenHistory,
    this.onOpenArchived,
    this.archived = false,
    this.routeObserver,
  });

  final ChatController controller;
  final VoidCallback onFindDevices;
  final VoidCallback onOpenConnected;
  final ValueChanged<Conversation> onOpenHistory;
  final VoidCallback? onOpenArchived;
  final bool archived;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final displayed = c.conversations
        .where((p) => p.archived == archived)
        .toList();
    final archivedChats = c.conversations.where((p) => p.archived).toList();
    final archivedUnread = archivedChats.fold<int>(
      0,
      (sum, p) => sum + p.unreadCount,
    );
    return ListView(
      key: PageStorageKey(archived ? 'archived-chats-list' : 'chats-list'),
      primary: false,
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          archived ? 'Saved for later' : 'Your chats',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (!archived && c.groups.histories.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final group in c.groups.histories)
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(group.title),
                subtitle: Text(
                  'Group • ${group.unread} unread${c.groups.active?.id == group.id ? ' • active' : ''}',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupChatScreen(
                      controller: c,
                      id: group.id,
                      routeObserver: routeObserver,
                    ),
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          archived
              ? 'Archived chats stay here when new messages arrive. Unarchive to return them to Chats.'
              : c.isDemo
              ? 'Your demo conversations stay in this browser tab until reload.'
              : 'Your conversations stay saved on this phone.',
        ),
        if (!archived &&
            (c.connectedPeer != null || c.state == 'Connecting')) ...[
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Icon(c.ready ? Icons.lock : Icons.wifi_tethering),
              title: const Text('Active chat'),
              subtitle: Text(c.isDemo ? 'Demo • ${c.state}' : c.state),
              trailing: c.connectedPeer == null
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: onOpenConnected,
                      child: const Text('Open'),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (!archived && archivedChats.isNotEmpty)
          Card(
            child: ListTile(
              key: const ValueKey('open-archived-chats'),
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archived chats'),
              subtitle: Text(
                '${archivedChats.length} ${archivedChats.length == 1 ? 'chat' : 'chats'}'
                '${archivedUnread > 0 ? ' · $archivedUnread unread ${archivedUnread == 1 ? 'message' : 'messages'}' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenArchived,
            ),
          ),
        if (displayed.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    archived
                        ? 'No archived chats'
                        : archivedChats.isNotEmpty
                        ? 'All your chats are archived'
                        : 'No chats yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    archived
                        ? 'Archive a conversation from its chat options to keep it here.'
                        : 'Find a nearby friend and verify your connection '
                              'to start a conversation.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (!archived)
                    FilledButton.icon(
                      onPressed: onFindDevices,
                      icon: const Icon(Icons.radar),
                      label: const Text('Find nearby devices'),
                    ),
                ],
              ),
            ),
          )
        else
          for (final peer in displayed)
            Card(
              key: ValueKey('conversation-card-${peer.id}'),
              child: ListTile(
                key: ValueKey('conversation-${peer.id}'),
                leading: CircleAvatar(
                  child: Icon(
                    peer.pinned ? Icons.push_pin : Icons.chat_bubble_outline,
                    semanticLabel: peer.pinned ? 'Pinned chat' : null,
                  ),
                ),
                title: Text(
                  peer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: peer.unreadCount > 0
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.latestMessage == null
                          ? 'No messages yet'
                          : '${peer.latestMessage!.outgoing ? 'You: ' : ''}${peer.latestMessage!.text.replaceAll(RegExp(r'\s+'), ' ').trim()}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (peer.latestMessage != null)
                      Text(
                        formatConversationTime(peer.updated),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    if (peer.queuedCount > 0)
                      Text(
                        '${peer.queuedCount} queued',
                        key: ValueKey('queued-${peer.id}'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (peer.unreadCount > 0)
                      Semantics(
                        label:
                            '${peer.unreadCount} unread ${peer.unreadCount == 1 ? 'message' : 'messages'}',
                        child: ExcludeSemantics(
                          child: Badge(
                            key: ValueKey('unread-${peer.id}'),
                            label: Text(
                              peer.unreadCount > 99
                                  ? '99+'
                                  : '${peer.unreadCount}',
                            ),
                          ),
                        ),
                      ),
                    ConversationMenu(controller: c, peer: peer),
                  ],
                ),
                onTap: () => onOpenHistory(peer),
              ),
            ),
      ],
    );
  }
}
