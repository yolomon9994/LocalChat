import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/chat_controller.dart';
import '../services/chat_search_controller.dart';
import 'chat_screen.dart';
import 'chats_tab.dart';

String searchSnippet(String text, String query) {
  final match = text.toLowerCase().indexOf(query.trim().toLowerCase());
  var start = ((match < 0 ? 0 : match) - 50).clamp(0, text.length);
  var end = ((match < 0 ? 0 : match) + query.length + 80).clamp(0, text.length);
  // Keep UTF-16 surrogate pairs intact when shortening emoji-containing text.
  if (start > 0 &&
      text.codeUnitAt(start) >= 0xdc00 &&
      text.codeUnitAt(start) <= 0xdfff) {
    start--;
  }
  if (end > 0 &&
      end < text.length &&
      text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff) {
    end++;
  }
  final excerpt = text
      .substring(start, end)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${start > 0 ? '…' : ''}$excerpt${end < text.length ? '…' : ''}';
}

class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({
    super.key,
    required this.controller,
    this.routeObserver,
  });
  final ChatController controller;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  late final _search = ChatSearchController(widget.controller);
  final _text = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _search.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _open(Conversation peer, {ChatMessage? target}) async {
    if (_opening) return;
    setState(() => _opening = true);
    FocusScope.of(context).unfocus();
    final opened = await widget.controller.viewHistory(peer);
    if (!mounted) return;
    if (opened) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            controller: widget.controller,
            routeObserver: widget.routeObserver,
            focusMessage: target,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this conversation. Please try again.'),
        ),
      );
    }
    if (mounted) setState(() => _opening = false);
  }

  Widget _notice(String text, {Widget? action}) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(text, textAlign: TextAlign.center),
      if (action != null) action,
    ],
  );

  Widget _results(ChatSearchController search) {
    if (search.query.isEmpty) {
      return _notice('Search your saved chats by name or message text.');
    }
    if (search.loading) return _notice('Searching…');
    if (search.error != null) {
      return _notice(
        search.error!,
        action: TextButton(onPressed: search.retry, child: const Text('Retry')),
      );
    }
    final found = search.results;
    if (found.conversations.isEmpty && found.messages.isEmpty) {
      return _notice('No results for “${search.query}”.');
    }
    final tiles = <Widget>[
      if (found.conversations.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Conversations'),
        ),
        for (final peer in found.conversations)
          ListTile(
            key: ValueKey('search-conversation-${peer.id}'),
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(
              peer.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            subtitle: peer.archived ? const Text('Archived chat') : null,
            onTap: _opening ? null : () => _open(peer),
          ),
      ],
      if (found.messages.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.all(12), child: Text('Messages')),
        for (final hit in found.messages)
          ListTile(
            key: ValueKey((
              'search-message',
              hit.message.peerId,
              hit.message.id,
              hit.message.outgoing,
            )),
            leading: const Icon(Icons.search),
            title: Text(
              hit.conversation.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hit.conversation.archived) const Text('Archived chat'),
                Text(
                  '${hit.message.outgoing ? 'You: ' : ''}${searchSnippet(hit.message.text, search.query)}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatConversationTime(hit.message.timestamp),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            onTap: _opening
                ? null
                : () => _open(hit.conversation, target: hit.message),
          ),
        if (found.hasMoreMessages)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Showing the newest 100 matching messages. Refine your search to find more.',
            ),
          ),
      ],
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: tiles,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _search,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Search chats')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const ValueKey('chat-search-field'),
              controller: _text,
              autofocus: true,
              maxLength: 256,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search names or messages',
                counterText: '',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _text.text.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('clear-chat-search'),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _text.clear();
                          _search.setQuery('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (value) {
                _search.setQuery(value);
                // Raw whitespace edits can leave the normalized query unchanged.
                setState(() {});
              },
              onSubmitted: (_) => _search.retry(),
            ),
          ),
          if (_search.loading || _opening) const LinearProgressIndicator(),
          Expanded(child: _results(_search)),
        ],
      ),
    ),
  );
}
