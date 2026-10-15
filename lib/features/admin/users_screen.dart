import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';

final _usersProvider = FutureProvider.autoDispose<List<UserRow>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/users');
  return (res as List).map((e) => UserRow(e as Json)).toList();
});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(_usersProvider);
    final meId = ref.watch(authProvider).user?.id;
    final recipients =
        users.value?.where((u) => u.isActive && u.receivesDailyEmail).length ?? 0;

    return PageScaffold(
      title: 'Utilisateurs',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Utilisateur'),
      ),
      onRefresh: () => ref.refresh(_usersProvider.future),
      children: [
        KpiGrid(children: [
          KpiCard(
            label: 'Comptes',
            value: '${users.value?.length ?? '—'}',
            sub: '${users.value?.where((u) => u.isActive).length ?? 0} actif(s)',
            icon: Icons.group_outlined,
          ),
          KpiCard(
            label: 'Email quotidien',
            value: '$recipients',
            sub: 'destinataire(s)',
            icon: Icons.mark_email_read_outlined,
          ),
        ]),
        AsyncView(
          value: users,
          onRetry: () => ref.invalidate(_usersProvider),
          builder: (list) => Column(
            children: [for (final u in list) _UserCard(user: u, isMe: u.id == meId)],
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Nouvel utilisateur',
      builder: (_) => const _UserForm(),
    );
    if (body == null || !context.mounted) return;
    final created = await runAction(
      context,
      () async => UserRow(await ref.read(apiClientProvider).post('/users', body: body) as Json),
      success: 'Utilisateur créé',
    );
    ref.invalidate(_usersProvider);
    if (created?.temporaryPassword != null && context.mounted) {
      await showTempPassword(context, created!.temporaryPassword!, forced: false);
    }
  }
}

Future<void> showTempPassword(BuildContext context, String password, {required bool forced}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Mot de passe temporaire'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Affiché une seule fois :'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ctx.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              password,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          if (forced) ...[
            const SizedBox(height: 12),
            Text(
              'Un email de bienvenue a été envoyé. L’utilisateur devra changer ce '
              'mot de passe à la prochaine connexion.',
              style: TextStyle(color: ctx.palette.textMuted),
            ),
          ],
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: password));
            showToast(ctx, 'Copié');
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copier'),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
      ],
    ),
  );
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user, required this.isMe});

  final UserRow user;
  final bool isMe;

  Future<UserRow?> _patch(BuildContext context, WidgetRef ref, Map<String, dynamic> body,
      {String? success}) async {
    final res = await runAction(
      context,
      () async =>
          UserRow(await ref.read(apiClientProvider).patch('/users/${user.id}', body: body) as Json),
      success: success,
    );
    ref.invalidate(_usersProvider);
    return res;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = user;
    final p = context.palette;
    final admin = u.role == 'admin';
    final avatarColor = admin ? p.accent : p.seriesAt(u.id % p.chartSeries.length);
    return ListCard(
      leading: Opacity(
        opacity: u.isActive ? 1 : 0.5,
        child: CircleAvatar(
          radius: 22,
          backgroundColor: p.tint(avatarColor),
          child: Text(
            _initials(u.username),
            style: TextStyle(color: avatarColor, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      title: Text('${u.username}${isMe ? ' (vous)' : ''}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(u.email, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              StatusChip(admin ? 'Administrateur' : 'Utilisateur', color: admin ? p.accent : p.info),
              StatusChip(u.isActive ? 'Actif' : 'Inactif', color: u.isActive ? p.success : p.textMuted),
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, color: p.textMuted),
        onSelected: (v) => _action(context, ref, v),
        itemBuilder: (_) => [
          menuItem('edit', Icons.edit_outlined, 'Modifier'),
          menuItem('force', Icons.key_rounded, 'Forcer MDP', enabled: !isMe),
          menuItem(
            'active',
            u.isActive ? Icons.person_off_outlined : Icons.person_outline_rounded,
            u.isActive ? 'Désactiver' : 'Activer',
            enabled: !isMe,
          ),
          menuItem('delete', Icons.delete_outline_rounded, 'Supprimer', enabled: !isMe, danger: true),
        ],
      ),
      footer: Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 15, color: p.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Connexion : ${u.lastLoginAt != null ? formatDate(u.lastLoginAt) : '—'}',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
            ),
            Icon(Icons.mail_outline_rounded, size: 16, color: p.textMuted),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: u.receivesDailyEmail,
                onChanged: (v) =>
                    _patch(context, ref, {'receivesDailyEmail': v}, success: 'Utilisateur mis à jour'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.split(RegExp(r'[\s._-]+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(1, 2)).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<void> _action(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'edit':
        final body = await showFormSheet<Map<String, dynamic>>(
          context,
          title: 'Modifier ${user.username}',
          builder: (_) => _UserForm(initial: user),
        );
        if (body == null || !context.mounted) return;
        await _patch(context, ref, body, success: 'Utilisateur mis à jour');
      case 'force':
        if (!await confirmDialog(
              context,
              'Forcer un nouveau mot de passe pour ${user.username} ? Un email de bienvenue sera envoyé.',
            ) ||
            !context.mounted) {
          return;
        }
        final res = await _patch(context, ref, {'forcePassword': true},
            success: 'Mot de passe forcé — email envoyé');
        if (res?.temporaryPassword != null && context.mounted) {
          await showTempPassword(context, res!.temporaryPassword!, forced: true);
        }
      case 'active':
        await _patch(context, ref, {'isActive': !user.isActive}, success: 'Utilisateur mis à jour');
      case 'delete':
        if (!await confirmDialog(context, 'Supprimer ${user.username} ?',
                confirmLabel: 'Supprimer', danger: true) ||
            !context.mounted) {
          return;
        }
        await runAction(context, () => ref.read(apiClientProvider).delete('/users/${user.id}'),
            success: 'Utilisateur supprimé');
        ref.invalidate(_usersProvider);
    }
  }
}

class _UserForm extends StatefulWidget {
  const _UserForm({this.initial});

  final UserRow? initial;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  late final _username = TextEditingController(text: widget.initial?.username ?? '');
  late final _email = TextEditingController(text: widget.initial?.email ?? '');
  late String _role = widget.initial?.role ?? 'user';
  late bool _daily = widget.initial?.receivesDailyEmail ?? false;

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim();
    if (!_editing && _username.text.trim().length < 3) {
      showToast(context, 'Identifiant : au moins 3 caractères', error: true);
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showToast(context, 'Email invalide', error: true);
      return;
    }
    Navigator.pop(context, {
      if (!_editing) 'username': _username.text.trim(),
      'email': email,
      'role': _role,
      'receivesDailyEmail': _daily,
    });
  }

  @override
  Widget build(BuildContext context) {
    final inactive = _editing && !widget.initial!.isActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _username,
          enabled: !_editing,
          decoration: const InputDecoration(labelText: 'Identifiant'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Rôle',
          value: _role,
          items: const {'user': 'Utilisateur', 'admin': 'Administrateur'},
          onChanged: (v) => setState(() => _role = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reçoit l’email quotidien'),
          subtitle: Text(inactive
              ? 'Compte inactif : aucun email tant qu’il n’est pas réactivé'
              : 'Rapport des prix envoyé chaque jour ouvré'),
          value: _daily,
          onChanged: (v) => setState(() => _daily = v),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _submit, child: Text(_editing ? 'Enregistrer' : 'Créer')),
      ],
    );
  }
}
