import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/app_lock_controller.dart';
import '../services/appearance_controller.dart';
import '../services/chat_controller.dart';
import 'chat_screen.dart';
import 'chats_tab.dart';
import 'nearby_tab.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.appLock,
    this.appearance,
  });
  final ChatController controller;
  final AppLockController? appLock;
  final AppearanceController? appearance;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;

  void _chat() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(controller: widget.controller),
      ),
    );
  }

  Future<void> _openConnected() async {
    await widget.controller.viewConnected();
    if (mounted && widget.controller.connectedPeer != null) _chat();
  }

  Future<void> _openHistory(Conversation peer) async {
    await widget.controller.viewHistory(peer);
    if (mounted) _chat();
  }

  Future<void> _connect(Peer peer) async {
    await widget.controller.connect(peer);
    if (mounted) _chat();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(
          title: const Text('LocalChat'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    controller: c,
                    appLock: widget.appLock,
                    appearance: widget.appearance,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: c.loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (c.error != null)
                    Card(
                      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(child: Text(c.error!)),
                            IconButton(
                              onPressed: c.dismissError,
                              icon: const Icon(Icons.close),
                              tooltip: 'Dismiss',
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: !c.initialized
                        ? Center(
                            child: FilledButton(
                              onPressed: c.initialize,
                              child: const Text('Retry setup'),
                            ),
                          )
                        : IndexedStack(
                            index: _selectedTab,
                            children: [
                              ChatsTab(
                                controller: c,
                                onFindDevices: () =>
                                    setState(() => _selectedTab = 1),
                                onOpenConnected: _openConnected,
                                onOpenHistory: _openHistory,
                              ),
                              NearbyTab(controller: c, onConnect: _connect),
                            ],
                          ),
                  ),
                ],
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: (index) =>
              setState(() => _selectedTab = index),
          destinations: const [
            NavigationDestination(
              key: ValueKey('chats-destination'),
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            NavigationDestination(
              key: ValueKey('nearby-destination'),
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar),
              label: 'Nearby',
            ),
          ],
        ),
      );
    },
  );
}
