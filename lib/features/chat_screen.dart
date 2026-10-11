import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';
import 'outgoing_message_actions.dart';

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
    return Align(
      key: ValueKey((message.peerId, message.id, message.outgoing)),
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
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
            SelectableText(message.text, style: TextStyle(color: foreground)),
            const SizedBox(height: 5),
            Text(
              '$stamp${message.outgoing ? ' · ${message.status}' : ''}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: foreground),
            ),
            if (message.outgoing &&
                (message.status == 'queued' || message.status == 'unconfirmed'))
              OutgoingMessageActions(
                controller: widget.controller,
                message: message,
              ),
          ],
        ),
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
                  child: Padding(
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
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
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
