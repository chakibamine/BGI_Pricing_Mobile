import 'package:bgi_pricing_mobile/core/biometric_login.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements CredentialStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeGate implements BiometricGate {
  _FakeGate({this.available = true, this.accept = true});

  bool available;
  bool accept;
  int prompts = 0;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accept;
  }
}

void main() {
  test('enable saves the secret only after a successful prompt', () async {
    final store = _MemoryStore();
    final gate = _FakeGate();
    final login = BiometricLogin(store: store, gate: gate);

    expect(await login.isEnabled, isFalse);
    expect(
      await login.enable(username: 'amine', password: 'secret'),
      BiometricEnableResult.enabled,
    );
    expect(gate.prompts, 1);
    expect(await login.isEnabled, isTrue);
    final saved = await login.read();
    expect(saved?.username, 'amine');
    expect(saved?.password, 'secret');
  });

  test('disable deletes the secret', () async {
    final store = _MemoryStore();
    final login = BiometricLogin(store: store, gate: _FakeGate());
    await login.enable(username: 'amine', password: 'secret');

    await login.disable();

    expect(await login.isEnabled, isFalse);
    expect(await login.read(), isNull);
    expect(store.values, isEmpty);
  });

  test('a cancelled prompt or a missing sensor does not save anything', () async {
    final cancelled = BiometricLogin(store: _MemoryStore(), gate: _FakeGate(accept: false));
    expect(
      await cancelled.enable(username: 'amine', password: 'secret'),
      BiometricEnableResult.cancelled,
    );
    expect(await cancelled.isEnabled, isFalse);

    final missing = BiometricLogin(store: _MemoryStore(), gate: _FakeGate(available: false));
    expect(
      await missing.enable(username: 'amine', password: 'secret'),
      BiometricEnableResult.unavailable,
    );
    expect(await missing.isEnabled, isFalse);
    expect(await missing.unlock(), isNull);
  });

  test('password updates apply only while login is enabled', () async {
    final store = _MemoryStore();
    final login = BiometricLogin(store: store, gate: _FakeGate());

    await login.refreshIfEnabled('amine', 'secret');
    await login.updatePasswordIfEnabled('newer');
    expect(store.values, isEmpty);

    await login.enable(username: 'amine', password: 'secret');
    await login.refreshIfEnabled('sara', 'other');
    expect((await login.read())?.username, 'sara');
    expect((await login.read())?.password, 'other');

    await login.updatePasswordIfEnabled('changed');
    expect((await login.read())?.username, 'sara');
    expect((await login.read())?.password, 'changed');
  });
}
