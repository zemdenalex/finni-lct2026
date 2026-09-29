import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Ловит: экран S0–S16 переполняется в одной из ориентаций. Альбомная —
/// основная, портрет от 360 dp обязан работать (решение команды 27.09,
/// ТЗ §3.1 п. 2); масштаб шрифта 1,3 — ТЗ 3.6.4.
void main() {
  // AppState.boot() читает контент через rootBundle: без очистки кеша второй
  // boot() в файле ждёт Future из зоны первого теста вечно.
  setUp(rootBundle.clear);

  forEachWorld((WorldKind kind) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final double scale in <double>[1, 1.3]) {
        for (final MapEntry<String, (Widget, World Function())> s
            in worldScreens(kind).entries) {
          testWidgets('${s.key} · ${o.key} · шрифт $scale',
              (WidgetTester tester) async {
            await pumpListedScreen(tester, s.key, s.value,
                size: o.value, textScale: scale);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
