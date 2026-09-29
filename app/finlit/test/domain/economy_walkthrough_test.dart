import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/economy/period_rules.dart';
import 'package:finlit/domain/economy/savings_rules.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_fold.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/goal.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Как ребёнок играет неделю.
class Strategy {
  const Strategy({
    required this.name,
    required this.buysOnWeek,
    required this.wantsBudget,
  });

  final String name;

  /// Что покупается из «Нужного» на конкретной неделе (1-based).
  final List<String> Function(int week) buysOnWeek;

  /// Сколько монеток кладётся в «Хочу».
  final int wantsBudget;
}

class WeekResult {
  WeekResult(this.week, this.outcome, this.snapshot, this.spentOnNeeds);
  final int week;
  final PeriodOutcome outcome;
  final GameSnapshot snapshot;
  final int spentOnNeeds;
}

/// Проигрывает пять игровых недель выбранной стратегией.
List<WeekResult> play(
  GameContent content,
  Strategy s, {
  int weeks = 5,
  String goalId = 'scooter',
  int tasksPerWeek = 2,
  bool payUnexpectedFromSavings = true,
}) {
  final Game g = Game(
    content: content,
    profile: GameProfile.fresh(isDemo: true),
  );
  g.chooseGoal(goalId);
  final List<WeekResult> out = <WeekResult>[];

  for (int w = 1; w <= weeks; w++) {
    g.startPeriod();

    // 🔴 Сначала подработка, потом план. С 19.09 база недели — это то, что
    // доверили родители, и на поздних стадиях она меньше (10 → 8 → 6):
    // остальное ребёнок зарабатывает сам. Раньше прогон планировал неделю
    // до заданий и складывал заработанное в копилку — при старой экономике
    // базы хватало на всё. Теперь на третьей стадии без подработки хотелки
    // не помещаются, и это ровно то, чему экономика должна учить.
    for (int t = 0; t < tasksPerWeek; t++) {
      g.completeTask(content.tasks[t % content.tasks.length], best: true);
    }

    final List<String> needIds = s.buysOnWeek(w);
    final int needsCost = needIds.fold<int>(
        0, (int a, String id) => a + content.item(id).price);

    final int income = g.snapshot.wallet.unallocated;
    final int wants = s.wantsBudget;
    final int savings = income - needsCost - wants;
    expect(savings, greaterThanOrEqualTo(0),
        reason: 'стратегия «${s.name}» не помещается в доход недели $w');

    g.confirmPlan(
        Allocation(needs: needsCost, wants: wants, savings: savings));

    for (final String id in needIds) {
      g.buy(content.item(id));
    }
    if (wants > 0) {
      for (final CatalogItem i in content.catalog.where(
          (CatalogItem i) => !i.isNeed && i.price <= wants)) {
        if (g.canBuy(i).allowed) {
          g.buy(i);
          break;
        }
      }
    }

    if (g.unexpectedPending) {
      if (payUnexpectedFromSavings) {
        g.payUnexpected(Envelope.savings);
      } else {
        g.deferUnexpected();
      }
    }

    final GameSnapshot before = g.snapshot;
    final PeriodOutcome o = g.closePeriod();
    out.add(WeekResult(w, o, before, needsCost));
  }
  return out;
}

void main() {
  late GameContent content;

  setUpAll(() async {
    content = await loadRealContent();
  });

  test('§2.1 за одну неделю нельзя купить всё сразу', () {
    final int whole = content.catalog
        .fold<int>(0, (int a, CatalogItem i) => a + i.price);
    final int weekIncome = content.economy.pocketMoney +
        content.tasks
            .take(2)
            .fold<int>(0, (int a, GameTask t) => a + t.reward);
    expect(whole, greaterThan(weekIncome),
        reason: 'весь каталог $whole против дохода недели $weekIncome');
  });

  test('бережливая стратегия жизнеспособна: Финни накормлен все 5 недель', () {
    final List<WeekResult> r = play(
      content,
      Strategy(
        name: 'бережливая',
        buysOnWeek: (int w) => <String>['porridge', 'water'],
        wantsBudget: 0,
      ),
    );
    for (final WeekResult w in r) {
      expect(
        w.snapshot.meters.needsCovered(content.economy.needsThreshold),
        isTrue,
        reason: 'неделя ${w.week}: ${w.snapshot.meters}',
      );
    }
  });

  test('оптовая стратегия жизнеспособна и дешевле за неделю', () {
    final List<WeekResult> bulk = play(
      content,
      Strategy(
        name: 'оптовая',
        // Овощи и купание берутся раз в две недели — их хватает надолго.
        // Овощи хватает на две недели, купания — на три.
        buysOnWeek: (int w) => <String>[
              if (w.isOdd) 'veggies',
              if (w == 1 || w == 4) 'bath',
            ],
        wantsBudget: 0,
      ),
    );
    for (final WeekResult w in bulk) {
      expect(
        w.snapshot.meters.needsCovered(content.economy.needsThreshold),
        isTrue,
        reason: 'неделя ${w.week}: ${w.snapshot.meters}',
      );
    }

    final int bulkTotal =
        bulk.fold<int>(0, (int a, WeekResult w) => a + w.spentOnNeeds);
    final int piecemealTotal = 5 *
        (content.item('porridge').price + content.item('water').price);

    expect(bulkTotal, lessThan(piecemealTotal),
        reason: 'опт $bulkTotal против поштучно $piecemealTotal — '
            'дорогой набор обязан давать выигрыш, иначе выбора нет');
  });

  test('§8.4 выбор не вырожден: щедрая стратегия тоже доживает до конца', () {
    final List<WeekResult> r = play(
      content,
      Strategy(
        name: 'щедрая',
        buysOnWeek: (int w) =>
            w.isOdd ? <String>['veggies', 'bath'] : <String>['porridge'],
        wantsBudget: 4,
      ),
    );
    for (final WeekResult w in r) {
      expect(w.snapshot.meters.needsCovered(content.economy.needsThreshold),
          isTrue,
          reason: 'неделя ${w.week}: ${w.snapshot.meters}');
    }
  });

  test('§2.6 три стадии развития достижимы за 5 недель при средней игре', () {
    final List<WeekResult> r = play(
      content,
      Strategy(
        name: 'средняя',
        buysOnWeek: (int w) =>
            w.isOdd ? <String>['veggies', 'bath'] : <String>[],
        wantsBudget: 2,
      ),
    );
    int total = 0;
    for (final WeekResult w in r) {
      total += w.outcome.points;
    }
    expect(PetStage.forPoints(total), PetStage.planner,
        reason: 'очков за 5 недель: $total, '
            'порог третьей стадии ${PetStage.planner.threshold}');
  });

  test('цель берётся к пятой неделе, и непредвиденный расход её не ломает', () {
    final Goal scooter = content.goals.firstWhere((Goal g) => g.id == 'scooter');
    final List<WeekResult> r = play(
      content,
      Strategy(
        name: 'копящая',
        buysOnWeek: (int w) =>
            w.isOdd ? <String>['veggies', 'bath'] : <String>[],
        wantsBudget: 1,
      ),
    );
    final int saved = r.last.snapshot.wallet.savings;
    expect(saved, greaterThanOrEqualTo(scooter.price),
        reason: 'накоплено $saved из ${scooter.price}');
  });

  test('небрежная игра цель не берёт — и это учебная ситуация, а не тупик', () {
    final Goal scooter = content.goals.firstWhere((Goal g) => g.id == 'scooter');
    final List<WeekResult> r = play(
      content,
      Strategy(
        name: 'тратящая',
        buysOnWeek: (int w) => <String>['porridge', 'water'],
        wantsBudget: 6,
      ),
    );
    expect(r.last.snapshot.wallet.savings, lessThan(scooter.price));
    // 🔴 Но прогресс не обнулён: §2.2 «не обнулять ранее достигнутый прогресс».
    int total = 0;
    for (final WeekResult w in r) {
      total += w.outcome.points;
    }
    expect(total, greaterThan(0));
  });

  test('непредвиденный расход можно перенести, и Финни не страдает', () {
    final List<WeekResult> r = play(
      content,
      Strategy(
        name: 'перенос',
        buysOnWeek: (int w) =>
            w.isOdd ? <String>['veggies', 'bath'] : <String>[],
        wantsBudget: 0,
      ),
      payUnexpectedFromSavings: false,
    );
    for (final WeekResult w in r) {
      expect(w.snapshot.meters.needsCovered(content.economy.needsThreshold),
          isTrue);
      expect(w.snapshot.meters.mood, greaterThan(0),
          reason: 'перенос траты не должен обнулять настроение');
    }
  });

  test('§2.5.7.4 срок до цели считается по средней сумме пополнения', () {
    final Goal zoo = content.goals.firstWhere((Goal g) => g.id == 'zoo');
    final GoalForecast f = SavingsRules.forecast(
      goal: zoo,
      savings: 8,
      depositHistory: <int>[3, 3, 3],
    );
    expect(f.averageDeposit, 3);
    expect(f.weeks, 4, reason: '(20 − 8) / 3 = 4');
  });
}
