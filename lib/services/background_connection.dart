import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class BackgroundPlatform {
  Future<Map<String, dynamic>> status();
  Future<void> configure(bool enabled);
  Future<void> requestPermission();
  Future<Map<String, dynamic>> start(int? generation);
  Future<void> stop();
  Future<void> frameProcessed(int generation);
  Future<void> openSettings(String target);
}

class AndroidBackgroundPlatform implements BackgroundPlatform {
  const AndroidBackgroundPlatform();
  static const _channel = MethodChannel('dev.localchat/background');
  static const _notifications = MethodChannel('dev.localchat/notifications');
  @override
  Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await _channel.invokeMapMethod('status') ?? {});
  @override
  Future<void> configure(bool enabled) =>
      _channel.invokeMethod('configure', {'enabled': enabled});
  @override
  Future<void> requestPermission() async {
    // Message alerts and the ongoing connection notification are separate channels.
    // Read our own channel's status afterwards, rather than using Messages status.
    await _notifications.invokeMethod<bool>('requestPermission');
  }

  @override
  Future<Map<String, dynamic>> start(int? generation) async =>
      Map<String, dynamic>.from(
        await _channel.invokeMapMethod('start', {'generation': generation}) ??
            {},
      );
  @override
  Future<void> stop() => _channel.invokeMethod('stop');
  @override
  Future<void> frameProcessed(int generation) =>
      _channel.invokeMethod('frameProcessed', {'generation': generation});
  @override
  Future<void> openSettings(String target) =>
      _channel.invokeMethod('openSettings', {'target': target});
}

class MemoryBackgroundPlatform implements BackgroundPlatform {
  bool enabled = false;
  bool active = false;
  bool allowed = true;
  bool batteryExempt = false;
  int starts = 0;
  @override
  Future<Map<String, dynamic>> status() async => {
    'enabled': enabled,
    'active': active,
    'allowed': allowed,
    'batteryExempt': batteryExempt,
  };
  @override
  Future<void> configure(bool enabled) async {
    this.enabled = enabled;
    if (!enabled) active = false;
  }

  @override
  Future<void> requestPermission() async {}
  @override
  Future<Map<String, dynamic>> start(int? generation) async {
    if (!enabled || !allowed) {
      throw PlatformException(code: 'NOTIFICATIONS_BLOCKED');
    }
    starts++;
    active = true;
    return status();
  }

  @override
  Future<void> stop() async => active = false;
  @override
  Future<void> frameProcessed(int generation) async {}
  @override
  Future<void> openSettings(String target) async {}
}

class BackgroundConnection extends ChangeNotifier {
  BackgroundConnection(this.platform, {this.isDemo = false});
  final BackgroundPlatform platform;
  final bool isDemo;
  bool initialized = false;
  bool enabled = false;
  bool active = false;
  bool allowed = false;
  bool batteryExempt = false;
  bool busy = false;
  String? error;
  String? notice;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _queue = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) {
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (e) {
        if (!(e is PlatformException && e.code == 'BACKGROUND_CANCELLED')) {
          error = e is PlatformException && e.code == 'NOTIFICATIONS_BLOCKED'
              ? 'Allow Android notifications and the Connection channel, then try again.'
              : 'Could not protect the background connection. Return to the app and try again.';
        }
      }
      _notify();
    });
    return _queue;
  }

  void _read(Map<String, dynamic> values) {
    enabled = values['enabled'] == true;
    active = values['active'] == true;
    allowed = values['allowed'] == true;
    batteryExempt = values['batteryExempt'] == true;
    final reason = values['reason'];
    if (reason is String && reason.isNotEmpty) {
      notice = switch (reason) {
        'user' => 'Background connection stopped from the notification.',
        'lost' =>
          'Connection ended. Reconnect in Nearby and verify both phones.',
        'closed' =>
          'The app closed. Reconnect and verify both phones to resume.',
        'system' =>
          'Android stopped the connection. Reopen Nearby and reconnect.',
        _ => null,
      };
    }
    if (active) {
      notice = null;
      error = null;
    }
  }

  Future<void> initialize() => _run(() async {
    if (initialized) return;
    error = null;
    _read(await platform.status());
    initialized = true;
  });

  Future<void> refresh() => _run(() async {
    if (!initialized) return;
    _read(await platform.status());
  });

  Future<void> setEnabled(bool value) async {
    if (!initialized || busy) return;
    busy = true;
    ++_revision;
    _notify();
    await _run(() async {
      try {
        error = null;
        if (value) {
          await platform.requestPermission();
          _read(await platform.status());
          if (!allowed) {
            throw PlatformException(code: 'NOTIFICATIONS_BLOCKED');
          }
        }
        await platform.configure(value);
        _read(await platform.status());
        if (!value) active = false;
        if (value) notice = null;
      } finally {
        busy = false;
      }
    });
  }

  Future<void> protect(
    int? generation, {
    required bool Function() canStart,
    required bool Function() sameConnection,
  }) => _run(() async {
    if (!initialized || !enabled || active || busy || !canStart()) return;
    final revision = _revision;
    busy = true;
    _notify();
    try {
      final values = await platform.start(generation);
      if (_disposed) {
        await platform.stop();
        return;
      }
      if (revision != _revision || !sameConnection()) {
        await platform.stop();
        return;
      }
      _read(values);
    } finally {
      busy = false;
    }
  });

  void nativeStatus(Map<String, dynamic> values) {
    if (_disposed) return;
    if (values['active'] != true) ++_revision;
    _read(values);
    _notify();
  }

  void connectionEnded({bool unexpected = false}) {
    ++_revision;
    final wasActive = active;
    active = false;
    if (unexpected && wasActive) {
      notice = 'Connection ended. Reconnect in Nearby and verify both phones.';
    }
    unawaited(_run(platform.stop));
    _notify();
  }

  Future<void> frameProcessed(int? generation) => _run(() async {
    if (generation != null) await platform.frameProcessed(generation);
  });
  Future<void> openSettings(String target) =>
      _run(() => platform.openSettings(target));
  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    unawaited(platform.stop().catchError((Object _) {}));
    super.dispose();
  }
}
