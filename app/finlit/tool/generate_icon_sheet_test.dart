import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';

/// Контрольный лист пиктограмм: все значки разом, в двух размерах.
///
/// Шесть десятков иконок, написанных кодом без предпросмотра, невозможно
/// проверить чтением исходника. Лист рендерится за секунду и показывает всё:
/// где перо слишком толстое, где силуэт не читается на мелком размере,
/// где форма просто не получилась.
///
///     flutter test tool/generate_icon_sheet_test.dart
void main() {
  testWidgets('лист пиктограмм', (WidgetTester tester) async {
    await loadAppFonts();
    final File f = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (f.existsSync()) {
      final FontLoader l = FontLoader('Roboto')
        ..addFont(Future<ByteData>.value(
            ByteData.view(f.readAsBytesSync().buffer)));
      await l.load();
    }

    const Color ink = Color(0xFF1E2749);
    const Color paper = Color(0xFFF5F7FC);

    // Поле считается от числа пиктограмм: восемь в ряду по 126 логических
    // точек. Иначе Wrap переносит всё вниз и лист обрезается по высоте.
    const int perRow = 8;
    final int rows = (Pic.values.length + perRow - 1) ~/ perRow;
    final double sheetW = perRow * 126 + 48;
    final double sheetH = rows * 124 + 48;
    tester.view.physicalSize = Size(sheetW * 2, sheetH * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            color: paper,
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 18,
              runSpacing: 18,
              children: <Widget>[
                for (final Pic p in Pic.values)
                  SizedBox(
                    width: 108,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Pictogram(p, size: 56, color: ink),
                        const SizedBox(height: 6),
                        // Мелкий размер — главная проверка: на 20 px форма
                        // либо читается, либо превращается в кляксу.
                        Pictogram(p, size: 20, color: ink),
                        const SizedBox(height: 4),
                        Text(p.name,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF5A6486))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.runAsync(() async {
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 2.0);
      final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
      final File out = File('build/icon-sheet.png');
      await out.create(recursive: true);
      await out.writeAsBytes(png!.buffer.asUint8List());
      // ignore: avoid_print
      print('лист: ${img.width}×${img.height} → ${out.path}');
    });
  });
}
