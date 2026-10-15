import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/charts.dart';
import '../../core/export.dart';
import '../../core/format.dart';
import '../../core/pdf_report.dart';
import '../../core/quinzaine.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/models.dart';

class _Row {
  const _Row(this.label, this.value, this.digits);
  final String label;
  final double Function(Calculation c) value;
  final int digits;
}

final _breakdown = <_Row>[
  _Row('Taux USD/MAD moyen', (c) => c.exchangeRate, valueDigits),
  _Row('Premium', (c) => c.premium, valueDigits),
  _Row('Facteur densité', (c) => c.densityFactor, valueDigits),
  _Row('Prix reprise HT', (c) => c.prixRepriseHt, priceDigits),
  _Row('TIC', (c) => c.tic, valueDigits),
  _Row('TVA', (c) => c.tva, valueDigits),
  _Row('Crédit de droit', (c) => c.creditDroit, valueDigits),
  _Row('Divers frais', (c) => c.diversFrais, valueDigits),
];

const _pdfSeriesColors = [pdfNavy, pdfTeal, pdfViolet];

typedef _ConfigLast = ({ConfigRef cfg, Calculation last});

class QuinzainesScreen extends ConsumerStatefulWidget {
  const QuinzainesScreen({super.key});

  @override
  ConsumerState<QuinzainesScreen> createState() => _QuinzainesScreenState();
}

class _QuinzainesScreenState extends ConsumerState<QuinzainesScreen> {
  bool _busy = false;
  int? _configToAdd;

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(quinzaineSelectionProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final detail = ref.watch(quinzaineDetailProvider(key));

    return PageScaffold(
      title: 'Quinzaines',
      actions: [
        if (isAdmin)
          ActionMenu<String>(
            busy: _busy,
            onSelected: (v) {
              switch (v) {
                case 'recalc':
                  _recalculate(key, detail.value);
                case 'xlsx':
                  _exportExcel(key);
                case 'pdf':
                  if (detail.value != null) _exportPdf(key, detail.value!);
              }
            },
            items: [
              menuItem('recalc', Icons.refresh_rounded, 'Recalculer'),
              menuItem('xlsx', Icons.grid_on_rounded, 'Export Excel', enabled: detail.hasValue),
              menuItem('pdf', Icons.picture_as_pdf_outlined, 'Export PDF', enabled: detail.hasValue),
            ],
          ),
      ],
      onRefresh: () async {
        invalidatePricing(ref);
        await ref.read(quinzaineDetailProvider(key).future);
      },
      filterBar: SizedBox(
        width: double.infinity,
        child: ProductSelector(
          value: key.product,
          onChanged: (p) => _select((product: p, year: key.year, month: key.month, period: key.period)),
        ),
      ),
      children: [
        _PeriodNavigator(value: key, onChanged: _select),
        const SizedBox(height: 14),
        AsyncView(
          value: detail,
          onRetry: () => ref.invalidate(quinzaineDetailProvider(key)),
          builder: (d) => _content(key, d, isAdmin),
        ),
      ],
    );
  }

  void _select(QuinzaineKey k) {
    _configToAdd = null;
    ref.read(quinzaineSelectionProvider.notifier).set(k);
  }

  List<_ConfigLast> _lastByConfig(QuinzaineDetail d) {
    final out = <_ConfigLast>[];
    for (final cfg in d.configs) {
      final rows = d.calculations.where((c) => c.configId == cfg.id).toList();
      if (rows.isNotEmpty) out.add((cfg: cfg, last: rows.last));
    }
    return out;
  }

  Widget _content(QuinzaineKey k, QuinzaineDetail d, bool isAdmin) {
    final p = context.palette;
    final lastByConfig = _lastByConfig(d);
    final reference = lastByConfig.isEmpty ? null : lastByConfig.first.last;
    final multi = lastByConfig.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(children: [
          if (lastByConfig.isEmpty)
            const KpiCard(
              label: 'Prix TTC',
              value: '—',
              sub: 'MAD/M³',
              accent: true,
              icon: Icons.local_gas_station_rounded,
            ),
          for (final x in lastByConfig)
            KpiCard(
              label: multi ? 'Prix TTC — ${x.cfg.name}' : 'Prix TTC',
              value: formatPrice(x.last.purchasePriceTtc),
              sub: 'MAD/M³',
              accent: x.cfg.isDefault,
              icon: Icons.local_gas_station_rounded,
            ),
          KpiCard(
            label: 'Statut',
            value: '${quinzaineStatusLabels[d.status] ?? d.status}${d.frozen ? ' · figée' : ''}',
            valueColor: p.status(d.status),
            icon: d.frozen ? Icons.lock_outline_rounded : Icons.flag_outlined,
            sub: d.frozen
                ? reference != null
                    ? 'Résultats du ${formatDate(reference.calculationDate)}, conservés'
                    : 'Résultats conservés'
                : null,
          ),
          KpiCard(
            label: 'Fenêtre cotations',
            value: '${formatDate(d.windowStart)} → ${formatDate(d.windowEnd)}',
            icon: Icons.date_range_rounded,
          ),
          KpiCard(
            label: 'CIF NWE moyen',
            value: reference != null ? formatValue(reference.cifNweAverage) : '—',
            sub: reference != null ? '${reference.quotationsCount} cotation(s)' : 'Aucun calcul',
            icon: Icons.water_drop_outlined,
          ),
        ]),
        _configsPanel(k, d, isAdmin),
        if (reference == null)
          const InfoBanner(
            'Aucun calcul pour cette quinzaine. Importez des cotations ou récupérez Platts / BDT.',
            kind: BannerKind.info,
          )
        else ...[
          Panel(
            title: 'Décomposition',
            subtitle: 'Dernier calcul',
            icon: Icons.receipt_long_rounded,
            child: SimpleTable(
              headers: multi ? ['', for (final x in lastByConfig) x.cfg.name] : ['', ''],
              highlightLast: true,
              rows: [
                ['Date calcul', for (final x in lastByConfig) formatDate(x.last.calculationDate)],
                for (final r in _breakdown)
                  [r.label, for (final x in lastByConfig) formatNumber(r.value(x.last), r.digits)],
                ['Prix TTC', for (final x in lastByConfig) formatPrice(x.last.purchasePriceTtc)],
              ],
            ),
          ),
          Panel(
            title: 'Évolution intra-quinzaine',
            subtitle: r'CIF $/T à gauche · TTC MAD/M³ à droite',
            icon: Icons.timeline_rounded,
            child: _chart(d, lastByConfig),
          ),
          for (final x in lastByConfig)
            Panel(
              title: 'Calculs jour par jour',
              subtitle: multi ? x.cfg.name : null,
              icon: Icons.view_list_rounded,
              child: SimpleTable(
                headers: const ['Date', 'CIF moy.', 'Nb', 'USD/MAD', 'HT', 'TTC'],
                rows: [
                  for (final c in d.calculations.where((c) => c.configId == x.cfg.id))
                    [
                      formatDate(c.calculationDate),
                      formatValue(c.cifNweAverage),
                      '${c.quotationsCount}',
                      formatValue(c.exchangeRate),
                      formatPrice(c.prixRepriseHt),
                      formatPrice(c.purchasePriceTtc),
                    ],
                ],
              ),
            ),
        ],
      ],
    );
  }

  ({List<String> dates, Map<String, double> cif, Map<int, Map<String, double>> ttc}) _chartData(
    QuinzaineDetail d,
  ) {
    final dates = <String>{for (final c in d.calculations) c.calculationDate}.toList()..sort();
    final cif = <String, double>{};
    final ttc = <int, Map<String, double>>{};
    for (final c in d.calculations) {
      cif.putIfAbsent(c.calculationDate, () => c.cifNweAverage);
      (ttc[c.configId] ??= {})[c.calculationDate] = c.purchasePriceTtc;
    }
    return (dates: dates, cif: cif, ttc: ttc);
  }

  /// CIF on the left axis, TTC per config on the right axis.
  Widget _chart(QuinzaineDetail d, List<_ConfigLast> lastByConfig) {
    final p = context.palette;
    final data = _chartData(d);
    final multi = lastByConfig.length > 1;
    return SeriesChart(
      height: 260,
      labels: [for (final dt in data.dates) formatDate(dt)],
      leftAxisName: r'CIF $/T',
      rightAxisName: 'TTC MAD/M³',
      series: [
        for (final (i, x) in lastByConfig.indexed)
          ChartSeries(
            name: multi ? 'Prix TTC — ${x.cfg.name}' : 'Prix TTC',
            values: [for (final dt in data.dates) data.ttc[x.cfg.id]?[dt]],
            color: i == 0 ? p.primary : p.seriesAt(i),
            axis: ChartAxis.right,
            area: i == 0,
            dots: false,
          ),
        ChartSeries(
          name: 'CIF NWE moy.',
          values: [for (final dt in data.dates) data.cif[dt]],
          color: p.chartAlt,
          dashed: true,
          dots: false,
          digits: valueDigits,
        ),
      ],
    );
  }

  Widget _configsPanel(QuinzaineKey k, QuinzaineDetail d, bool isAdmin) {
    final p = context.palette;
    final attachments = isAdmin ? ref.watch(quinzaineAttachmentsProvider(k)).value ?? const [] : const [];
    final productConfigs = isAdmin ? ref.watch(productConfigsProvider(k.product)).value ?? const [] : const [];
    final used = {...attachments.map((a) => a.configId), ...d.configs.map((c) => c.id)};
    final addable = productConfigs.where((c) => c.isActive && !c.isDefault && !used.contains(c.id)).toList();

    return Panel(
      title: 'Configurations',
      subtitle: 'Appliquées à cette quinzaine',
      icon: Icons.tune_rounded,
      child: d.configs.isEmpty
          ? InfoBanner(
              'Aucune configuration par défaut pour ${k.product.code}. '
              'Définissez-en une dans Plus › Configurations.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final cfg in d.configs)
                  Builder(builder: (context) {
                    final att = attachments.where((a) => a.configId == cfg.id).firstOrNull;
                    final kind = cfg.isDefault ? 'Par défaut' : (att != null ? 'Ajoutée' : 'Par période');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      decoration: BoxDecoration(
                        color: p.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          IconBubble(
                            cfg.isDefault ? Icons.star_rounded : Icons.layers_outlined,
                            color: cfg.isDefault ? p.accent : p.info,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cfg.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(kind, style: TextStyle(fontSize: 12, color: p.textMuted)),
                              ],
                            ),
                          ),
                          if (isAdmin && att != null)
                            TextButton(
                              onPressed: () => _detach(att.id),
                              style: TextButton.styleFrom(foregroundColor: p.danger),
                              child: const Text('Retirer'),
                            ),
                        ],
                      ),
                    );
                  }),
                if (isAdmin && d.frozen)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Text(
                      'Quinzaine clôturée : ajouter ou retirer une configuration '
                      'n’est appliqué qu’après « Recalculer ».',
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                  ),
                if (isAdmin) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('add-${k.product}-${addable.length}'),
                          initialValue: _configToAdd,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(12),
                          decoration: const InputDecoration(labelText: 'Ajouter une configuration'),
                          hint: Text(addable.isEmpty ? 'Aucune autre config active' : 'Choisir…'),
                          items: [
                            for (final c in addable) DropdownMenuItem(value: c.id, child: Text(c.name)),
                          ],
                          onChanged: addable.isEmpty ? null : (v) => setState(() => _configToAdd = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _configToAdd == null ? null : () => _attach(k, _configToAdd!),
                        icon: const Icon(Icons.add_rounded),
                        tooltip: 'Ajouter',
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _attach(QuinzaineKey k, int configId) async {
    await runAction(
      context,
      () => ref
          .read(apiClientProvider)
          .post('/pricing/quinzaine/configs', body: {...quinzaineQuery(k), 'configId': configId}),
      success: 'Configuration ajoutée à la quinzaine',
    );
    if (!mounted) return;
    setState(() => _configToAdd = null);
    invalidatePricing(ref);
  }

  Future<void> _detach(int id) async {
    await runAction(
      context,
      () => ref.read(apiClientProvider).delete('/pricing/quinzaine/configs/$id'),
      success: 'Configuration retirée de la quinzaine',
    );
    invalidatePricing(ref);
  }

  Future<void> _recalculate(QuinzaineKey k, QuinzaineDetail? d) async {
    if (d?.frozen ?? false) {
      final ok = await confirmDialog(
        context,
        'Cette quinzaine est clôturée. Recalculer avec les paramètres actuels ?',
        confirmLabel: 'Recalculer',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    await runAction(
      context,
      () => ref.read(apiClientProvider).post('/pricing/recalculate', body: {...quinzaineQuery(k), 'force': true}),
      success: 'Quinzaine recalculée',
    );
    invalidatePricing(ref);
    if (mounted) setState(() => _busy = false);
  }

  String _fileBase(QuinzaineKey k) => 'quinzaine-${k.product.code}-Q${k.period}-${k.month}-${k.year}';

  Future<void> _exportExcel(QuinzaineKey k) async {
    setState(() => _busy = true);
    await runAction(context, () async {
      final file = await ref.read(apiClientProvider).download(
            '/pricing/quinzaine/export',
            query: quinzaineQuery(k),
            fallbackName: '${_fileBase(k)}.xlsx',
          );
      if (mounted) await saveAndOffer(context, file.bytes, file.filename);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportPdf(QuinzaineKey k, QuinzaineDetail d) async {
    final lastByConfig = _lastByConfig(d);
    if (lastByConfig.isEmpty) {
      showToast(context, 'Rien à exporter : la quinzaine est vide', error: true);
      return;
    }
    setState(() => _busy = true);
    await runAction(context, () async {
      final reference = lastByConfig.first.last;
      final multi = lastByConfig.length > 1;
      final chart = _chartData(d);
      final name = 'Q${k.period} ${monthLabels[k.month - 1]} ${k.year}';
      final bytes = await buildA4Report(
        title: 'Quinzaine ${k.product.code} - $name',
        subtitle: 'Fenêtre cotations du ${formatDate(d.windowStart)} au ${formatDate(d.windowEnd)}'
            ' · Exporté le ${exportStamp()}',
        blocks: [
          PdfKpis([
            PdfKpi('Statut', '${quinzaineStatusLabels[d.status] ?? d.status}${d.frozen ? ' · figée' : ''}'),
            PdfKpi('Fenêtre', '${formatDate(d.windowStart)} au ${formatDate(d.windowEnd)}'),
            PdfKpi('CIF NWE moyen', formatValue(reference.cifNweAverage),
                sub: '${reference.quotationsCount} cotation(s)'),
            for (final x in lastByConfig)
              PdfKpi(multi ? 'TTC — ${x.cfg.name}' : 'Prix TTC', formatPrice(x.last.purchasePriceTtc),
                  sub: 'MAD/M³', accent: x.cfg.isDefault),
          ]),
          PdfTable(
            title: 'Décomposition (dernier calcul)',
            headers: ['Composante', for (final x in lastByConfig) multi ? x.cfg.name : 'Valeur'],
            totalRow: true,
            rows: [
              ['Date calcul', for (final x in lastByConfig) formatDate(x.last.calculationDate)],
              for (final r in _breakdown)
                [r.label, for (final x in lastByConfig) formatNumber(r.value(x.last), r.digits)],
              ['Prix TTC', for (final x in lastByConfig) formatPrice(x.last.purchasePriceTtc)],
            ],
          ),
          if (chart.dates.isNotEmpty)
            PdfLineChart(
              title: 'Évolution intra-quinzaine',
              labels: [for (final dt in chart.dates) formatDate(dt)],
              leftAxisName: r'CIF $/T',
              rightAxisName: 'TTC MAD/M³',
              series: [
                for (final (i, x) in lastByConfig.indexed)
                  PdfSeries(
                    multi ? 'Prix TTC — ${x.cfg.name}' : 'Prix TTC',
                    [for (final dt in chart.dates) chart.ttc[x.cfg.id]?[dt]],
                    color: _pdfSeriesColors[i % _pdfSeriesColors.length],
                    rightAxis: true,
                    area: i == 0,
                  ),
                PdfSeries(
                  'CIF NWE moy.',
                  [for (final dt in chart.dates) chart.cif[dt]],
                  color: pdfOrange,
                  dashed: true,
                ),
              ],
            ),
          for (final x in lastByConfig)
            PdfTable(
              title: 'Calculs jour par jour${multi ? ' — ${x.cfg.name}' : ''}',
              headers: const ['Date', 'CIF moy.', 'Nb', 'USD/MAD', 'HT', 'TTC'],
              half: multi,
              rows: [
                for (final c in d.calculations.where((c) => c.configId == x.cfg.id))
                  [
                    formatDate(c.calculationDate),
                    formatValue(c.cifNweAverage),
                    '${c.quotationsCount}',
                    formatValue(c.exchangeRate),
                    formatPrice(c.prixRepriseHt),
                    formatPrice(c.purchasePriceTtc),
                  ],
              ],
            ),
        ],
      );
      if (mounted) await saveAndOffer(context, bytes, '${_fileBase(k)}.pdf');
    });
    if (mounted) setState(() => _busy = false);
  }
}

/// "‹  Q1 · Octobre 2026  ›" with a picker sheet on tap.
class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({required this.value, required this.onChanged});

  final QuinzaineKey value;
  final ValueChanged<QuinzaineKey> onChanged;

  QuinzaineKey _shift(int delta) {
    var index = value.year * 24 + (value.month - 1) * 2 + (value.period - 1) + delta;
    final year = index ~/ 24;
    index %= 24;
    return (product: value.product, year: year, month: index ~/ 2 + 1, period: index % 2 + 1);
  }

  /// Cotation window: Q1 = 13→27 of M-1, Q2 = 28 of M-1 → 12 of M.
  String get _windowHint {
    final prev = monthShortLabels[(value.month + 10) % 12];
    final cur = monthShortLabels[value.month - 1];
    return value.period == 1 ? 'Cotations du 13 au 27 $prev' : 'Cotations du 28 $prev au 12 $cur';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: cardDecoration(p),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onChanged(_shift(-1)),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Quinzaine précédente',
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openPicker(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      'Q${value.period} · ${monthLabels[value.month - 1]} ${value.year}',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _windowHint,
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(_shift(1)),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Quinzaine suivante',
          ),
        ],
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    var year = value.year;
    var month = value.month;
    var period = value.period;
    final now = DateTime.now().year;
    final ok = await showFormSheet<bool>(
      context,
      title: 'Choisir une quinzaine',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledDropdown<int>(
              label: 'Année',
              icon: Icons.calendar_today_rounded,
              value: year,
              items: {for (final y in {now - 1, now, now + 1, value.year}) y: '$y'},
              onChanged: (v) => setSheet(() => year = v),
            ),
            const SizedBox(height: 12),
            LabeledDropdown<int>(
              label: 'Mois',
              icon: Icons.event_note_rounded,
              value: month,
              items: {for (var m = 1; m <= 12; m++) m: monthLabels[m - 1]},
              onChanged: (v) => setSheet(() => month = v),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Q1')),
                ButtonSegment(value: 2, label: Text('Q2')),
              ],
              selected: {period},
              onSelectionChanged: (s) => setSheet(() => period = s.first),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Afficher'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      onChanged((product: value.product, year: year, month: month, period: period));
    }
  }
}
