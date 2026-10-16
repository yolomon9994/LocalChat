import 'package:flutter/material.dart';
import '../services/chat_notifications.dart';

class NotificationSettings extends StatelessWidget {
  const NotificationSettings({super.key, required this.notifications});
  final ChatNotifications notifications;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifications,
    builder: (context, _) {
      final n = notifications;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Message notifications'),
            subtitle: Text(
              n.isDemo
                  ? 'Demo settings only; no browser alerts.'
                  : 'Alert when a message arrives outside the chat you are reading.',
            ),
            value: n.enabled,
            onChanged: n.initialized && !n.busy ? n.setEnabled : null,
          ),
          const Text('Notification previews'),
          DropdownButton<NotificationPreview>(
            key: const ValueKey('notification-preview-mode'),
            value: n.previewMode,
            isExpanded: true,
            itemHeight: null,
            items: [
              for (final mode in NotificationPreview.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            selectedItemBuilder: (_) => [
              for (final mode in NotificationPreview.values)
                Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            onChanged: n.initialized && n.enabled && !n.busy
                ? (value) => n.setPreviewMode(value!)
                : null,
          ),
          const Text(
            'Sender or message content appears only while LocalChat is unlocked and in the foreground. '
            'Android may retain previously delivered previews in notification history.',
          ),
          if (n.enabled && !n.allowed && !n.isDemo) ...[
            const Text(
              'Android notifications are blocked. Allow LocalChat notifications and its Messages channel in Android Settings.',
            ),
            TextButton(
              onPressed: n.busy ? null : n.openSettings,
              child: const Text('Open notification settings'),
            ),
          ],
          if (n.error != null)
            Text(
              n.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const Text(
            'Notifications require an active connection. Use Background connection below to protect a verified link while away from the app.',
          ),
          if (!n.initialized && n.error != null)
            TextButton(
              onPressed: n.initialize,
              child: const Text('Retry notification setup'),
            ),
          const SizedBox(height: 28),
        ],
      );
    },
  );
}
