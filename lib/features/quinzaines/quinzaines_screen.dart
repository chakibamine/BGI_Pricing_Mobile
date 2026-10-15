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

typedef _ConfigLast = ({ConfigRef cfg, Calculation last});

class QuinzainesScreen extends ConsumerStatefulWidget {
  const QuinzainesScreen({super.key});

  @override
  ConsumerState<QuinzainesScreen> createState() => _QuinzainesScreenState();
}

class _QuinzainesScreenState extends ConsumerState<QuinzainesScreen> {
  final _chartKey = GlobalKey();
  bool _busy = false;
  int? _configToAdd;

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(quinzaineSelectionProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final detail = ref.watch(quinzaineDetailProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quinzaines'),
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
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'recalc', child: Text('Recalculer')),
                PopupMenuItem(
                  value: 'xlsx',
                  enabled: detail.hasValue,
                  child: const Text('Export Excel'),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  enabled: detail.hasValue,
                  child: const Text('Export PDF'),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          invalidatePricing(ref);
          await ref.read(quinzaineDetailProvider(key).future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(key),
              const SizedBox(height: 12),
              AsyncView(
                value: detail,
                onRetry: () => ref.invalidate(quinzaineDetailProvider(key)),
                builder: (d) => _content(key, d, isAdmin),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(QuinzaineKey k) {
    _configToAdd = null;
    ref.read(quinzaineSelectionProvider.notifier).set(k);
  }

  Widget _toolbar(QuinzaineKey k) {
    final now = DateTime.now().year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProductSelector(
          value: k.product,
          onChanged: (p) => _select((product: p, year: k.year, month: k.month, period: k.period)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: LabeledDropdown<int>(
                label: 'Année',
                value: k.year,
                items: {for (final y in {now - 1, now, now + 1, k.year}) y: '$y'},
                onChanged: (y) =>
                    _select((product: k.product, year: y, month: k.month, period: k.period)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: LabeledDropdown<int>(
                label: 'Mois',
                value: k.month,
                items: {for (var m = 1; m <= 12; m++) m: monthLabels[m - 1]},
                onChanged: (m) =>
                    _select((product: k.product, year: k.year, month: m, period: k.period)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: LabeledDropdown<int>(
                label: 'Période',
                value: k.period,
                items: const {1: 'Q1', 2: 'Q2'},
                onChanged: (p) =>
                    _select((product: k.product, year: k.year, month: k.month, period: p)),
              ),
            ),
          ],
        ),
      ],
    );
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
    final lastByConfig = _lastByConfig(d);
    final reference = lastByConfig.isEmpty ? null : lastByConfig.first.last;
    final multi = lastByConfig.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(children: [
          KpiCard(
            label: 'Statut',
            value: '${quinzaineStatusLabels[d.status] ?? d.status}${d.frozen ? ' · figée' : ''}',
            valueColor: AppColors.status(d.status),
            sub: d.frozen
                ? reference != null
                    ? 'Résultats du ${formatDate(reference.calculationDate)}, conservés'
                    : 'Résultats conservés'
                : null,
          ),
          KpiCard(
            label: 'Fenêtre cotations',
            value: '${formatDate(d.windowStart)} → ${formatDate(d.windowEnd)}',
          ),
          KpiCard(
            label: 'CIF NWE moyen',
            value: reference != null ? formatValue(reference.cifNweAverage) : '—',
            sub: reference != null ? '${reference.quotationsCount} cotation(s)' : 'Aucun calcul',
          ),
          if (lastByConfig.isEmpty)
            const KpiCard(label: 'Prix TTC', value: '—', sub: 'MAD/M³', accent: true),
          for (final x in lastByConfig)
            KpiCard(
              label: multi ? 'Prix TTC — ${x.cfg.name}' : 'Prix TTC',
              value: formatPrice(x.last.purchasePriceTtc),
              sub: 'MAD/M³',
              accent: x.cfg.isDefault,
            ),
        ]),
        const SizedBox(height: 12),
        _configsPanel(k, d, isAdmin),
        const SizedBox(height: 12),
        if (reference == null)
          const InfoBanner(
            'Aucun calcul pour cette quinzaine. Importez des cotations ou récupérez Platts / BDT.',
          )
        else ...[
          Panel(
            title: 'Décomposition (dernier calcul)',
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
          const SizedBox(height: 12),
          Panel(
            title: 'Évolution intra-quinzaine',
            child: RepaintBoundary(
              key: _chartKey,
              child: Container(color: Colors.white, child: _chart(d, lastByConfig)),
            ),
          ),
          const SizedBox(height: 12),
          for (final x in lastByConfig) ...[
            Panel(
              title: 'Calculs jour par jour${multi ? ' — ${x.cfg.name}' : ''}',
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
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  /// CIF on the left axis, TTC per config on the right axis.
  Widget _chart(QuinzaineDetail d, List<_ConfigLast> lastByConfig) {
    final dates = <String>{for (final c in d.calculations) c.calculationDate}.toList()..sort();
    final cifByDate = <String, double>{};
    final ttc = <int, Map<String, double>>{};
    for (final c in d.calculations) {
      cifByDate.putIfAbsent(c.calculationDate, () => c.cifNweAverage);
      (ttc[c.configId] ??= {})[c.calculationDate] = c.purchasePriceTtc;
    }
    final multi = lastByConfig.length > 1;
    return SeriesChart(
      height: 260,
      labels: [for (final dt in dates) formatDate(dt)],
      leftAxisName: r'CIF $/T',
      rightAxisName: 'TTC MAD/M³',
      series: [
        for (final (i, x) in lastByConfig.indexed)
          ChartSeries(
            name: multi ? 'Prix TTC — ${x.cfg.name}' : 'Prix TTC',
            values: [for (final dt in dates) ttc[x.cfg.id]?[dt]],
            color: AppColors.lineColors[i % AppColors.lineColors.length],
            axis: ChartAxis.right,
            dots: false,
          ),
        ChartSeries(
          name: 'CIF NWE moy.',
          values: [for (final dt in dates) cifByDate[dt]],
          color: const Color(0xFFC47B2B),
          dashed: true,
          dots: false,
          digits: valueDigits,
        ),
      ],
    );
  }

  Widget _configsPanel(QuinzaineKey k, QuinzaineDetail d, bool isAdmin) {
    final attachments =
        isAdmin ? ref.watch(quinzaineAttachmentsProvider(k)).value ?? const [] : const [];
    final productConfigs =
        isAdmin ? ref.watch(productConfigsProvider(k.product)).value ?? const [] : const [];
    final used = {...attachments.map((a) => a.configId), ...d.configs.map((c) => c.id)};
    final addable =
        productConfigs.where((c) => c.isActive && !c.isDefault && !used.contains(c.id)).toList();

    return Panel(
      title: 'Configurations de la quinzaine',
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
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(cfg.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        cfg.isDefault ? 'Par défaut' : (att != null ? 'Ajoutée' : 'Par période'),
                      ),
                      trailing: isAdmin && att != null
                          ? TextButton(
                              onPressed: () => _detach(att.id),
                              child: const Text('Retirer'),
                            )
                          : null,
                    );
                  }),
                if (isAdmin && d.frozen)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Quinzaine clôturée : ajouter ou retirer une configuration '
                      'n’est appliqué qu’après « Recalculer ».',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                if (isAdmin) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('add-${k.product}-${addable.length}'),
                          initialValue: _configToAdd,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Ajouter une configuration'),
                          hint: Text(
                            addable.isEmpty ? 'Aucune autre config active' : 'Choisir…',
                          ),
                          items: [
                            for (final c in addable)
                              DropdownMenuItem(value: c.id, child: Text(c.name)),
                          ],
                          onChanged: addable.isEmpty
                              ? null
                              : (v) => setState(() => _configToAdd = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _configToAdd == null ? null : () => _attach(k, _configToAdd!),
                        child: const Text('Ajouter'),
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
      () => ref
          .read(apiClientProvider)
          .post('/pricing/recalculate', body: {...quinzaineQuery(k), 'force': true}),
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
      final chart = await captureWidget(_chartKey);
      final reference = lastByConfig.first.last;
      final multi = lastByConfig.length > 1;
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
          if (chart != null) PdfImage('Évolution intra-quinzaine', chart),
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
