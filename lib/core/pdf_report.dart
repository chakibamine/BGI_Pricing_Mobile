import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

/// Single A4 page: content is scaled down when it would overflow.
Future<Uint8List> buildA4Report({
  required String title,
  required String subtitle,
  required List<PdfBlock> blocks,
}) async {
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/OpenSans-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/OpenSans-Bold.ttf'));
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
      children.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _block(b)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _block(next)),
          ],
        ),
      );
      i++;
    } else {
      children.add(_block(b));
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
    (b is PdfTable && b.half) || (b is PdfImage && b.half);

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

pw.Widget _block(PdfBlock b) {
  switch (b) {
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
