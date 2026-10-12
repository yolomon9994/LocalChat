import 'package:flutter/material.dart';
import '../core/group_models.dart';
import '../services/chat_controller.dart';
import '../services/group_controller.dart';
import 'chats_tab.dart' show formatConversationTime;

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
        title: const Text('Create nearby group'),
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
              const Text(
                'You host and relay messages. Verify every joining member. Keep this phone connected; leaving pauses the group.',
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
      appBar: AppBar(title: const Text('Group chats')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Nearby groups use one host. Each guest verifies the host; the host approves every member and can read and relay group messages. Other members’ identities are vouched for by the host.',
          ),
          const SizedBox(height: 12),
          Text(
            c.isDemo
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
                    !c.isDemo &&
                        c.appAccessible &&
                        c.appForeground &&
                        !g.busy &&
                        !g.running
                    ? _create
                    : null,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Create group'),
              ),
              OutlinedButton.icon(
                onPressed:
                    !c.isDemo &&
                        c.appAccessible &&
                        c.appForeground &&
                        !g.busy &&
                        !g.connected
                    ? g.discover
                    : null,
                icon: const Icon(Icons.radar),
                label: const Text('Find groups'),
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
          if (g.histories.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Group history will appear here after creating or joining a verified group.',
              ),
            ),
          for (final group in g.histories)
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(group.title),
                subtitle: Text(
                  '${group.messages.length} messages${group.unread > 0 ? ' • ${group.unread} unread' : ''}',
                ),
                onTap: () => _open(group.id),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Keep the host open for reliable delivery. Connection protection currently applies to direct chats. No host migration, automatic reconnect or offline group outbox. New members receive new messages only. Group history is included in encrypted backups.',
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
                    const Text(
                      'Compare this entire code on both phones in person. Display names alone do not verify identity.',
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
  });
  final ChatController controller;
  final String id;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> with RouteAware {
  final _text = TextEditingController();
  final _routeToken = Object();
  ModalRoute<dynamic>? _route;
  bool _sending = false;
  GroupController get g => widget.controller.groups;
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
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final text = _text.text;
    final accepted = await g.sendText(text);
    if (!mounted) return;
    if (accepted && _text.text == text) _text.clear();
    setState(() => _sending = false);
  }

  Future<void> _delete() async {
    final token = widget.controller.accessRevision;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group history?'),
        content: const Text(
          'This deletes saved messages on this phone and leaves the group if active. Other phones keep their copies.',
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final found = g.histories.where((h) => h.id == widget.id);
      final GroupHistory? history = found.isEmpty ? null : found.first;
      final active = g.active?.id == widget.id;
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(
          title: Text(history?.title ?? 'Group unavailable'),
          actions: [
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
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                        onPressed: !c.isDemo && !g.busy && !g.running
                            ? () => g.host(history.title, previous: history)
                            : null,
                        child: const Text('Host this group again'),
                      ),
                    if (active) ...[
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
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                  onPressed: c.appAccessible && c.appForeground
                                      ? () {
                                          final matches = g.links.values.where(
                                            (l) =>
                                                l.session.peerId == member.id,
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
                    for (final message in history?.messages ?? <GroupText>[])
                      Align(
                        alignment: message.author == g.selfId
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 520),
                          decoration: BoxDecoration(
                            color: message.author == g.selfId
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                message.author == g.selfId
                                    ? 'You'
                                    : '${message.name} • ${message.author.substring(0, 8)}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              SelectableText(message.text),
                              Text(
                                formatConversationTime(message.timestamp),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              if (message.author == g.selfId) ...[
                                Text(
                                  'Saved locally • ${message.receipts.entries.where((e) => e.key != g.selfId && e.value == 'received').length}/${message.targets.length - 1} received',
                                ),
                                for (final id in message.targets.where(
                                  (id) => id != g.selfId,
                                ))
                                  Text(
                                    '${g.members.where((m) => m.id == id).isNotEmpty ? g.members.firstWhere((m) => m.id == id).name : id.substring(0, 8)}: ${message.receipts[id] ?? 'unconfirmed'}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                              ],
                            ],
                          ),
                        ),
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
                        enabled: active && g.canSend,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: active && g.connected
                              ? 'Group message'
                              : 'Join and verify to send',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: active && g.canSend && !_sending
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
