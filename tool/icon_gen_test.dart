// Renders the launcher icon sources: flutter test tool/icon_gen_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _navy = Color(0xFF0B1F33);
const _amber = Color(0xFFD97706);

class _Icon extends StatelessWidget {
  const _Icon({required this.background, required this.scale});

  final bool background;

  /// Share of the canvas used by the mark (adaptive icons need a safe zone).
  final double scale;

  @override
  Widget build(BuildContext context) {
    const size = 1024.0;
    final mark = size * scale;
    return Container(
      width: size,
      height: size,
      color: background ? _navy : Colors.transparent,
      alignment: Alignment.center,
      child: SizedBox(
        width: mark,
        height: mark,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'BGI',
              style: TextStyle(
                fontFamily: 'OpenSansBold',
                fontSize: mark * 0.36,
                height: 1,
                color: Colors.white,
                letterSpacing: mark * 0.01,
              ),
            ),
            SizedBox(height: mark * 0.06),
            Container(
              width: mark * 0.62,
              height: mark * 0.07,
              decoration: BoxDecoration(
                color: _amber,
                borderRadius: BorderRadius.circular(mark * 0.035),
              ),
            ),
            SizedBox(height: mark * 0.05),
            Text(
              'PRICING',
              style: TextStyle(
                fontFamily: 'OpenSansBold',
                fontSize: mark * 0.11,
                height: 1,
                color: _amber,
                letterSpacing: mark * 0.025,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _render(WidgetTester tester, Widget icon, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: RepaintBoundary(key: key, child: icon)),
    ),
  );
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('generate launcher icons', (tester) async {
    final loader = FontLoader('OpenSansBold')
      ..addFont(rootBundle.load('assets/fonts/OpenSans-Bold.ttf'));
    await loader.load();
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _render(tester, const _Icon(background: true, scale: 0.78), 'assets/icon/icon.png');
    await _render(tester, const _Icon(background: false, scale: 0.56), 'assets/icon/icon_foreground.png');
  });
}
