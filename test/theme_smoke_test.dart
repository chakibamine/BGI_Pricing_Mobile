import 'package:bgi_pricing_mobile/core/charts.dart';
import 'package:bgi_pricing_mobile/core/pdf_report.dart';
import 'package:bgi_pricing_mobile/core/theme.dart';
import 'package:bgi_pricing_mobile/core/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  for (final (name, theme) in [('light', buildLightTheme()), ('dark', buildDarkTheme())]) {
    testWidgets('components render in $name mode', (tester) async {
      await tester.pumpWidget(_harness(
        theme,
        Builder(builder: (context) {
          final p = context.palette;
          return Column(
            children: [
              const KpiGrid(children: [
                KpiCard(label: 'Prix TTC', value: '12,34', sub: 'MAD/M³', accent: true, icon: Icons.local_gas_station),
                KpiCard(label: 'CIF NWE', value: '700,0000', icon: Icons.water_drop_outlined),
              ]),
              Panel(
                title: 'Graphique',
                subtitle: 'Sous-titre',
                icon: Icons.show_chart,
                child: SeriesChart(
                  labels: const ['01/10/2026', '02/10/2026', '03/10/2026'],
                  referenceY: 2,
                  referenceLabel: 'Moyenne',
                  series: [
                    ChartSeries(name: 'A', values: const [1, 2, 3], color: p.primary, area: true),
                    ChartSeries(name: 'B', values: const [3, null, 1], color: p.chartAlt, dashed: true),
                  ],
                ),
              ),
              StatusChip('En cours', color: p.status('en_cours')),
              const InfoBanner('Info', kind: BannerKind.info),
              const InfoBanner('Erreur', kind: BannerKind.error),
              ListCard(title: const Text('Ligne'), subtitle: const Text('Détail'), onTap: () {}),
              const EmptyState('Vide'),
            ],
          );
        }),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Prix TTC'), findsOneWidget);
      expect(Theme.of(tester.element(find.text('Vide'))).extension<AppPalette>()?.isDark, name == 'dark');
    });
  }

  testWidgets('skeleton loading animates without errors', (tester) async {
    await tester.pumpWidget(_harness(buildDarkTheme(), const SkeletonPage()));
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);
  });

  test('PDF report with native line charts builds', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await buildA4Report(
      title: 'Test',
      subtitle: 'Sous-titre',
      blocks: [
        const PdfKpis([PdfKpi('Prix', '12,34', accent: true)]),
        const PdfLineChart(
          title: 'Double axe',
          labels: ['01/10/2026', '02/10/2026', '03/10/2026', '04/10/2026'],
          leftAxisName: r'CIF $/T',
          rightAxisName: 'TTC',
          referenceY: 705,
          referenceLabel: 'Moyenne',
          series: [
            PdfSeries('TTC', [12.1, 12.3, null, 12.2], rightAxis: true, area: true),
            PdfSeries('CIF', [700, 710, 705, 702], color: pdfOrange, dashed: true),
          ],
        ),
        const PdfLineChart(title: 'Demi 1', labels: ['a'], series: [PdfSeries('x', [1])], half: true),
        const PdfLineChart(title: 'Demi 2', labels: [], series: [], half: true),
      ],
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
