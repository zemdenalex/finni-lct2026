import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/plan_sheet.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/world_harness.dart';

/// Число в строке конверта листа плана — из её подписи «ИМЯ: число».
int _shown(WidgetTester tester, String name) {
  final Semantics s = tester.widget<Semantics>(find.byWidgetPredicate(
      (Widget w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('$name: ') ?? false)));
  return int.parse(s.properties.label!.substring(name.length + 2));
}

(int, int, int) _plan(WidgetTester tester) =>
    (_shown(tester, 'НУЖНО'), _shown(tester, 'ХОЧУ'), _shown(tester, 'ЦЕЛЬ'));

Future<void> _press(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
}

bool _enabled(WidgetTester tester, String tooltip) =>
    tester
        .widget<IconButton>(find.ancestor(
            of: find.byTooltip(tooltip), matching: find.byType(IconButton)))
        .onPressed !=
    null;

String _rest(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey<String>('plan:rest'))).data!;

/// Ловит (ТЗ 2.5.5.2, 2.5.5.3): правка степперами не доходит до мира —
/// подтверждается подсказка по умолчанию, а не то, что ребёнок выставил;
/// «+» разрешает разложить больше доступного; остаток не виден.
void main() {
  forEachWorld((WorldKind kind) {
    testWidgets('план меняется до «Готово»; подтверждён изменённый',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      await pumpWorldScreen(
        tester,
        Scaffold(
          body: Builder(
            builder: (BuildContext c) => TextButton(
              onPressed: () => showPlanSheet(c, c.read<WorldState>()),
              child: const Text('open'),
            ),
          ),
        ),
        world: w,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final (int need0, int want0, int goal0) = _plan(tester);
      expect(need0, greaterThanOrEqualTo(30),
          reason: 'настройка: из НУЖНО есть что убрать');
      expect(goal0, 0);
      expect(_rest(tester), planAllSpentLine);
      // Телефон 28.09: погашенный «+» выглядел сломанным. Настоящее касание
      // «+» при остатке 0 план не меняет и говорит, что сделать.
      await _press(tester, 'ЦЕЛЬ больше');
      expect(_plan(tester), (need0, want0, goal0));
      expect(find.text(planAllSpentHint), findsOneWidget);

      for (int i = 0; i < 3; i++) {
        await _press(tester, 'НУЖНО меньше');
      }
      expect(_rest(tester), 'Не разложено: 30 — уйдёт в кошелёк.');
      for (int i = 0; i < 3; i++) {
        await _press(tester, 'ЦЕЛЬ больше');
      }
      await _press(tester, 'ЦЕЛЬ меньше');
      await _press(tester, 'ХОЧУ больше');

      final (int need, int want, int goal) = _plan(tester);
      expect((need, want, goal), (need0 - 30, want0 + 10, 20));
      expect(_rest(tester), planAllSpentLine);
      for (final String t in <String>['НУЖНО больше', 'ХОЧУ больше']) {
        expect(_enabled(tester, t), isTrue, reason: '$t не гаснет');
        await _press(tester, t);
        expect(_plan(tester), (need, want, goal), reason: '$t при остатке 0');
      }

      // Подсказка добавляет строку — на 360×640 «Готово» уходит под край листа.
      await tester
          .ensureVisible(find.byKey(const ValueKey<String>('plan:confirm')));
      await tester.tap(find.byKey(const ValueKey<String>('plan:confirm')));
      await tester.pumpAndSettle();
      expect(w.phase, WeekPhase.living);
      final WeekPlanFact f = w.weekHistory.last;
      expect(
          (f.need.planned, f.want.planned, f.goal.planned), (need, want, goal));
    });
  });
}
