import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/quinzaine.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/models.dart';

final _ratesProvider = FutureProvider.autoDispose
    .family<List<ExchangeRate>, ({String from, String to})>((ref, k) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/exchange-rates', query: {'dateFrom': k.from, 'dateTo': k.to});
  return (res as List).map((e) => ExchangeRate.fromJson(e as Json)).toList();
});

class TauxScreen extends ConsumerStatefulWidget {
  const TauxScreen({super.key});

  @override
  ConsumerState<TauxScreen> createState() => _TauxScreenState();
}

class _TauxScreenState extends ConsumerState<TauxScreen> {
  static const _pageSize = 25;

  String _from = '';
  String _to = '';
  String _source = '';
  int _shown = _pageSize;
  bool _busy = false;

  ({String from, String to}) get _key => (from: _from, to: _to);

  void _update(VoidCallback change) => setState(() {
        change();
        _shown = _pageSize;
      });

  void _refreshData() {
    ref.invalidate(_ratesProvider);
    invalidatePricing(ref);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final rates = ref.watch(_ratesProvider(_key));
    final data = rates.value ?? const <ExchangeRate>[];
    final sources = {...data.map((r) => r.source)}.toList()..sort();
    final hasFilters = _from.isNotEmpty || _to.isNotEmpty || _source.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Taux USD/MAD'),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              enabled: !_busy,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.more_vert),
              onSelected: (v) => v == 'fetch' ? _fetchToday() : _backfill(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'fetch', child: Text('Récupérer Bank Al-Maghrib (BDT)')),
                PopupMenuItem(value: 'backfill', child: Text('Backfill BDT')),
              ],
            ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: _upsert,
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshData();
          await ref.read(_ratesProvider(_key).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DateField(label: 'Du', value: _from, onChanged: (v) => _update(() => _from = v)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DateField(label: 'Au', value: _to, onChanged: (v) => _update(() => _to = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LabeledDropdown<String>(
                    key: ValueKey('src-${sources.join()}'),
                    label: 'Source',
                    value: sources.contains(_source) ? _source : '',
                    items: {'': 'Toutes', for (final s in sources) s: s},
                    onChanged: (v) => _update(() => _source = v),
                  ),
                  if (hasFilters)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _update(() => _from = _to = _source = ''),
                        child: const Text('Réinitialiser'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AsyncView(
              value: rates,
              onRetry: () => ref.invalidate(_ratesProvider(_key)),
              builder: (data) => _list(data, isAdmin, hasFilters),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<ExchangeRate> data, bool isAdmin, bool hasFilters) {
    final filtered = _source.isEmpty ? data : data.where((r) => r.source == _source).toList();
    if (filtered.isEmpty) {
      return EmptyState(hasFilters ? 'Aucun taux pour ces filtres' : 'Aucun taux');
    }
    final stats = <String, ({int count, double sum})>{};
    for (final r in filtered) {
      final key = quinzaineOf(r.rateDate).key;
      final s = stats[key] ?? (count: 0, sum: 0.0);
      stats[key] = (count: s.count + 1, sum: s.sum + r.usdMadRate);
    }
    final page = filtered.take(_shown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in withQuinzaineHeaders(page, (r) => r.rateDate))
          switch (item) {
            GroupHeader(:final quinzaine) => QuinzaineHeaderTile(
                label: quinzaine.label,
                window: quinzaine.windowLabel,
                meta: [
                  if (stats[quinzaine.key] case final s?)
                    '${s.count} taux · Moyenne ${formatValue(s.sum / s.count)}',
                ],
              ),
            GroupItem(:final row) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text(formatDate(row.rateDate), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(row.source),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatValue(row.usdMadRate),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.red),
                          onPressed: () => _delete(row),
                        ),
                    ],
                  ),
                ),
              ),
          },
        LoadMoreButton(
          shown: page.length,
          total: filtered.length,
          onPressed: () => setState(() => _shown += _pageSize),
        ),
      ],
    );
  }

  Future<void> _fetchToday() async {
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => await ref.read(apiClientProvider).post('/exchange-rates/fetch-today') as Json,
    );
    if (mounted) setState(() => _busy = false);
    if (res == null || !mounted) return;
    switch (res['status']) {
      case 'ok':
        showToast(context, 'BDT OK : ${formatDate(res['date'] as String?)} → ${formatValue(toDouble(res['rate']))} MAD');
      case 'no_data':
        showToast(context, 'BDT : aucune donnée publiée pour ${res['date'] ?? 'aujourd’hui'}');
      default:
        showToast(context, 'BDT : week-end — pas de cours');
    }
    _refreshData();
  }

  Future<void> _backfill() async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Backfill Bank Al-Maghrib (BDT)',
      builder: (_) => const _RangeForm(),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => await ref.read(apiClientProvider).post('/exchange-rates/backfill', body: body) as Json,
    );
    if (mounted) setState(() => _busy = false);
    if (res != null && mounted) {
      showToast(context, 'Backfill BDT terminé : ${res['imported'] ?? 0} taux importé(s)');
    }
    _refreshData();
  }

  Future<void> _upsert() async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Taux USD/MAD',
      builder: (_) => const _UpsertForm(),
    );
    if (body == null || !mounted) return;
    await runAction(
      context,
      () => ref.read(apiClientProvider).post('/exchange-rates', body: body),
      success: 'Taux enregistré',
    );
    _refreshData();
  }

  Future<void> _delete(ExchangeRate r) async {
    if (!await confirmDialog(context, 'Supprimer ce taux ?', confirmLabel: 'Supprimer', danger: true) ||
        !mounted) {
      return;
    }
    await runAction(
      context,
      () => ref.read(apiClientProvider).delete('/exchange-rates/${r.id}'),
      success: 'Taux supprimé',
    );
    _refreshData();
  }
}

class _UpsertForm extends StatefulWidget {
  const _UpsertForm();

  @override
  State<_UpsertForm> createState() => _UpsertFormState();
}

class _UpsertFormState extends State<_UpsertForm> {
  String _date = isoDate(DateTime.now());
  final _rate = TextEditingController();

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DateField(label: 'Date', value: _date, clearable: false, onChanged: (v) => setState(() => _date = v)),
        const SizedBox(height: 12),
        TextField(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Taux'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final v = parseDecimal(_rate.text);
            if (v == null || v <= 0) {
              showToast(context, 'Taux invalide', error: true);
              return;
            }
            Navigator.pop(context, {'rateDate': _date, 'usdMadRate': v});
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _RangeForm extends StatefulWidget {
  const _RangeForm();

  @override
  State<_RangeForm> createState() => _RangeFormState();
}

class _RangeFormState extends State<_RangeForm> {
  String _from = '';
  String _to = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Maximum 100 jours calendaires. Un seul backfill à la fois.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        DateField(label: 'Du', value: _from, onChanged: (v) => setState(() => _from = v)),
        const SizedBox(height: 12),
        DateField(label: 'Au', value: _to, onChanged: (v) => setState(() => _to = v)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _from.isEmpty || _to.isEmpty
              ? null
              : () => Navigator.pop(context, {'dateFrom': _from, 'dateTo': _to}),
          child: const Text('Lancer'),
        ),
      ],
    );
  }
}
