import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin ?? false;
    final url = ref.watch(apiUrlProvider);

    Widget tile(IconData icon, String label, String path, {String? sub}) =>
        ListTile(
          leading: Icon(icon, color: AppColors.navy),
          title: Text(label),
          subtitle: sub == null ? null : Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(path),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Plus')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.amber,
              child: Text(
                (user?.username.isNotEmpty ?? false)
                    ? user!.username[0].toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(user?.username ?? ''),
            subtitle: Text(user?.email ?? ''),
            trailing: StatusChip(
              isAdmin ? 'Admin' : 'Utilisateur',
              color: isAdmin ? AppColors.amber : AppColors.muted,
            ),
          ),
          const Divider(),
          if (isAdmin) ...[
            const _Section('Administration'),
            tile(Icons.tune, 'Configurations', '/more/config'),
            tile(Icons.upload_file, 'Import', '/more/import'),
            tile(Icons.people_outline, 'Utilisateurs', '/more/users'),
            tile(Icons.history, 'Journal d’audit', '/more/audit'),
            const Divider(),
          ],
          const _Section('Compte'),
          tile(Icons.dns_outlined, 'Serveur', '/more/settings', sub: url),
          tile(Icons.password, 'Changer le mot de passe', '/more/password'),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.red),
            title: const Text(
              'Déconnexion',
              style: TextStyle(color: AppColors.red),
            ),
            onTap: () async {
              if (await confirmDialog(context, 'Se déconnecter ?',
                  confirmLabel: 'Déconnexion')) {
                await ref.read(authProvider.notifier).logout();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
