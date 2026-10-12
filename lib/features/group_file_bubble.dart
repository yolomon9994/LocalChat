import 'package:flutter/material.dart';
import '../core/group_models.dart';
import '../services/chat_controller.dart';

class GroupFileBubble extends StatefulWidget {
  const GroupFileBubble({
    super.key,
    required this.controller,
    required this.groupId,
    required this.message,
  });
  final ChatController controller;
  final String groupId;
  final GroupText message;
  @override
  State<GroupFileBubble> createState() => _GroupFileBubbleState();
}

class _GroupFileBubbleState extends State<GroupFileBubble> {
  bool _busy = false;
  Future<void> _save() async {
    final c = widget.controller, access = widget.controller.accessRevision;
    if (_busy || !c.appAccessible || !c.appForeground) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Save file to phone?'),
        content: Text(
          'Choose where to save ${widget.message.file!.name}. The saved copy is outside LocalChat and will not be protected by its app lock or chat encryption.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save file'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !c.appAccessible ||
        !c.appForeground ||
        access != c.accessRevision) {
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await c.groups.files.saveToPhone(
        widget.groupId,
        widget.message,
      );
      if (mounted && saved && c.appAccessible && c.appForeground) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File saved.')));
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
        TextButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_alt),
          label: const Text('Save to phone'),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
