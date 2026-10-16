import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_controller.dart';

class AppLockSettings extends StatelessWidget {
  const AppLockSettings({super.key, required this.lock});
  final AppLockController lock;

  Future<void> _edit(BuildContext context, _Action action) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PinDialog(lock: lock, action: action),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lock,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('App lock', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          lock.isDemo
              ? 'Try a PIN in this demo. It resets on reload; biometrics require Android.'
              : 'Require your app PIN on launch and after your chosen auto-lock delay. '
                    'Remember it: there is no PIN recovery.',
        ),
        const SizedBox(height: 8),
        if (!lock.enabled)
          OutlinedButton.icon(
            onPressed: lock.busy ? null : () => _edit(context, _Action.enable),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Set up app lock'),
          )
        else ...[
          ListTile(
            key: const ValueKey('auto-lock-timing'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-lock timing'),
            subtitle: Text(lock.autoLockDelay.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: lock.busy ? null : () => _edit(context, _Action.delay),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fingerprint / biometrics'),
            subtitle: Text(
              lock.biometricAvailable
                  ? 'Use your enrolled biometrics, with app PIN fallback.'
                  : lock.isDemo
                  ? 'Available on supported Android phones.'
                  : 'No enrolled biometrics available. You can still use your PIN.',
            ),
            value: lock.biometricEnabled,
            onChanged:
                lock.busy ||
                    (!lock.biometricEnabled && !lock.biometricAvailable)
                ? null
                : (value) => _edit(
                    context,
                    value ? _Action.enableBiometric : _Action.disableBiometric,
                  ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: lock.busy
                    ? null
                    : () => _edit(context, _Action.change),
                child: const Text('Change PIN'),
              ),
              OutlinedButton(
                onPressed: lock.busy
                    ? null
                    : () => _edit(context, _Action.disable),
                child: const Text('Disable app lock'),
              ),
              FilledButton.icon(
                onPressed: lock.busy ? null : lock.lock,
                icon: const Icon(Icons.lock),
                label: const Text('Lock now'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 28),
      ],
    ),
  );
}

enum _Action {
  enable,
  change,
  disable,
  enableBiometric,
  disableBiometric,
  delay,
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.lock, required this.action});
  final AppLockController lock;
  final _Action action;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;
  late AutoLockDelay _delay = widget.lock.autoLockDelay;
  bool get _settingPin =>
      widget.action == _Action.enable || widget.action == _Action.change;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: true,
      keyboardType: TextInputType.number,
      enableSuggestions: false,
      autocorrect: false,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, counterText: ''),
    ),
  );

  Future<void> _save() async {
    if (_busy) return;
    if (_settingPin && !AppLockController.validPin(_new.text)) {
      setState(() => _error = 'Use exactly six digits for your new PIN.');
      return;
    }
    if (_settingPin && _new.text != _confirm.text) {
      setState(() => _error = 'The new PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final lock = widget.lock;
    final accepted = switch (widget.action) {
      _Action.enable => await lock.enable(_new.text),
      _Action.change => await lock.changePin(_current.text, _new.text),
      _Action.disable => await lock.disable(_current.text),
      _Action.enableBiometric => await lock.setBiometric(true, _current.text),
      _Action.disableBiometric => await lock.setBiometric(false, _current.text),
      _Action.delay => await lock.setAutoLockDelay(_delay, _current.text),
    };
    if (!mounted) return;
    _current.clear();
    if (accepted) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = lock.error ?? 'Could not save app lock settings.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(switch (widget.action) {
        _Action.enable => 'Set up app lock',
        _Action.change => 'Change app PIN',
        _Action.disable => 'Disable app lock?',
        _Action.enableBiometric => 'Enable biometrics',
        _Action.disableBiometric => 'Disable biometrics',
        _Action.delay => 'Auto-lock timing',
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.action != _Action.enable)
            _field(_current, 'Current app PIN'),
          if (widget.action == _Action.delay) ...[
            DropdownButtonFormField<AutoLockDelay>(
              key: const ValueKey('auto-lock-delay'),
              initialValue: _delay,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(
                labelText: 'Require unlock after',
              ),
              items: [
                for (final delay in AutoLockDelay.values)
                  DropdownMenuItem(value: delay, child: Text(delay.label)),
              ],
              selectedItemBuilder: (context) => [
                for (final delay in AutoLockDelay.values)
                  Text(
                    delay.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _delay = value!),
            ),
            const SizedBox(height: 12),
            const Text(
              'Starts when LocalChat loses focus. Chats stay hidden while '
              'you are away. Returning before the delay ends skips another unlock. '
              'Launch and Lock now always require unlocking.',
            ),
          ],
          if (_settingPin) ...[
            _field(_new, 'New six-digit PIN'),
            _field(_confirm, 'Confirm new PIN'),
            const Text(
              'Remember your PIN. There is no recovery option. '
              'Resetting app data removes your chat history and identity.',
            ),
          ],
          if (widget.action == _Action.disable)
            const Text(
              'LocalChat will open without asking for authentication.',
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
