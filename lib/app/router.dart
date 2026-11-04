import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../features/admin/audit_screen.dart';
import '../features/admin/config_screen.dart';
import '../features/admin/import_screen.dart';
import '../features/admin/users_screen.dart';
import '../features/auth/change_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/cotations/cotations_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/more/more_screen.dart';
import '../features/more/settings_screen.dart';
import '../features/quinzaines/quinzaines_screen.dart';
import '../features/taux/taux_screen.dart';
import '../features/importations/importations_screen.dart';
import '../features/importations/importation_detail_screen.dart';
import 'shell.dart';

const _adminPaths = ['/more/config', '/more/import', '/more/users', '/more/audit'];

/// Bridges Riverpod auth changes to go_router's refreshListenable.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (auth.initializing) return loc == '/splash' ? null : '/splash';
      if (!auth.isAuthenticated) {
        return loc == '/login' || loc == '/server' ? null : '/login';
      }
      if (auth.user!.mustChangePassword) {
        return loc == '/change-password' ? null : '/change-password';
      }
      if (loc == '/login' || loc == '/splash' || loc == '/change-password') {
        return '/dashboard';
      }
      if (!auth.isAdmin && _adminPaths.any(loc.startsWith)) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/server', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/change-password',
        builder: (_, _) => const ChangePasswordScreen(forced: true),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, _) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/quinzaines',
              builder: (_, _) => const QuinzainesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/cotations',
              builder: (_, _) => const CotationsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/taux', builder: (_, _) => const TauxScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/more',
              builder: (_, _) => const MoreScreen(),
              routes: [
                GoRoute(
                  path: 'config',
                  builder: (_, _) => const ConfigScreen(),
                ),
                GoRoute(
                  path: 'importations',
                  builder: (_, _) => const ImportationsScreen(),
                ),
                GoRoute(
                  path: 'importations/:id',
                  builder: (_, state) => ImportationDetailScreen(
                    id: int.parse(state.pathParameters['id']!),
                  ),
                ),
                GoRoute(
                  path: 'import',
                  builder: (_, _) => const ImportScreen(),
                ),
                GoRoute(
                  path: 'users',
                  builder: (_, _) => const UsersScreen(),
                ),
                GoRoute(
                  path: 'audit',
                  builder: (_, _) => const AuditScreen(),
                ),
                GoRoute(
                  path: 'settings',
                  builder: (_, _) => const SettingsScreen(),
                ),
                GoRoute(
                  path: 'password',
                  builder: (_, _) =>
                      const ChangePasswordScreen(forced: false),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});
