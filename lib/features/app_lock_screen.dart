import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_controller.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, required this.lock});
  final AppLockController lock;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final pin = _pin.text;
    _pin.clear();
    await widget.lock.unlockPin(pin);
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.lock;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    'LocalChat locked',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (lock.loading)
                    const CircularProgressIndicator()
                  else if (lock.storageFailed) ...[
                    Text(lock.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: lock.busy ? null : lock.initialize,
                      child: const Text('Retry lock setup'),
                    ),
                  ] else ...[
                    const Text('Enter your six-digit app PIN.'),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pin,
                      enabled: !lock.busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'App PIN',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                    const SizedBox(height: 16),
                    if (lock.error != null) ...[
                      Text(
                        lock.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (lock.busy)
                      const CircularProgressIndicator()
                    else ...[
                      FilledButton(
                        onPressed: _unlock,
                        child: const Text('Unlock'),
                      ),
                      if (lock.biometricEnabled && lock.biometricAvailable)
                        TextButton.icon(
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Unlock with biometrics'),
                          onPressed: lock.unlockBiometric,
                        ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      lock.isDemo
                          ? 'Demo PIN resets when this browser tab reloads. '
                                'Fingerprint unlock requires Android.'
                          : 'Use the PIN you created in LocalChat, '
                                'which may differ from your phone PIN.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
