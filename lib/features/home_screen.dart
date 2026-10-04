import 'package:flutter/material.dart';
import '../services/chat_controller.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});
  final ChatController controller;
  void _chat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      return Scaffold(
        appBar: AppBar(
          title: const Text('LocalChat'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(controller: c),
                ),
              ),
            ),
          ],
        ),
        body: c.loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Stay close. Stay connected.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Text nearby friends with Wi-Fi Direct. No router, account, or mobile data needed.',
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            c.ready ? Icons.lock : Icons.wifi_tethering,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.profileName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(c.state),
                              ],
                            ),
                          ),
                          if (c.connectedPeer != null)
                            TextButton(
                              onPressed: () async {
                                await c.viewConnected();
                                if (context.mounted) _chat(context);
                              },
                              child: const Text('Open'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (c.error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(child: Text(c.error!)),
                            IconButton(
                              onPressed: c.dismissError,
                              icon: const Icon(Icons.close),
                              tooltip: 'Dismiss',
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (!c.initialized)
                    FilledButton(
                      onPressed: c.initialize,
                      child: const Text('Retry setup'),
                    )
                  else if (!c.started)
                    FilledButton.icon(
                      onPressed: c.start,
                      icon: const Icon(Icons.radar),
                      label: const Text('Go nearby'),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Nearby devices',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Scan again',
                          onPressed: c.scanning ? null : c.scan,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  if (c.scanning) const LinearProgressIndicator(),
                  if (c.started && c.peers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.devices, size: 48),
                          SizedBox(height: 12),
                          Text('Looking for LocalChat phones'),
                          SizedBox(height: 6),
                          Text(
                            'Open LocalChat and tap Go nearby on both phones.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  for (final peer in c.peers)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(peer.name),
                        subtitle: const Text('Nearby • tap to connect'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: c.state == 'Connecting'
                            ? null
                            : () async {
                                await c.connect(peer);
                                if (context.mounted) _chat(context);
                              },
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Conversations',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (c.conversations.isEmpty)
                    const Text('Your verified conversations will appear here.'),
                  for (final peer in c.conversations)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        child: Icon(Icons.chat_bubble_outline),
                      ),
                      title: Text(peer.name),
                      subtitle: Text(
                        peer.id == c.connectedPeer
                            ? 'Connected'
                            : 'Saved on this phone',
                      ),
                      onTap: () async {
                        await c.viewHistory(peer);
                        if (context.mounted) _chat(context);
                      },
                    ),
                  const SizedBox(height: 32),
                  const Text(
                    'Keep the app open while chatting. Wi-Fi must be on. Some older Android phones also require Location to be on.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
      );
    },
  );
}
