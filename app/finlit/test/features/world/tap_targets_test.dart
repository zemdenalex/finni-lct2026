import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/tap_target_guideline.dart';
import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// ТЗ 3.6.3: каждая цель касания на каждом экране нового мира — не меньше
/// 48 × 48 dp (`androidTapTargetGuideline`), в обеих ориентациях.
///
/// Ловит: кнопку-иконку или плитку меньше пальца. Штатное правило пропускает
/// цели у края экрана (HUD, нижняя панель комнаты), поэтому рядом —
/// [edgeTapTargetGuideline]. Проверено мутацией: нижняя панель комнаты
/// высотой 40 dp штатное правило проходит, это — нет.
///
/// Охват: начальное состояние каждого экрана из [worldScreens]. Главные
/// диалоги и листы — `dialog_a11y_test.dart`; содержимое за прокруткой не
/// проверяется.
void main() {
  setUp(rootBundle.clear);

  forEachWorld((WorldKind kind) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final MapEntry<String, (Widget, World Function())> s
          in worldScreens(kind).entries) {
        testWidgets('${s.key} · ${o.key}: цели касания ≥ 48 dp',
            (WidgetTester tester) async {
          final SemanticsHandle sem = tester.ensureSemantics();
          await pumpListedScreen(tester, s.key, s.value, size: o.value);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(edgeTapTargetGuideline));
          sem.dispose();
        });
      }
    }
  });
}
