import 'package:flutter/material.dart';
import '../core/group_models.dart';
import '../services/chat_controller.dart';
import 'group_menu.dart';
import 'group_screen.dart';

/// Shared saved-group row for Chats, Archived chats and the group hub.
class GroupChatTile extends StatelessWidget {
  const GroupChatTile({
    super.key,
    required this.controller,
    required this.group,
    this.routeObserver,
    this.showMessageCount = false,
  });
  final ChatController controller;
  final GroupHistory group;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  final bool showMessageCount;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('group-card-${group.id}'),
    child: ListTile(
      key: ValueKey('group-${group.id}'),
      leading: CircleAvatar(
        child: Icon(
          group.pinned ? Icons.push_pin : Icons.groups_outlined,
          semanticLabel: group.pinned ? 'Pinned group' : null,
        ),
      ),
      title: Text(
        group.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: group.unread > 0
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      ),
      subtitle: Text(
        '${showMessageCount ? '${group.messages.length} messages' : 'Group'} · ${group.unread} unread${controller.groups.active?.id == group.id ? ' · active' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: GroupMenu(controller: controller, group: group),
      onTap: controller.appAccessible && controller.appForeground
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GroupChatScreen(
                  controller: controller,
                  id: group.id,
                  routeObserver: routeObserver,
                ),
              ),
            )
          : null,
    ),
  );
}
