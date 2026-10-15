import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class _BreakdownRow {
  const _BreakdownRow(this.label, this.value, this.digits, this.unit,
      {this.strong = false});
  final String Function(Calculation c) label;
  final double Function(Calculation c) value;
  final int digits;
  final String unit;
  final bool strong;
}

String _creditDroitLabel(Calculation c) {
  final pct = '${formatNumber(c.creditDroitRate * 100, 2)} %';
  return 'Crédit de droit $pct${c.creditDroit == 0 ? ' (désactivé)' : ''}';
}

final _breakdown = <_BreakdownRow>[
  _BreakdownRow((_) => 'CIF NWE (moy. fenêtre)', (c) => c.cifNweAverage, valueDigits, r'$/T'),
  _BreakdownRow((_) => 'Premium', (c) => c.premium, valueDigits, r'$/T'),
  _BreakdownRow((_) => 'USD/MAD (moy. fenêtre)', (c) => c.exchangeRate, valueDigits, 'MAD/USD'),
  _BreakdownRow((_) => 'Prix de reprise HT', (c) => c.prixRepriseHt, priceDigits, 'MAD/M³', strong: true),
  _BreakdownRow((_) => 'TIC', (c) => c.tic, valueDigits, 'MAD/M³'),
  _BreakdownRow((_) => 'TVA 10 %', (c) => c.tva, valueDigits, 'MAD/M³'),
  _BreakdownRow(_creditDroitLabel, (c) => c.creditDroit, valueDigits, 'MAD/M³'),
  _BreakdownRow((_) => 'Divers frais', (c) => c.diversFrais, valueDigits, 'MAD/M³ TTC'),
];

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Product _product = Product.gasoil;
  int _year = DateTime.now().year;
  ({int month, int period})? _selected;
  bool _busy = false;

  final _comparisonKey = GlobalKey();
  final _evolutionKey = GlobalKey();
  final _plattsKey = GlobalKey();

  ({Product product, int year}) get _dashKey => (product: _product, year: _year);

  QuinzaineKey? get _quinzaineKey => _selected == null
      ? null
      : (
          product: _product,
          year: _year,
          month: _selected!.month,
          period: _selected!.period,
        );

  void _reset(VoidCallback change) => setState(() {
        change();
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final dash = ref.watch(dashboardProvider(_dashKey));

    // Pre-select the quinzaine the server displays (active, or last with data).
    final display = dash.value?.displayQuinzaine;
    if (_selected == null && display != null && display.year == _year) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected == null) {
          setState(() => _selected = (month: display.month, period: display.period));
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              enabled: !_busy && dash.hasValue,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'xlsx':
                    _exportExcel();
                  case 'pdf':
                    _exportPdf(dash.requireValue);
                  case 'email':
                    _testEmail();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
                PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                PopupMenuItem(value: 'email', child: Text('Tester l’email')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          invalidatePricing(ref);
          await ref.read(dashboardProvider(_dashKey).future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(),
              const SizedBox(height: 12),
              AsyncView(
                value: dash,
                onRetry: () => ref.invalidate(dashboardProvider(_dashKey)),
                builder: (data) => _content(data, isAdmin),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final now = DateTime.now().year;
    return Row(
      children: [
        Expanded(
          child: ProductSelector(
            value: _product,
            onChanged: (p) => _reset(() => _product = p),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: LabeledDropdown<int>(
            label: 'Année',
            value: _year,
            items: {for (final y in [now - 1, now, now + 1]) y: '$y'},
            onChanged: (y) => _reset(() => _year = y),
          ),
        ),
      ],
    );
  }

  Widget _content(DashboardData data, bool isAdmin) {
    final k = _quinzaineKey;
    final detail = k == null ? null : ref.watch(quinzaineDetailProvider(k));
    final defaultCalcs = [
      ...?detail?.value?.calculations.where((c) => c.isDefaultConfig),
    ]..sort((a, b) => a.calculationDate.compareTo(b.calculationDate));
    final latest = defaultCalcs.isEmpty ? null : defaultCalcs.last;

    final selectedIndex = data.grid.indexWhere(
      (q) => q.month == _selected?.month && q.period == _selected?.period,
    );
    final selectedCell = selectedIndex >= 0 ? data.grid[selectedIndex] : null;
    final previousPrice =
        selectedIndex > 0 ? data.grid[selectedIndex - 1].lastPriceTtc : null;
    final variation = latest != null && previousPrice != null
        ? latest.purchasePriceTtc - previousPrice
        : null;

    final evolution = _selected != null && detail?.value != null
        ? [for (final c in defaultCalcs) DatedValue(c.calculationDate, c.purchasePriceTtc)]
        : data.evolution;

    final window = detail?.value;
    final windowQuotes = window == null
        ? null
        : ref.watch(windowQuotesProvider(
            (product: _product, from: window.windowStart, to: window.windowEnd),
          ));
    final quotes = _selected != null && windowQuotes?.value != null
        ? windowQuotes!.value!
        : data.rawQuotations;
    final quotesAverage = quotes.isEmpty
        ? null
        : quotes.fold<double>(0, (s, q) => s + q.value) / quotes.length;

    final selectedLabel = selectedCell?.label ?? data.displayQuinzaine?.label ?? '';
    final hasNoData =
        data.todayPriceTtc == null && data.grid.every((q) => q.lastPriceTtc == null);

    _lastView = _DashboardView(
      data: data,
      latest: latest,
      variation: variation,
      selectedLabel: selectedLabel,
      quotes: quotes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasNoData) ...[
          InfoBanner(
            'Aucune cotation disponible pour ${_product.code} / $_year. '
            '${isAdmin ? 'Importez des données' : 'Consultez les cotations'} '
            'pour afficher les KPIs.',
          ),
          const SizedBox(height: 12),
        ],
        if (data.usingFallback && data.displayQuinzaine != null) ...[
          InfoBanner(
            'Pas de calcul sur la quinzaine active'
            '${data.activeQuinzaine != null ? ' (${data.activeQuinzaine!.label})' : ''}'
            ' — affichage de ${data.displayQuinzaine!.label}. '
            'Touchez une case de la grille pour changer.',
            color: AppColors.navy,
          ),
          const SizedBox(height: 12),
        ],
        KpiGrid(children: [
          KpiCard(
            label: 'Quinzaine active',
            value: data.activeQuinzaine?.label ?? 'Aucune',
            sub: data.usingFallback && data.displayQuinzaine != null
                ? 'Affichage : ${data.displayQuinzaine!.label}'
                : null,
          ),
          KpiCard(
            label: 'CIF NWE moyen',
            value: formatValue(data.cifNweAverage),
            sub: data.cifNweAverage != null
                ? '${data.cifQuotationsCount} cotation(s) · \$/T'
                : '—',
          ),
          KpiCard(
            label: 'Prix TTC du jour',
            value: formatPrice(data.todayPriceTtc),
            sub: '${data.todayPriceDate != null ? formatDate(data.todayPriceDate) : '—'} · MAD/M³',
            accent: true,
          ),
          KpiCard(
            label: 'Fenêtre de cotation',
            value: data.windowStart != null
                ? '${formatDate(data.windowStart)} → ${formatDate(data.windowEnd)}'
                : '—',
          ),
        ]),
        const SizedBox(height: 12),
        Panel(
          title: 'Prix MAD TTC/M³ — ${_product.code} ($_year vs ${_year - 1})',
          child: RepaintBoundary(
            key: _comparisonKey,
            child: Container(
              color: Colors.white,
              child: SeriesChart(
                labels: [for (final c in data.currentYear) c.label],
                leftAxisName: 'MAD/M³',
                series: [
                  ChartSeries(
                    name: '$_year',
                    values: [for (final c in data.currentYear) c.value],
                    color: AppColors.navy,
                  ),
                  ChartSeries(
                    name: '${_year - 1}',
                    values: [
                      for (var i = 0; i < data.currentYear.length; i++)
                        i < data.previousYear.length ? data.previousYear[i].value : null,
                    ],
                    color: AppColors.orange,
                    dashed: true,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          title: 'Prix MAD TTC/M³ — ${_product.code} ($_year)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StatusLegend(),
              const SizedBox(height: 10),
              _QuinzaineGrid(
                cells: data.grid,
                selected: _selected,
                onTap: (c) => setState(() => _selected = (month: c.month, period: c.period)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          title: 'Détail — $selectedLabel',
          trailing: k == null
              ? null
              : TextButton(
                  onPressed: () {
                    ref.read(quinzaineSelectionProvider.notifier).set(k);
                    context.go('/quinzaines');
                  },
                  child: const Text('Ouvrir'),
                ),
          child: detail?.isLoading ?? false
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : latest == null
                  ? EmptyState(
                      'Aucun calcul pour cette quinzaine.'
                      '${isAdmin ? ' Utilisez « Recalculer » dans Quinzaines.' : ''}',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Calculé le ${formatDate(latest.calculationDate)} · '
                          '${latest.quotationsCount} cotation(s)',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                        const SizedBox(height: 6),
                        for (final row in _breakdown)
                          KeyValueRow(
                            row.label(latest),
                            formatNumber(row.value(latest), row.digits),
                            unit: row.unit,
                            strong: row.strong,
                          ),
                        KeyValueRow(
                          'Prix d’achat TTC',
                          formatPrice(latest.purchasePriceTtc),
                          unit: 'MAD/M³',
                          strong: true,
                          highlight: true,
                        ),
                        if (variation != null)
                          KeyValueRow(
                            'Variation vs quinzaine précédente',
                            formatSigned(variation),
                            unit: 'MAD/M³',
                            valueColor: variation <= 0 ? AppColors.green : AppColors.red,
                            strong: true,
                          ),
                      ],
                    ),
        ),
        const SizedBox(height: 12),
        Panel(
          title: 'Évolution — $selectedLabel',
          child: evolution.isEmpty
              ? const EmptyState('Pas de données d’évolution')
              : RepaintBoundary(
                  key: _evolutionKey,
                  child: Container(
                    color: Colors.white,
                    child: SeriesChart(
                      labels: [for (final e in evolution) formatDate(e.date)],
                      leftAxisName: 'MAD TTC/M³',
                      series: [
                        ChartSeries(
                          name: 'Prix MAD TTC/M³',
                          values: [for (final e in evolution) e.value],
                          color: AppColors.navy,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Panel(
          title: 'Cotations Platts CIF NWE — $selectedLabel',
          child: quotes.isEmpty
              ? const EmptyState('Aucune cotation dans la fenêtre.')
              : RepaintBoundary(
                  key: _plattsKey,
                  child: Container(
                    color: Colors.white,
                    child: SeriesChart(
                      labels: [for (final q in quotes) formatDate(q.date)],
                      leftAxisName: r'CIF NWE $/T',
                      referenceY: quotesAverage,
                      referenceLabel: quotesAverage == null
                          ? null
                          : 'Moyenne : ${formatValue(quotesAverage)} \$/T',
                      series: [
                        ChartSeries(
                          name: r'CIF NWE $/T',
                          values: [for (final q in quotes) q.value],
                          color: AppColors.navy,
                          area: true,
                          digits: valueDigits,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  _DashboardView? _lastView;

  Future<void> _exportExcel() async {
    setState(() => _busy = true);
    await runAction(context, () async {
      final file = await ref.read(apiClientProvider).download(
        '/dashboard/export',
        query: {
          'product': _product.code,
          'year': _year,
          'month': _selected?.month,
          'period': _selected?.period,
        },
        fallbackName: 'tableau-de-bord-${_product.code}-$_year.xlsx',
      );
      if (mounted) await saveAndOffer(context, file.bytes, file.filename);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportPdf(DashboardData data) async {
    final view = _lastView;
    if (view == null) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      final comparison = await captureWidget(_comparisonKey);
      final evolution = await captureWidget(_evolutionKey);
      final platts = await captureWidget(_plattsKey);

      final months = List.generate(12, (i) => i + 1);
      String cell(int m, int p) {
        final c = data.grid.where((g) => g.month == m && g.period == p);
        return c.isEmpty ? '—' : formatPrice(c.first.lastPriceTtc);
      }

      final latest = view.latest;
      final bytes = await buildA4Report(
        title: 'Tableau de bord - ${_product.code} $_year',
        subtitle: '${view.selectedLabel.isNotEmpty ? 'Quinzaine affichée : ${view.selectedLabel} · ' : ''}'
            'Exporté le ${exportStamp()}',
        blocks: [
          PdfKpis([
            PdfKpi('Quinzaine active', data.activeQuinzaine?.label ?? 'Aucune'),
            PdfKpi('CIF NWE moyen', formatValue(data.cifNweAverage),
                sub: '${data.cifQuotationsCount} cotation(s) · \$/T'),
            PdfKpi('Prix TTC du jour', formatPrice(data.todayPriceTtc),
                sub: '${formatDate(data.todayPriceDate)} · MAD/M³', accent: true),
            PdfKpi(
              'Fenêtre de cotation',
              data.windowStart == null
                  ? '—'
                  : '${formatDate(data.windowStart)} au ${formatDate(data.windowEnd)}',
            ),
          ]),
          if (comparison != null)
            PdfImage('Prix MAD TTC/M³ — ${_product.code} ($_year vs ${_year - 1})', comparison),
          PdfTable(
            title: 'Prix TTC par quinzaine ($_year)',
            headers: const ['Mois', 'Q1', 'Q2'],
            rows: [
              for (final m in months) [monthLabels[m - 1], cell(m, 1), cell(m, 2)],
            ],
            half: true,
          ),
          PdfTable(
            title: 'Détail — ${view.selectedLabel}',
            headers: const ['Composante', 'Valeur', 'Unité'],
            rows: latest == null
                ? [
                    ['Aucun calcul', '', ''],
                  ]
                : [
                    for (final r in _breakdown)
                      [r.label(latest), formatNumber(r.value(latest), r.digits), r.unit],
                    if (view.variation != null)
                      ['Variation vs Q-1', formatSigned(view.variation), 'MAD/M³'],
                    ['Prix d’achat TTC', formatPrice(latest.purchasePriceTtc), 'MAD/M³'],
                  ],
            totalRow: latest != null,
            half: true,
          ),
          if (evolution != null)
            PdfImage('Évolution — ${view.selectedLabel}', evolution, half: platts != null),
          if (platts != null)
            PdfImage('Cotations Platts CIF NWE — ${view.selectedLabel}', platts,
                half: evolution != null),
        ],
      );
      if (mounted) {
        await saveAndOffer(context, bytes, 'tableau-de-bord-${_product.code}-$_year.pdf');
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _testEmail() async {
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => await ref.read(apiClientProvider).post('/email/test-daily') as Json,
    );
    if (mounted) setState(() => _busy = false);
    if (res == null || !mounted) return;
    if (res['sent'] == true) {
      showToast(
        context,
        'Email envoyé (${res['quinzaine'] ?? 'quinzaine'}'
        '${res['fallback'] == true ? ' — dernière avec données' : ''})',
      );
    } else {
      final reason = switch (res['reason']) {
        'no_calculations' => 'aucun calcul en base — recalculez une quinzaine d’abord',
        'no_active_quinzaine' => 'pas de quinzaine active',
        'no_recipients' =>
          'aucun destinataire — cochez « Reçoit l’email quotidien » dans Utilisateurs',
        final r => r?.toString() ?? 'inconnu',
      };
      showToast(context, 'Email non envoyé : $reason', error: true);
    }
  }
}

class _DashboardView {
  _DashboardView({
    required this.data,
    required this.latest,
    required this.variation,
    required this.selectedLabel,
    required this.quotes,
  });

  final DashboardData data;
  final Calculation? latest;
  final double? variation;
  final String selectedLabel;
  final List<DatedValue> quotes;
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      children: [
        for (final e in quinzaineStatusLabels.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.status(e.key),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(e.value, style: const TextStyle(fontSize: 11)),
            ],
          ),
      ],
    );
  }
}

class _QuinzaineGrid extends StatelessWidget {
  const _QuinzaineGrid({
    required this.cells,
    required this.selected,
    required this.onTap,
  });

  final List<GridCell> cells;
  final ({int month, int period})? selected;
  final ValueChanged<GridCell> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth > 600 ? 6 : 4;
        final w = (c.maxWidth - (perRow - 1) * 6) / perRow;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final cell in cells)
              SizedBox(
                width: w,
                child: _cell(cell),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(GridCell cell) {
    final active = selected?.month == cell.month && selected?.period == cell.period;
    final color = AppColors.status(cell.status);
    return Material(
      color: active ? AppColors.amberSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: active ? AppColors.amber : AppColors.border,
          width: active ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTap(cell),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cell.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              Text(
                quinzaineStatusLabels[cell.status] ?? cell.status,
                style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w600),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatPrice(cell.lastPriceTtc),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
