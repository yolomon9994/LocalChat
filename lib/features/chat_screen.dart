import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';
import 'outgoing_message_actions.dart';
import 'connection_help.dart';
import 'chat_image_view.dart';
import 'chat_file_bubble.dart';
import 'text_message_actions.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    this.routeObserver,
    this.focusMessage,
  });
  final ChatController controller;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  final ChatMessage? focusMessage;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with RouteAware {
  ModalRoute<dynamic>? _route;
  String? _draftPeer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_chatChanged);
    widget.controller.drafts.addListener(_draftChanged);
    _chatChanged();
  }

  void _chatChanged() {
    final peer = widget.controller.selectedPeer;
    if (peer == _draftPeer) return;
    _draftPeer = peer;
    _text.clear();
    if (peer != null) {
      _restoreDraft();
      unawaited(widget.controller.drafts.load(peer));
    }
  }

  void _restoreDraft() {
    final peer = _draftPeer;
    final text = peer == null ? '' : widget.controller.drafts.textFor(peer);
    if (_text.text != text) {
      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _draftChanged() {
    if (!mounted) return;
    _restoreDraft();
    final peer = _draftPeer;
    if (peer != null &&
        !widget.controller.drafts.isLoaded(peer) &&
        widget.controller.drafts.errorFor(peer) == null) {
      unawaited(widget.controller.drafts.load(peer));
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      widget.routeObserver?.unsubscribe(this);
      _route = route;
      if (route != null) widget.routeObserver?.subscribe(this, route);
    }
    _showWhenCurrent();
  }

  void _showWhenCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.setChatVisible(this, _route?.isCurrent ?? true);
      }
    });
  }

  @override
  void didPush() => _showWhenCurrent();
  @override
  void didPopNext() => _showWhenCurrent();
  @override
  void didPushNext() => widget.controller.setChatVisible(this, false);
  @override
  void didPop() => widget.controller.setChatVisible(this, false);
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focusScroll = ScrollController();
  late bool _showTarget = widget.focusMessage != null;
  bool _sending = false;
  Future<void> _pickImage() async {
    await widget.controller.pickImage();
    if (mounted &&
        widget.controller.appAccessible &&
        widget.controller.appForeground &&
        widget.controller.pendingImagePeer == widget.controller.selectedPeer) {
      await _reviewImage();
    }
  }

  Future<void> _reviewImage() async {
    final c = widget.controller, peer = widget.controller.selectedPeer;
    final access = c.accessRevision;
    final bytes = await c.reviewPendingImage();
    if (!mounted ||
        bytes == null ||
        !c.appAccessible ||
        access != c.accessRevision) {
      return;
    }
    try {
      final send = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Send image?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(bytes, height: 200, fit: BoxFit.contain),
              const SizedBox(height: 8),
              Text(
                '${(bytes.length / 1024).ceil()} KiB · resized to at most 1600 pixels. Source metadata removed.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: c.canSendImage
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Send image'),
            ),
          ],
        ),
      );
      if (!mounted ||
          !c.appAccessible ||
          !c.appForeground ||
          access != c.accessRevision ||
          c.selectedPeer != peer) {
        return;
      }
      if (send == true) {
        await c.sendImage(bytes);
      } else if (send == false) {
        c.discardPendingImage();
      }
    } finally {
      unawaited(MemoryImage(bytes).evict());
    }
  }

  Future<void> _pickFile() async {
    final c = widget.controller;
    await c.pickFile();
    if (mounted &&
        c.appAccessible &&
        c.appForeground &&
        c.pendingFilePeer == c.selectedPeer) {
      await _reviewFile();
    }
  }

  Future<void> _reviewFile() async {
    final c = widget.controller,
        peer = widget.controller.selectedPeer,
        access = widget.controller.accessRevision;
    final selection = await c.reviewPendingFile();
    if (!mounted ||
        selection == null ||
        !c.appAccessible ||
        !c.appForeground ||
        access != c.accessRevision) {
      return;
    }
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Send file?'),
        content: Text(
          '${selection.name}\n${(selection.bytes.length / 1024).ceil()} KiB · maximum 8 MiB. The complete file will be shared, including any metadata it contains.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: c.canSendFile
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('Send file'),
          ),
        ],
      ),
    );
    if (!mounted ||
        !c.appAccessible ||
        !c.appForeground ||
        access != c.accessRevision ||
        c.selectedPeer != peer) {
      return;
    }
    if (send == true) {
      await c.sendFile(selection);
    } else if (send == false) {
      c.discardPendingFile();
    }
  }

  Future<void> _send() async {
    if (_sending || !widget.controller.canSubmit || _text.text.trim().isEmpty) {
      return;
    }
    final text = _text.text;
    setState(() {
      _sending = true;
    });
    await widget.controller.sendText(text, queueIfOffline: true);
    if (!mounted) return;
    setState(() {
      _sending = false;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_chatChanged);
    widget.controller.drafts.removeListener(_draftChanged);
    widget.routeObserver?.unsubscribe(this);
    widget.controller.setChatVisible(this, false);
    _text.dispose();
    _scroll.dispose();
    _focusScroll.dispose();
    super.dispose();
  }

  bool _isTarget(ChatMessage message) {
    final target = widget.focusMessage;
    return _showTarget &&
        target != null &&
        target.peerId == message.peerId &&
        target.id == message.id &&
        target.outgoing == message.outgoing;
  }

  Widget _messageBubble(ChatMessage message) {
    final colors = Theme.of(context).colorScheme;
    final highlighted = _isTarget(message);
    final foreground = message.outgoing
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final time = DateTime.fromMillisecondsSinceEpoch(
      message.timestamp,
    ).toLocal();
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    Widget bubble(EditableTextContextMenuBuilder? menu) => Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .8,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: message.outgoing
            ? colors.primaryContainer
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: highlighted
            ? Border.all(color: colors.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Search result',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: foreground),
              ),
            ),
          if (message.file != null)
            ChatFileBubble(controller: widget.controller, message: message)
          else if (message.image != null)
            ChatImageBubble(controller: widget.controller, message: message)
          else
            SelectableText(
              message.text,
              style: TextStyle(color: foreground),
              contextMenuBuilder: menu,
            ),
          const SizedBox(height: 5),
          Text(
            '$stamp${message.outgoing ? ' · ${message.status}' : ''}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: foreground),
          ),
          if (message.image == null &&
              message.file == null &&
              message.outgoing &&
              (message.status == 'queued' || message.status == 'unconfirmed'))
            OutgoingMessageActions(
              controller: widget.controller,
              message: message,
            ),
        ],
      ),
    );
    return Align(
      key: ValueKey((message.peerId, message.id, message.outgoing)),
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: message.image != null || message.file != null
          ? bubble(null)
          : TextMessageActions(
              controller: widget.controller,
              messageKey: (message.peerId, message.id, message.outgoing),
              text: message.text,
              isCurrent: () =>
                  widget.controller.selectedPeer == message.peerId &&
                  widget.controller.messages.any(
                    (m) =>
                        m.peerId == message.peerId &&
                        m.id == message.id &&
                        m.outgoing == message.outgoing &&
                        m.image == null &&
                        m.file == null &&
                        m.text == message.text,
                  ),
              builder: bubble,
            ),
    );
  }

  Widget _messageList(ChatController chat) {
    final pivot = _showTarget ? chat.messages.indexWhere(_isTarget) : -1;
    if (pivot < 0) {
      return ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.all(16),
        itemCount: chat.messages.length,
        itemBuilder: (_, index) =>
            _messageBubble(chat.messages[chat.messages.length - 1 - index]),
      );
    }
    // Anchor the matched message directly. Both sides remain lazy and reachable,
    // regardless of history length, bubble heights or text scale.
    return CustomScrollView(
      key: const ValueKey('search-message-history'),
      controller: _focusScroll,
      anchor: .25,
      center: const ValueKey('search-anchor'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) => _messageBubble(chat.messages[pivot - 1 - index]),
              childCount: pivot,
            ),
          ),
        ),
        SliverPadding(
          key: const ValueKey('search-anchor'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) => _messageBubble(chat.messages[pivot + index]),
              childCount: chat.messages.length - pivot,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final current = c.selectedPeer == c.connectedPeer;
      final verifying = c.code != null && !c.ready && current;
      final draftReady = _draftPeer != null && c.drafts.isLoaded(_draftPeer!);
      final draftError = _draftPeer == null
          ? null
          : c.drafts.errorFor(_draftPeer!);
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.selectedName.isEmpty ? 'Nearby chat' : c.selectedName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                c.isDemo
                    ? 'Demo • ${current ? c.state : 'Saved conversation'}'
                    : current
                    ? c.state
                    : c.queuedCount > 0
                    ? 'Saved conversation • ${c.queuedCount} queued'
                    : 'Saved conversation',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (!verifying && (c.canSend || c.pickingFile))
              IconButton(
                tooltip: c.remoteSupportsFiles
                    ? 'Attach file'
                    : 'Files require both phones to use the updated app',
                onPressed: c.canSendFile ? _pickFile : null,
                icon: c.pickingFile
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file),
              ),
            if (c.queuedCount > 0)
              IconButton(
                tooltip: 'Why messages are queued',
                icon: const Icon(Icons.schedule_send),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    scrollable: true,
                    title: Text('${c.queuedCount} queued'),
                    content: Text(c.queueWaitingReason),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_showTarget && !verifying)
              IconButton(
                tooltip: 'Jump to latest',
                icon: const Icon(Icons.arrow_downward),
                onPressed: () => setState(() => _showTarget = false),
              ),
            if (c.connectedPeer != null || c.state == 'Connecting')
              IconButton(
                tooltip: 'Disconnect',
                onPressed: c.disconnect,
                icon: const Icon(Icons.link_off),
              ),
          ],
        ),
        body: Column(
          children: [
            if (c.error != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .2,
                ),
                child: SingleChildScrollView(
                  child: c.hasConnectionHelp
                      ? ConnectionHelp(controller: c)
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            c.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                ),
              ),
            if (_showTarget && !verifying && !c.messages.any(_isTarget))
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('The matching message is no longer in this chat.'),
              ),
            if (verifying)
              Expanded(
                child: SingleChildScrollView(
                  child: Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          const Icon(Icons.verified_user_outlined, size: 36),
                          const SizedBox(height: 10),
                          Text(
                            'Verify this connection',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            c.isDemo
                                ? 'Demo verification: tap Codes match to continue. The other phone and its confirmation are simulated.'
                                : 'Compare this code with the other phone in person. Only confirm if every group matches.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            c.code!.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 19,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: c.localVerified ? null : c.confirmCode,
                            child: Text(
                              c.localVerified
                                  ? 'Waiting for the other phone'
                                  : 'Codes match',
                            ),
                          ),
                          TextButton(
                            onPressed: c.disconnect,
                            child: const Text('Codes differ — disconnect'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (c.ready && current)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  c.isDemo
                      ? 'Demo chat • simulated peer and delivery acknowledgements'
                      : 'Verified connection • messages are encrypted',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            if (!verifying)
              Expanded(
                child: c.messages.isEmpty
                    ? Center(
                        child: Text(
                          c.canSend
                              ? 'Say hello.'
                              : 'Connect and verify to start chatting.',
                        ),
                      )
                    : _messageList(c),
              ),
            if (!verifying)
              if (draftError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          draftError,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => c.drafts.retry(_draftPeer!),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
            if (!verifying)
              if (c.outboxPaused)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Queued sending is paused.')),
                      TextButton(
                        onPressed: c.resumeOutbox,
                        child: const Text('Resume outbox'),
                      ),
                    ],
                  ),
                ),
            if (!verifying)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .2,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final transfer in c.images.progress.where(
                        (p) => p.peer == c.selectedPeer,
                      ))
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${transfer.outgoing ? 'Sending' : 'Receiving'} image · ${(transfer.fraction * 100).round()}%',
                                    ),
                                    LinearProgressIndicator(
                                      value: transfer.fraction,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cancel image transfer',
                                onPressed: c.cancelImageTransfers,
                                icon: const Icon(Icons.cancel_outlined),
                              ),
                            ],
                          ),
                        ),
                      if (c.images.notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Text(
                            c.images.notice!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (c.pendingImagePeer == c.selectedPeer &&
                          c.pendingImagePeer != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: _reviewImage,
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('Review image'),
                              ),
                              TextButton(
                                onPressed: c.discardPendingImage,
                                child: const Text('Discard'),
                              ),
                            ],
                          ),
                        ),
                      for (final transfer in c.files.progress.where(
                        (p) => p.peer == c.selectedPeer,
                      ))
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${transfer.outgoing ? 'Sending' : 'Receiving'} file · ${(transfer.fraction * 100).round()}%',
                                    ),
                                    LinearProgressIndicator(
                                      value: transfer.fraction,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cancel file transfer',
                                onPressed: c.cancelFileTransfers,
                                icon: const Icon(Icons.cancel_outlined),
                              ),
                            ],
                          ),
                        ),
                      if (c.files.notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Text(
                            c.files.notice!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (c.pendingFilePeer == c.selectedPeer &&
                          c.pendingFilePeer != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: _reviewFile,
                                icon: const Icon(
                                  Icons.insert_drive_file_outlined,
                                ),
                                label: const Text('Review file'),
                              ),
                              TextButton(
                                onPressed: c.discardPendingFile,
                                child: const Text('Discard'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (!verifying)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (c.canSend || c.pickingImage)
                        IconButton(
                          tooltip: c.remoteSupportsImages
                              ? 'Attach image'
                              : 'Images require both phones to use the updated app',
                          onPressed: c.canSendImage ? _pickImage : null,
                          icon: c.pickingImage
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_photo_alternate_outlined),
                        ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('message-composer'),
                          controller: _text,
                          enabled: draftReady && !_sending,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 4096,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: c.canSend
                                ? 'Message…'
                                : 'Message to queue…',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                          onChanged: (text) =>
                              c.drafts.setText(_draftPeer!, text),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: c.canSend ? 'Send' : 'Queue message',
                        onPressed: c.canSubmit && draftReady && !_sending
                            ? _send
                            : null,
                        icon: _sending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                c.canSend ? Icons.send : Icons.schedule_send,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
