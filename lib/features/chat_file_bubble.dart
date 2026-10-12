import 'package:flutter/material.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';
import '../services/chat_files.dart';

class ChatFileBubble extends StatefulWidget {
  const ChatFileBubble({
    super.key,
    required this.controller,
    required this.message,
  });
  final ChatController controller;
  final ChatMessage message;
  @override
  State<ChatFileBubble> createState() => _ChatFileBubbleState();
}

class _ChatFileBubbleState extends State<ChatFileBubble> {
  bool _busy = false;
  Future<void> _act({required bool retry}) async {
    final c = widget.controller,
        peer = widget.message.peerId,
        access = widget.controller.accessRevision;
    if (_busy || !c.appAccessible || !c.appForeground) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(retry ? 'Send file again?' : 'Save file to phone?'),
        content: Text(
          retry
              ? 'The other phone may already have this file. Sending again keeps its original message ID.'
              : 'Choose where to save ${widget.message.file!.name}. The saved copy is outside LocalChat and will not be protected by its app lock or chat encryption.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(retry ? 'Send again' : 'Save file'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !c.appAccessible ||
        !c.appForeground ||
        c.accessRevision != access ||
        c.selectedPeer != peer) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (retry) {
        final bytes = await c.store.fileBytes(widget.message);
        if (!mounted ||
            !c.canSendFile ||
            c.accessRevision != access ||
            c.selectedPeer != peer) {
          return;
        }
        await c.sendFile(
          SelectedFile(widget.message.file!.name, bytes),
          retry: widget.message,
        );
      } else {
        final saved = await c.saveFileToPhone(widget.message);
        if (mounted && saved && c.appAccessible && c.appForeground) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('File saved.')));
        }
      }
    } catch (_) {
      if (mounted && c.appAccessible && c.appForeground) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File is unavailable. Try reopening the chat.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, file = widget.message.file!;
    if (!c.appAccessible || !c.appForeground) {
      return const Icon(Icons.lock_outline);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.insert_drive_file_outlined),
        Text(file.name, maxLines: 3, overflow: TextOverflow.ellipsis),
        Text('${(file.length / 1024).ceil()} KiB'),
        Wrap(
          children: [
            TextButton.icon(
              onPressed: _busy ? null : () => _act(retry: false),
              icon: const Icon(Icons.save_alt),
              label: const Text('Save to phone'),
            ),
            if (widget.message.outgoing &&
                widget.message.status == 'unconfirmed')
              TextButton(
                onPressed: !_busy && c.canSendFile
                    ? () => _act(retry: true)
                    : null,
                child: const Text('Send file again'),
              ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
