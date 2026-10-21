import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

const biometricReason = 'Confirmez votre identité pour vous connecter à BGI Pricing';

enum BiometricEnableResult { enabled, unavailable, cancelled }

class BiometricCredentials {
  const BiometricCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

/// Key/value store for the biometric login secret. Tests use an in-memory one.
abstract class CredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Device biometric prompt. Tests substitute a fake.
abstract class BiometricGate {
  Future<bool> get isAvailable;
  Future<bool> authenticate(String reason);
}

class LocalAuthGate implements BiometricGate {
  LocalAuthGate([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> get isAvailable async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    }
  }
}

class BiometricLogin {
  BiometricLogin({required this.store, required this.gate});

  static const _userKey = 'bgi_bio_user';
  static const _passKey = 'bgi_bio_pass';

  final CredentialStore store;
  final BiometricGate gate;

  Future<bool> get isEnabled async {
    final saved = await read();
    return saved != null;
  }

  Future<BiometricCredentials?> read() async {
    final username = await store.read(_userKey);
    final password = await store.read(_passKey);
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return null;
    }
    return BiometricCredentials(username: username, password: password);
  }

  /// Prompts for a fingerprint or Face ID, then saves [username] and [password].
  Future<BiometricEnableResult> enable({
    required String username,
    required String password,
  }) async {
    if (!await gate.isAvailable) return BiometricEnableResult.unavailable;
    if (!await gate.authenticate(biometricReason)) return BiometricEnableResult.cancelled;
    await store.write(_userKey, username);
    await store.write(_passKey, password);
    return BiometricEnableResult.enabled;
  }

  Future<void> disable() async {
    await store.delete(_userKey);
    await store.delete(_passKey);
  }

  /// Rewrites the saved secret after a password login, only when already enabled.
  Future<void> refreshIfEnabled(String username, String password) async {
    if (!await isEnabled) return;
    await store.write(_userKey, username);
    await store.write(_passKey, password);
  }

  /// Rewrites the saved password after an in-app change, only when already enabled.
  Future<void> updatePasswordIfEnabled(String password) async {
    if (!await isEnabled) return;
    await store.write(_passKey, password);
  }

  /// Prompts, then returns the saved credentials. Null if off, cancelled, or unavailable.
  Future<BiometricCredentials?> unlock() async {
    final saved = await read();
    if (saved == null) return null;
    if (!await gate.isAvailable) return null;
    if (!await gate.authenticate(biometricReason)) return null;
    return read();
  }
}

final biometricLoginProvider = Provider<BiometricLogin>(
  (ref) => BiometricLogin(store: SecureCredentialStore(), gate: LocalAuthGate()),
);

class BiometricLoginNotifier extends Notifier<bool> {
  @override
  bool build() {
    Future.microtask(reload);
    return false;
  }

  BiometricLogin get _login => ref.read(biometricLoginProvider);

  Future<void> reload() async {
    state = await _login.isEnabled;
  }

  Future<BiometricEnableResult> enable({
    required String username,
    required String password,
  }) async {
    final result = await _login.enable(username: username, password: password);
    state = await _login.isEnabled;
    return result;
  }

  Future<void> disable() async {
    await _login.disable();
    state = false;
  }
}

final biometricLoginNotifierProvider = NotifierProvider<BiometricLoginNotifier, bool>(
  BiometricLoginNotifier.new,
);
