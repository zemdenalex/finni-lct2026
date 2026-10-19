import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/goal_eta.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Неделя истории с чистым отложенным [saved]; [paid] — закрыта.
WeekPlanFact _week(int no, int saved, {bool paid = true}) => WeekPlanFact(
      weekNo: no,
      planMade: true,
      billsPaid: paid,
      need: const EnvelopePlanFact(planned: 0, actual: 0),
      want: const EnvelopePlanFact(planned: 0, actual: 0),
      goal: EnvelopePlanFact(planned: 0, actual: saved),
    );

/// Ловит (ТЗ 2.5.7.4, решение владельца 17.10, вариант A): срок округлён
/// вниз (обещает раньше, чем будет), недели без взноса тянут среднее вниз,
/// берётся вся история вместо последних трёх законченных недель с взносом,
/// идущая неделя попадает в среднее (один взнос 20 на знакомстве давал
/// «149 недель» до собаки), срок показан до первой законченной недели с
/// взносом.
void main() {
  // (название, история, осталось, среднее, недель, причина)
  final List<(String, List<WeekPlanFact>, int, int?, int?, GoalEtaGap?)> cases =
      <(String, List<WeekPlanFact>, int, int?, int?, GoalEtaGap?)>[
    ('истории нет', <WeekPlanFact>[], 300, null, null, GoalEtaGap.noDeposit),
    (
      'взносов не было: ноль и снятие',
      <WeekPlanFact>[_week(1, 0), _week(2, -80)],
      300,
      null,
      null,
      GoalEtaGap.noDeposit
    ),
    (
      'взнос только в идущей неделе — срока ещё нет',
      <WeekPlanFact>[_week(1, 100, paid: false)],
      300,
      null,
      null,
      GoalEtaGap.weekNotOver
    ),
    (
      'закрытые недели без взноса, взнос в идущей — срока ещё нет',
      <WeekPlanFact>[_week(1, 0), _week(2, 20, paid: false)],
      300,
      null,
      null,
      GoalEtaGap.weekNotOver
    ),
    (
      'идущая неделя в среднее не входит',
      <WeekPlanFact>[_week(1, 50), _week(2, 200, paid: false)],
      100,
      50,
      2,
      null
    ),
    (
      'с остатком — вверх: 301 при 100 — 4',
      <WeekPlanFact>[_week(1, 100)],
      301,
      100,
      4,
      null
    ),
    (
      'недели без взноса не тянут среднее вниз',
      <WeekPlanFact>[_week(1, 60), _week(2, 0), _week(3, -30), _week(4, 60)],
      120,
      60,
      2,
      null
    ),
    (
      'дробное среднее: 100 за 3 недели, осталось 100 — 3',
      <WeekPlanFact>[_week(1, 30), _week(2, 30), _week(3, 40)],
      100,
      33,
      3,
      null
    ),
    (
      'из четырёх недель с взносом — последние три',
      <WeekPlanFact>[_week(1, 10), _week(2, 60), _week(3, 60), _week(4, 60)],
      120,
      60,
      2,
      null
    ),
    (
      'среднее меньше монеты — показываем 1',
      <WeekPlanFact>[_week(1, 1)],
      10,
      1,
      10,
      null
    ),
  ];

  for (final (
        String name,
        List<WeekPlanFact> h,
        int left,
        int? per,
        int? weeks,
        GoalEtaGap? why
      ) in cases) {
    test(name, () {
      final GoalEta e = goalEta(h, left)!;
      expect((e.perWeek, e.weeks, e.reason), (per, weeks, why));
      expect(e.hasEstimate, weeks != null);
    });
  }

  test('цели хватает — срока нет вовсе', () {
    expect(goalEta(<WeekPlanFact>[_week(1, 100)], 0), isNull);
    expect(goalEta(<WeekPlanFact>[_week(1, 100)], -20), isNull);
  });

  // Ловит на настоящем движке: неделя в разгаре с одним взносом 20 даёт
  // срок (до собаки «149 недель»); в режиме дней срок появляется раньше
  // итогов недели; после перезапуска из журнала срок другой.
  for (final (String mode, WorldGame Function() make) in <(
    String,
    WorldGame Function()
  )>[
    ('неделя', () => contentWorld()),
    ('дни', () => contentDayWorld()),
  ]) {
    test('движок, режим «$mode»: срок только после законченной недели', () {
      final WorldGame w = make();
      ok(w.startWeek());
      ok(w.plan(needs: 0, wants: 0, goal: 20));
      ok(w.chooseGoal('pet_dog'));
      final int price = w.catalogItem('pet_dog')!.price;
      (int?, int?, GoalEtaGap?) eta(World x) {
        final GoalEta e = goalEta(x.weekHistory, price - x.snapshot.goal)!;
        return (e.perWeek, e.weeks, e.reason);
      }

      expect(w.weekHistory.single.goal.actual, 20,
          reason: 'настройка: в идущей неделе отложено ровно 20');
      expect(eta(w), (null, null, GoalEtaGap.weekNotOver));
      expect(eta(WorldGame.fromJson(w.toJson(), config: w.config)),
          (null, null, GoalEtaGap.weekNotOver),
          reason: 'перезапуск посреди недели');

      // Дни недели и итоги до оплаты счетов: срока всё ещё нет.
      WorldResult r = w.sleep();
      while (r.ok && r.reasonCode == 'day.next') {
        expect(eta(w), (null, null, GoalEtaGap.weekNotOver),
            reason: 'день ${w.snapshot.dayInWeek}: неделя не закончена');
        r = w.sleep();
      }
      expect((r.ok, w.phase), (true, WeekPhase.review), reason: 'сон: $r');
      expect(eta(w), (null, null, GoalEtaGap.weekNotOver),
          reason: 'итоги: счета ещё не оплачены');
      ok(w.payBills());

      final WeekPlanFact week = w.weekHistory.single;
      expect((week.billsPaid, week.goal.actual), (true, 20),
          reason: 'настройка: неделя закрыта, отложено 20');
      final int left = price - w.snapshot.goal;
      expect(left, greaterThan(20), reason: 'настройка: копить не одну неделю');
      final (int?, int?, GoalEtaGap?) after = eta(w);
      expect(after, (20, (left + 19) ~/ 20, null));
      expect(eta(WorldGame.fromJson(w.toJson(), config: w.config)), after,
          reason: 'перезапуск после итогов');
    });
  }
}
