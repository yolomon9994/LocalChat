import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/group_search.dart';
import '../services/chat_controller.dart';
import '../services/chat_search_controller.dart';
import 'chat_screen.dart';
import 'chats_tab.dart';
import 'group_screen.dart';

class HighlightedSearchText extends StatelessWidget {
  const HighlightedSearchText(
    this.text,
    this.query, {
    super.key,
    this.maxLines,
    this.selectable = false,
  });
  final String text, query;
  final int? maxLines;
  final bool selectable;
  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var end = 0;
    if (query.trim().isNotEmpty) {
      for (final match in RegExp(
        RegExp.escape(query.trim()),
        caseSensitive: false,
        unicode: true,
      ).allMatches(text)) {
        spans.add(TextSpan(text: text.substring(end, match.start)));
        spans.add(
          TextSpan(
            text: match.group(0),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        );
        end = match.end;
      }
    }
    spans.add(TextSpan(text: text.substring(end)));
    if (selectable) return SelectableText.rich(TextSpan(children: spans));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}

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
    this.groupId,
  });
  final ChatController controller;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  final String? groupId;
  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  late final _search = ChatSearchController(
    widget.controller,
    groupId: widget.groupId,
  );
  final _text = TextEditingController();
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_privacyChanged);
  }

  void _privacyChanged() {
    if (!widget.controller.appAccessible) _text.clear();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_privacyChanged);
    _search.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _open(Conversation peer, {ChatMessage? target}) async {
    final c = widget.controller;
    if (!mounted || _opening || !c.appAccessible || !c.appForeground) return;
    final access = c.accessRevision;
    setState(() => _opening = true);
    FocusScope.of(context).unfocus();
    final opened = await widget.controller.viewHistory(peer);
    if (!mounted ||
        !c.appAccessible ||
        !c.appForeground ||
        access != c.accessRevision) {
      if (mounted) setState(() => _opening = false);
      return;
    }
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

  Future<void> _openGroup(
    GroupSearchGroup group, {
    GroupSearchHit? target,
  }) async {
    final c = widget.controller;
    if (!mounted || _opening || !c.appAccessible || !c.appForeground) return;
    if (!c.groups.histories.any((h) => h.id == group.id)) {
      _search.retry();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This group is no longer saved.')),
      );
      return;
    }
    setState(() => _opening = true);
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          controller: c,
          id: group.id,
          routeObserver: widget.routeObserver,
          focusMessageKey: target?.key,
          searchQuery: _search.query,
        ),
      ),
    );
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
      return _notice(
        widget.groupId == null
            ? 'Search your saved chats by name or message text.'
            : 'Search saved messages in this group.',
      );
    }
    if (search.loading) return _notice('Searching…');
    if (search.error != null) {
      return _notice(
        search.error!,
        action: TextButton(onPressed: search.retry, child: const Text('Retry')),
      );
    }
    final found = search.results;
    final groups = search.groupResults;
    if (found.conversations.isEmpty &&
        found.messages.isEmpty &&
        groups.groups.isEmpty &&
        groups.messages.isEmpty) {
      return _notice('No results for “${search.query}”.');
    }
    final tiles = <Widget>[
      if (groups.groups.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.all(12), child: Text('Groups')),
        for (final group in groups.groups)
          ListTile(
            key: ValueKey('search-group-${group.id}'),
            leading: const Icon(Icons.groups_outlined),
            title: HighlightedSearchText(
              group.title,
              search.query,
              maxLines: 2,
            ),
            subtitle: group.archived ? const Text('Archived group') : null,
            onTap: _opening ? null : () => _openGroup(group),
          ),
      ],
      if (groups.messages.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Group messages'),
        ),
        for (final hit in groups.messages)
          ListTile(
            key: ValueKey(('search-group-message', hit.group.id, hit.key)),
            leading: const Icon(Icons.groups_outlined),
            title: Text(
              hit.group.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hit.group.archived) const Text('Archived group'),
                Text(
                  hit.author == widget.controller.groups.selfId
                      ? 'You'
                      : hit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                HighlightedSearchText(
                  searchSnippet(hit.text, search.query),
                  search.query,
                  maxLines: 3,
                ),
                Text(
                  formatConversationTime(hit.timestamp),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            onTap: _opening ? null : () => _openGroup(hit.group, target: hit),
          ),
        if (groups.hasMoreMessages)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Showing the newest 100 matching group messages. Refine your search to find more.',
            ),
          ),
      ],
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
      appBar: AppBar(
        title: Text(widget.groupId == null ? 'Search chats' : 'Search group'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const ValueKey('chat-search-field'),
              controller: _text,
              autofocus: true,
              enabled:
                  widget.controller.appAccessible &&
                  widget.controller.appForeground,
              maxLength: 256,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: widget.groupId == null
                    ? 'Search names or messages'
                    : 'Search group messages',
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
          Expanded(
            child:
                widget.controller.appAccessible &&
                    widget.controller.appForeground
                ? _results(_search)
                : _notice('Return to the unlocked app to search.'),
          ),
        ],
      ),
    ),
  );
}
