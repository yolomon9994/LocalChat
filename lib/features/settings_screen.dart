import 'package:flutter/material.dart';
import '../services/chat_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final ChatController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _name = TextEditingController(text: widget.controller.profileName);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _name,
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'Nearby display name'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            await widget.controller.rename(_name.text);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    widget.controller.error ??
                        (widget.controller.isDemo
                            ? 'Demo name saved until reload. Tap Go nearby to continue.'
                            : 'Name saved. Tap Go nearby to advertise it.'),
                  ),
                ),
              );
            }
          },
          child: const Text('Save name'),
        ),
        const SizedBox(height: 28),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: Text(
            widget.controller.isDemo
                ? 'Simulated verification'
                : 'Private nearby conversations',
          ),
          subtitle: Text(
            widget.controller.isDemo
                ? 'The preview confirms a simulated peer. Real Android conversations require comparing the complete code on both phones.'
                : 'Compare security codes on both phones every time you connect. Names are public and can be copied.',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storage),
          title: Text(
            widget.controller.isDemo
                ? 'Temporary demo history'
                : 'History stays on your phone',
          ),
          subtitle: Text(
            widget.controller.isDemo
                ? 'Messages and settings live in memory in this browser tab. Reloading resets them. The demo does not use SQLite or secure storage.'
                : 'Message text is encrypted locally. Names, timestamps and delivery status are not encrypted in the database.',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: Text(
            widget.controller.isDemo
                ? 'LocalChat 0.1 • Browser demo'
                : 'LocalChat 0.1 • Android',
          ),
          subtitle: Text(
            widget.controller.isDemo
                ? 'Interface preview only. Devices, replies and delivery status are simulated. No real Wi-Fi Direct communication takes place.'
                : 'Text only. Keep the app open on both phones. Bluetooth fallback, media and background messaging are planned. This prototype has not had an independent security audit.',
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete all chat history'),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete history?'),
                content: Text(
                  widget.controller.isDemo
                      ? 'This clears the temporary messages in this demo tab.'
                      : 'This permanently deletes saved messages on this phone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await widget.controller.clearHistory();
            }
          },
        ),
      ],
    ),
  );
}
