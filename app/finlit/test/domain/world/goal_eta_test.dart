import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/goal_eta.dart';
import 'package:flutter_test/flutter_test.dart';

/// Неделя истории с чистым отложенным [saved]; [paid] — закрыта.
WeekPlanFact _week(int no, int saved, {bool paid = true}) => WeekPlanFact(
      weekNo: no,
      planMade: true,
      billsPaid: paid,
      need: const EnvelopePlanFact(planned: 0, actual: 0),
      want: const EnvelopePlanFact(planned: 0, actual: 0),
      goal: EnvelopePlanFact(planned: 0, actual: saved),
    );

/// Ловит (ТЗ 2.5.7.4, правило `docs/spec-igry.md`): срок округлён вниз
/// (обещает раньше, чем будет), недели без взноса тянут среднее вниз, берётся
/// вся история вместо последних трёх недель с взносом, идущая неделя с
/// взносом не считается, срок показан до первого взноса.
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
      'взнос в идущей неделе — срок уже есть',
      <WeekPlanFact>[_week(1, 100, paid: false)],
      300,
      100,
      3,
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
}
