import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/onboarding/onboarding_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

// Скриншот Саши 15.10 («Знакомство», план в альбомной): «390» в ХОЧУ мельче
// «10» и «0». Уронит: число снова ужимается каждое в своём конверте.
// (Высота карточек проверена рендером: тест на неё не падал на старом коде.)
void main() {
  setUpAll(loadAppFonts);

  testWidgets('альбомная: числа в трёх конвертах одного размера',
      (WidgetTester tester) async {
    tester.view.physicalSize = landscape;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const ResourceSnapshot snap = ResourceSnapshot(
      weekNo: 1,
      need: 0,
      want: 0,
      goal: 0,
      free: 0,
      unallocated: 400,
      energy: 10,
      happiness: 50,
      growthPoints: 0,
      stage: WorldStage.village,
      experience: 0,
      shiftsThisWeek: 0,
      weeklyBill: 460,
      owned: <String>{},
    );
    await tester.pumpWidget(MaterialApp(
      home: WorldTheme(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 490,
              child: PlanEditor(
                ui: contentScript,
                snapshot: snap,
                planning: true,
                needs: 10,
                wants: 390,
                goal: 0,
                onChange: (int a, int b, int c) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    double glyph(String v) => tester.getRect(find.text(v)).height;
    expect(glyph('390'), closeTo(glyph('10'), 0.5), reason: '390 мельче 10');
    expect(glyph('0'), closeTo(glyph('10'), 0.5));
  });
}
