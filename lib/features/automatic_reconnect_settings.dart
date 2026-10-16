import 'package:flutter/material.dart';
import '../services/chat_controller.dart';

class AutomaticReconnectSettings extends StatelessWidget {
  const AutomaticReconnectSettings({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final p = controller.reconnectPreferences;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connection recovery',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SwitchListTile(
            key: const ValueKey('automatic-reconnect-setting'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatically reconnect direct chats'),
            subtitle: Text(
              controller.isDemo
                  ? 'Temporary in this demo tab. Retries are simulated.'
                  : 'Retry a dropped, verified connection while this app is open and unlocked.',
            ),
            value: p.enabled,
            onChanged:
                p.loading ||
                    p.saving ||
                    !controller.appAccessible ||
                    !controller.appForeground
                ? null
                : controller.setAutomaticReconnectEnabled,
          ),
          const Text(
            'Up to 3 attempts, waiting 2, 5 and 10 seconds. The last selected device must still be listed in Nearby. Compare fresh codes on both phones before messaging resumes. Group chats reconnect manually.',
          ),
          if (p.saving) const LinearProgressIndicator(),
          if (p.error != null)
            Text(
              p.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 28),
        ],
      );
    },
  );
}
