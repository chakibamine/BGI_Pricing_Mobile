import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

enum ChartAxis { left, right }

class ChartSeries {
  const ChartSeries({
    required this.name,
    required this.values,
    required this.color,
    this.axis = ChartAxis.left,
    this.dashed = false,
    this.area = false,
    this.dots = true,
    this.digits = priceDigits,
  });

  final String name;

  /// One value per label; null = gap.
  final List<double?> values;
  final Color color;
  final ChartAxis axis;
  final bool dashed;
  final bool area;
  final bool dots;

  /// Tooltip precision.
  final int digits;
}

class _Domain {
  const _Domain(this.min, this.max);
  final double min;
  final double max;
  double get span => max - min;
}

/// Range hugging the data with a margin (same rule as the web charts).
_Domain _tightDomain(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return const _Domain(0, 1);
  final lo = list.reduce(math.min);
  final hi = list.reduce(math.max);
  final pad = hi > lo ? (hi - lo) * 0.15 : (hi.abs() * 0.01 == 0 ? 1 : hi.abs() * 0.01);
  return _Domain((lo - pad).floorToDouble(), (hi + pad).ceilToDouble());
}

/// Line / area chart with optional right axis (values rescaled onto the left
/// axis) and an optional horizontal reference line.
class SeriesChart extends StatelessWidget {
  const SeriesChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 240,
    this.leftAxisName,
    this.rightAxisName,
    this.referenceY,
    this.referenceLabel,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final double height;
  final String? leftAxisName;
  final String? rightAxisName;
  final double? referenceY;
  final String? referenceLabel;

  @override
  Widget build(BuildContext context) {
    Iterable<double> valuesOf(ChartAxis axis) => series
        .where((s) => s.axis == axis)
        .expand((s) => s.values)
        .whereType<double>();

    final leftValues = [...valuesOf(ChartAxis.left), ?referenceY];
    final left = _tightDomain(leftValues);
    final hasRight = series.any((s) => s.axis == ChartAxis.right);
    final right = hasRight ? _tightDomain(valuesOf(ChartAxis.right)) : left;

    double toLeft(double v) => right.span == 0
        ? v
        : left.min + (v - right.min) / right.span * left.span;
    double fromLeft(double v) => left.span == 0
        ? v
        : right.min + (v - left.min) / left.span * right.span;

    final p = context.palette;
    final step = math.max(1, (labels.length / 6).ceil());
    final tickStyle = TextStyle(fontSize: 10, color: p.textMuted);

    AxisTitles valueTitles(bool isRight, String? name) => AxisTitles(
          axisNameWidget: name == null
              ? null
              : Text(name, style: TextStyle(fontSize: 10, color: p.textMuted)),
          axisNameSize: name == null ? 0 : 16,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox.shrink();
              }
              final v = isRight ? fromLeft(value) : value;
              return SideTitleWidget(
                meta: meta,
                child: Text(formatNumber(v, 0), style: tickStyle),
              );
            },
          ),
        );

    final bars = [
      for (final s in series)
        LineChartBarData(
          spots: [
            for (var i = 0; i < s.values.length; i++)
              s.values[i] == null
                  ? FlSpot.nullSpot
                  : FlSpot(
                      i.toDouble(),
                      s.axis == ChartAxis.right ? toLeft(s.values[i]!) : s.values[i]!,
                    ),
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          color: s.color,
          barWidth: 2.4,
          isStrokeCapRound: true,
          dashArray: s.dashed ? [5, 4] : null,
          dotData: FlDotData(
            show: s.dots && labels.length <= 31,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 2.6,
              color: s.color,
              strokeWidth: 1.5,
              strokeColor: p.surface,
            ),
          ),
          belowBarData: BarAreaData(
            show: s.area,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [s.color.withValues(alpha: p.isDark ? 0.30 : 0.20), s.color.withValues(alpha: 0)],
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in series)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: p.tint(s.color),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: s.dashed ? 12 : 8,
                      height: s.dashed ? 3 : 8,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.name,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textPrimary),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(0, labels.length - 1).toDouble(),
              minY: left.min,
              maxY: left.max,
              lineBarsData: bars,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: p.chartGrid, strokeWidth: 1, dashArray: const [3, 3]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                leftTitles: valueTitles(false, leftAxisName),
                rightTitles: hasRight
                    ? valueTitles(true, rightAxisName)
                    : const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (value != i || i < 0 || i >= labels.length || i % step != 0) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(_shortLabel(labels[i]), style: tickStyle),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: referenceY == null
                  ? const ExtraLinesData()
                  : ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: referenceY!,
                          color: p.chartAlt,
                          strokeWidth: 1.5,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: referenceLabel != null,
                            alignment: Alignment.topRight,
                            style: TextStyle(
                              fontSize: 10,
                              color: p.chartAlt,
                              fontWeight: FontWeight.w600,
                            ),
                            labelResolver: (_) => referenceLabel ?? '',
                          ),
                        ),
                      ],
                    ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => p.isDark ? p.surfaceAlt : AppColors.navyDeep,
                  tooltipBorderRadius: BorderRadius.circular(10),
                  getTooltipItems: (spots) => [
                    for (final (n, spot) in spots.indexed)
                      LineTooltipItem(
                        '${n == 0 ? '${labels[spot.x.round()]}\n' : ''}'
                        '${series[spot.barIndex].name} : '
                        '${formatNumber(series[spot.barIndex].values[spot.x.round()], series[spot.barIndex].digits)}',
                        TextStyle(color: p.isDark ? p.textPrimary : Colors.white, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// "14/10/2026" -> "14/10" to keep the x axis readable.
  static String _shortLabel(String label) =>
      RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(label) ? label.substring(0, 5) : label;
}
