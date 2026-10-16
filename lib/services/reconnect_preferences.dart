import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class ReconnectStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureReconnectStorage implements ReconnectStorage {
  static const _vault = FlutterSecureStorage();
  @override
  Future<String?> read() => _vault.read(key: 'automatic_reconnect_v1');
  @override
  Future<void> write(String value) =>
      _vault.write(key: 'automatic_reconnect_v1', value: value);
}

class MemoryReconnectStorage implements ReconnectStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class ReconnectPreferences extends ChangeNotifier {
  ReconnectPreferences(this.storage);
  final ReconnectStorage storage;
  bool enabled = false, loading = true, saving = false;
  bool _disposed = false;
  Future<void>? _initializing;
  String? error;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    try {
      final saved = await storage.read();
      if (_disposed) return;
      if (saved != null) {
        final value = jsonDecode(saved);
        if (value is! Map ||
            value.length != 2 ||
            value['v'] != 1 ||
            value['enabled'] is! bool) {
          throw const FormatException('Invalid reconnect preference');
        }
        enabled = value['enabled'] as bool;
      }
    } catch (_) {
      enabled = false;
      error =
          'Could not load automatic reconnection. Choose the setting again to save.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> setEnabled(bool value) async {
    if (_disposed || loading || saving) return false;
    saving = true;
    error = null;
    _notify();
    try {
      await storage.write(jsonEncode({'v': 1, 'enabled': value}));
      if (!_disposed) enabled = value;
      return true;
    } catch (_) {
      error = 'Could not save automatic reconnection. Please try again.';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
