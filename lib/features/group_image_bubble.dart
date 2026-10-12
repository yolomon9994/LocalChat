import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/group_models.dart';
import '../services/chat_controller.dart';
import 'chat_image_view.dart';

class GroupImageBubble extends StatefulWidget {
  const GroupImageBubble({
    super.key,
    required this.controller,
    required this.message,
  });
  final ChatController controller;
  final GroupText message;
  @override
  State<GroupImageBubble> createState() => _GroupImageBubbleState();
}

class _GroupImageBubbleState extends State<GroupImageBubble> {
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  void _sync() {
    final c = widget.controller;
    final next = c.appAccessible && c.appForeground
        ? widget.message.imageBytes
        : null;
    if (identical(next, _bytes)) return;
    if (_bytes != null) unawaited(MemoryImage(_bytes!).evict());
    if (mounted) setState(() => _bytes = next);
  }

  @override
  void didUpdateWidget(GroupImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    if (_bytes != null) unawaited(MemoryImage(_bytes!).evict());
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const Icon(Icons.lock_outline);
    return Semantics(
      label: 'Group image. Open to zoom.',
      button: true,
      child: InkWell(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatImageViewer(controller: widget.controller, bytes: bytes),
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
    );
  }
}
