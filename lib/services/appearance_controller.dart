import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AppPalette {
  mint('Mint', Color(0xff48d8b0)),
  blue('Blue', Color(0xff2563eb)),
  purple('Purple', Color(0xff8b5cf6)),
  amber('Amber', Color(0xfff59e0b));

  const AppPalette(this.label, this.seed);
  final String label;
  final Color seed;
}

abstract class AppearanceStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureAppearanceStorage implements AppearanceStorage {
  static const _vault = FlutterSecureStorage();
  static const _key = 'appearance_v1';

  @override
  Future<String?> read() => _vault.read(key: _key);
  @override
  Future<void> write(String value) => _vault.write(key: _key, value: value);
}

/// Appearance follows the browser demo's temporary-settings behavior.
class MemoryAppearanceStorage implements AppearanceStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

ThemeData buildAppTheme(AppPalette palette, Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: brightness,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    filled: true,
  ),
  appBarTheme: const AppBarTheme(centerTitle: false),
);

class AppearanceController extends ChangeNotifier {
  AppearanceController(this.storage, {this.isDemo = false});

  factory AppearanceController.platform({required bool isDemo}) =>
      AppearanceController(
        isDemo ? MemoryAppearanceStorage() : SecureAppearanceStorage(),
        isDemo: isDemo,
      );

  final AppearanceStorage storage;
  final bool isDemo;
  ThemeMode _mode = ThemeMode.dark;
  AppPalette _palette = AppPalette.mint;
  bool loading = true;
  bool saving = false;
  bool _disposed = false;
  String? error;

  ThemeMode get mode => _mode;
  AppPalette get palette => _palette;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (saving) return;
    error = null;
    try {
      final saved = await storage.read();
      if (saved != null) {
        final json = jsonDecode(saved) as Map<String, dynamic>;
        if (json['version'] != 1) {
          throw const FormatException('Unsupported appearance');
        }
        final mode = ThemeMode.values.byName(json['mode'] as String);
        final palette = AppPalette.values.byName(json['palette'] as String);
        _mode = mode;
        _palette = palette;
      }
    } catch (_) {
      // Preferences never bypass or block the independent app-lock gate.
      error = 'Could not load appearance settings. Choose them again to save.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> setMode(ThemeMode mode) => _save(mode, _palette);
  Future<bool> setPalette(AppPalette palette) => _save(_mode, palette);

  Future<bool> _save(ThemeMode mode, AppPalette palette) async {
    if (loading || saving) return false;
    saving = true;
    error = null;
    _notify();
    try {
      await storage.write(
        jsonEncode({'version': 1, 'mode': mode.name, 'palette': palette.name}),
      );
      _mode = mode;
      _palette = palette;
      return true;
    } catch (_) {
      error = 'Could not save appearance settings. Please try again.';
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
