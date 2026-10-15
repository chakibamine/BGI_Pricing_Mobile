import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'format.dart';

const _navy = PdfColor.fromInt(0xFF0B1F33);
const _amber = PdfColor.fromInt(0xFFD97706);
const _amberSoft = PdfColor.fromInt(0xFFFEF3C7);
const _muted = PdfColor.fromInt(0xFF64748B);
const _border = PdfColor.fromInt(0xFFE3E8EF);
const _steel = PdfColor.fromInt(0xFFF1F4F8);

sealed class PdfBlock {
  const PdfBlock();
}

class PdfKpi {
  const PdfKpi(this.label, this.value, {this.sub, this.accent = false});
  final String label;
  final String value;
  final String? sub;
  final bool accent;
}

class PdfKpis extends PdfBlock {
  const PdfKpis(this.items);
  final List<PdfKpi> items;
}

class PdfTable extends PdfBlock {
  const PdfTable({
    required this.title,
    required this.headers,
    required this.rows,
    this.totalRow = false,
    this.half = false,
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  /// Highlights the last row (e.g. "Prix TTC").
  final bool totalRow;

  /// Rendered side by side with the next half-width table.
  final bool half;
}

class PdfImage extends PdfBlock {
  const PdfImage(this.title, this.png, {this.half = false});
  final String title;
  final Uint8List png;
  final bool half;
}

class PdfNote extends PdfBlock {
  const PdfNote(this.text);
  final String text;
}

class PdfSeries {
  const PdfSeries(
    this.name,
    this.values, {
    this.color = _navy,
    this.dashed = false,
    this.area = false,
    this.rightAxis = false,
  });

  final String name;

  /// One value per label; null = gap.
  final List<double?> values;
  final PdfColor color;
  final bool dashed;
  final bool area;
  final bool rightAxis;
}

/// Vector line chart (always light, independent of the app theme).
class PdfLineChart extends PdfBlock {
  const PdfLineChart({
    required this.title,
    required this.labels,
    required this.series,
    this.leftAxisName,
    this.rightAxisName,
    this.referenceY,
    this.referenceLabel,
    this.half = false,
    this.height = 150,
  });

  final String title;
  final List<String> labels;
  final List<PdfSeries> series;
  final String? leftAxisName;
  final String? rightAxisName;
  final double? referenceY;
  final String? referenceLabel;
  final bool half;
  final double height;
}

const pdfNavy = _navy;
const pdfOrange = PdfColor.fromInt(0xFFE67E22);
const pdfTeal = PdfColor.fromInt(0xFF0F766E);
const pdfViolet = PdfColor.fromInt(0xFF7C3AED);

/// Single A4 page: content is scaled down when it would overflow.
Future<Uint8List> buildA4Report({
  required String title,
  required String subtitle,
  required List<PdfBlock> blocks,
}) async {
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: title,
  );

  const margin = 24.0;
  final contentWidth = PdfPageFormat.a4.width - 2 * margin;

  final children = <pw.Widget>[];
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final next = i + 1 < blocks.length ? blocks[i + 1] : null;
    if (_isHalf(b) && next != null && _isHalf(next)) {
      final halfWidth = (contentWidth - 10) / 2;
      children.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _block(b, halfWidth)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _block(next, halfWidth)),
          ],
        ),
      );
      i++;
    } else {
      children.add(_block(b, contentWidth));
    }
    children.add(pw.SizedBox(height: 10));
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: const pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topCenter,
                child: pw.SizedBox(
                  width: contentWidth,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

bool _isHalf(PdfBlock b) =>
    (b is PdfTable && b.half) ||
    (b is PdfImage && b.half) ||
    (b is PdfLineChart && b.half);

pw.Widget _title(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
          color: _navy,
        ),
      ),
    );

pw.Widget _block(PdfBlock b, double width) {
  switch (b) {
    case PdfLineChart():
      return _lineChart(b, width);
    case PdfKpis(:final items):
      return pw.Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 6),
            pw.Expanded(child: _kpi(items[i])),
          ],
        ],
      );
    case PdfTable():
      return _table(b);
    case PdfImage(:final title, :final png):
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [_title(title), pw.Image(pw.MemoryImage(png))],
      );
    case PdfNote(:final text):
      return pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: _muted));
  }
}

pw.Widget _kpi(PdfKpi k) => pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: k.accent ? _amberSoft : PdfColors.white,
        border: pw.Border.all(color: k.accent ? _amber : _border),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            k.label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 6.5,
              color: _muted,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            k.value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: k.accent ? _amber : _navy,
            ),
          ),
          if (k.sub != null)
            pw.Text(k.sub!, style: const pw.TextStyle(fontSize: 6.5, color: _muted)),
        ],
      ),
    );

pw.Widget _table(PdfTable t) {
  final cols = t.headers.length;
  pw.Widget cell(String text, {bool header = false, bool strong = false, int col = 0}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
        child: pw.Text(
          text,
          textAlign: col == 0 ? pw.TextAlign.left : pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: header || strong ? pw.FontWeight.bold : null,
            color: header ? PdfColors.white : null,
          ),
        ),
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _title(t.title),
      pw.Table(
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _border, width: 0.5),
          bottom: pw.BorderSide(color: _border, width: 0.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.6),
          for (var c = 1; c < cols; c++) c: const pw.FlexColumnWidth(1),
        },
        children: [
          if (t.headers.any((h) => h.isNotEmpty))
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _navy),
              children: [
                for (var c = 0; c < cols; c++)
                  cell(t.headers[c], header: true, col: c),
              ],
            ),
          for (var r = 0; r < t.rows.length; r++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: t.totalRow && r == t.rows.length - 1
                    ? _amberSoft
                    : (r.isOdd ? _steel : null),
              ),
              children: [
                for (var c = 0; c < cols; c++)
                  cell(
                    c < t.rows[r].length ? t.rows[r][c] : '',
                    col: c,
                    strong: t.totalRow && r == t.rows.length - 1,
                  ),
              ],
            ),
        ],
      ),
    ],
  );
}

class _Range {
  const _Range(this.min, this.max);
  final double min;
  final double max;
  double get span => max - min;
}

_Range _tightRange(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return const _Range(0, 1);
  final lo = list.reduce(math.min);
  final hi = list.reduce(math.max);
  final pad = hi > lo ? (hi - lo) * 0.15 : (hi.abs() * 0.01 == 0 ? 1 : hi.abs() * 0.01);
  return _Range((lo - pad).floorToDouble(), (hi + pad).ceilToDouble());
}

String _shortLabel(String label) =>
    RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(label) ? label.substring(0, 5) : label;

pw.Widget _lineChart(PdfLineChart c, double width) {
  const axisWidth = 30.0;
  const tickCount = 5;
  const labelStyle = pw.TextStyle(fontSize: 6, color: _muted);
  final n = c.labels.length;
  final hasRight = c.series.any((s) => s.rightAxis);

  Iterable<double> valuesOf(bool right) =>
      c.series.where((s) => s.rightAxis == right).expand((s) => s.values).whereType<double>();
  final left = _tightRange([...valuesOf(false), ?c.referenceY]);
  final right = hasRight ? _tightRange(valuesOf(true)) : left;

  final plotWidth = width - axisWidth - (hasRight ? axisWidth + 4 : 0);
  final h = c.height;
  double xAt(int i) => n <= 1 ? plotWidth / 2 : i / (n - 1) * plotWidth;
  double yAt(double v, _Range r) => r.span == 0 ? h / 2 : (v - r.min) / r.span * h;
  final ticks = [for (var t = 0; t <= tickCount - 1; t++) t / (tickCount - 1)];

  pw.Widget axisLabels(_Range r, pw.TextAlign align) => pw.SizedBox(
        width: axisWidth,
        height: h,
        child: pw.Stack(
          overflow: pw.Overflow.visible,
          children: [
            for (final t in ticks)
              pw.Positioned(
                left: 0,
                top: h - t * h - 4,
                child: pw.SizedBox(
                  width: axisWidth - 4,
                  child: pw.Text(
                    formatNumber(r.min + t * r.span, 0),
                    style: labelStyle,
                    textAlign: align,
                  ),
                ),
              ),
          ],
        ),
      );

  final plot = pw.CustomPaint(
    size: PdfPoint(plotWidth, h),
    painter: (canvas, size) {
      canvas
        ..setStrokeColor(_border)
        ..setLineWidth(0.5)
        ..setLineDashPattern([2, 2]);
      for (final t in ticks) {
        canvas
          ..moveTo(0, t * h)
          ..lineTo(plotWidth, t * h);
      }
      canvas
        ..strokePath()
        ..setLineDashPattern();

      for (final s in c.series) {
        final r = s.rightAxis ? right : left;
        final segments = <List<PdfPoint>>[[]];
        for (var i = 0; i < s.values.length && i < n; i++) {
          final v = s.values[i];
          if (v == null) {
            if (segments.last.isNotEmpty) segments.add([]);
          } else {
            segments.last.add(PdfPoint(xAt(i), yAt(v, r)));
          }
        }
        for (final seg in segments.where((s) => s.isNotEmpty)) {
          if (s.area && seg.length > 1) {
            canvas
              ..saveContext()
              ..setGraphicState(const PdfGraphicState(fillOpacity: 0.12))
              ..setFillColor(s.color)
              ..moveTo(seg.first.x, 0);
            for (final p in seg) {
              canvas.lineTo(p.x, p.y);
            }
            canvas
              ..lineTo(seg.last.x, 0)
              ..closePath()
              ..fillPath()
              ..restoreContext();
          }
          canvas
            ..setStrokeColor(s.color)
            ..setLineWidth(1.4)
            ..setLineJoin(PdfLineJoin.round)
            ..setLineCap(PdfLineCap.round)
            ..setLineDashPattern(s.dashed ? [4, 3] : [])
            ..moveTo(seg.first.x, seg.first.y);
          for (final p in seg.skip(1)) {
            canvas.lineTo(p.x, p.y);
          }
          canvas
            ..strokePath()
            ..setLineDashPattern();
          if (n <= 31) {
            canvas.setFillColor(s.color);
            for (final p in seg) {
              canvas.drawEllipse(p.x, p.y, 1.4, 1.4);
            }
            canvas.fillPath();
          }
        }
      }

      if (c.referenceY != null) {
        final y = yAt(c.referenceY!, left);
        canvas
          ..setStrokeColor(pdfOrange)
          ..setLineWidth(1)
          ..setLineDashPattern([5, 3])
          ..moveTo(0, y)
          ..lineTo(plotWidth, y)
          ..strokePath()
          ..setLineDashPattern();
      }
    },
  );

  final step = math.max(1, (n / 6).ceil());
  final xLabels = pw.SizedBox(
    width: plotWidth,
    height: 10,
    child: pw.Stack(
      overflow: pw.Overflow.visible,
      children: [
        for (var i = 0; i < n; i += step)
          pw.Positioned(
            left: xAt(i) - 18,
            top: 2,
            child: pw.SizedBox(
              width: 36,
              child: pw.Text(_shortLabel(c.labels[i]), style: labelStyle, textAlign: pw.TextAlign.center),
            ),
          ),
      ],
    ),
  );

  pw.Widget legendItem(PdfColor color, String label, {bool dashed = false}) => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: dashed ? 10 : 6,
            height: dashed ? 2 : 6,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Text(label, style: const pw.TextStyle(fontSize: 6.5)),
        ],
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _title(c.title),
      pw.Wrap(
        spacing: 10,
        runSpacing: 3,
        children: [
          for (final s in c.series)
            legendItem(
              s.color,
              s.rightAxis && c.rightAxisName != null ? '${s.name} (axe droit)' : s.name,
              dashed: s.dashed,
            ),
          if (c.referenceY != null && c.referenceLabel != null)
            legendItem(pdfOrange, c.referenceLabel!, dashed: true),
        ],
      ),
      pw.SizedBox(height: 5),
      if (c.leftAxisName != null || c.rightAxisName != null)
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(c.leftAxisName ?? '', style: labelStyle),
            pw.Text(c.rightAxisName ?? '', style: labelStyle),
          ],
        ),
      pw.SizedBox(height: 3),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          axisLabels(left, pw.TextAlign.right),
          plot,
          if (hasRight)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 4),
              child: axisLabels(right, pw.TextAlign.left),
            ),
        ],
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: axisWidth),
        child: pw.Align(alignment: pw.Alignment.centerLeft, child: xLabels),
      ),
    ],
  );
}
