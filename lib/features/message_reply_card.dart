import 'package:flutter/material.dart';

import '../core/message_reply.dart';

class MessageReplyCard extends StatelessWidget {
  const MessageReplyCard({
    super.key,
    required this.reply,
    required this.name,
    this.onTap,
    this.onCancel,
    this.notice,
  });
  final MessageReply reply;
  final String name;
  final VoidCallback? onTap, onCancel;
  final String? notice;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.reply, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Reply to $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    reply.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notice != null)
                    Text(notice!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (onCancel != null)
              IconButton(
                tooltip: 'Cancel reply',
                onPressed: onCancel,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    ),
  );
}
