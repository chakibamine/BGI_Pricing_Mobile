import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_client.dart';

class AuthState {
  const AuthState({this.user, this.initializing = false, this.notice});

  final AuthUser? user;
  final bool initializing;

  /// Message shown on the login screen (e.g. session expired).
  final String? notice;

  bool get isAuthenticated => user != null;
  bool get isAdmin => user?.isAdmin ?? false;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    ref.read(unauthorizedHandlerProvider).callback = _sessionExpired;
    Future.microtask(_restore);
    return const AuthState(initializing: true);
  }

  ApiClient get _api => ref.read(apiClientProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  Future<void> _restore() async {
    final token = await _tokens.read();
    if (token == null) {
      state = const AuthState();
      return;
    }
    try {
      state = AuthState(user: await _fetchMe());
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _tokens.clear();
        state = const AuthState();
      } else {
        // Keep the token (VPN may just be down); let the user retry from login.
        state = AuthState(notice: e.message);
      }
    }
  }

  Future<AuthUser> _fetchMe() async =>
      AuthUser.fromJson(await _api.get('/auth/me') as Json);

  Future<void> login(String username, String password) async {
    final res = await _api.post(
      '/auth/login',
      body: {'username': username, 'password': password},
    ) as Json;
    await _tokens.write(res['accessToken'] as String);
    final me = await _fetchMe();
    state = AuthState(
      user: me.copyWith(
        mustChangePassword:
            res['mustChangePassword'] == true || me.mustChangePassword,
      ),
    );
  }

  Future<void> changePassword(String current, String next) async {
    await _api.post(
      '/auth/change-password',
      body: {'currentPassword': current, 'newPassword': next},
    );
    final user = state.user;
    if (user != null) {
      state = AuthState(user: user.copyWith(mustChangePassword: false));
    }
  }

  Future<void> logout() async {
    await _tokens.clear();
    state = const AuthState();
  }

  void _sessionExpired() {
    if (state.user == null) return;
    _tokens.clear();
    state = const AuthState(notice: 'Session expirée, reconnectez-vous.');
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(authProvider.select((s) => s.isAdmin)),
);
