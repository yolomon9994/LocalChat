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
                        'Name saved. Tap Go nearby to advertise it.',
                  ),
                ),
              );
            }
          },
          child: const Text('Save name'),
        ),
        const SizedBox(height: 28),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline),
          title: Text('Private nearby conversations'),
          subtitle: Text(
            'Compare security codes on both phones every time you connect. Names are public and can be copied.',
          ),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.storage),
          title: Text('History stays on your phone'),
          subtitle: Text(
            'Message text is encrypted locally. Names, timestamps and delivery status are not encrypted in the database.',
          ),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.info_outline),
          title: Text('LocalChat 0.1 • Android'),
          subtitle: Text(
            'Text only. Keep the app open on both phones. Bluetooth fallback, media and background messaging are planned. This prototype has not had an independent security audit.',
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
                content: const Text(
                  'This permanently deletes saved messages on this phone.',
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
