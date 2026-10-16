import 'dart:async';
import 'package:flutter/material.dart';
import '../services/chat_controller.dart';
import 'action_feedback.dart';

class FeedbackSettings extends StatelessWidget {
  const FeedbackSettings({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.feedback]),
    builder: (context, _) {
      final f = controller.feedback;
      final disabled =
          f.loading ||
          f.saving ||
          !controller.appAccessible ||
          !controller.appForeground;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Action feedback',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SwitchListTile(
            key: const ValueKey('vibration-feedback'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibration feedback'),
            subtitle: Text(
              controller.isDemo || f.isDemo
                  ? 'Demo preference only. This preview does not vibrate and resets on reload.'
                  : 'Short feedback after sending a message or confirming a connection. Android touch feedback settings still apply.',
            ),
            value: f.enabled,
            onChanged: disabled ? null : f.setEnabled,
          ),
          TextButton.icon(
            key: const ValueKey('try-vibration'),
            onPressed:
                !disabled && !controller.isDemo && f.enabled && f.supported
                ? () => unawaited(
                    withActionFeedback(context, controller, () async => true),
                  )
                : null,
            icon: const Icon(Icons.vibration),
            label: const Text('Try vibration'),
          ),
          if (!f.supported && !f.isDemo)
            const Text('Action vibration is available on Android.'),
          const Text(
            'Feedback confirms a local action, not delivery or peer verification.',
          ),
          if (f.saving) const LinearProgressIndicator(),
          if (f.error != null)
            Text(
              f.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 28),
        ],
      );
    },
  );
}
