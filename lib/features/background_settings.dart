import 'package:flutter/material.dart';
import '../services/chat_controller.dart';

class BackgroundSettings extends StatelessWidget {
  const BackgroundSettings({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.background]),
    builder: (context, _) {
      final b = controller.background;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Background connection',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep connection active'),
            subtitle: Text(
              b.isDemo
                  ? 'Simulated mode only; no background browser connection.'
                  : 'Keep the current verified direct chat while using another app or turning the screen off. Uses additional battery. Hosted groups are not protected.',
            ),
            value: b.enabled,
            onChanged: b.initialized && !b.busy
                ? controller.setBackgroundEnabled
                : null,
          ),
          Text(
            b.active
                ? (b.isDemo
                      ? 'Demo connection protection active'
                      : 'Connection protection active')
                : b.busy
                ? 'Updating connection protection…'
                : b.enabled
                ? 'Waiting for an unlocked, verified connection.'
                : 'Background connection protection is off.',
          ),
          if (b.notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(b.notice!),
            ),
          if (b.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                b.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (b.enabled && !b.active && controller.ready)
            TextButton(
              onPressed: b.busy ? null : controller.retryBackground,
              child: const Text('Retry connection protection'),
            ),
          if (!b.initialized && b.error != null)
            TextButton(
              onPressed: b.initialize,
              child: const Text('Retry background setup'),
            ),
          if (!b.isDemo) ...[
            TextButton(
              onPressed: b.busy ? null : () => b.openSettings('notifications'),
              child: const Text('Connection notification settings'),
            ),
            Text(
              b.batteryExempt
                  ? 'Android battery-optimization exemption is enabled.'
                  : 'Android battery optimization or phone-specific restrictions may interrupt screen-off delivery.',
            ),
            TextButton(
              onPressed: b.busy ? null : () => b.openSettings('battery'),
              child: const Text('Open battery settings'),
            ),
          ],
          const Text(
            'The ongoing notification has a Stop action. Queued messages send only while unlocked and in the foreground. Reconnection stays manual.',
          ),
          const SizedBox(height: 28),
        ],
      );
    },
  );
}
