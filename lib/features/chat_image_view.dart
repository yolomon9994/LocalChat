import 'action_feedback.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';

class ChatImageBubble extends StatefulWidget {
  const ChatImageBubble({
    super.key,
    required this.controller,
    required this.message,
  });
  final ChatController controller;
  final ChatMessage message;
  @override
  State<ChatImageBubble> createState() => _ChatImageBubbleState();
}

class _ChatImageBubbleState extends State<ChatImageBubble> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_accessChanged);
    unawaited(_load());
  }

  void _accessChanged() {
    if (!mounted) return;
    final c = widget.controller;
    if (!c.appAccessible || !c.appForeground) {
      if (_bytes != null) {
        unawaited(MemoryImage(_bytes!).evict());
        setState(() => _bytes = null);
      }
    } else if (_bytes == null && !_loading && !_failed) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final c = widget.controller, access = widget.controller.accessRevision;
    if (!c.appAccessible || !c.appForeground || _loading) return;
    _loading = true;
    try {
      final bytes = await c.store.imageBytes(widget.message);
      if (mounted &&
          c.appAccessible &&
          c.appForeground &&
          access == c.accessRevision) {
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _loading = false;
      if (mounted) _accessChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_accessChanged);
    if (_bytes != null) unawaited(MemoryImage(_bytes!).evict());
    _bytes = null;
    super.dispose();
  }

  Future<void> _retry() async {
    final c = widget.controller,
        peer = widget.message.peerId,
        access = c.accessRevision;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send image again?'),
        content: const Text(
          'The other phone may already have this image. Its original message ID will be reused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send again'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        c.canSendImage &&
        c.selectedPeer == peer &&
        access == c.accessRevision &&
        _bytes != null) {
      await withActionFeedback(
        context,
        c,
        () => c.sendImage(_bytes!, retry: widget.message),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.controller.appAccessible ||
            !widget.controller.appForeground)
          const Icon(Icons.lock_outline)
        else if (bytes != null)
          Semantics(
            label: 'Image message. Open to zoom.',
            button: true,
            child: InkWell(
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatImageViewer(
                    controller: widget.controller,
                    bytes: bytes,
                  ),
                ),
              ),
              child: Image.memory(
                bytes,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Text('Image could not be displayed.'),
              ),
            ),
          )
        else if (_failed)
          const Text('Image is unavailable.')
        else
          const SizedBox(
            height: 60,
            width: 60,
            child: Center(child: CircularProgressIndicator()),
          ),
        if (widget.message.outgoing && widget.message.status == 'unconfirmed')
          TextButton(
            onPressed: bytes != null && widget.controller.canSendImage
                ? _retry
                : null,
            child: const Text('Send image again'),
          ),
      ],
    );
  }
}

class ChatImageViewer extends StatefulWidget {
  const ChatImageViewer({
    super.key,
    required this.controller,
    required this.bytes,
  });
  final ChatController controller;
  final Uint8List bytes;
  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  @override
  void dispose() {
    unawaited(MemoryImage(widget.bytes).evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Image')),
      body: widget.controller.appAccessible && widget.controller.appForeground
          ? Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(
                  widget.bytes,
                  errorBuilder: (_, _, _) =>
                      const Text('Image could not be displayed.'),
                ),
              ),
            )
          : const Center(child: Icon(Icons.lock_outline)),
    ),
  );
}
