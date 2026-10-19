import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// ТЗ 3.6 (озвучка) и §5.8: всё, что нажимается, TalkBack называет словами
/// (`labeledTapTargetGuideline`); текст на сплошном фоне читается — контраст
/// не ниже 4,5:1 (`textContrastGuideline`). Каждый экран нового мира, обе
/// ориентации.
///
/// Уронит: кнопку-значок без подписи, касание фона, объявленное кнопкой
/// без имени (так было на карте города и в сценках знакомства — аудит
/// 16.10), бледный текст на панели.
void main() {
  setUp(rootBundle.clear);

  forEachWorld((WorldKind kind) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final MapEntry<String, (Widget, World Function())> s
          in worldScreens(kind).entries) {
        testWidgets('${s.key} · ${o.key}: подписи и контраст',
            (WidgetTester tester) async {
          final SemanticsHandle sem = tester.ensureSemantics();
          await pumpListedScreen(tester, s.key, s.value, size: o.value);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          sem.dispose();
        });
      }
    }
  });
}
