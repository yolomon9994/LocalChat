import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/chat_controller.dart';

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
  });

  final ChatController controller;
  final VoidCallback onFindDevices;
  final VoidCallback onOpenConnected;
  final ValueChanged<Conversation> onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      key: const PageStorageKey('chats-list'),
      primary: false,
      padding: const EdgeInsets.all(20),
      children: [
        Text('Your chats', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          c.isDemo
              ? 'Your demo conversations stay in this browser tab until reload.'
              : 'Your conversations stay saved on this phone.',
        ),
        if (c.connectedPeer != null || c.state == 'Connecting') ...[
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
        if (c.conversations.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No chats yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Find a nearby friend and verify your connection '
                    'to start a conversation.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
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
          for (final peer in c.conversations)
            Card(
              child: ListTile(
                key: ValueKey('conversation-${peer.id}'),
                leading: const CircleAvatar(
                  child: Icon(Icons.chat_bubble_outline),
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
                  ],
                ),
                trailing: peer.unreadCount > 0
                    ? Semantics(
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
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => onOpenHistory(peer),
              ),
            ),
      ],
    );
  }
}
