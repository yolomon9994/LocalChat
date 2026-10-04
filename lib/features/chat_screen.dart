import 'package:flutter/material.dart';
import '../services/chat_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    final text = _text.text;
    setState(() {
      _sending = true;
    });
    await widget.controller.sendText(text);
    if (!mounted) return;
    if (widget.controller.error == null) _text.clear();
    setState(() {
      _sending = false;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final current = c.selectedPeer == c.connectedPeer;
      final verifying = c.code != null && !c.ready && current;
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.selectedName.isEmpty ? 'Nearby chat' : c.selectedName),
              Text(
                c.isDemo
                    ? 'Demo • ${current ? c.state : 'Saved conversation'}'
                    : current
                    ? c.state
                    : 'Saved conversation',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
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
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: c.messages.length,
                        itemBuilder: (context, index) {
                          final m = c.messages[c.messages.length - 1 - index];
                          final time = DateTime.fromMillisecondsSinceEpoch(
                            m.timestamp,
                          ).toLocal();
                          final stamp =
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                          return Align(
                            alignment: m.outgoing
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width * .8,
                              ),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: m.outgoing
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : const Color(0xff26302e),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(m.text),
                                  const SizedBox(height: 5),
                                  Text(
                                    '$stamp${m.outgoing ? ' · ${m.status}' : ''}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
                          controller: _text,
                          enabled: c.canSend && !_sending,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 4096,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: c.canSend
                                ? 'Message…'
                                : 'Connect and verify first',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: c.canSend && !_sending ? _send : null,
                        icon: _sending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
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
