import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/charts.dart';
import '../../core/export.dart';
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

typedef _Filters = ({String from, String to, String source});

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

  int get _filterCount => [_from, _to, _source].where((v) => v.isNotEmpty).length;

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
    final p = context.palette;
    final isAdmin = ref.watch(isAdminProvider);
    final rates = ref.watch(_ratesProvider(_key));
    final data = rates.value ?? const <ExchangeRate>[];

    return PageScaffold(
      title: 'Taux USD/MAD',
      actions: [
        ActionMenu<String>(
          busy: _busy,
          onSelected: (v) {
            switch (v) {
              case 'export':
                _exportExcel();
              case 'fetch':
                _fetchToday();
              case 'backfill':
                _backfill();
            }
          },
          items: [
            menuItem('export', Icons.grid_on_rounded, 'Export Excel'),
            if (isAdmin) ...[
              menuItem('fetch', Icons.cloud_download_outlined, 'Récupérer Bank Al-Maghrib (BDT)'),
              menuItem('backfill', Icons.history_toggle_off_rounded, 'Backfill BDT'),
            ],
          ],
        ),
      ],
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _upsert,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Taux'),
            )
          : null,
      onRefresh: () async {
        _refreshData();
        await ref.read(_ratesProvider(_key).future);
      },
      filterBar: Row(
        children: [
          Expanded(
            child: Text(
              _from.isEmpty && _to.isEmpty
                  ? 'Toutes les dates'
                  : '${_from.isEmpty ? '…' : formatDate(_from)} → ${_to.isEmpty ? '…' : formatDate(_to)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w500),
            ),
          ),
          Badge(
            isLabelVisible: _filterCount > 0,
            label: Text('$_filterCount'),
            backgroundColor: p.accent,
            child: OutlinedButton.icon(
              onPressed: () => _openFilters(data),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Filtres'),
            ),
          ),
        ],
      ),
      children: [
        AsyncView(
          value: rates,
          onRetry: () => ref.invalidate(_ratesProvider(_key)),
          builder: (data) => _list(data, isAdmin),
        ),
      ],
    );
  }

  Future<void> _openFilters(List<ExchangeRate> data) async {
    final sources = {...data.map((r) => r.source)}.toList()..sort();
    final result = await showFormSheet<_Filters>(
      context,
      title: 'Filtres',
      builder: (_) => _FiltersForm(initial: (from: _from, to: _to, source: _source), sources: sources),
    );
    if (result == null) return;
    _update(() {
      _from = result.from;
      _to = result.to;
      _source = result.source;
    });
  }

  Widget _list(List<ExchangeRate> data, bool isAdmin) {
    final p = context.palette;
    final filtered = _source.isEmpty ? data : data.where((r) => r.source == _source).toList();
    if (filtered.isEmpty) {
      return EmptyState(
        _filterCount > 0 ? 'Aucun taux pour ces filtres' : 'Aucun taux',
        icon: Icons.currency_exchange_rounded,
      );
    }
    final stats = <String, ({int count, double sum})>{};
    for (final r in filtered) {
      final key = quinzaineOf(r.rateDate).key;
      final s = stats[key] ?? (count: 0, sum: 0.0);
      stats[key] = (count: s.count + 1, sum: s.sum + r.usdMadRate);
    }
    final page = filtered.take(_shown).toList();
    final chronological = [...filtered]..sort((a, b) => a.rateDate.compareTo(b.rateDate));
    final recent = chronological.length > 60 ? chronological.sublist(chronological.length - 60) : chronological;
    final latest = chronological.last;
    final average = filtered.fold<double>(0, (s, r) => s + r.usdMadRate) / filtered.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(children: [
          KpiCard(
            label: 'Dernier taux',
            value: formatValue(latest.usdMadRate),
            sub: '${formatDate(latest.rateDate)} · MAD/USD',
            icon: Icons.currency_exchange_rounded,
            accent: true,
          ),
          KpiCard(
            label: 'Moyenne',
            value: formatValue(average),
            sub: '${filtered.length} taux',
            icon: Icons.functions_rounded,
          ),
        ]),
        if (recent.length > 1)
          Panel(
            title: 'Tendance',
            subtitle: recent.length < chronological.length ? '60 derniers taux' : null,
            icon: Icons.show_chart_rounded,
            child: SeriesChart(
              height: 180,
              labels: [for (final r in recent) formatDate(r.rateDate)],
              series: [
                ChartSeries(
                  name: 'USD/MAD',
                  values: [for (final r in recent) r.usdMadRate],
                  color: p.seriesAt(1),
                  area: true,
                  dots: false,
                  digits: valueDigits,
                ),
              ],
            ),
          ),
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
            GroupItem(:final row) => ListCard(
                leading: IconBubble(Icons.attach_money_rounded, color: p.seriesAt(1), size: 40),
                title: Text(formatDate(row.rateDate)),
                subtitle: Text(row.source),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatValue(row.usdMadRate),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: p.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (isAdmin)
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: p.danger),
                        onPressed: () => _delete(row),
                      )
                    else
                      const SizedBox(width: 10),
                  ],
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

  Future<void> _exportExcel() async {
    final body = await showFormSheet<Map<String, String>>(
      context,
      title: 'Export Excel taux de change',
      builder: (_) => _ExportForm(from: _from, to: _to),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      final query = <String, dynamic>{
        'dateFrom': body['dateFrom'],
        'dateTo': body['dateTo'],
        if (_source.isNotEmpty) 'source': _source,
      };
      final file = await ref.read(apiClientProvider).download(
            '/exchange-rates/export',
            query: query,
            fallbackName: 'taux-de-change-${body['dateFrom']}-${body['dateTo']}.xlsx',
          );
      if (mounted) await saveAndOffer(context, file.bytes, file.filename);
    });
    if (mounted) setState(() => _busy = false);
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

class _ExportForm extends StatefulWidget {
  const _ExportForm({required this.from, required this.to});

  final String from;
  final String to;

  @override
  State<_ExportForm> createState() => _ExportFormState();
}

class _ExportFormState extends State<_ExportForm> {
  late String _from = widget.from;
  late String _to = widget.to;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBanner(
          'Même format que l’import (Date | Devise | Taux). Choisissez la période.',
          kind: BannerKind.info,
        ),
        DateField(label: 'Du', value: _from, clearable: false, onChanged: (v) => setState(() => _from = v)),
        const SizedBox(height: 12),
        DateField(label: 'Au', value: _to, clearable: false, onChanged: (v) => setState(() => _to = v)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_from.isEmpty || _to.isEmpty) {
              showToast(context, 'Choisissez la période Du / Au', error: true);
              return;
            }
            if (_from.compareTo(_to) > 0) {
              showToast(context, 'La date de début doit précéder la date de fin', error: true);
              return;
            }
            Navigator.pop(context, {'dateFrom': _from, 'dateTo': _to});
          },
          child: const Text('Télécharger'),
        ),
      ],
    );
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
        const InfoBanner(
          'Maximum 100 jours calendaires. Un seul backfill à la fois.',
          kind: BannerKind.info,
        ),
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

class _FiltersForm extends StatefulWidget {
  const _FiltersForm({required this.initial, required this.sources});

  final _Filters initial;
  final List<String> sources;

  @override
  State<_FiltersForm> createState() => _FiltersFormState();
}

class _FiltersFormState extends State<_FiltersForm> {
  late String _from = widget.initial.from;
  late String _to = widget.initial.to;
  late String _source = widget.sources.contains(widget.initial.source) ? widget.initial.source : '';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: DateField(label: 'Du', value: _from, onChanged: (v) => setState(() => _from = v))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'Au', value: _to, onChanged: (v) => setState(() => _to = v))),
          ],
        ),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Source',
          icon: Icons.source_outlined,
          value: _source,
          items: {'': 'Toutes', for (final s in widget.sources) s: s},
          onChanged: (v) => setState(() => _source = v),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, (from: '', to: '', source: '')),
                child: const Text('Réinitialiser'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, (from: _from, to: _to, source: _source)),
                child: const Text('Appliquer'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}