import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/features/world/adaptive_sweep_test.dart'
    show SweepOpen, sweepScreens, sweepSizes;
import '../test/support/world_screens.dart';
import 'test_fonts.dart';

/// Кадры обхода адаптива — все экраны [sweepScreens] на [sweepSizes]:
///
///     flutter test tool/render_adaptive_sweep_test.dart  →  build/adaptive-sweep/*.png
///
/// `ONLY=S6` — экраны, чьё имя содержит строку; `SCALE=1.3` — шрифт ×1,3.
/// На CI не гоняется.
void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  final String only = Platform.environment['ONLY'] ?? '';
  final double scale =
      double.tryParse(Platform.environment['SCALE'] ?? '') ?? 1;
  for (final MapEntry<String, ((Widget, World Function()), SweepOpen?)> s
      in sweepScreens().entries) {
    if (only.isNotEmpty && !s.key.contains(only)) continue;
    for (final Size size in sweepSizes) {
      final String tag = '${size.width.toInt()}x${size.height.toInt()}'
          '${scale == 1 ? '' : '-$scale'}';
      testWidgets('${s.key} $tag', (WidgetTester tester) async {
        await pumpListedScreen(tester, s.key, s.value.$1,
            size: size, textScale: scale);
        if (s.value.$2 case final SweepOpen open) await open(tester);
        tester.takeException();
        await tester.runAsync(() async {
          // Весь экран с листами и меню (они — в оверлее навигатора).
          final ui.Image img =
              await captureImage(find.byType(Navigator).first.evaluate().first);
          final ByteData? png =
              await img.toByteData(format: ui.ImageByteFormat.png);
          final String name = s.key
              .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁё_-]+'), '_')
              .replaceAll(RegExp('_+'), '_');
          final File out = File('build/adaptive-sweep/$name-$tag.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}
