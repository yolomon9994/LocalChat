import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/chat_controller.dart';

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
                leading: const CircleAvatar(
                  child: Icon(Icons.chat_bubble_outline),
                ),
                title: Text(peer.name),
                subtitle: Text(
                  peer.id == c.connectedPeer
                      ? c.ready
                            ? 'Connected'
                            : 'Verify connection'
                      : c.isDemo
                      ? 'In-memory demo history'
                      : 'Saved on this phone',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenHistory(peer),
              ),
            ),
      ],
    );
  }
}
