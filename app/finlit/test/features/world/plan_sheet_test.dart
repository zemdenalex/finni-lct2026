import 'package:finlit/app_state.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/models/profile.dart';
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

/// Ловит (ТЗ 2.5.5.2, 2.5.5.3): правка степперами не доходит до мира;
/// «+» разрешает разложить больше доступного; остаток не виден. И первые
/// телефоны 29.09: конверты не с нуля (Денис), «+» без остатка молчит
/// (Саша: «потрясти элемент Пришло»), копилка читается как деньги на
/// неделю (Денис: «всего 600»).
void main() {
  Future<World> open(WidgetTester tester, World w, {AppState? app}) async {
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
      app: app,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return w;
  }

  double poolShift(WidgetTester tester) {
    final Iterable<Transform> t = tester.widgetList<Transform>(find.descendant(
        of: find.byKey(const ValueKey<String>('plan:pool')),
        matching: find.byType(Transform)));
    return t.isEmpty ? 0 : t.first.transform.getTranslation().x;
  }

  forEachWorld((WorldKind kind) {
    testWidgets('план с нуля, меняется до «Готово»; подтверждён изменённый',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      final int total = w.snapshot.unallocated;
      await open(tester, w);

      expect(_plan(tester), (0, 0, 0), reason: 'конверты с нуля');
      expect(_rest(tester), 'Не разложено: $total — уйдёт в кошелёк.');
      for (int i = 0; i < 3; i++) {
        await _press(tester, 'ЦЕЛЬ больше');
      }
      await _press(tester, 'ЦЕЛЬ меньше');
      await _press(tester, 'ХОЧУ больше');
      expect(_plan(tester), (0, 10, 20));
      while (_rest(tester) != planAllSpentLine) {
        await _press(tester, 'НУЖНО больше');
      }
      final (int need, int want, int goal) = _plan(tester);
      expect(need + want + goal, total);
      for (final String t in <String>['НУЖНО больше', 'ХОЧУ больше']) {
        expect(_enabled(tester, t), isTrue, reason: '$t не гаснет');
        await _press(tester, t);
        expect(_plan(tester), (need, want, goal), reason: '$t при остатке 0');
      }

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

  // «+» без остатка: «На неделю» трясётся и говорит «Всё уже разложено»;
  // «Анимации» выкл. — не трясётся (ТЗ 3.6.7), надпись та же.
  for (final bool motion in <bool>[true, false]) {
    testWidgets(
        '«+» без остатка: ${motion ? 'трясётся' : 'без тряски'} и '
        '«Всё уже разложено»', (WidgetTester tester) async {
      AppState? app;
      if (!motion) {
        await tester.runAsync(() async {
          app = AppState(MemoryStorage());
          await app!.boot();
          await app!.updateProfile(app!.game.profile
              .copyWith(settings: const GameSettings(animationsOn: false)));
        });
      }
      final World w = worldKinds.last.make();
      ok(w.startWeek());
      await open(tester, w, app: app);
      while (_rest(tester) != planAllSpentLine) {
        await _press(tester, 'НУЖНО больше');
      }
      expect(find.byKey(const ValueKey<String>('plan:full')), findsNothing);
      await _press(tester, 'ХОЧУ больше');
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byKey(const ValueKey<String>('plan:full')), findsOneWidget);
      expect(find.text('Всё уже разложено'), findsOneWidget);
      if (motion) {
        expect(poolShift(tester).abs(), greaterThan(0.5), reason: 'трясётся');
      } else {
        expect(poolShift(tester), 0, reason: 'без анимаций — на месте');
      }
      await tester.pumpAndSettle();
      expect(poolShift(tester), 0, reason: 'встал на место');
      // Переложил — надпись ушла.
      await _press(tester, 'НУЖНО меньше');
      expect(find.byKey(const ValueKey<String>('plan:full')), findsNothing);
    });
  }

  // Денис 29.09: «всего 600, в копилке то, что ты не можешь трогать» —
  // раскладывают только недельные; копилка отдельной строкой.
  testWidgets('копилка отдельно: «На неделю» без неё, «тратить нельзя»',
      (WidgetTester tester) async {
    final World w = worldKinds.last.make();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated - 50, wants: 0, goal: 50));
    ok(w.sleep());
    ok(w.payBills());
    ok(w.startWeek());
    final int saved = w.snapshot.saved;
    final int pool = w.snapshot.unallocated;
    expect(saved, greaterThan(0), reason: 'настройка: в копилке есть');
    await open(tester, w);
    final Finder row = find.byKey(const ValueKey<String>('plan:pool'));
    expect(
        find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
                (Widget x) => x is Coins && x.amount == pool)),
        findsOneWidget);
    expect(
        find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
                (Widget x) => x is Coins && x.amount == pool + saved)),
        findsNothing);
    expect(find.text('В копилке: $saved — на цель, тратить нельзя'),
        findsOneWidget);
  });
}
