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

    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(context, ref),
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_usersProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Text(
              '$recipients destinataire(s) de l’email quotidien',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            AsyncView(
              value: users,
              onRetry: () => ref.invalidate(_usersProvider),
              builder: (list) => Column(
                children: [for (final u in list) _UserCard(user: u, isMe: u.id == meId)],
              ),
            ),
          ],
        ),
      ),
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
          SelectableText(
            password,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (forced) ...[
            const SizedBox(height: 12),
            const Text(
              'Un email de bienvenue a été envoyé. L’utilisateur devra changer ce '
              'mot de passe à la prochaine connexion.',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: password));
            showToast(ctx, 'Copié');
          },
          child: const Text('Copier'),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${u.username}${isMe ? ' (vous)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(u.email, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ],
                  ),
                ),
                StatusChip(u.isActive ? 'Actif' : 'Inactif',
                    color: u.isActive ? AppColors.green : AppColors.muted),
                PopupMenuButton<String>(
                  onSelected: (v) => _action(context, ref, v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                    PopupMenuItem(value: 'force', enabled: !isMe, child: const Text('Forcer MDP')),
                    PopupMenuItem(
                      value: 'active',
                      enabled: !isMe,
                      child: Text(u.isActive ? 'Désactiver' : 'Activer'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: !isMe,
                      child: const Text('Supprimer', style: TextStyle(color: AppColors.red)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${u.role == 'admin' ? 'Administrateur' : 'Utilisateur'} · '
                  'Dernière connexion : ${u.lastLoginAt != null ? formatDate(u.lastLoginAt) : '—'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('Email quotidien', style: TextStyle(fontSize: 13))),
                Switch(
                  value: u.receivesDailyEmail,
                  onChanged: (v) => _patch(context, ref, {'receivesDailyEmail': v},
                      success: 'Utilisateur mis à jour'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
