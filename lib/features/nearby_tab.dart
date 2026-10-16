import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/chat_controller.dart';
import 'automatic_reconnect_status.dart';

class NearbyTab extends StatelessWidget {
  const NearbyTab({
    super.key,
    required this.controller,
    required this.onConnect,
    this.onReconnect,
  });

  final ChatController controller;
  final ValueChanged<Peer> onConnect;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      key: const PageStorageKey('nearby-list'),
      primary: false,
      padding: const EdgeInsets.all(20),
      children: [
        AutomaticReconnectStatus(controller: c),
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
            onPressed: c.canUseNearby ? c.start : null,
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
                onPressed: c.canScan ? c.scan : null,
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
                    c.scanning
                        ? (c.isDemo
                              ? 'Looking for simulated devices'
                              : 'Looking for LocalChat phones')
                        : (c.isDemo
                              ? 'No demo devices found'
                              : 'No LocalChat phones found'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.scanning && c.isDemo
                        ? 'Demo friends will appear shortly.'
                        : 'Open Nearby and tap Go nearby on both phones, keep them close, then scan again.',
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
                onTap: !c.canUseNearby || c.state == 'Connecting'
                    ? null
                    : () => onConnect(peer),
              ),
            ),
        ],
        if (c.nearbyBusy) const LinearProgressIndicator(),
        if (c.connectedPeer != null || c.state == 'Connecting')
          TextButton.icon(
            onPressed: c.canUseNearby ? c.disconnect : null,
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect'),
          ),
        if (c.lastNearbyPeer != null &&
            c.connectedPeer == null &&
            c.state != 'Connecting')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last device: ${c.lastNearbyPeer!.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Reconnect requires comparing a new security code on both phones.',
                  ),
                  if (c.canReconnect)
                    TextButton.icon(
                      onPressed: onReconnect ?? c.reconnect,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect'),
                    )
                  else
                    const Text(
                      'Scan again to find this phone in the current nearby list.',
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.isDemo ? 'Demo access checks' : 'Nearby access',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (c.nearbyStatus case final status?) ...[
                  Text(
                    'Wi-Fi Direct: ${status.supported ? 'supported' : 'unavailable'}',
                  ),
                  Text('Wi-Fi: ${status.wifiEnabled ? 'on' : 'off'}'),
                  Text(
                    'Nearby permission: ${status.permissionGranted ? 'allowed' : 'needed'}',
                  ),
                  if (status.locationRequired)
                    Text(
                      'Location switch: ${status.locationEnabled ? 'on' : 'off'}',
                    ),
                ] else
                  const Text(
                    'Check Wi-Fi and permission access without starting discovery.',
                  ),
                TextButton.icon(
                  onPressed: c.canUseNearby ? c.refreshNearbyAccess : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Check access'),
                ),
              ],
            ),
          ),
        ),
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
