import 'package:flutter/material.dart';
import '../core/contact_nickname.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';

class ContactNicknameDialog extends StatefulWidget {
  const ContactNicknameDialog({
    super.key,
    required this.controller,
    required this.peer,
  });
  final ChatController controller;
  final Conversation peer;
  @override
  State<ContactNicknameDialog> createState() => _ContactNicknameDialogState();
}

class _ContactNicknameDialogState extends State<ContactNicknameDialog> {
  late final _text = TextEditingController(text: widget.peer.nickname ?? '');
  late final int _revision;
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  bool get _allowed =>
      mounted &&
      widget.controller.appAccessible &&
      widget.controller.appForeground &&
      widget.controller.interactionRevision == _revision;

  @override
  void initState() {
    super.initState();
    // Capture the privacy epoch before any async work.
    _revision = widget.controller.interactionRevision;
    widget.controller.addListener(_privacyChanged);
  }

  void _privacyChanged() {
    if (!_allowed) {
      _text.clear();
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
  }

  Future<void> _save({bool remove = false}) async {
    if (_busy || !_allowed || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    if (!remove && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final success = await widget.controller.setNickname(
      widget.peer.id,
      remove ? null : _text.text,
      isCurrent: () => _allowed && (ModalRoute.of(context)?.isCurrent ?? false),
    );
    if (!mounted || !_allowed) return;
    if (success) {
      final route = ModalRoute.of(context)!;
      if (route.isCurrent) {
        Navigator.pop(context);
      } else {
        Navigator.of(context).removeRoute(route);
      }
    } else {
      setState(() {
        _busy = false;
        _error = 'Could not save the nickname. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_privacyChanged);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.peer.nickname == null ? 'Set nickname' : 'Edit nickname',
    ),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Phone name: ${widget.peer.originalName}'),
          const SizedBox(height: 12),
          Text(
            widget.controller.isDemo
                ? 'Private in this demo tab. Resets on reload.'
                : 'Private on this phone. Included in your encrypted chat backups.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('contact-nickname'),
            controller: _text,
            enabled: !_busy,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nickname',
              helperText: 'Leave blank to use the phone name',
              helperMaxLines: 3,
            ),
            validator: (value) {
              try {
                normalizeContactNickname(value);
                return null;
              } on FormatException catch (e) {
                return e.message;
              }
            },
            onFieldSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (widget.peer.nickname != null)
        TextButton(
          onPressed: _busy ? null : () => _save(remove: true),
          child: const Text('Remove nickname'),
        ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
    ],
  );
}
