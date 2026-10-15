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
import '../auth/splash_screen.dart';

class _BreakdownRow {
  const _BreakdownRow(this.label, this.value, this.digits, this.unit, {this.strong = false});
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
  _DashboardView? _lastView;

  ({Product product, int year}) get _dashKey => (product: _product, year: _year);

  QuinzaineKey? get _quinzaineKey => _selected == null
      ? null
      : (product: _product, year: _year, month: _selected!.month, period: _selected!.period);

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

    return PageScaffold(
      title: 'Tableau de bord',
      actions: [
        if (isAdmin)
          ActionMenu<String>(
            busy: _busy,
            enabled: dash.hasValue,
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
            items: [
              menuItem('xlsx', Icons.grid_on_rounded, 'Export Excel'),
              menuItem('pdf', Icons.picture_as_pdf_outlined, 'Export PDF'),
              menuItem('email', Icons.mark_email_read_outlined, 'Tester l’email'),
            ],
          ),
      ],
      onRefresh: () async {
        invalidatePricing(ref);
        await ref.read(dashboardProvider(_dashKey).future);
      },
      filterBar: Row(
        children: [
          Expanded(
            child: ProductSelector(value: _product, onChanged: (p) => _reset(() => _product = p)),
          ),
          const SizedBox(width: 8),
          YearSelector(value: _year, onChanged: (y) => _reset(() => _year = y)),
        ],
      ),
      children: [
        AsyncView(
          value: dash,
          onRetry: () => ref.invalidate(dashboardProvider(_dashKey)),
          builder: (data) => _content(data, isAdmin),
        ),
      ],
    );
  }

  Widget _content(DashboardData data, bool isAdmin) {
    final p = context.palette;
    final k = _quinzaineKey;
    final detail = k == null ? null : ref.watch(quinzaineDetailProvider(k));
    final defaultCalcs = [...?detail?.value?.calculations.where((c) => c.isDefaultConfig)]
      ..sort((a, b) => a.calculationDate.compareTo(b.calculationDate));
    final latest = defaultCalcs.isEmpty ? null : defaultCalcs.last;

    final selectedIndex = data.grid.indexWhere(
      (q) => q.month == _selected?.month && q.period == _selected?.period,
    );
    final selectedCell = selectedIndex >= 0 ? data.grid[selectedIndex] : null;
    final previousPrice = selectedIndex > 0 ? data.grid[selectedIndex - 1].lastPriceTtc : null;
    final variation =
        latest != null && previousPrice != null ? latest.purchasePriceTtc - previousPrice : null;

    final evolution = _selected != null && detail?.value != null
        ? [for (final c in defaultCalcs) DatedValue(c.calculationDate, c.purchasePriceTtc)]
        : data.evolution;

    final window = detail?.value;
    final windowQuotes = window == null
        ? null
        : ref.watch(windowQuotesProvider(
            (product: _product, from: window.windowStart, to: window.windowEnd),
          ));
    final quotes =
        _selected != null && windowQuotes?.value != null ? windowQuotes!.value! : data.rawQuotations;
    final quotesAverage =
        quotes.isEmpty ? null : quotes.fold<double>(0, (s, q) => s + q.value) / quotes.length;

    final selectedLabel = selectedCell?.label ?? data.displayQuinzaine?.label ?? '';
    final hasNoData = data.todayPriceTtc == null && data.grid.every((q) => q.lastPriceTtc == null);

    _lastView = _DashboardView(
      data: data,
      latest: latest,
      variation: variation,
      selectedLabel: selectedLabel,
      quotes: quotes,
      quotesAverage: quotesAverage,
      evolution: evolution,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasNoData)
          InfoBanner(
            'Aucune cotation disponible pour ${_product.code} / $_year. '
            '${isAdmin ? 'Importez des données' : 'Consultez les cotations'} '
            'pour afficher les KPIs.',
          ),
        if (data.usingFallback && data.displayQuinzaine != null)
          InfoBanner(
            'Pas de calcul sur la quinzaine active'
            '${data.activeQuinzaine != null ? ' (${data.activeQuinzaine!.label})' : ''}'
            ' — affichage de ${data.displayQuinzaine!.label}. '
            'Touchez une case de la grille pour changer.',
            kind: BannerKind.info,
          ),
        _HeroPrice(data: data, variation: variation, product: _product),
        const SizedBox(height: 10),
        KpiGrid(children: [
          KpiCard(
            label: 'Quinzaine active',
            value: data.activeQuinzaine?.label ?? 'Aucune',
            icon: Icons.event_available_rounded,
            sub: data.usingFallback && data.displayQuinzaine != null
                ? 'Affichage : ${data.displayQuinzaine!.label}'
                : null,
          ),
          KpiCard(
            label: 'CIF NWE moyen',
            value: formatValue(data.cifNweAverage),
            icon: Icons.water_drop_outlined,
            sub: data.cifNweAverage != null ? '${data.cifQuotationsCount} cotation(s) · \$/T' : '—',
          ),
        ]),
        Panel(
          title: 'Prix MAD TTC/M³',
          subtitle: '${_product.code} · $_year vs ${_year - 1}',
          icon: Icons.stacked_line_chart_rounded,
          child: SeriesChart(
            labels: [for (final c in data.currentYear) c.label],
            leftAxisName: 'MAD/M³',
            series: [
              ChartSeries(
                name: '$_year',
                values: [for (final c in data.currentYear) c.value],
                color: p.primary,
                area: true,
              ),
              ChartSeries(
                name: '${_year - 1}',
                values: _previousYearValues(data),
                color: p.chartAlt,
                dashed: true,
              ),
            ],
          ),
        ),
        Panel(
          title: 'Quinzaines $_year',
          subtitle: 'Dernier prix TTC calculé',
          icon: Icons.calendar_view_month_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StatusLegend(),
              const SizedBox(height: 12),
              _QuinzaineGrid(
                cells: data.grid,
                selected: _selected,
                onTap: (c) => setState(() => _selected = (month: c.month, period: c.period)),
              ),
            ],
          ),
        ),
        Panel(
          title: 'Détail du calcul',
          subtitle: selectedLabel,
          icon: Icons.receipt_long_rounded,
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
              ? const Column(children: [
                  Skeleton(height: 18),
                  SizedBox(height: 10),
                  Skeleton(height: 18),
                  SizedBox(height: 10),
                  Skeleton(height: 18),
                ])
              : latest == null
                  ? EmptyState(
                      'Aucun calcul pour cette quinzaine.'
                      '${isAdmin ? ' Utilisez « Recalculer » dans Quinzaines.' : ''}',
                      icon: Icons.calculate_outlined,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Calculé le ${formatDate(latest.calculationDate)} · '
                          '${latest.quotationsCount} cotation(s)',
                          style: TextStyle(fontSize: 12, color: p.textMuted),
                        ),
                        const SizedBox(height: 4),
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
                          valueColor: p.accent,
                        ),
                        if (variation != null)
                          KeyValueRow(
                            'Variation vs quinzaine précédente',
                            formatSigned(variation),
                            unit: 'MAD/M³',
                            valueColor: variation <= 0 ? p.success : p.danger,
                            strong: true,
                          ),
                      ],
                    ),
        ),
        Panel(
          title: 'Évolution du prix',
          subtitle: selectedLabel,
          icon: Icons.timeline_rounded,
          child: evolution.isEmpty
              ? const EmptyState('Pas de données d’évolution', icon: Icons.show_chart_rounded)
              : SeriesChart(
                  labels: [for (final e in evolution) formatDate(e.date)],
                  leftAxisName: 'MAD TTC/M³',
                  series: [
                    ChartSeries(
                      name: 'Prix MAD TTC/M³',
                      values: [for (final e in evolution) e.value],
                      color: p.primary,
                      area: true,
                    ),
                  ],
                ),
        ),
        Panel(
          title: 'Cotations Platts CIF NWE',
          subtitle: selectedLabel,
          icon: Icons.insights_rounded,
          child: quotes.isEmpty
              ? const EmptyState('Aucune cotation dans la fenêtre.', icon: Icons.insights_rounded)
              : SeriesChart(
                  labels: [for (final q in quotes) formatDate(q.date)],
                  leftAxisName: r'CIF NWE $/T',
                  referenceY: quotesAverage,
                  referenceLabel:
                      quotesAverage == null ? null : 'Moyenne : ${formatValue(quotesAverage)} \$/T',
                  series: [
                    ChartSeries(
                      name: r'CIF NWE $/T',
                      values: [for (final q in quotes) q.value],
                      color: p.seriesAt(1),
                      area: true,
                      digits: valueDigits,
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  static List<double?> _previousYearValues(DashboardData data) => [
        for (var i = 0; i < data.currentYear.length; i++)
          i < data.previousYear.length ? data.previousYear[i].value : null,
      ];

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
      final months = List.generate(12, (i) => i + 1);
      String cell(int m, int p) {
        final c = data.grid.where((g) => g.month == m && g.period == p);
        return c.isEmpty ? '—' : formatPrice(c.first.lastPriceTtc);
      }

      final latest = view.latest;
      final bytes = await buildA4Report(
        title: 'Tableau de bord - ${_product.code} $_year',
        subtitle:
            '${view.selectedLabel.isNotEmpty ? 'Quinzaine affichée : ${view.selectedLabel} · ' : ''}'
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
          if (data.currentYear.isNotEmpty)
            PdfLineChart(
              title: 'Prix MAD TTC/M³ — ${_product.code} ($_year vs ${_year - 1})',
              labels: [for (final c in data.currentYear) c.label],
              leftAxisName: 'MAD/M³',
              height: 130,
              series: [
                PdfSeries('$_year', [for (final c in data.currentYear) c.value], area: true),
                PdfSeries('${_year - 1}', _previousYearValues(data), color: pdfOrange, dashed: true),
              ],
            ),
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
          if (view.evolution.isNotEmpty)
            PdfLineChart(
              title: 'Évolution — ${view.selectedLabel}',
              labels: [for (final e in view.evolution) formatDate(e.date)],
              leftAxisName: 'MAD TTC/M³',
              half: view.quotes.isNotEmpty,
              series: [
                PdfSeries('Prix MAD TTC/M³', [for (final e in view.evolution) e.value], area: true),
              ],
            ),
          if (view.quotes.isNotEmpty)
            PdfLineChart(
              title: 'Cotations Platts CIF NWE — ${view.selectedLabel}',
              labels: [for (final q in view.quotes) formatDate(q.date)],
              leftAxisName: r'CIF NWE $/T',
              referenceY: view.quotesAverage,
              referenceLabel: view.quotesAverage == null
                  ? null
                  : 'Moyenne : ${formatValue(view.quotesAverage)} \$/T',
              half: view.evolution.isNotEmpty,
              series: [
                PdfSeries(r'CIF NWE $/T', [for (final q in view.quotes) q.value],
                    color: pdfTeal, area: true),
              ],
            ),
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
        'no_recipients' => 'aucun destinataire — cochez « Reçoit l’email quotidien » dans Utilisateurs',
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
    required this.quotesAverage,
    required this.evolution,
  });

  final DashboardData data;
  final Calculation? latest;
  final double? variation;
  final String selectedLabel;
  final List<DatedValue> quotes;
  final double? quotesAverage;
  final List<DatedValue> evolution;
}

/// Today's TTC price on the brand gradient.
class _HeroPrice extends StatelessWidget {
  const _HeroPrice({required this.data, required this.variation, required this.product});

  final DashboardData data;
  final double? variation;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.72);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.palette.isDark
            ? null
            : [BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.amberBright.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  product.code,
                  style: const TextStyle(color: AppColors.amberBright, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Prix d’achat TTC du jour', style: TextStyle(color: muted, fontSize: 13)),
              ),
              if (variation != null) _HeroVariation(variation!),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatPrice(data.todayPriceTtc),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('MAD/M³', style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _HeroMeta(Icons.today_rounded,
                  data.todayPriceDate != null ? formatDate(data.todayPriceDate) : '—'),
              _HeroMeta(
                Icons.date_range_rounded,
                data.windowStart != null
                    ? 'Fenêtre ${formatDate(data.windowStart)} → ${formatDate(data.windowEnd)}'
                    : 'Fenêtre —',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.72);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: muted),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: muted, fontSize: 12.5)),
      ],
    );
  }
}

class _HeroVariation extends StatelessWidget {
  const _HeroVariation(this.value);

  final double value;

  @override
  Widget build(BuildContext context) {
    final down = value <= 0;
    final color = down ? const Color(0xFF5EEAD4) : const Color(0xFFFCA5A5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(down ? Icons.trending_down_rounded : Icons.trending_up_rounded, size: 15, color: color),
          const SizedBox(width: 4),
          Text(formatSigned(value), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in quinzaineStatusLabels.entries) StatusChip(e.value, color: p.status(e.key)),
      ],
    );
  }
}

class _QuinzaineGrid extends StatelessWidget {
  const _QuinzaineGrid({required this.cells, required this.selected, required this.onTap});

  final List<GridCell> cells;
  final ({int month, int period})? selected;
  final ValueChanged<GridCell> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth > 600 ? 6 : 3;
        final w = (c.maxWidth - (perRow - 1) * 8) / perRow;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final cell in cells) SizedBox(width: w, child: _cell(context, cell))],
        );
      },
    );
  }

  Widget _cell(BuildContext context, GridCell cell) {
    final p = context.palette;
    final active = selected?.month == cell.month && selected?.period == cell.period;
    final color = p.status(cell.status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: active ? p.accentSoft : p.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? p.accent : Colors.transparent, width: 1.6),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(cell),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cell.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textMuted),
                      ),
                    ),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatPrice(cell.lastPriceTtc),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cell.lastPriceTtc == null ? p.textMuted : p.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
