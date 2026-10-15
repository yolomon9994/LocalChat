import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../services/chat_controller.dart';

/// Shared message actions, including text selection and saved-history anchors.
class TextMessageActions extends StatefulWidget {
  const TextMessageActions({
    super.key,
    required this.controller,
    required this.messageKey,
    required this.text,
    required this.isCurrent,
    required this.builder,
    this.onReply,
    this.onStar,
    this.starred = false,
    this.allowCopy = true,
  });

  final ChatController controller;
  final Object messageKey;
  final String text;
  final bool Function() isCurrent;
  final Widget Function(EditableTextContextMenuBuilder menu) builder;
  final VoidCallback? onReply, onStar;
  final bool starred, allowCopy;

  @override
  State<TextMessageActions> createState() => _TextMessageActionsState();
}

class _TextMessageActionsState extends State<TextMessageActions> {
  ModalRoute<dynamic>? _menuRoute;
  EditableTextState? _selection;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _notice;
  int _revision = 0;
  bool _copying = false;
  bool _showingMenu = false;
  ScaffoldMessengerState? _messenger;

  bool get _allowed =>
      mounted &&
      widget.controller.initialized &&
      widget.controller.appAccessible &&
      widget.controller.appForeground &&
      widget.isCurrent() &&
      (ModalRoute.of(context)?.isCurrent != false ||
          _menuRoute?.isCurrent == true);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(TextMessageActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (oldWidget.messageKey != widget.messageKey ||
        oldWidget.text != widget.text ||
        oldWidget.controller != widget.controller) {
      _invalidate();
    }
  }

  void _changed() {
    if (!_allowed) _invalidate();
  }

  void _invalidate() {
    _revision++;
    // Locking removes the Navigator during build. Close surviving overlays at
    // the frame boundary; captured callbacks are invalid immediately.
    final route = _menuRoute;
    final selection = _selection;
    final notice = _notice;
    final messenger = _messenger;
    _menuRoute = null;
    _selection = null;
    _notice = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
      if (selection?.mounted == true) selection!.hideToolbar();
      if (messenger?.mounted == true) notice?.close();
    });
  }

  bool _valid(int revision, int access) =>
      _allowed &&
      revision == _revision &&
      access == widget.controller.accessRevision;

  void _star(int revision, int access) {
    if (!_valid(revision, access)) return;
    final action = widget.onStar;
    _selection?.hideToolbar();
    if (_menuRoute?.isCurrent == true) _menuRoute!.navigator?.pop();
    action?.call();
  }

  void _reply(int revision, int access) {
    if (!_valid(revision, access)) return;
    final action = widget.onReply;
    _selection?.hideToolbar();
    if (_menuRoute?.isCurrent == true) _menuRoute!.navigator?.pop();
    action?.call();
  }

  Future<void> _copy(String text, int revision, int access) async {
    if (_copying || text.isEmpty || !_valid(revision, access)) return;
    _copying = true;
    var success = false;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      success = true;
    } catch (_) {
      // Browser permission failures and platform details never expose message text.
    } finally {
      _copying = false;
    }
    if (!mounted || !_valid(revision, access)) return;
    _selection?.hideToolbar();
    final route = _menuRoute;
    if (route?.isCurrent == true) route!.navigator?.pop();
    _notice?.close();
    _messenger = ScaffoldMessenger.of(context);
    _notice = _messenger!.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Message copied.' : 'Could not copy. Try again.',
        ),
      ),
    );
  }

  Future<void> _showMenu() async {
    if (!_allowed || _showingMenu) return;
    _showingMenu = true;
    final revision = _revision, access = widget.controller.accessRevision;
    final text = widget.text;
    await showDialog<void>(
      context: context,
      builder: (context) {
        _menuRoute = ModalRoute.of(context);
        if (!_valid(revision, access)) {
          _invalidate();
          return const SizedBox.shrink();
        }
        return SimpleDialog(
          title: const Text('Message actions'),
          children: [
            if (widget.onReply != null)
              SimpleDialogOption(
                onPressed: () => _reply(revision, access),
                child: const Row(
                  children: [
                    Icon(Icons.reply),
                    SizedBox(width: 12),
                    Text('Reply'),
                  ],
                ),
              ),
            if (widget.onStar != null)
              SimpleDialogOption(
                onPressed: () => _star(revision, access),
                child: Row(
                  children: [
                    Icon(widget.starred ? Icons.star : Icons.star_border),
                    const SizedBox(width: 12),
                    Text(widget.starred ? 'Unstar' : 'Star'),
                  ],
                ),
              ),
            if (widget.allowCopy)
              SimpleDialogOption(
                onPressed: () => unawaited(_copy(text, revision, access)),
                child: const Row(
                  children: [
                    Icon(Icons.copy_outlined),
                    SizedBox(width: 12),
                    Text('Copy'),
                  ],
                ),
              ),
          ],
        );
      },
    );
    _menuRoute = null;
    _showingMenu = false;
  }

  Widget _selectionMenu(BuildContext context, EditableTextState editable) {
    if (!_allowed) return const SizedBox.shrink();
    _selection = editable;
    final revision = _revision, access = widget.controller.accessRevision;
    final text = widget.text;
    final selection = editable.textEditingValue.selection;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: [
        if (widget.onReply != null)
          ContextMenuButtonItem(
            label: 'Reply',
            onPressed: () => _reply(revision, access),
          ),
        if (widget.onStar != null)
          ContextMenuButtonItem(
            label: widget.starred ? 'Unstar' : 'Star',
            onPressed: () => _star(revision, access),
          ),
        if (widget.allowCopy)
          ContextMenuButtonItem(
            label: 'Copy message',
            onPressed: () => unawaited(_copy(text, revision, access)),
          ),
        if (selection.isValid && !selection.isCollapsed)
          ContextMenuButtonItem(
            label: 'Copy selection',
            onPressed: () =>
                unawaited(_copy(selection.textInside(text), revision, access)),
          ),
        for (final item in editable.contextMenuButtonItems)
          if (item.type == ContextMenuButtonType.selectAll)
            ContextMenuButtonItem(
              type: item.type,
              onPressed: () {
                if (_valid(revision, access)) item.onPressed?.call();
              },
            ),
      ],
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _invalidate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final revision = _revision, access = widget.controller.accessRevision;
    return Semantics(
      customSemanticsActions: {
        if (widget.onReply != null)
          const CustomSemanticsAction(label: 'Reply to message'): () =>
              _reply(revision, access),
        if (widget.onStar != null)
          CustomSemanticsAction(
            label: widget.starred ? 'Unstar message' : 'Star message',
          ): () =>
              _star(revision, access),
        if (widget.allowCopy)
          const CustomSemanticsAction(label: 'Copy message'): () =>
              unawaited(_copy(text, revision, access)),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _showMenu,
        onSecondaryTap: _showMenu,
        child: widget.builder(_selectionMenu),
      ),
    );
  }
}
