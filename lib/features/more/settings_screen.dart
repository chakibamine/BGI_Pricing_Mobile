import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _url;
  bool _testing = false;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ref.read(apiUrlProvider));
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Any HTTP answer (even 401) means the API is reachable.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      ).get<dynamic>('$url/auth/me');
      _ok = true;
      _result = 'Serveur joignable (HTTP ${res.statusCode})';
    } catch (_) {
      _ok = false;
      _result =
          'Serveur injoignable. Vérifiez la connexion VPN et l’adresse.';
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (!RegExp(r'^https?://').hasMatch(url)) {
      showToast(context, 'L’adresse doit commencer par http:// ou https://',
          error: true);
      return;
    }
    await ref.read(apiUrlProvider.notifier).set(url);
    if (mounted) showToast(context, 'Adresse du serveur enregistrée');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final current = ref.watch(apiUrlProvider);
    return PageScaffold(
      title: 'Serveur',
      children: [
        Panel(
          title: 'Adresse de l’API',
          subtitle: current,
          icon: Icons.dns_rounded,
          trailing: StatusChip(
            envLabelFor(current),
            color: current == defaultApiUrl ? p.success : p.warning,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'http://10.10.2.10:3000',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final e in apiUrlPresets.entries)
                    ActionChip(
                      avatar: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(e.key),
                      onPressed: () => setState(() => _url.text = e.value),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_result != null)
                InfoBanner(_result!, kind: _ok ? BannerKind.success : BannerKind.error),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.network_check_rounded, size: 18),
                      label: Text(_testing ? 'Test…' : 'Tester'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const InfoBanner(
          'L’application accède à l’API de production via le VPN de '
          'l’entreprise. Connectez le VPN avant d’ouvrir l’application.',
          kind: BannerKind.info,
        ),
      ],
    );
  }
}
