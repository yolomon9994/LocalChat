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

enum AppTextSize {
  system('Follow system', 1),
  larger('Larger (+15%)', 1.15),
  largest('Largest (+30%)', 1.3);

  const AppTextSize(this.label, this.multiplier);
  final String label;
  final double multiplier;

  TextScaler applyTo(TextScaler system) =>
      multiplier == 1 ? system : _EnlargedTextScaler(system, multiplier);
}

/// Enlarge the platform's result, preserving nonlinear scaling and never
/// replacing or capping the user's device text preference.
class _EnlargedTextScaler extends TextScaler {
  const _EnlargedTextScaler(this.system, this.multiplier);
  final TextScaler system;
  final double multiplier;
  @override
  double scale(double fontSize) => system.scale(fontSize) * multiplier;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is _EnlargedTextScaler &&
      system == other.system &&
      multiplier == other.multiplier;
  @override
  int get hashCode => Object.hash(system, multiplier);
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

ThemeData buildAppTheme(
  AppPalette palette,
  Brightness brightness, {
  bool highContrast = false,
}) => ThemeData(
  useMaterial3: true,
  colorScheme: _colors(palette, brightness, highContrast),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    filled: true,
  ),
  appBarTheme: const AppBarTheme(centerTitle: false),
);

ColorScheme _colors(AppPalette palette, Brightness brightness, bool enhanced) {
  final base = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: brightness,
  );
  if (!enhanced) return base;
  final high = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: brightness,
    contrastLevel: 1,
  );
  double contrast(Color foreground, Color background) {
    final a = foreground.computeLuminance(), b = background.computeLuminance();
    return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
  }

  // Material's enhanced containers can invert their tones. Keep an existing
  // pair when it already offers more contrast (especially light chat bubbles).
  bool keep(Color a, Color b, Color x, Color y) =>
      contrast(a, b) > contrast(x, y);
  final primary = keep(
    base.onPrimaryContainer,
    base.primaryContainer,
    high.onPrimaryContainer,
    high.primaryContainer,
  );
  final secondary = keep(
    base.onSecondaryContainer,
    base.secondaryContainer,
    high.onSecondaryContainer,
    high.secondaryContainer,
  );
  final tertiary = keep(
    base.onTertiaryContainer,
    base.tertiaryContainer,
    high.onTertiaryContainer,
    high.tertiaryContainer,
  );
  final error = keep(
    base.onErrorContainer,
    base.errorContainer,
    high.onErrorContainer,
    high.errorContainer,
  );
  return high.copyWith(
    primaryContainer: primary ? base.primaryContainer : high.primaryContainer,
    onPrimaryContainer: primary
        ? base.onPrimaryContainer
        : high.onPrimaryContainer,
    secondaryContainer: secondary
        ? base.secondaryContainer
        : high.secondaryContainer,
    onSecondaryContainer: secondary
        ? base.onSecondaryContainer
        : high.onSecondaryContainer,
    tertiaryContainer: tertiary
        ? base.tertiaryContainer
        : high.tertiaryContainer,
    onTertiaryContainer: tertiary
        ? base.onTertiaryContainer
        : high.onTertiaryContainer,
    errorContainer: error ? base.errorContainer : high.errorContainer,
    onErrorContainer: error ? base.onErrorContainer : high.onErrorContainer,
  );
}

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
  AppTextSize _textSize = AppTextSize.system;
  bool _highContrast = false;
  bool loading = true;
  bool saving = false;
  bool _disposed = false;
  String? error;

  ThemeMode get mode => _mode;
  AppPalette get palette => _palette;
  AppTextSize get textSize => _textSize;
  bool get highContrast => _highContrast;

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
        if (json['version'] != 1 && json['version'] != 2) {
          throw const FormatException('Unsupported appearance');
        }
        final mode = ThemeMode.values.byName(json['mode'] as String);
        final palette = AppPalette.values.byName(json['palette'] as String);
        // Old theme-only preferences keep their exact mode/palette.
        final textSize = json['version'] == 1
            ? AppTextSize.system
            : AppTextSize.values.byName(json['textSize'] as String);
        final highContrast = json['version'] == 1
            ? false
            : json['highContrast'] as bool;
        _mode = mode;
        _palette = palette;
        _textSize = textSize;
        _highContrast = highContrast;
      }
    } catch (_) {
      // Preferences never bypass or block the independent app-lock gate.
      error = 'Could not load appearance settings. Choose them again to save.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> setMode(ThemeMode mode) =>
      _save(mode, _palette, _textSize, _highContrast);
  Future<bool> setPalette(AppPalette palette) =>
      _save(_mode, palette, _textSize, _highContrast);
  Future<bool> setTextSize(AppTextSize textSize) =>
      _save(_mode, _palette, textSize, _highContrast);
  Future<bool> setHighContrast(bool highContrast) =>
      _save(_mode, _palette, _textSize, highContrast);

  Future<bool> _save(
    ThemeMode mode,
    AppPalette palette,
    AppTextSize textSize,
    bool highContrast,
  ) async {
    if (_disposed || loading || saving) return false;
    saving = true;
    error = null;
    _notify();
    try {
      await storage.write(
        jsonEncode({
          'version': 2,
          'mode': mode.name,
          'palette': palette.name,
          'textSize': textSize.name,
          'highContrast': highContrast,
        }),
      );
      _mode = mode;
      _palette = palette;
      _textSize = textSize;
      _highContrast = highContrast;
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
