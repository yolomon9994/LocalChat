import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

abstract class LockStorage {
  Future<String?> read();
  Future<void> write(String? value);
}

class SecureLockStorage implements LockStorage {
  static const _vault = FlutterSecureStorage();
  static const _key = 'app_lock_v1';

  @override
  Future<String?> read() => _vault.read(key: _key);

  @override
  Future<void> write(String? value) => value == null
      ? _vault.delete(key: _key)
      : _vault.write(key: _key, value: value);
}

/// Browser preview only. Configuration is discarded when the tab reloads.
class MemoryLockStorage implements LockStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? value) async => this.value = value;
}

abstract class Biometrics {
  Future<bool> available();
  Future<bool> authenticate();
  Future<void> cancel();
}

class DeviceBiometrics implements Biometrics {
  final _auth = LocalAuthentication();
  @override
  Future<bool> available() async =>
      await _auth.canCheckBiometrics &&
      (await _auth.getAvailableBiometrics()).isNotEmpty;
  @override
  Future<bool> authenticate() => _auth.authenticate(
    localizedReason: 'Unlock LocalChat',
    biometricOnly: true,
    persistAcrossBackgrounding: false,
  );
  @override
  Future<void> cancel() async {
    await _auth.stopAuthentication();
  }
}

class NoBiometrics implements Biometrics {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate() async => false;
  @override
  Future<void> cancel() async {}
}

typedef PinHasher = Future<List<int>> Function(String pin, List<int> salt);

Future<List<int>> _derivePin((String, List<int>) input) async =>
    (await Pbkdf2.hmacSha256(iterations: 600000, bits: 256).deriveKey(
      secretKey: SecretKey(utf8.encode(input.$1)),
      nonce: input.$2,
    )).extractBytes();

Future<List<int>> hashAppPin(String pin, List<int> salt) =>
    compute(_derivePin, (pin, salt));

enum AutoLockDelay {
  immediately(0, 'Immediately'),
  seconds30(30, '30 seconds'),
  minute1(60, '1 minute'),
  minutes5(300, '5 minutes');

  const AutoLockDelay(this.seconds, this.label);
  final int seconds;
  final String label;
}

class _LockRecord {
  const _LockRecord({
    required this.salt,
    required this.hash,
    this.biometrics = false,
    this.failures = 0,
    this.retryAt = 0,
    this.delay = AutoLockDelay.immediately,
  });
  final List<int> salt;
  final List<int> hash;
  final bool biometrics;
  final int failures;
  final int retryAt;
  final AutoLockDelay delay;

  factory _LockRecord.parse(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final salt = base64Decode(json['salt'] as String);
    final hash = base64Decode(json['hash'] as String);
    final failures = json['failures'] as int;
    final retryAt = json['retryAt'] as int;
    final version = json['version'];
    final seconds = version == 1 ? 0 : json['autoLockSeconds'];
    if (version is! int ||
        (version != 1 && version != 2) ||
        (version == 1 && json.containsKey('autoLockSeconds')) ||
        seconds is! int ||
        !AutoLockDelay.values.any((d) => d.seconds == seconds) ||
        json['iterations'] != 600000 ||
        salt.length != 32 ||
        hash.length != 32 ||
        failures < 0 ||
        failures > 4 ||
        retryAt < 0) {
      throw const FormatException('Invalid app lock configuration');
    }
    return _LockRecord(
      salt: salt,
      hash: hash,
      biometrics: json['biometrics'] as bool,
      failures: failures,
      retryAt: retryAt,
      delay: AutoLockDelay.values.singleWhere((d) => d.seconds == seconds),
    );
  }

  _LockRecord copy({
    bool? biometrics,
    int? failures,
    int? retryAt,
    AutoLockDelay? delay,
  }) => _LockRecord(
    salt: salt,
    hash: hash,
    biometrics: biometrics ?? this.biometrics,
    failures: failures ?? this.failures,
    retryAt: retryAt ?? this.retryAt,
    delay: delay ?? this.delay,
  );

  String encode() => jsonEncode({
    'version': 2,
    'autoLockSeconds': delay.seconds,
    'iterations': 600000,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
    'biometrics': biometrics,
    'failures': failures,
    'retryAt': retryAt,
  });
}

class AppLockController extends ChangeNotifier {
  AppLockController({
    required this.storage,
    required this.biometrics,
    this.isDemo = false,
    PinHasher? hasher,
    DateTime Function()? now,
    Duration Function()? elapsed,
    Future<void> Function(bool)? privacy,
  }) : _hasher = hasher ?? hashAppPin,
       _now = now ?? DateTime.now,
       _privacy = privacy ?? _noPrivacy {
    _elapsed = elapsed ?? () => _clock.elapsed;
  }

  static Future<void> _noPrivacy(bool enabled) async {}

  factory AppLockController.platform({required bool isDemo}) =>
      AppLockController(
        storage: isDemo ? MemoryLockStorage() : SecureLockStorage(),
        biometrics: isDemo ? NoBiometrics() : DeviceBiometrics(),
        isDemo: isDemo,
        privacy: isDemo
            ? null
            : (enabled) => const MethodChannel(
                'dev.localchat/privacy',
              ).invokeMethod<void>('setSecure', {'enabled': enabled}),
      );

  final LockStorage storage;
  final Biometrics biometrics;
  final bool isDemo;
  final PinHasher _hasher;
  final DateTime Function() _now;
  final Future<void> Function(bool) _privacy;
  final _clock = Stopwatch()..start();
  late final Duration Function() _elapsed;
  Timer? _graceTimer;
  DateTime? _leftAt;
  Duration? _leftElapsed;
  _LockRecord? _record;
  bool loading = true;
  bool locked = true;
  bool busy = false;
  bool biometricAvailable = false;
  bool _biometricPrompt = false;
  bool _foreground = true;
  int _generation = 0;
  bool _disposed = false;
  String? error;
  bool storageFailed = false;

  bool get enabled => _record != null;
  bool get biometricEnabled => _record?.biometrics ?? false;
  AutoLockDelay get autoLockDelay =>
      _record?.delay ?? AutoLockDelay.immediately;
  bool get covered => enabled && !_foreground;
  bool get canAccess =>
      !_disposed && !loading && !storageFailed && !locked && !covered;
  int get retrySeconds => max(
    0,
    (((_record?.retryAt ?? 0) - _now().millisecondsSinceEpoch) / 1000).ceil(),
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (busy || _disposed) return;
    _clearGrace();
    _generation++;
    busy = true;
    loading = true;
    locked = true;
    error = null;
    _notify();
    try {
      final saved = await storage.read();
      _record = saved == null ? null : _LockRecord.parse(saved);
      await _privacy(enabled);
      storageFailed = false;
      locked = enabled;
      try {
        biometricAvailable = await biometrics.available();
      } catch (_) {
        biometricAvailable = false;
      }
    } catch (_) {
      storageFailed = true;
      locked = true;
      error = 'Could not read app lock settings. Retry to continue.';
    } finally {
      loading = false;
      busy = false;
      _notify();
    }
  }

  static bool validPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

  Future<void> _save(_LockRecord? record) async {
    await _privacy(record != null);
    try {
      await storage.write(record?.encode());
    } catch (_) {
      await _privacy(enabled);
      rethrow;
    }
    _record = record;
  }

  Future<bool> _operation(Future<bool> Function(int generation) action) async {
    if (_disposed || busy || loading || storageFailed || !_foreground) {
      return false;
    }
    busy = true;
    error = null;
    final generation = _generation;
    _notify();
    try {
      return await action(generation);
    } catch (_) {
      // Storage/crypto failures never unlock or silently remove protection.
      error = 'Could not update app lock. Please try again.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<_LockRecord> _newPin(
    String pin, {
    bool biometrics = false,
    AutoLockDelay delay = AutoLockDelay.immediately,
  }) async {
    if (!validPin(pin)) throw const FormatException('Use a six-digit PIN');
    final random = Random.secure();
    final salt = List<int>.generate(32, (_) => random.nextInt(256));
    return _LockRecord(
      salt: salt,
      hash: await _hasher(pin, salt),
      biometrics: biometrics,
      delay: delay,
    );
  }

  Future<bool> enable(String pin) => _operation((generation) async {
    if (enabled || !canAccess || !validPin(pin)) return false;
    final record = await _newPin(pin);
    if (generation != _generation || !_foreground) return false;
    await _save(record);
    // If the app backgrounded during the write, its next view must be locked.
    locked = generation != _generation || !_foreground;
    return true;
  });

  Future<bool> _checkPin(String pin) async {
    final record = _record;
    if (record == null) return false;
    if (retrySeconds > 0) {
      error = 'Too many attempts. Try again in $retrySeconds seconds.';
      return false;
    }
    if (!validPin(pin)) {
      error = 'Enter your six-digit PIN.';
      return false;
    }
    final candidate = await _hasher(pin, record.salt);
    var difference = candidate.length ^ record.hash.length;
    for (var i = 0; i < record.hash.length; i++) {
      difference |= record.hash[i] ^ (i < candidate.length ? candidate[i] : 0);
    }
    if (difference == 0) {
      await _save(record.copy(failures: 0, retryAt: 0));
      return true;
    }
    final failures = record.failures + 1;
    await _save(
      record.copy(
        failures: failures >= 5 ? 0 : failures,
        retryAt: failures >= 5
            ? _now().add(const Duration(seconds: 30)).millisecondsSinceEpoch
            : 0,
      ),
    );
    error = failures >= 5
        ? 'Too many attempts. Try again in 30 seconds.'
        : 'Incorrect PIN. ${5 - failures} attempts before a short wait.';
    return false;
  }

  Future<bool> unlockPin(String pin) => _operation((generation) async {
    if (!locked || !await _checkPin(pin)) return false;
    if (generation != _generation || !_foreground) return false;
    locked = false;
    return true;
  });

  Future<bool> unlockBiometric() => _operation((generation) async {
    if (!locked || !biometricEnabled || !biometricAvailable) return false;
    _biometricPrompt = true;
    try {
      final accepted = await biometrics.authenticate();
      if (!accepted || generation != _generation) {
        error = 'Biometric unlock cancelled. Try again or use your PIN.';
        return false;
      }
      await _save(_record!.copy(failures: 0, retryAt: 0));
      if (generation != _generation) return false;
      locked = false;
      return true;
    } catch (_) {
      error = 'Biometric unlock unavailable. Use your app PIN.';
      return false;
    } finally {
      _biometricPrompt = false;
    }
  });

  Future<bool> changePin(String current, String replacement) => _operation((
    generation,
  ) async {
    if (!canAccess || !validPin(replacement) || !await _checkPin(current)) {
      return false;
    }
    final record = await _newPin(
      replacement,
      biometrics: biometricEnabled,
      delay: autoLockDelay,
    );
    if (generation != _generation || !canAccess || !_foreground) return false;
    await _save(record);
    return true;
  });

  Future<bool> disable(String current) => _operation((generation) async {
    if (!canAccess || !await _checkPin(current)) return false;
    if (generation != _generation || !canAccess || !_foreground) return false;
    await _save(null);
    locked = false;
    return true;
  });

  Future<bool> setBiometric(bool value, String current) => _operation((
    generation,
  ) async {
    if (!canAccess ||
        (value && !biometricAvailable) ||
        !await _checkPin(current)) {
      return false;
    }
    if (generation != _generation || !canAccess || !_foreground) return false;
    await _save(_record!.copy(biometrics: value));
    return true;
  });

  Future<bool> setAutoLockDelay(AutoLockDelay value, String current) =>
      _operation((generation) async {
        if (!enabled || !canAccess || !await _checkPin(current)) return false;
        if (generation != _generation || !canAccess || !_foreground) {
          return false;
        }
        await _save(_record!.copy(delay: value));
        return true;
      });

  void _clearGrace() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _leftAt = null;
    _leftElapsed = null;
  }

  bool get _withinGrace {
    if (_leftAt == null || _leftElapsed == null) return false;
    final wallAge = _now().difference(_leftAt!);
    final elapsedAge = _elapsed() - _leftElapsed!;
    final limit = Duration(seconds: autoLockDelay.seconds);
    // Either clock can expire the grant. A rollback never extends access.
    return !wallAge.isNegative &&
        !elapsedAge.isNegative &&
        wallAge < limit &&
        elapsedAge < limit;
  }

  void lock() {
    if (_disposed) return;
    _clearGrace();
    _generation++;
    if (enabled) locked = true;
    error = null;
    _notify();
  }

  void lifecycle(AppLifecycleState state) {
    if (_disposed) return;
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      if (_leftAt != null && !_withinGrace) {
        locked = enabled;
      }
      _clearGrace();
      _notify();
      return;
    }
    // The OS biometric dialog can briefly make the activity inactive.
    if (_biometricPrompt && state == AppLifecycleState.inactive) {
      _notify();
      return;
    }
    if (state == AppLifecycleState.detached) {
      lock();
    } else if (enabled &&
        !locked &&
        !busy &&
        wasForeground &&
        autoLockDelay != AutoLockDelay.immediately) {
      _generation++;
      _leftAt = _now();
      _leftElapsed = _elapsed();
      _graceTimer = Timer(Duration(seconds: autoLockDelay.seconds), lock);
      error = null;
      _notify();
    } else if (_leftAt != null) {
      // Inactive -> hidden -> paused is one absence, not three new grants.
      _notify();
    } else {
      lock();
    }
    if (_biometricPrompt) {
      biometrics.cancel().catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _clearGrace();
    _generation++;
    _foreground = false;
    _clock.stop();
    _disposed = true;
    super.dispose();
  }
}
