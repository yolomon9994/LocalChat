import 'package:flutter/material.dart';
import '../core/models.dart';
import '../services/chat_controller.dart';
import 'chat_screen.dart';
import 'chats_tab.dart';

class ArchivedChatsScreen extends StatelessWidget {
  const ArchivedChatsScreen({
    super.key,
    required this.controller,
    this.routeObserver,
  });
  final ChatController controller;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;

  Future<void> _open(BuildContext context, Conversation peer) async {
    final opened = await controller.viewHistory(peer);
    if (!context.mounted || !opened) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(controller: controller, routeObserver: routeObserver),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Archived chats')),
      body: ChatsTab(
        controller: controller,
        archived: true,
        onFindDevices: () {},
        onOpenConnected: () {},
        onOpenHistory: (peer) => _open(context, peer),
      ),
    ),
  );
}
