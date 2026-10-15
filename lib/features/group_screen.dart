import 'dart:async';
import 'package:flutter/material.dart';
import '../core/group_models.dart';
import '../core/starred_message.dart';
import '../services/chat_controller.dart';
import '../services/group_controller.dart';
import 'chats_tab.dart' show formatConversationTime;
import 'group_image_bubble.dart';
import 'group_file_bubble.dart';
import 'text_message_actions.dart';
import 'message_reply_card.dart';
import '../core/message_reply.dart';
import 'group_chat_tile.dart';
import 'group_menu.dart';
import 'archived_chats_screen.dart';
import 'chat_search_screen.dart';

class GroupHubScreen extends StatefulWidget {
  const GroupHubScreen({
    super.key,
    required this.controller,
    this.routeObserver,
  });
  final ChatController controller;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  @override
  State<GroupHubScreen> createState() => _GroupHubScreenState();
}

class _GroupHubScreenState extends State<GroupHubScreen> {
  final _title = TextEditingController();
  ChatController get c => widget.controller;
  GroupController get g => c.groups;
  void _open(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GroupChatScreen(
        controller: c,
        id: id,
        routeObserver: widget.routeObserver,
      ),
    ),
  );
  Future<void> _create() async {
    final token = c.accessRevision;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          c.simulatedGroups ? 'Create demo group' : 'Create nearby group',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                maxLength: 64,
                decoration: const InputDecoration(labelText: 'Group name'),
                autofocus: true,
              ),
              Text(
                c.simulatedGroups
                    ? 'Simulated members join inside this tab. Their confirmations and receipts are simulated; tap Codes match to confirm each demo member. Reloading clears demo data.'
                    : 'You host and relay messages. Verify every joining member. Keep this phone connected; leaving pauses the group.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _title.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (!mounted ||
        name == null ||
        token != c.accessRevision ||
        !c.appAccessible ||
        !c.appForeground) {
      return;
    }
    final created = await g.host(name);
    _title.clear();
    if (mounted && created && g.active != null) _open(g.active!.id);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(c.simulatedGroups ? 'Group chats (Demo)' : 'Group chats'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Nearby groups use one host. Each guest verifies the host; the host approves every member and can read and relay group messages. Other members’ identities are vouched for by the host.',
          ),
          const SizedBox(height: 12),
          Text(
            c.simulatedGroups
                ? 'Browser group demo: members, verification and receipts are simulated inside this tab. No other phones or browser tabs are connected. Reloading clears all demo history and drafts.'
                : c.isDemo
                ? 'Android phones are needed to discover or host groups. Saved demo group backups can be viewed here.'
                : 'One nearby connection mode at a time. Starting a group closes the direct chat connection. Up to 8 members including the host; phones may support fewer.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    c.canUseGroups &&
                        c.appAccessible &&
                        c.appForeground &&
                        !g.busy &&
                        !g.running
                    ? _create
                    : null,
                icon: const Icon(Icons.group_add_outlined),
                label: Text(
                  c.simulatedGroups ? 'Create demo group' : 'Create group',
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    c.canUseGroups &&
                        c.appAccessible &&
                        c.appForeground &&
                        !g.busy &&
                        !g.connected
                    ? g.discover
                    : null,
                icon: const Icon(Icons.radar),
                label: Text(
                  c.simulatedGroups ? 'Find demo groups' : 'Find groups',
                ),
              ),
              if (g.running)
                TextButton(
                  onPressed: !g.busy ? g.stop : null,
                  child: Text(g.hosting ? 'End hosting' : 'Leave / stop'),
                ),
            ],
          ),
          if (g.busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(g.state),
          if (g.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                g.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final peer in g.nearby)
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(peer['title'] as String),
                subtitle: Text('Host: ${peer['name']} • verify before joining'),
                onTap: !g.busy && !g.connected
                    ? () => g.join(peer['address'] as String)
                    : null,
              ),
            ),
          GroupVerification(controller: c),
          if (g.active != null)
            Card(
              child: ListTile(
                title: Text(g.active!.title),
                subtitle: Text(
                  g.connected
                      ? 'Active group • ${g.members.length} members'
                      : 'Waiting for verification',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(g.active!.id),
              ),
            ),
          const SizedBox(height: 24),
          Text('Saved groups', style: Theme.of(context).textTheme.titleLarge),
          if (g.histories.where((h) => !h.archived).isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                g.histories.isEmpty
                    ? 'Group history will appear here after creating or joining a verified group.'
                    : 'Your saved groups are archived. Open Archived chats to view them.',
              ),
            ),
          for (final group in g.histories.where((h) => !h.archived))
            GroupChatTile(
              key: ValueKey('saved-group-${group.id}'),
              controller: c,
              group: group,
              routeObserver: widget.routeObserver,
              showMessageCount: true,
            ),
          if (g.histories.any((h) => h.archived))
            Card(
              child: ListTile(
                key: const ValueKey('open-archived-groups'),
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archived chats'),
                subtitle: const Text(
                  'Find your archived groups and direct chats',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArchivedChatsScreen(
                      controller: c,
                      routeObserver: widget.routeObserver,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            c.simulatedGroups
                ? 'Demo connections stay inside this tab. Background controls are simulated; no Android service, real device discovery or screen-off delivery is tested here. Demo backups can only import into the browser demo.'
                : 'Keep the host connected. Enable Keep connection active in Settings to help receive and relay group text in the background. Images and files require foreground unlock. No host migration, automatic reconnect or offline group outbox. New members receive new messages only. Group history is included in encrypted backups.',
          ),
        ],
      ),
    ),
  );
}

class GroupVerification extends StatelessWidget {
  const GroupVerification({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) {
    final g = controller.groups;
    return Column(
      children: [
        for (final link in g.links.values.where((l) => !l.admitted))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${g.hosting ? 'Joining member' : 'Host'}: ${link.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (link.session.verificationCode != null) ...[
                    Text(
                      controller.simulatedGroups
                          ? 'Demo verification: the member and its confirmation are simulated. Tap Codes match to try this flow. On Android, compare the entire code on both phones in person.'
                          : 'Compare this entire code on both phones in person. Display names alone do not verify identity.',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      link.session.verificationCode!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      link.localVerified
                          ? 'Waiting for the other phone to confirm.'
                          : 'Confirm only when both codes match.',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed:
                              !link.localVerified &&
                                  controller.appAccessible &&
                                  controller.appForeground
                              ? () => g.confirm(link.id)
                              : null,
                          child: const Text('Codes match'),
                        ),
                        TextButton(
                          onPressed:
                              controller.appAccessible &&
                                  controller.appForeground
                              ? () => g.reject(link.id)
                              : null,
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  ] else
                    const Text('Exchanging keys…'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.controller,
    required this.id,
    this.routeObserver,
    this.focusMessageKey,
    this.searchQuery = '',
    this.fromStar = false,
  });
  final ChatController controller;
  final String id;
  final String? focusMessageKey;
  final String searchQuery;
  final bool fromStar;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> with RouteAware {
  final _text = TextEditingController();
  final _composerFocus = FocusNode();
  late String? _focusMessageKey = widget.focusMessageKey;
  bool _fromReply = false;
  final _routeToken = Object();
  ModalRoute<dynamic>? _route;
  bool _sending = false;
  bool _showTarget = true;
  bool _atLatest = false;
  final _scroll = ScrollController();
  final _focusScroll = ScrollController();
  GroupController get g => widget.controller.groups;
  @override
  void initState() {
    super.initState();
    g.drafts.addListener(_draftChanged);
    _restoreDraft();
    if (g.drafts.errorFor(widget.id, group: true) == null) {
      unawaited(g.drafts.load(widget.id, group: true));
    }
  }

  void _restoreDraft() {
    if (!g.drafts.isLoaded(widget.id, group: true)) return;
    final text = g.drafts.textFor(widget.id, group: true);
    if (_text.text != text) {
      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void didUpdateWidget(covariant GroupChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.groups.drafts.removeListener(_draftChanged);
      g.drafts.addListener(_draftChanged);
    }
    if (oldWidget.id != widget.id ||
        oldWidget.controller != widget.controller) {
      _focusMessageKey = widget.focusMessageKey;
      _fromReply = false;
      _showTarget = true;
      _atLatest = false;
      _text.clear();
      _restoreDraft();
      if (g.drafts.errorFor(widget.id, group: true) == null) {
        unawaited(g.drafts.load(widget.id, group: true));
      }
    }
  }

  void _draftChanged() {
    if (!mounted) return;
    _restoreDraft();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      widget.routeObserver?.unsubscribe(this);
      _route = route;
      if (route != null) widget.routeObserver?.subscribe(this, route);
    }
    g.setVisible(_routeToken, widget.id, route?.isCurrent ?? false);
  }

  @override
  void didPush() => g.setVisible(_routeToken, widget.id, true);
  @override
  void didPopNext() => g.setVisible(_routeToken, widget.id, true);
  @override
  void didPushNext() => g.setVisible(_routeToken, widget.id, false);
  @override
  void didPop() => g.setVisible(_routeToken, widget.id, false);
  @override
  void dispose() {
    widget.routeObserver?.unsubscribe(this);
    g.setVisible(_routeToken, widget.id, false);
    g.drafts.removeListener(_draftChanged);
    _composerFocus.dispose();
    _text.dispose();
    _scroll.dispose();
    _focusScroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final text = _text.text;
    await g.sendText(
      text,
      reply: g.drafts.replyFor(widget.id, group: true),
      draftText: text,
      draftRevision: g.drafts.revisionFor(widget.id, group: true),
    );
    if (!mounted) return;
    setState(() => _sending = false);
  }

  Future<void> _pickImage() async {
    await g.images.pick();
    if (mounted) await _reviewImage();
  }

  Future<void> _reviewImage() async {
    final c = widget.controller,
        access = widget.controller.accessRevision,
        view = g.view,
        epoch = g.epoch;
    final bytes = await g.images.review(widget.id);
    if (!mounted ||
        bytes == null ||
        !c.appAccessible ||
        !c.appForeground ||
        access != c.accessRevision) {
      return;
    }
    try {
      final send = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Send group image?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(bytes, height: 180, fit: BoxFit.contain),
              Text(
                '${(bytes.length / 1024).ceil()} KiB · ${g.members.length - 1} recipients. The host receives and relays this image. Keep all apps unlocked and open.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: g.images.canSend
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
          g.active?.id != widget.id ||
          epoch != g.epoch ||
          view != g.view) {
        return;
      }
      if (send == true) {
        await g.images.send(bytes);
      } else if (send == false) {
        g.images.discard();
      }
    } finally {
      unawaited(MemoryImage(bytes).evict());
    }
  }

  Future<void> _pickFile() async {
    await g.files.pick();
    if (mounted) await _reviewFile();
  }

  Future<void> _reviewFile() async {
    final c = widget.controller,
        access = widget.controller.accessRevision,
        view = g.view,
        epoch = g.epoch;
    final selection = await g.files.review(widget.id);
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
        title: const Text('Send group file?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(selection.name),
            Text(
              '${(selection.bytes.length / 1024).ceil()} KiB · ${g.members.length - 1} recipients. The host receives and relays this file. Keep all apps unlocked and open.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: g.files.canSend
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
        g.active?.id != widget.id ||
        epoch != g.epoch ||
        view != g.view) {
      return;
    }
    if (send == true) {
      await g.files.send(selection);
    } else if (send == false) {
      g.files.discard();
    }
  }

  Future<void> _delete() async {
    final token = widget.controller.accessRevision;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group history?'),
        content: const Text(
          'This deletes saved messages and the draft on this phone and leaves the group if active. Other phones keep their copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true || token != widget.controller.accessRevision) {
      return;
    }
    await g.delete(widget.id);
    if (mounted) Navigator.pop(context);
  }

  Widget _messageBubble(GroupText message) {
    final c = widget.controller;
    final interaction = c.interactionRevision;
    final highlighted = _showTarget && message.key == _focusMessageKey;
    final star = StarredMessage(
      target: widget.id,
      id: message.id,
      author: message.author,
    );
    Widget bubble(EditableTextContextMenuBuilder? menu) => Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: message.author == g.selfId
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: highlighted
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.isStarred(star))
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Icon(
                Icons.star,
                size: 18,
                semanticLabel: 'Starred message',
              ),
            ),
          if (highlighted)
            Text(
              _fromReply
                  ? 'Original message'
                  : widget.fromStar
                  ? 'Starred message'
                  : 'Search result',
            ),
          Text(
            message.author == g.selfId
                ? 'You'
                : '${message.name} • ${message.author.substring(0, 8)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (message.reply != null && c.appAccessible && c.appForeground)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MessageReplyCard(
                key: ValueKey(('group-quote', widget.id, message.key)),
                reply: message.reply!,
                name: message.reply!.author == g.selfId
                    ? 'You'
                    : message.reply!.name,
                onTap: () =>
                    _openReply(message.reply!, interaction: interaction),
              ),
            ),
          if (message.file != null)
            GroupFileBubble(
              key: ValueKey(message.key),
              controller: c,
              groupId: widget.id,
              message: message,
            )
          else if (message.image != null)
            GroupImageBubble(
              key: ValueKey(message.key),
              controller: c,
              message: message,
            )
          else if (highlighted)
            HighlightedSearchText(
              message.text,
              widget.searchQuery,
              selectable: true,
              contextMenuBuilder: menu,
            )
          else
            SelectableText(message.text, contextMenuBuilder: menu),
          Text(
            formatConversationTime(message.timestamp),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (message.author == g.selfId) ...[
            Text(
              'Saved locally • ${message.receipts.entries.where((e) => e.key != g.selfId && e.value == 'received').length}/${message.targets.length - 1} received',
            ),
            for (final id in message.targets.where((id) => id != g.selfId))
              Text(
                '${g.members.where((m) => m.id == id).isNotEmpty ? g.members.firstWhere((m) => m.id == id).name : id.substring(0, 8)}: ${message.receipts[id] ?? 'unconfirmed'}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ],
      ),
    );
    return Align(
      key: ValueKey(('group-message', widget.id, message.key)),
      alignment: message.author == g.selfId
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: TextMessageActions(
        controller: c,
        messageKey: (widget.id, message.key),
        text: message.text,
        onReply: message.image == null && message.file == null
            ? () => unawaited(_replyTo(message))
            : null,
        allowCopy: message.image == null && message.file == null,
        starred: c.isStarred(star),
        onStar: () => unawaited(_starMessage(star)),
        isCurrent: () => g.histories.any(
          (h) =>
              h.id == widget.id &&
              h.messages.any(
                (m) => m.key == message.key && m.text == message.text,
              ),
        ),
        builder: bubble,
      ),
    );
  }

  Future<void> _starMessage(StarredMessage star) async {
    final c = widget.controller;
    final interaction = c.interactionRevision;
    final ok = await c.setStarred(star, !c.isStarred(star));
    if (!ok &&
        mounted &&
        c.appAccessible &&
        c.appForeground &&
        interaction == c.interactionRevision &&
        ModalRoute.of(context)?.isCurrent == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update this starred message. Try again.'),
        ),
      );
    }
  }

  Future<void> _replyTo(GroupText message) async {
    if (await g.replyTo(widget.id, message) &&
        mounted &&
        widget.controller.appAccessible &&
        widget.controller.appForeground &&
        ModalRoute.of(context)?.isCurrent == true) {
      _composerFocus.requestFocus();
    }
  }

  void _openReply(MessageReply reply, {int? interaction}) {
    if (!mounted) return;
    final c = widget.controller;
    if (!c.appAccessible ||
        !c.appForeground ||
        ModalRoute.of(context)?.isCurrent != true ||
        (interaction != null && c.interactionRevision != interaction)) {
      return;
    }
    final histories = g.histories.where((h) => h.id == widget.id);
    final matches = histories.isEmpty
        ? <GroupText>[]
        : histories.first.messages
              .where(
                (m) =>
                    m.key == '${reply.author}/${reply.id}' &&
                    m.image == null &&
                    m.file == null &&
                    reply.matchesText(m.text),
              )
              .toList();
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original message unavailable.')),
      );
      return;
    }
    setState(() {
      _focusMessageKey = matches.first.key;
      _fromReply = true;
      _showTarget = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusScroll.hasClients) _focusScroll.jumpTo(0);
    });
  }

  void _jumpToLatest() {
    setState(() {
      _showTarget = false;
      _atLatest = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Widget _historyView(GroupHistory? history, List<Widget> header) {
    final messages = history?.messages ?? <GroupText>[];
    final pivot = _showTarget && _focusMessageKey != null
        ? messages.indexWhere((m) => m.key == _focusMessageKey)
        : -1;
    if (pivot < 0) {
      return ListView.builder(
        key: ValueKey(
          _atLatest ? 'group-message-latest' : 'group-message-history',
        ),
        controller: _scroll,
        reverse: _atLatest,
        padding: const EdgeInsets.all(16),
        itemCount: messages.length + 1,
        itemBuilder: (_, index) =>
            (_atLatest ? index == messages.length : index == 0)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...header,
                  if (_showTarget && _focusMessageKey != null)
                    Text(
                      _fromReply
                          ? 'Original message unavailable.'
                          : 'The matching message is no longer in this group.',
                    ),
                ],
              )
            : _messageBubble(
                messages[_atLatest ? messages.length - 1 - index : index - 1],
              ),
      );
    }
    // Center the exact author/message key. Both sides are lazy even for long
    // histories and variable-height attachments; the target starts on screen.
    return CustomScrollView(
      key: const ValueKey('group-search-message-history'),
      controller: _focusScroll,
      anchor: .2,
      center: const ValueKey('group-search-anchor'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) => index < pivot
                  ? _messageBubble(messages[pivot - 1 - index])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: header,
                    ),
              childCount: pivot + 1,
            ),
          ),
        ),
        SliverPadding(
          key: const ValueKey('group-search-anchor'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) => _messageBubble(messages[pivot + index]),
              childCount: messages.length - pivot,
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
      final found = g.histories.where((h) => h.id == widget.id);
      final GroupHistory? history = found.isEmpty ? null : found.first;
      final active = g.active?.id == widget.id;
      final c = widget.controller;
      final interaction = c.interactionRevision;
      final groupId = widget.id;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            '${c.simulatedGroups ? 'Demo • ' : ''}${history?.title ?? 'Group unavailable'}',
          ),
          actions: [
            if (history != null && !(_showTarget && _focusMessageKey != null))
              IconButton(
                tooltip: 'Search group messages',
                icon: const Icon(Icons.search),
                onPressed: c.appAccessible && c.appForeground
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatSearchScreen(
                            controller: c,
                            groupId: widget.id,
                            routeObserver: widget.routeObserver,
                          ),
                        ),
                      )
                    : null,
              ),
            if (_showTarget && _focusMessageKey != null)
              IconButton(
                tooltip: 'Jump to latest',
                onPressed: _jumpToLatest,
                icon: const Icon(Icons.vertical_align_bottom),
              ),
            if (active && (g.connected || g.images.picking))
              IconButton(
                tooltip: 'Attach group image',
                onPressed: g.images.canSend ? _pickImage : null,
                icon: g.images.picking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
              ),
            if (active && (g.connected || g.files.picking))
              IconButton(
                tooltip: 'Attach group file',
                onPressed: g.files.canSend ? _pickFile : null,
                icon: g.files.picking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file),
              ),
            if (history != null) GroupMenu(controller: c, group: history),
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete group history',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _historyView(history, [
                  if (c.simulatedGroups)
                    const Text(
                      'Demo group • simulated members, verification and receipts. Data resets on reload.',
                    ),
                  Text(
                    active
                        ? g.state
                        : 'Saved history • join the original host to continue',
                  ),
                  if (g.error != null)
                    Text(
                      g.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (!active &&
                      history != null &&
                      history.host == g.selfPublic)
                    TextButton(
                      onPressed:
                          c.canUseGroups &&
                              !g.busy &&
                              !g.running &&
                              c.appAccessible &&
                              c.appForeground
                          ? () => g.host(history.title, previous: history)
                          : null,
                      child: const Text('Host this group again'),
                    ),
                  if (active) ...[
                    _GroupAttachmentControls(
                      hub: g.images,
                      connected: g.connected,
                      groupId: widget.id,
                      review: _reviewImage,
                    ),
                    _GroupAttachmentControls(
                      hub: g.files,
                      connected: g.connected,
                      groupId: widget.id,
                      review: _reviewFile,
                    ),
                    GroupVerification(controller: c),
                    Text(
                      'Members (${g.members.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Each member verifies the host. Trust the host’s admission of other members.',
                    ),
                    for (final member in g.members)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${member.name}${member.id == g.selfId ? ' (you)' : ''}${member.public == history?.host ? ' • host' : ''}',
                        ),
                        subtitle: Text(member.id.substring(0, 12)),
                        trailing: g.hosting && member.id != g.selfId
                            ? IconButton(
                                tooltip: 'Remove member',
                                icon: const Icon(Icons.person_remove_outlined),
                                onPressed: c.appAccessible && c.appForeground
                                    ? () {
                                        final matches = g.links.values.where(
                                          (l) => l.session.peerId == member.id,
                                        );
                                        if (matches.isNotEmpty) {
                                          g.reject(matches.first.id);
                                        }
                                      }
                                    : null,
                              )
                            : null,
                      ),
                    TextButton(
                      onPressed: !g.busy ? g.stop : null,
                      child: Text(g.hosting ? 'End hosting' : 'Leave group'),
                    ),
                  ],
                  if (history?.messages.isEmpty ?? true)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No group messages yet.'),
                    ),
                ]),
              ),
              if (c.appAccessible && c.appForeground)
                if (g.drafts.replyFor(widget.id, group: true)
                    case final MessageReply reply)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: MessageReplyCard(
                      key: const ValueKey('group-reply-composer-preview'),
                      reply: reply,
                      name: reply.author == g.selfId ? 'You' : reply.name,
                      onTap: () => _openReply(reply, interaction: interaction),
                      onCancel: () {
                        if (mounted &&
                            c.appAccessible &&
                            c.appForeground &&
                            c.interactionRevision == interaction &&
                            widget.id == groupId &&
                            ModalRoute.of(context)?.isCurrent == true &&
                            g.drafts.replyFor(groupId, group: true) == reply) {
                          g.drafts.setReply(groupId, null, group: true);
                        }
                      },
                      notice: active && !g.repliesAvailable
                          ? 'Replies require every group member to use the updated app.'
                          : null,
                    ),
                  ),
              if (g.drafts.errorFor(widget.id, group: true)
                  case final String error)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(child: Text(error)),
                      TextButton(
                        onPressed:
                            widget.controller.appAccessible &&
                                widget.controller.appForeground
                            ? () => g.drafts.retry(widget.id, group: true)
                            : null,
                        child: const Text('Retry draft'),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        key: const ValueKey('group-message-composer'),
                        focusNode: _composerFocus,
                        enabled:
                            history != null &&
                            widget.controller.appAccessible &&
                            widget.controller.appForeground &&
                            g.drafts.isLoaded(widget.id, group: true),
                        onChanged: (text) =>
                            g.drafts.setText(widget.id, text, group: true),
                        maxLength: 4096,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: active && g.connected
                              ? 'Group message'
                              : 'Draft (join and verify to send)',
                          counterText: '',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          active &&
                              g.canSend &&
                              (g.drafts.replyFor(widget.id, group: true) ==
                                      null ||
                                  g.repliesAvailable) &&
                              !_sending &&
                              g.drafts.isLoaded(widget.id, group: true)
                          ? _send
                          : null,
                      tooltip: 'Send group message',
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GroupAttachmentControls extends StatelessWidget {
  const _GroupAttachmentControls({
    required this.hub,
    required this.connected,
    required this.groupId,
    required this.review,
  });
  final GroupAttachments<dynamic> hub;
  final bool connected;
  final String groupId;
  final Future<void> Function() review;
  @override
  Widget build(BuildContext context) {
    final label = hub.fileMode ? 'File' : 'Image', kind = label.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (connected && !hub.available)
          Text(
            '${label}s require at least two verified members, with every member using an updated app.',
          ),
        for (final p in hub.progress)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label: ${p.transfer.outgoing ? 'Sending to' : 'Receiving from'} ${p.member} (${(p.transfer.fraction * 100).round()}%)',
                ),
                LinearProgressIndicator(value: p.transfer.fraction),
              ],
            ),
          ),
        if (hub.waiting && hub.progress.isEmpty)
          Text('$label saved locally; waiting for recipient receipts.'),
        if (hub.progress.isNotEmpty || hub.waiting)
          TextButton(
            onPressed: hub.cancelByUser,
            child: Text('Cancel $kind transfers'),
          ),
        if (hub.notice != null) Text(hub.notice!),
        if (hub.pendingGroup == groupId)
          Wrap(
            children: [
              TextButton.icon(
                onPressed: review,
                icon: Icon(
                  hub.fileMode ? Icons.attach_file : Icons.image_outlined,
                ),
                label: Text('Review group $kind'),
              ),
              TextButton(onPressed: hub.discard, child: const Text('Discard')),
            ],
          ),
      ],
    );
  }
}
