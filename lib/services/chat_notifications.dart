import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NotificationPreview {
  hidden('hidden', 'Hidden'),
  sender('sender', 'Sender only'),
  message('message', 'Sender and message');

  const NotificationPreview(this.value, this.label);
  final String value, label;
  static NotificationPreview parse(Map<String, dynamic> values) {
    if (!values.containsKey('previewMode')) {
      return values['previews'] == true ? message : hidden;
    }
    return values['previewMode'] == 'message'
        ? message
        : values['previewMode'] == 'sender'
        ? sender
        : hidden;
  }
}

abstract class NotificationPlatform {
  Stream<String> get taps;
  Future<Map<String, dynamic>> settings();
  Future<void> configure({
    required bool enabled,
    required bool previews,
    NotificationPreview? previewMode,
  });
  Future<bool> requestPermission();
  Future<void> privacy(bool accessible);
  Future<void> show(String peer, {String? name, String? text});
  Future<void> cancel(String? peer);
  Future<String?> takeTap();
  Future<void> openSettings();
  void dispose();
}

class AndroidNotificationPlatform implements NotificationPlatform {
  AndroidNotificationPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tapAvailable') {
        final peer = await takeTap();
        if (peer != null && !_taps.isClosed) _taps.add(peer);
      }
    });
  }
  static const _channel = MethodChannel('dev.localchat/notifications');
  final _taps = StreamController<String>.broadcast();
  @override
  Stream<String> get taps => _taps.stream;
  @override
  Future<Map<String, dynamic>> settings() async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod('settings') ?? {},
  );
  @override
  Future<void> configure({
    required bool enabled,
    required bool previews,
    NotificationPreview? previewMode,
  }) => _channel.invokeMethod('configure', {
    'enabled': enabled,
    'previews': previews,
    if (previewMode != null) 'previewMode': previewMode.value,
  });
  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;
  @override
  Future<void> privacy(bool accessible) =>
      _channel.invokeMethod('privacy', {'accessible': accessible});
  @override
  Future<void> show(String peer, {String? name, String? text}) =>
      _channel.invokeMethod('show', {'peer': peer, 'name': name, 'text': text});
  @override
  Future<void> cancel(String? peer) =>
      _channel.invokeMethod('cancel', {'peer': peer});
  @override
  Future<String?> takeTap() => _channel.invokeMethod<String>('takeTap');
  @override
  Future<void> openSettings() => _channel.invokeMethod('openSettings');
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_taps.close());
  }
}

/// Browser demo and injectable test implementation. Never requests web permission.
class MemoryNotificationPlatform implements NotificationPlatform {
  final tapEvents = StreamController<String>.broadcast();
  final alerts = <String, ({String? name, String? text})>{};
  bool enabled = false;
  bool previews = false;
  NotificationPreview? savedPreviewMode;
  bool allowed = true;
  bool accessible = false;
  String? launchPeer;
  @override
  Stream<String> get taps => tapEvents.stream;
  @override
  Future<Map<String, dynamic>> settings() async => {
    'enabled': enabled,
    'previews': previews,
    if (savedPreviewMode != null) 'previewMode': savedPreviewMode!.value,
    'allowed': allowed,
  };
  @override
  Future<void> configure({
    required bool enabled,
    required bool previews,
    NotificationPreview? previewMode,
  }) async {
    this.enabled = enabled;
    final mode =
        previewMode ??
        (previews ? NotificationPreview.message : NotificationPreview.hidden);
    if (mode != savedPreviewMode) await privacy(false);
    savedPreviewMode = mode;
    this.previews = mode == NotificationPreview.message;
    if (!enabled) alerts.clear();
    if (!previews) await privacy(false);
  }

  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<void> privacy(bool accessible) async {
    this.accessible = accessible;
    if (!accessible) {
      for (final peer in alerts.keys.toList()) {
        alerts[peer] = (name: null, text: null);
      }
    }
  }

  @override
  Future<void> show(String peer, {String? name, String? text}) async {
    if (enabled && allowed) {
      alerts[peer] = (
        name:
            accessible &&
                (savedPreviewMode ??
                        (previews
                            ? NotificationPreview.message
                            : NotificationPreview.hidden)) !=
                    NotificationPreview.hidden
            ? name
            : null,
        text:
            accessible &&
                (savedPreviewMode ??
                        (previews
                            ? NotificationPreview.message
                            : NotificationPreview.hidden)) ==
                    NotificationPreview.message
            ? text
            : null,
      );
    }
  }

  @override
  Future<void> cancel(String? peer) async {
    if (peer == null) {
      alerts.clear();
    } else {
      alerts.remove(peer);
    }
  }

  @override
  Future<String?> takeTap() async {
    final peer = launchPeer;
    launchPeer = null;
    return peer;
  }

  @override
  Future<void> openSettings() async {}
  @override
  void dispose() => unawaited(tapEvents.close());
}

/// Notification failures are isolated from message persistence and ACK delivery.
class ChatNotifications extends ChangeNotifier {
  ChatNotifications(this.platform, {this.isDemo = false});
  final NotificationPlatform platform;
  final bool isDemo;
  bool initialized = false;
  bool enabled = false;
  NotificationPreview previewMode = NotificationPreview.hidden;
  NotificationPreview _ceiling = NotificationPreview.message;
  bool get previews => previewMode != NotificationPreview.hidden;
  bool allowed = false;
  bool busy = false;
  String? error;
  String? pendingPeer;
  bool _accessible = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  StreamSubscription<String>? _subscription;

  Future<void> _run(Future<void> Function() action) {
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (_) {
        error = 'Could not update notifications. Try again in Settings.';
      }
      if (!_disposed) notifyListeners();
    });
    return _queue;
  }

  void _tap(String peer) {
    if (peer.isEmpty || peer.length > 128 || _disposed) return;
    pendingPeer = peer;
    notifyListeners();
  }

  void consumeTap(String peer) {
    if (pendingPeer == peer) pendingPeer = null;
  }

  Future<void> initialize() => _run(() async {
    if (initialized) return;
    error = null;
    _subscription ??= platform.taps.listen(_tap);
    final values = await platform.settings();
    enabled = values['enabled'] == true;
    previewMode = NotificationPreview.parse(values);
    allowed = values['allowed'] == true;
    await platform.privacy(_accessible);
    final peer = await platform.takeTap();
    if (peer != null && pendingPeer == null) _tap(peer);
    initialized = true;
  });

  void setAccessible(bool accessible) {
    _accessible = accessible;
    if (initialized) {
      unawaited(_run(() => platform.privacy(accessible && _accessible)));
    }
  }

  Future<void> refreshPermission() => _run(() async {
    if (!initialized) return;
    allowed = (await platform.settings())['allowed'] == true;
  });

  Future<void> setEnabled(bool value) async {
    if (busy || !initialized) return;
    busy = true;
    notifyListeners();
    await _run(() async {
      try {
        error = null;
        if (value) allowed = await platform.requestPermission();
        await platform.configure(
          enabled: value,
          previews: previewMode == NotificationPreview.message,
          previewMode: previewMode,
        );
        enabled = value;
        await platform.privacy(_accessible);
      } finally {
        busy = false;
      }
    });
  }

  Future<void> setPreviews(bool value) => setPreviewMode(
    value ? NotificationPreview.message : NotificationPreview.hidden,
  );

  Future<void> setPreviewMode(NotificationPreview value) async {
    if (!initialized || busy || _disposed) return;
    busy = true;
    if (value.index < _ceiling.index) _ceiling = value;
    notifyListeners();
    await _run(() async {
      try {
        error = null;
        await platform.privacy(false);
        await platform.configure(
          enabled: enabled,
          previews: value == NotificationPreview.message,
          previewMode: value,
        );
        previewMode = value;
        _ceiling = value;
        await platform.privacy(_accessible);
      } finally {
        busy = false;
      }
    });
  }

  Future<void> openSettings() => _run(platform.openSettings);

  Future<void> incoming(
    String peer,
    String name,
    String text, {
    required bool Function() isReading,
  }) => _run(() async {
    if (!initialized || !enabled || isReading()) return;
    // Generic mode never sends plaintext sender/body across the native bridge.
    final mode = previewMode.index < _ceiling.index ? previewMode : _ceiling;
    final preview = mode != NotificationPreview.hidden && _accessible;
    await platform.show(
      peer,
      name: preview ? name : null,
      text: preview && mode == NotificationPreview.message ? text : null,
    );
  });

  Future<void> cancel(String? peer) => _run(() async {
    if (peer == null || pendingPeer == peer) pendingPeer = null;
    if (initialized) await platform.cancel(peer);
  });

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    platform.dispose();
    super.dispose();
  }
}
