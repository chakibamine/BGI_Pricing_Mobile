import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production API on the company network (reachable through the VPN).
const defaultApiUrl = 'http://10.10.2.10:3000';

const apiUrlPresets = <String, String>{
  'Production (VPN)': defaultApiUrl,
  'Émulateur Android (API locale)': 'http://10.0.2.2:3000',
};

const _apiUrlKey = 'api_url';

/// Overridden in main() once SharedPreferences is loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

class ApiUrlNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.read(sharedPreferencesProvider).getString(_apiUrlKey) ??
      defaultApiUrl;

  Future<void> set(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    await ref.read(sharedPreferencesProvider).setString(_apiUrlKey, clean);
    state = clean;
  }
}

final apiUrlProvider = NotifierProvider<ApiUrlNotifier, String>(
  ApiUrlNotifier.new,
);

const _themeModeKey = 'theme_mode';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_themeModeKey);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

String envLabelFor(String url) {
  if (url == defaultApiUrl) return 'PRODUCTION';
  if (url.contains('10.0.2.2') || url.contains('localhost')) return 'LOCAL';
  return 'PERSONNALISÉ';
}
