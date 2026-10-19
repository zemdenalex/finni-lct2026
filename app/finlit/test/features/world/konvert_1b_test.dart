import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/icons.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/onboarding/onboarding_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/lint_child_texts.dart' as lint;
import '../../support/world_harness.dart';

/// Правило 1Б Насти (18.10): «конверты» — образ методики, но один раз и
/// только в обучении: сценка знакомства `envelopes` называет «Три конверта:
/// «Нужное», «Хочу», «Копилка»» и показывает картинку конверта. Во всех
/// остальных детских строках — «три части».
///
/// Уронит: слово «конверт» вернулось в другой экран или контент; сценка
/// снова без конвертов (или с капсом); у трёх частей пропала картинка.
void main() {
  test('сценка envelopes называет три конверта обычными буквами', () {
    final OnboardingScene sc = contentScript.scenes
        .firstWhere((OnboardingScene s) => s.id == 'envelopes');
    expect(sc.showEnvelopes, isTrue);
    expect(
        sc.lines.single, contains('Три конверта: «Нужно», «Хочу», «Копилка»'));
  });

  test('«конверт» в детских строках — только в сценке envelopes', () {
    final List<String> where = <String>[];
    for (final File f in lint.childDartFiles()) {
      for (final (int line, String s)
          in lint.dartStrings(f.readAsStringSync())) {
        // Экраны банка (ТЗ Насти 18.10, экраны 10–11) больше не исключение:
        // тексты переписаны по Т1 Б («часть»), решение pm 19.10.
        if (RegExp('[Кк]онверт').hasMatch(s)) where.add('${f.path}:$line');
      }
    }
    for (final String p in lint.childJsonFiles) {
      for (final (String key, String s)
          in lint.jsonStrings(jsonDecode(File(p).readAsStringSync()))) {
        if (RegExp('[Кк]онверт').hasMatch(s)) where.add('$p:$key');
      }
    }
    expect(where, <String>['${lint.konvertAllowedAt}[0]']);
  });

  testWidgets('у каждой из трёх частей — картинка конверта',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: EnvelopeCards(need: 'еда', want: 'кино', goal: 'цель')),
    ));
    expect(
        find.byWidgetPredicate(
            (Widget w) => w is Pictogram && w.pic == Pic.envelope),
        findsNWidgets(3));
  });
}
