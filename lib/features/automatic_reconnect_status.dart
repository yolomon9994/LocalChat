import 'package:flutter/material.dart';
import '../services/chat_controller.dart';

class AutomaticReconnectStatus extends StatelessWidget {
  const AutomaticReconnectStatus({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final status = c.automaticReconnectStatus;
    if (status == null || !c.appAccessible || !c.appForeground) {
      return const SizedBox.shrink();
    }
    final token = c.automaticReconnectToken;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status, key: const ValueKey('automatic-reconnect-status')),
            if (token != null) ...[
              const Text(
                'Messages wait for fresh verification. Locking, leaving the app or cancelling stops these retries.',
              ),
              TextButton.icon(
                key: const ValueKey('cancel-automatic-reconnect'),
                onPressed: () => c.cancelAutomaticReconnect(token: token),
                icon: const Icon(Icons.close),
                label: const Text('Cancel reconnection'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
