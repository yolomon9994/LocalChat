import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/chat_controller.dart';

class NearbyTab extends StatelessWidget {
  const NearbyTab({
    super.key,
    required this.controller,
    required this.onConnect,
  });

  final ChatController controller;
  final ValueChanged<Peer> onConnect;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      key: const PageStorageKey('nearby-list'),
      primary: false,
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Find someone nearby',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          c.isDemo
              ? 'Explore the interface with simulated friends. Tap Go nearby to find demo devices.'
              : 'Text nearby friends with Wi-Fi Direct. No router, account, or mobile data needed.',
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.wifi_tethering,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(c.profileName),
            subtitle: Text(c.isDemo ? 'Demo • ${c.state}' : c.state),
          ),
        ),
        const SizedBox(height: 20),
        if (!c.started)
          FilledButton.icon(
            onPressed: c.start,
            icon: const Icon(Icons.radar),
            label: const Text('Go nearby'),
          )
        else ...[
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
          if (c.peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Icon(Icons.devices, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    c.isDemo
                        ? 'Looking for simulated devices'
                        : 'Looking for LocalChat phones',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.isDemo
                        ? 'Demo friends will appear shortly.'
                        : 'Open Nearby and tap Go nearby on both phones.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          for (final peer in c.peers)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(peer.name),
                subtitle: Text(
                  c.isDemo
                      ? 'Simulated device • tap to connect'
                      : 'Nearby • tap to connect',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: c.state == 'Connecting' ? null : () => onConnect(peer),
              ),
            ),
        ],
        const SizedBox(height: 28),
        Text(
          c.isDemo
              ? 'This browser preview does not discover or communicate with real phones. Use Android devices to test Wi-Fi Direct.'
              : 'Keep the app open while chatting. Wi-Fi must be on. Some older Android phones also require Location to be on.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
