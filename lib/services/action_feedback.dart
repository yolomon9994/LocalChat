import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class FeedbackStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureFeedbackStorage implements FeedbackStorage {
  static const _vault = FlutterSecureStorage();
  static const _key = 'action_feedback_v1';
  @override
  Future<String?> read() => _vault.read(key: _key);
  @override
  Future<void> write(String value) => _vault.write(key: _key, value: value);
}

class MemoryFeedbackStorage implements FeedbackStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

abstract class ActionHaptics {
  bool get supported;
  Future<void> lightImpact();
}

class AndroidActionHaptics implements ActionHaptics {
  const AndroidActionHaptics();
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<void> lightImpact() async {
    if (supported) await HapticFeedback.lightImpact();
  }
}

class FeedbackTicket {
  FeedbackTicket._(this.owner, this.revision, this.current);
  final ActionFeedback owner;
  final int revision;
  final bool Function() current;
  bool _used = false;
}

/// Best-effort feedback for successful local actions, never a delivery receipt.
class ActionFeedback extends ChangeNotifier {
  ActionFeedback(this.storage, {ActionHaptics? haptics, this.isDemo = false})
    : haptics = haptics ?? const AndroidActionHaptics();
  final FeedbackStorage storage;
  final ActionHaptics haptics;
  final bool isDemo;
  bool enabled = false, loading = true, saving = false;
  bool _disposed = false, _playing = false;
  int _revision = 0;
  Future<void>? _initializing;
  String? error;
  bool get supported => !isDemo && haptics.supported;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    try {
      final saved = await storage.read();
      if (_disposed) return;
      if (saved != null) {
        final record = jsonDecode(saved);
        if (record is! Map ||
            record.length != 2 ||
            record['v'] != 1 ||
            record['enabled'] is! bool) {
          throw const FormatException('Invalid feedback preference');
        }
        enabled = record['enabled'] as bool;
      }
    } catch (_) {
      enabled = false;
      error =
          'Could not load vibration feedback. Choose the setting again to save.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> setEnabled(bool value) async {
    if (_disposed || loading || saving) return false;
    _revision++;
    saving = true;
    error = null;
    _notify();
    try {
      await storage.write(jsonEncode({'v': 1, 'enabled': value}));
      if (!_disposed) enabled = value;
      return true;
    } catch (_) {
      if (!_disposed) {
        error = 'Could not save vibration feedback. Please try again.';
      }
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  FeedbackTicket? capture(bool Function() current) =>
      !_disposed && !loading && !saving && enabled && supported && current()
      ? FeedbackTicket._(this, _revision, current)
      : null;

  Future<void> complete(FeedbackTicket? ticket) async {
    if (ticket == null || !identical(ticket.owner, this) || ticket._used) {
      return;
    }
    ticket._used = true;
    if (_disposed ||
        loading ||
        saving ||
        !enabled ||
        !supported ||
        ticket.revision != _revision ||
        !ticket.current() ||
        _playing) {
      return;
    }
    _playing = true;
    try {
      await haptics.lightImpact();
    } catch (_) {
      // Missing hardware/plugins and platform failures never fail the action.
    } finally {
      _playing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
