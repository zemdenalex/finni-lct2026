import 'dart:convert';
import 'dart:io';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/plan_amount.dart';
import 'package:finlit/features/world/home/plan_sheet.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/world_harness.dart';

/// Быстрая раскладка недели (Денис, чат 1898, 17.10: «нажимать сейчас 74
/// раза просто чтобы распределить деньги это ужас»).
///
/// Защищает: план недели раскладывается за 3 касания или меньше — кнопкой
/// «Как советует Финни» или вводом числа; удержание «+» разгоняется и не
/// выходит за остаток; ввод больше остатка режется. Уронит: кнопку совета
/// или ввод числа убрали; удержание снова шаг за шагом; зажим по остатку
/// пропал. Старые тесты степперов этого не ловят: они жмут «+» по одному.

final Finder _advice = find.byKey(const ValueKey<String>('plan:advice'));
final Finder _field = find.byKey(const ValueKey<String>('amount:field'));
final Finder _ok = find.byKey(const ValueKey<String>('amount:ok'));
final Finder _next = find.byKey(const ValueKey<String>('onboarding-next'));

/// Все три мира: неделя (фейк и движок: на неделю 400, счета 460) и дни,
/// как в релизе (на неделю 820, счета 740 — это 74 касания «+» Дениса).
final List<WorldKind> _kinds = <WorldKind>[...worldKinds, dayWorldKind];

int _ceilTo(int v, int step) => (v + step - 1) ~/ step * step;

/// Касание с подсчётом: сколько раз ребёнок ткнул пальцем.
class _Taps {
  int n = 0;
  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    n++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Знакомство до сценки плана: ник → облик → «Пропустить».
Future<WorldState> _toPlanScene(WidgetTester tester, WorldKind kind,
    {Size size = portrait, double textScale = 1}) async {
  final WorldState ws = await pumpWorldScreen(
      tester, const WorldOnboardingScreen(),
      world: kind.make(), size: size, textScale: textScale);
  await tester.enterText(
      find.byKey(const ValueKey<String>('onboarding-nick')), 'Кот');
  await tester.pump();
  // ник → облик → сценки; «Пропустить» — сразу сценка плана.
  for (int i = 0; i < 3; i++) {
    final Finder f =
        i < 2 ? _next : find.byKey(const ValueKey<String>('onboarding:skip'));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
  expect(find.byKey(const ValueKey<String>('plus:need')), findsOneWidget,
      reason: 'открылась сценка плана');
  return ws;
}

/// «Дальше» на плане; «Нужное» меньше счетов — оставить план как есть.
Future<void> _confirmScene(WidgetTester tester) async {
  await tester.ensureVisible(_next);
  await tester.tap(_next);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  final Finder keep = find.byKey(const ValueKey<String>('confirm:yes'));
  if (keep.evaluate().isNotEmpty) {
    await tester.tap(keep);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// Лист плана из комнаты поверх пустого экрана.
Future<World> _openSheet(WidgetTester tester, WorldKind kind) async {
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
  return w;
}

/// Число в строке листа плана — из подписи «Имя: число».
int _sheet(WidgetTester tester, String name) {
  final Semantics s = tester.widget<Semantics>(find.byWidgetPredicate(
      (Widget w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('$name: ') ?? false)));
  return int.parse(s.properties.label!.substring(name.length + 2));
}

(int, int, int) _sheetPlan(WidgetTester tester) => (
      _sheet(tester, 'Нужно'),
      _sheet(tester, 'Хочу'),
      _sheet(tester, 'Копилка'),
    );

Future<void> _confirmSheet(WidgetTester tester) async {
  final Finder f = find.byKey(const ValueKey<String>('plan:confirm'));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Совет Финни: счета (до шага вверх) — в «Нужное», из остального 30 % в
/// «Хочу» (вниз до шага), прочее — в «Копилку». Сумма = всё, что пришло.
(int, int, int) _advised(int pool, int bill, {int step = 10}) {
  final int need = _ceilTo(bill, step).clamp(0, pool);
  final int rest = pool - need;
  final int want = (rest * 3 ~/ 10) ~/ step * step;
  return (need, want, rest - want);
}

/// План, подтверждённый в мире (копилка в снимке — вместе со старыми
/// накоплениями, поэтому берём план недели).
(int, int, int) _planned(World w) {
  final WeekPlanFact f = w.weekHistory.last;
  return (f.need.planned, f.want.planned, f.goal.planned);
}

void main() {
  for (final WorldKind kind in _kinds) {
    group(kind.name, () {
      testWidgets('знакомство: «Как советует Финни» — всё за одно касание',
          (WidgetTester tester) async {
        final WorldState ws = await _toPlanScene(tester, kind);
        final int pool = ws.snapshot.unallocated;
        final int bill = ws.snapshot.weeklyBill;
        final _Taps t = _Taps();
        await t.tap(tester, _advice);
        expect(t.n, lessThanOrEqualTo(3));
        expect(find.text(planAllSpentLine), findsOneWidget,
            reason: 'после совета не разложенного не осталось');
        await _confirmScene(tester);
        expect(ws.phase, WeekPhase.living);
        final (int need, int want, int goal) = _planned(ws.world);
        expect((need, want, goal), _advised(pool, bill));
        expect(need + want + goal, pool, reason: 'ничего не потерялось');
      });

      testWidgets('знакомство: число в одно поле + совет — не больше 3 касаний',
          (WidgetTester tester) async {
        final WorldState ws = await _toPlanScene(tester, kind);
        final int pool = ws.snapshot.unallocated;
        final int bill = ws.snapshot.weeklyBill;
        final _Taps t = _Taps();
        await t.tap(tester, find.byKey(const ValueKey<String>('amount:need')));
        await tester.enterText(_field, '$bill');
        await tester.pump();
        if (bill > pool) {
          // Счета больше, чем пришло: поле само ставит всё, что есть.
          expect(find.byKey(const ValueKey<String>('amount:capped')),
              findsOneWidget);
          expect(tester.widget<TextField>(_field).controller!.text, '$pool');
        }
        await t.tap(tester, _ok);
        await t.tap(tester, _advice);
        expect(t.n, lessThanOrEqualTo(3));
        expect(find.text(planAllSpentLine), findsOneWidget);
        await _confirmScene(tester);
        final (int need, int want, int goal) = _planned(ws.world);
        expect(need, bill > pool ? pool : bill);
        expect(need + want + goal, pool);
      });

      testWidgets('лист плана: «Как советует Финни» — всё за одно касание',
          (WidgetTester tester) async {
        final World w = await _openSheet(tester, kind);
        final int pool = w.snapshot.unallocated;
        final int bill = w.snapshot.weeklyBill;
        final _Taps t = _Taps();
        await t.tap(tester, _advice);
        expect(t.n, 1);
        expect(_sheetPlan(tester), _advised(pool, bill));
        await _confirmSheet(tester);
        expect(w.phase, WeekPhase.living);
        expect(_planned(w), _advised(pool, bill));
      });

      testWidgets('лист плана: число в одно поле + совет — не больше 3 касаний',
          (WidgetTester tester) async {
        final World w = await _openSheet(tester, kind);
        final int pool = w.snapshot.unallocated;
        final _Taps t = _Taps();
        await t.tap(tester, find.byKey(const ValueKey<String>('amount:goal')));
        await tester.enterText(_field, '100');
        await t.tap(tester, _ok);
        await t.tap(tester, _advice);
        expect(t.n, lessThanOrEqualTo(3));
        final (int need, int want, int goal) = _sheetPlan(tester);
        expect(need + want + goal, pool);
        expect(goal, greaterThanOrEqualTo(100),
            reason: 'совет не отнимает то, что положил ребёнок');
      });
    });
  }

  group('удержание «+» (лист плана, мир с днями: на неделю 820)', () {
    // Копилка: 0,4 с — первый шаг, дальше раз в 0,12 с; с 1,2 с — по 5
    // шагов, с 2,5 с — по 10. Считается по тикам, не по часам.
    testWidgets('разгоняется и останавливается на остатке',
        (WidgetTester tester) async {
      final World w = await _openSheet(tester, dayWorldKind);
      final int pool = w.snapshot.unallocated;
      expect(pool, greaterThan(700));
      // 5 в «Хочу»: остаток не кратен шагу — разгон по 100 должен упереться
      // в остаток, а не перескочить его.
      await tester.tap(find.byKey(const ValueKey<String>('amount:want')));
      await tester.pumpAndSettle();
      await tester.enterText(_field, '5');
      await tester.tap(_ok);
      await tester.pumpAndSettle();
      final TestGesture g = await tester
          .startGesture(tester.getCenter(find.byTooltip('Копилка: больше')));
      await tester.pump(const Duration(milliseconds: 1150));
      expect(_sheet(tester, 'Копилка'), 70, reason: '7 шагов по 10');
      await tester.pump(const Duration(milliseconds: 300));
      expect(_sheet(tester, 'Копилка'), 170, reason: 'после 1,2 с — по 50');
      await tester.pump(const Duration(seconds: 3));
      expect(_sheet(tester, 'Копилка'), pool - 5,
          reason: 'не больше, чем осталось');
      expect(find.text(planAllSpentLine), findsOneWidget);
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      expect(_sheetPlan(tester), (0, 5, pool - 5));
    });

    testWidgets('отпустил — остановилось, лишнего шага нет',
        (WidgetTester tester) async {
      await _openSheet(tester, dayWorldKind);
      final TestGesture g = await tester
          .startGesture(tester.getCenter(find.byTooltip('Хочу: больше')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_sheet(tester, 'Хочу'), 20, reason: 'шаги на 0,4 и 0,52 с');
      await g.up();
      await tester.pump(const Duration(seconds: 2));
      expect(_sheet(tester, 'Хочу'), 20);
    });

    testWidgets('палец ушёл с кнопки — остановилось',
        (WidgetTester tester) async {
      await _openSheet(tester, dayWorldKind);
      final TestGesture g = await tester
          .startGesture(tester.getCenter(find.byTooltip('Хочу: больше')));
      await tester.pump(const Duration(milliseconds: 600));
      await g.moveBy(const Offset(-120, 0));
      await tester.pump(const Duration(seconds: 2));
      expect(_sheet(tester, 'Хочу'), 20);
      await g.up();
      await tester.pump();
      expect(_sheet(tester, 'Хочу'), 20);
    });

    testWidgets('«−» удержанием не уходит ниже нуля',
        (WidgetTester tester) async {
      await _openSheet(tester, dayWorldKind);
      await tester.tap(_advice);
      await tester.pump();
      final int goal = _sheet(tester, 'Копилка');
      expect(goal, greaterThan(0));
      final TestGesture g = await tester
          .startGesture(tester.getCenter(find.byTooltip('Копилка: меньше')));
      await tester.pump(const Duration(seconds: 4));
      expect(_sheet(tester, 'Копилка'), 0);
      await g.up();
      await tester.pump();
    });

    testWidgets('остаток 0: удержание «+» ничего не добавляет',
        (WidgetTester tester) async {
      final World w = await _openSheet(tester, dayWorldKind);
      await tester.tap(_advice);
      await tester.pump();
      final (int, int, int) before = _sheetPlan(tester);
      final TestGesture g = await tester
          .startGesture(tester.getCenter(find.byTooltip('Хочу: больше')));
      await tester.pump(const Duration(seconds: 3));
      await g.up();
      await tester.pump();
      expect(_sheetPlan(tester), before);
      final (int a, int b, int c) = before;
      expect(a + b + c, w.snapshot.unallocated);
      expect(find.byKey(const ValueKey<String>('plan:full')), findsOneWidget);
    });
  });

  group('ввод числа', () {
    testWidgets('больше остатка — ставит всё, что осталось, и говорит об этом',
        (WidgetTester tester) async {
      final World w = await _openSheet(tester, dayWorldKind);
      final int pool = w.snapshot.unallocated;
      await tester.tap(find.byKey(const ValueKey<String>('amount:want')));
      await tester.pumpAndSettle();
      final TextField f = tester.widget<TextField>(_field);
      expect(f.keyboardType, TextInputType.number);
      await tester.enterText(_field, '99999');
      await tester.pump();
      expect(tester.widget<TextField>(_field).controller!.text, '$pool');
      expect(
          find.byKey(const ValueKey<String>('amount:capped')), findsOneWidget);
      await tester.tap(_ok);
      await tester.pumpAndSettle();
      expect(_sheetPlan(tester), (0, pool, 0));
      // Остаток 0: в другое поле можно только то, что в нём уже есть.
      await tester.tap(find.byKey(const ValueKey<String>('amount:goal')));
      await tester.pumpAndSettle();
      await tester.enterText(_field, '50');
      await tester.pump();
      expect(tester.widget<TextField>(_field).controller!.text, '0');
      await tester.tap(_ok);
      await tester.pumpAndSettle();
      expect(_sheetPlan(tester), (0, pool, 0));
    });

    testWidgets('нечётное число: «−» и «+» дальше работают',
        (WidgetTester tester) async {
      await _openSheet(tester, dayWorldKind);
      await tester.tap(find.byKey(const ValueKey<String>('amount:want')));
      await tester.pumpAndSettle();
      await tester.enterText(_field, '5');
      await tester.tap(_ok);
      await tester.pumpAndSettle();
      expect(_sheet(tester, 'Хочу'), 5);
      await tester.tap(find.byTooltip('Хочу: меньше'));
      await tester.pump();
      expect(_sheet(tester, 'Хочу'), 0, reason: '5 − 10 → 0, а не погашено');
    });
  });

  // Крупный шрифт (ТЗ 3.6, масштаб 1,3) на 360 dp и в альбомной: совет и
  // ввод числа не ломают раскладку (переполнение — исключение в тесте).
  group('шрифт 1,3', () {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      testWidgets('знакомство · ${o.key}: совет и ввод числа',
          (WidgetTester tester) async {
        await _toPlanScene(tester, dayWorldKind, size: o.value, textScale: 1.3);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_advice);
        await tester.tap(_advice);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(planAllSpentLine), findsOneWidget);
      });
    }

    testWidgets('лист плана и окно ввода · портрет 360×640',
        (WidgetTester tester) async {
      final World w = dayWorldKind.make();
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
        textScale: 1.3,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_advice);
      await tester.tap(_advice);
      await tester.pump();
      expect(
          _sheet(tester, 'Нужно') +
              _sheet(tester, 'Хочу') +
              _sheet(tester, 'Копилка'),
          w.snapshot.unallocated);
      final Finder want = find.byKey(const ValueKey<String>('amount:want'));
      await tester.ensureVisible(want);
      await tester.tap(want);
      await tester.pumpAndSettle();
      await tester.enterText(_field, '99999');
      await tester.pump();
      expect(
          find.byKey(const ValueKey<String>('amount:capped')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(_ok);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('TalkBack', () {
    testWidgets('метки «Нужно: меньше/больше» на месте; касание — один шаг',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await _toPlanScene(tester, worldKinds.first);
      for (final String l in <String>['Нужно: меньше', 'Нужно: больше']) {
        expect(find.byTooltip(l), findsOneWidget, reason: l);
      }
      // TalkBack: у «+» действие «касание», двойное касание — один шаг.
      final FinderBase<SemanticsNode> plus = find.semantics.byPredicate(
          (SemanticsNode n) =>
              n.getSemanticsData().tooltip == 'Нужно: больше' &&
              n.getSemanticsData().hasAction(SemanticsAction.tap));
      expect(plus, findsOne);
      tester.semantics.tap(plus);
      await tester.pump();
      final Finder n = find.byKey(const ValueKey<String>('amount:need'));
      expect(find.descendant(of: n, matching: find.text('10')), findsOneWidget);
      expect(tester.getSemantics(_advice).getSemanticsData().label,
          contains('Как советует'));
      h.dispose();
    });
  });
  group('совет Финни: расчёт', () {
    const PlanAdvice a = PlanAdvice();
    ({int need, int want, int goal}) adv(int pool, int bill,
            {int need = 0, int want = 0, int goal = 0}) =>
        advisePlan(
            pool: pool,
            bill: bill,
            step: 10,
            advice: a,
            need: need,
            want: want,
            goal: goal);

    test('доли из onboarding.json: 30 % в «Хочу», остальное — в «Копилку»', () {
      expect(contentScript.planAdvice.wantPercent, 30);
      expect(
          () => OnboardingScript.parse(
              OnboardingScriptTestJson.withAdvice(40, 70)),
          throwsFormatException,
          reason: 'доли не в сумме 100 — ошибка разбора, а не тихий совет');
    });

    test('460: счета вверх до шага, «Хочу» вниз до шага, остаток в копилку',
        () {
      expect(adv(460, 125), (need: 130, want: 90, goal: 240));
      expect(adv(460, 460), (need: 460, want: 0, goal: 0));
      expect(adv(460, 600), (need: 460, want: 0, goal: 0),
          reason: 'счета больше, чем пришло: всё в «Нужно»');
      expect(adv(465, 0), (need: 0, want: 130, goal: 335),
          reason: 'нечётный остаток уходит в копилку, ничего не теряется');
    });

    test('уже положенное не уменьшается; остатка нет — ничего не меняет', () {
      expect(adv(460, 125, need: 200, want: 55),
          (need: 200, want: 115, goal: 145));
      expect(adv(460, 125, need: 460), (need: 460, want: 0, goal: 0));
    });
  });
}

/// onboarding.json сборки с другим разделом `plan_advice`.
abstract final class OnboardingScriptTestJson {
  static String withAdvice(int want, int goal) {
    final Map<String, Object?> j =
        jsonDecode(File(OnboardingScript.path).readAsStringSync())
            as Map<String, Object?>;
    j['plan_advice'] = <String, Object?>{
      'want_percent': want,
      'goal_percent': goal,
    };
    return jsonEncode(j);
  }
}
