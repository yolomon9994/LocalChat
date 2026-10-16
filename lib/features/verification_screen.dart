import 'action_feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/session_verification.dart';
import '../services/chat_controller.dart';
import 'verification_camera.dart';

class VerificationActions extends StatelessWidget {
  const VerificationActions({
    super.key,
    required this.controller,
    required this.request,
    this.scannerBuilder,
  });
  final ChatController controller;
  final VerificationRequest request;
  final VerificationScannerBuilder? scannerBuilder;
  void _open(BuildContext context, bool scan) {
    if (!context.mounted ||
        !controller.verificationCurrent(request) ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VerificationScreen(
          controller: controller,
          request: request,
          scan: scan,
          scannerBuilder: scannerBuilder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 12,
    children: [
      OutlinedButton.icon(
        onPressed: () => _open(context, false),
        icon: const Icon(Icons.qr_code),
        label: const Text('Show QR'),
      ),
      OutlinedButton.icon(
        onPressed: controller.canConfirmVerification(request)
            ? () => _open(context, true)
            : null,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan QR'),
      ),
    ],
  );
}

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.controller,
    required this.request,
    this.scan = false,
    this.scannerBuilder,
  });
  final ChatController controller;
  final VerificationRequest request;
  final bool scan;
  final VerificationScannerBuilder? scannerBuilder;
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late bool _scan = widget.scan;
  bool _expired = false, _submitting = false;
  String? _matched, _notice;
  ModalRoute<dynamic>? _route;
  int _generation = 0;
  ChatController get c => widget.controller;
  bool get _current =>
      mounted && !_expired && c.verificationCurrent(widget.request);
  bool get _actionable => _current && (_route?.isCurrent ?? true);
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _changed() {
    if (_current) return;
    _expired = true;
    _matched = null;
    _generation++;
    final route = _route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  void _detected(String raw, int generation) {
    if (!_actionable ||
        generation != _generation ||
        _submitting ||
        _matched != null ||
        !c.canConfirmVerification(widget.request)) {
      return;
    }
    final matches = widget.request.qr.matchesRemote(raw);
    setState(() {
      _notice = matches
          ? null
          : 'This QR does not match this connection. Scan the other phone\'s current LocalChat QR, or compare codes manually.';
      if (matches) {
        _matched = raw;
        _generation++;
      }
    });
  }

  Future<void> _confirm(String raw, int generation) async {
    if (!_actionable ||
        _submitting ||
        generation != _generation ||
        _matched != raw ||
        !c.canConfirmVerification(widget.request)) {
      return;
    }
    setState(() => _submitting = true);
    final success = await withActionFeedback(
      context,
      c,
      () => c.confirmVerification(widget.request, raw),
    );
    if (!mounted || !_actionable || generation != _generation) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _submitting = false;
        _notice =
            'Could not verify this connection. Return to the chat and try again.';
      });
    }
  }

  void _back(int generation) {
    if (!_actionable || _submitting || generation != _generation) return;
    Navigator.of(context).pop();
  }

  void _mode(bool scan, int generation) {
    if (!_actionable || _submitting || generation != _generation) return;
    setState(() {
      _scan = scan;
      _matched = null;
      _notice = null;
      _generation++;
    });
  }

  @override
  void dispose() {
    _expired = true;
    _matched = null;
    _generation++;
    c.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final generation = _generation;
      final matched = _matched;
      return Scaffold(
        appBar: AppBar(title: const Text('Verify with QR')),
        body: !_current
            ? const Center(
                child: Text('This verification is no longer active.'),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.request.peerName,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      c.isDemo
                          ? 'This connection is simulated. QR display and manual confirmation demonstrate the flow; no real nearby phone is connected.'
                          : 'Scan directly from the other phone in person. Both phones must confirm: scan each other\'s QR, or compare the full security code manually.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      children: [
                        TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => _mode(false, generation),
                          icon: const Icon(Icons.qr_code),
                          label: const Text('Show my QR'),
                        ),
                        TextButton.icon(
                          onPressed:
                              !_submitting &&
                                  c.canConfirmVerification(widget.request)
                              ? () => _mode(true, generation)
                              : null,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan other phone'),
                        ),
                      ],
                    ),
                    if (!_scan) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Semantics(
                              label:
                                  'Verification QR for the current connection. Ask the other phone to scan this screen.',
                              image: true,
                              child: ColoredBox(
                                color: Colors.white,
                                child: QrImageView(
                                  data: widget.request.qr.encode,
                                  backgroundColor: Colors.white,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Colors.black,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colors.black,
                                  ),
                                  padding: const EdgeInsets.all(24),
                                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Only for this connection. Reconnects require a fresh QR.',
                        textAlign: TextAlign.center,
                      ),
                    ] else if (matched != null) ...[
                      const Icon(Icons.check_circle_outline, size: 48),
                      const Text(
                        'QR matches this connection.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _submitting
                            ? null
                            : () => unawaited(_confirm(matched, generation)),
                        child: Text(
                          _submitting ? 'Verifying…' : 'Verify connection',
                        ),
                      ),
                    ] else if (widget.scannerBuilder != null ||
                        verificationCameraSupported) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 280,
                        child:
                            widget.scannerBuilder?.call(
                              context,
                              (raw) => _detected(raw, generation),
                            ) ??
                            VerificationCamera(
                              key: ValueKey(generation),
                              onDetected: (raw) => _detected(raw, generation),
                            ),
                      ),
                    ] else ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Camera scanning is available on Android. You can still show this QR or return to compare the full security code manually.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_notice!, textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _submitting ? null : () => _back(generation),
                      child: const Text('Back to manual verification'),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}
