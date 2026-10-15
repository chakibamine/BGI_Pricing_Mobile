import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'splash_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Identifiant et mot de passe requis');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_username.text.trim(), _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final notice = ref.watch(authProvider.select((s) => s.notice));
    final url = ref.watch(apiUrlProvider);
    final env = envLabelFor(url);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: p.background,
        systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            Container(
              height: 340,
              decoration: const BoxDecoration(
                gradient: brandGradient,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BrandMark(),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: p.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: p.isDark ? Border.all(color: p.border) : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: p.isDark ? 0.4 : 0.10),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Connexion', style: Theme.of(context).textTheme.headlineSmall),
                                const SizedBox(height: 4),
                                Text(
                                  'Accédez à vos prix d’achat et cotations',
                                  style: TextStyle(color: p.textMuted, fontSize: 13.5),
                                ),
                                const SizedBox(height: 20),
                                if (_error != null || notice != null)
                                  InfoBanner(
                                    _error ?? notice!,
                                    kind: _error != null ? BannerKind.error : BannerKind.warning,
                                  ),
                                TextField(
                                  controller: _username,
                                  autofillHints: const [AutofillHints.username],
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Identifiant',
                                    prefixIcon: Icon(Icons.person_outline_rounded),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  autofillHints: const [AutofillHints.password],
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Mot de passe',
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                      ),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                FilledButton(
                                  onPressed: _busy ? null : _submit,
                                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                                  child: _busy
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimary),
                                        )
                                      : const Text('Se connecter'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: ActionChip(
                            onPressed: () => context.push('/server'),
                            avatar: Icon(Icons.dns_rounded, size: 18, color: p.textMuted),
                            label: Text(
                              '$env · $url',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.textMuted, fontSize: 12.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
