import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class PreviewPrivacyStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SecurePreviewPrivacyStorage implements PreviewPrivacyStorage {
  static const _vault = FlutterSecureStorage();
  @override
  Future<String?> read() => _vault.read(key: 'preview_privacy_v1');
  @override
  Future<void> write(String value) =>
      _vault.write(key: 'preview_privacy_v1', value: value);
}

class MemoryPreviewPrivacyStorage implements PreviewPrivacyStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class PreviewPrivacy extends ChangeNotifier {
  PreviewPrivacy(this.storage);
  final PreviewPrivacyStorage storage;
  bool hidden = true, loading = true, saving = false;
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
      if (saved == null) {
        hidden = false;
      } else {
        final record = jsonDecode(saved);
        if (record is! Map ||
            record.length != 2 ||
            record['v'] != 1 ||
            record['hidden'] is! bool) {
          throw const FormatException('Invalid preview preference');
        }
        hidden = record['hidden'] as bool;
      }
    } catch (_) {
      hidden = true;
      error =
          'Could not load preview privacy. Choose the setting again to save.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> setHidden(bool value) async {
    if (_disposed || loading || saving) return false;
    saving = true;
    error = null;
    _notify();
    try {
      await storage.write(jsonEncode({'v': 1, 'hidden': value}));
      if (!_disposed) hidden = value;
      return true;
    } catch (_) {
      error = 'Could not save preview privacy. Please try again.';
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
