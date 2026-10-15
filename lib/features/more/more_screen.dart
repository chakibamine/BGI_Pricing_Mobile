import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/splash_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin ?? false;
    final url = ref.watch(apiUrlProvider);
    final initial = (user?.username.isNotEmpty ?? false) ? user!.username[0].toUpperCase() : '?';

    return PageScaffold(
      title: 'Plus',
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: brandGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.amberBright, AppColors.amber]),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.username ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user?.email ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAdmin ? 'Admin' : 'Utilisateur',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (isAdmin) ...[
          const SectionLabel('Administration'),
          _Group(children: [
            _Tile(Icons.tune_rounded, p.info, 'Configurations', 'Primes, marges et paramètres', () => context.go('/more/config')),
            _Tile(Icons.upload_file_rounded, p.success, 'Import', 'Excel, Platts et BKAM', () => context.go('/more/import')),
            _Tile(Icons.group_outlined, p.violet, 'Utilisateurs', 'Comptes et rôles', () => context.go('/more/users')),
            _Tile(Icons.history_rounded, p.warning, 'Journal d’audit', 'Historique des modifications', () => context.go('/more/audit')),
          ]),
        ],
        const SectionLabel('Apparence'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: cardDecoration(p),
          child: const SizedBox(width: double.infinity, child: ThemeModePicker()),
        ),
        const SectionLabel('Compte'),
        _Group(children: [
          _Tile(Icons.dns_rounded, p.primary, 'Serveur', url, () => context.go('/more/settings')),
          _Tile(Icons.password_rounded, p.textMuted, 'Changer le mot de passe', null, () => context.go('/more/password')),
          _Tile(
            Icons.logout_rounded,
            p.danger,
            'Déconnexion',
            null,
            () async {
              if (await confirmDialog(context, 'Se déconnecter ?', confirmLabel: 'Déconnexion', danger: true)) {
                await ref.read(authProvider.notifier).logout();
              }
            },
            danger: true,
          ),
        ]),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: cardDecoration(p),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 64, color: p.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.color, this.label, this.sub, this.onTap, {this.danger = false});

  final IconData icon;
  final Color color;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: IconBubble(icon, color: color),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: danger ? p.danger : p.textPrimary),
      ),
      subtitle: sub == null ? null : Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: danger ? null : Icon(Icons.chevron_right_rounded, color: p.textMuted),
      onTap: onTap,
    );
  }
}
