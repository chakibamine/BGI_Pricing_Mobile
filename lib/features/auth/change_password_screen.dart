import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, required this.forced});

  /// First login: the user cannot leave the screen except by logging out.
  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 8) {
      setState(() => _error = 'Le nouveau mot de passe doit contenir au moins 8 caractères');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).changePassword(_current.text, _next.text);
      if (!mounted) return;
      showToast(context, 'Mot de passe modifié');
      if (!widget.forced) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mot de passe'),
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced)
            TextButton.icon(
              onPressed: () => ref.read(authProvider.notifier).logout(),
              icon: Icon(Icons.logout_rounded, size: 18, color: p.danger),
              label: Text('Déconnexion', style: TextStyle(color: p.danger)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: IconBubble(Icons.lock_reset_rounded, color: p.accent, size: 64)),
          const SizedBox(height: 14),
          Text('Changer le mot de passe', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Au moins 8 caractères',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textMuted),
          ),
          const SizedBox(height: 20),
          if (widget.forced) const InfoBanner('Vous devez définir un nouveau mot de passe avant de continuer.'),
          if (_error != null) InfoBanner(_error!, kind: BannerKind.error),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe actuel',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _next,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le nouveau mot de passe',
                    prefixIcon: Icon(Icons.check_circle_outline_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(_busy ? 'Enregistrement…' : 'Enregistrer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
