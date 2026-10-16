import 'action_feedback.dart';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';

class OutgoingMessageActions extends StatefulWidget {
  const OutgoingMessageActions({
    super.key,
    required this.controller,
    required this.message,
  });
  final ChatController controller;
  final ChatMessage message;
  @override
  State<OutgoingMessageActions> createState() => _OutgoingMessageActionsState();
}

class _OutgoingMessageActionsState extends State<OutgoingMessageActions> {
  bool _busy = false;
  Future<void> _act() async {
    if (_busy) return;
    final message = widget.message, c = widget.controller;
    final retry = message.status == 'unconfirmed';
    final sendNow = c.canSend;
    setState(() => _busy = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(retry ? 'Retry message?' : 'Cancel queued message?'),
        content: Text(
          retry
              ? '${sendNow ? 'Retry after this verified connection is ready.' : 'Queue a retry for when you reconnect and verify both phones.'} '
                    'The other phone may already have this message. The same message ID avoids a duplicate '
                    'while that phone still has its saved copy.'
              : 'Remove this unsent message from your local outbox?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep message'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              retry
                  ? (sendNow ? 'Retry now' : 'Queue retry')
                  : 'Cancel queued message',
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (retry) {
        await withActionFeedback(context, c, () => c.retryMessage(message));
      } else {
        await c.cancelQueuedMessage(message);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: ValueKey(
      'outgoing-action-${widget.message.peerId}-${widget.message.id}',
    ),
    onPressed: _busy || !widget.controller.canSubmit ? null : _act,
    icon: Icon(
      widget.message.status == 'queued' ? Icons.close : Icons.refresh,
      size: 16,
    ),
    label: Text(widget.message.status == 'queued' ? 'Cancel queued' : 'Retry'),
  );
}
