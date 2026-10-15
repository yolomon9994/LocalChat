import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

typedef VerificationScannerBuilder =
    Widget Function(BuildContext, ValueChanged<String>);

bool get verificationCameraSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Android-only: never starts the plugin's web/CDN-backed scanner.
class VerificationCamera extends StatefulWidget {
  const VerificationCamera({super.key, required this.onDetected});
  final ValueChanged<String> onDetected;
  @override
  State<VerificationCamera> createState() => _VerificationCameraState();
}

class _VerificationCameraState extends State<VerificationCamera>
    with WidgetsBindingObserver {
  // A late permission result must finish shutting down before a new view starts.
  static Future<void>? _previousCameraClosed;
  final _closed = Completer<void>();
  late final Future<void>? _previous;
  final _camera = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    returnImage: false,
  );
  Future<void>? _starting;
  bool _disposed = false, _failed = false, _suspended = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _suspended = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    _previous = _previousCameraClosed;
    _previousCameraClosed = _closed.future;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _starting = _start();
    });
  }

  Future<void> _start() async {
    await _previous;
    if (_disposed || _suspended || !verificationCameraSupported) return;
    try {
      await _camera.start();
    } catch (_) {
      if (mounted && !_disposed) setState(() => _failed = true);
    }
    if (_disposed || _suspended) {
      try {
        await _camera.stop();
      } catch (_) {}
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _camera.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _suspended = true;
    unawaited(_stopCamera());
  }

  Future<void> _shutdown() async {
    try {
      await _previous;
      await _starting;
      try {
        await _camera.stop();
      } catch (_) {}
      try {
        await _camera.dispose();
      } catch (_) {}
    } finally {
      if (identical(_previousCameraClosed, _closed.future)) {
        _previousCameraClosed = null;
      }
      if (!_closed.isCompleted) _closed.complete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopCamera());
    unawaited(_shutdown());
    super.dispose();
  }

  Widget _error() => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Camera unavailable. Allow camera permission in Android settings, then try scanning again, or compare the codes manually.',
        textAlign: TextAlign.center,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => _failed || !verificationCameraSupported
      ? _error()
      : MobileScanner(
          controller: _camera,
          useAppLifecycleState: false,
          onDetect: (capture) {
            if (_disposed || _suspended || !mounted) return;
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null) {
                widget.onDetected(value);
                break;
              }
            }
          },
          onDetectError: (_, _) {
            unawaited(_stopCamera());
            if (mounted && !_disposed) setState(() => _failed = true);
          },
          errorBuilder: (_, _) => _error(),
        );
}
