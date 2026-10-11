import 'package:flutter/material.dart';
import '../services/chat_controller.dart';
import '../services/nearby_support.dart';

class ConnectionHelp extends StatelessWidget {
  const ConnectionHelp({super.key, required this.controller, this.onReconnect});
  final ChatController controller;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final c = controller, issue = controller.connectionIssue!;
    final target = issue.settingsTarget;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    issue.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: c.dismissError,
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(issue.guidance),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (target != null && !c.isDemo)
                  TextButton.icon(
                    onPressed: c.canUseNearby
                        ? () => c.openNearbySettings(target)
                        : null,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(switch (target) {
                      NearbySettings.wifi => 'Open Wi-Fi settings',
                      NearbySettings.permissions => 'Open app settings',
                      NearbySettings.location => 'Open Location settings',
                    }),
                  ),
                TextButton(
                  onPressed: c.canUseNearby ? c.refreshNearbyAccess : null,
                  child: const Text('Check access'),
                ),
                if (issue != ConnectionIssue.unsupported) ...[
                  if (!c.started)
                    TextButton(
                      onPressed: c.canUseNearby ? c.start : null,
                      child: const Text('Go nearby'),
                    )
                  else
                    TextButton(
                      onPressed: c.canScan ? c.scan : null,
                      child: const Text('Scan again'),
                    ),
                  if (c.canReconnect)
                    TextButton(
                      onPressed: onReconnect ?? c.reconnect,
                      child: const Text('Reconnect'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
