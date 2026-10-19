import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/features/world/adaptive_sweep_test.dart'
    show SweepOpen, sweepScreens;
import '../test/support/world_screens.dart';
import 'test_fonts.dart';

/// Кадры «стиль Алины» — ключевые экраны ребёнка на 360×640 и 640×360:
///
///     OUT=before flutter test tool/render_stil_alina_test.dart
///       →  build/stil-alina/<OUT>/*.png
///
/// Сравниваются с её кадрами `docs/final/stil-alina-kadry/` (вне репозитория).
/// На CI не гоняется.
const List<String> stilScreens = <String>[
  'S1 комната · дни',
  'S1 комната · меню «Ещё»',
  'S2 город',
  'S4 магазин',
  'S6 доска',
  'S7 мини-игра consultant',
  'S9 копилка',
  'S11 итоги',
  'S11 итоги · оплачено',
  'S12 прогресс',
  'S15 настройки',
  'S6 доска · окно «Монеты»',
  'S9 копилка · окно «Силы»',
];

/// Окна поверх экрана: экран из обхода + касание по ключу.
const Map<String, (String, String)> _windows = <String, (String, String)>{
  'S6 доска · окно «Монеты»': ('S6 доска', 'hud:coins'),
  'S9 копилка · окно «Силы»': ('S9 копилка', 'hud:energy'),
};

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  final String outDir = Platform.environment['OUT'] ?? 'after';
  final double scale =
      double.tryParse(Platform.environment['SCALE'] ?? '') ?? 1;
  final Map<String, ((Widget, World Function()), SweepOpen?)> all =
      sweepScreens();
  for (final String name in stilScreens) {
    final (String, String)? win = _windows[name];
    final ((Widget, World Function()), SweepOpen?)? s = win == null
        ? all[name]
        : switch (all[win.$1]) {
            final ((Widget, World Function()), SweepOpen?) base => (
                base.$1,
                (WidgetTester t) async {
                  final Finder f = find.byKey(ValueKey<String>(win.$2));
                  await t.ensureVisible(f.last);
                  await t.pump();
                  await t.tap(f.last);
                  await t.pump();
                  await t.pump(const Duration(milliseconds: 400));
                }
              ),
            null => null,
          };
    if (s == null) continue;
    for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
      final String tag = '${size.width.toInt()}x${size.height.toInt()}'
          '${scale == 1 ? '' : '-$scale'}';
      testWidgets('$name $tag', (WidgetTester tester) async {
        await pumpListedScreen(tester, name, s.$1,
            size: size, textScale: scale);
        if (s.$2 case final SweepOpen open) await open(tester);
        tester.takeException();
        await tester.runAsync(() async {
          // Картинки (фон экрана) успевают раскодироваться.
          for (int i = 0; i < 6; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump();
          }
          final ui.Image img =
              await captureImage(find.byType(Navigator).first.evaluate().first);
          final ByteData? png =
              await img.toByteData(format: ui.ImageByteFormat.png);
          final String file = name
              .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁё_-]+'), '_')
              .replaceAll(RegExp('_+'), '_');
          final File out = File('build/stil-alina/$outDir/$file-$tag.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}
