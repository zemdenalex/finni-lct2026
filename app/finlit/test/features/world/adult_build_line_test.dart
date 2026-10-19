import 'dart:math';

import 'package:finlit/core/build_info.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// C10, правило 8 Насти: «Сборка» — только во «Взрослым», не на экране
/// ребёнка. Строка нужна взрослому и команде (устаревший кэш веб-демо уже
/// дважды выдавал старую сборку), поэтому она переехала из меню ⋮ комнаты в
/// конец раздела взрослого. Уронит: строку убрали совсем или вернули в
/// комнату (это ловит `room_screen_test`).
void main() {
  testWidgets('раздел взрослого: последняя строка — сборка',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, WorldAdultScreen(random: Random(6)),
        world: contentWorld());
    final String q =
        tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
    await tester.enterText(find.byKey(WorldAdultScreen.answerKey),
        '${WorldAdultScreen.answerOf(q)}');
    final Finder enter = find.byKey(const ValueKey<String>('adult:enter'));
    if (enter.evaluate().isEmpty) {
      await tester.scrollUntilVisible(enter, 200,
          scrollable: find.byType(Scrollable).last);
    }
    await tester.ensureVisible(enter);
    await tester.pump();
    await tester.tap(enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final Finder line = find.byKey(const ValueKey<String>('adult:build'));
    await tester.scrollUntilVisible(line, 300,
        scrollable: find.byType(Scrollable).last);
    expect(tester.widget<Text>(line).data, 'Сборка $buildSha');
  });
}
