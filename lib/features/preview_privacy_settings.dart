import 'package:flutter/material.dart';
import '../services/chat_controller.dart';

class PreviewPrivacySettings extends StatelessWidget {
  const PreviewPrivacySettings({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.previewPrivacy,
    builder: (context, _) {
      final p = controller.previewPrivacy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview privacy',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SwitchListTile(
            key: const ValueKey('hide-chat-previews'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Hide chat-list previews'),
            subtitle: Text(
              controller.isDemo
                  ? 'Temporary in this demo tab. Hide message text in saved chat lists.'
                  : 'Hide message text in Chats and Archived chats. Names, counts and times stay visible.',
            ),
            value: p.hidden,
            onChanged:
                p.loading ||
                    p.saving ||
                    !controller.appAccessible ||
                    !controller.appForeground
                ? null
                : p.setHidden,
          ),
          if (p.saving) const LinearProgressIndicator(),
          if (p.error != null)
            Text(
              p.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const Text(
            'Group rows show counts and status only. Draft text stays inside its chat. '
            'Search results and opened chats still show their content.',
          ),
          const SizedBox(height: 28),
        ],
      );
    },
  );
}
