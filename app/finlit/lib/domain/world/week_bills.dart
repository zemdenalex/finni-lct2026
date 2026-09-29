import 'world_config.dart';

/// Какой обязательный счёт. Порядок значений = порядок оплаты:
/// 🔴 корм питомцам первым (ТЗ §2 — питомцу навредить нельзя).
///
/// [extra] — добавка события к обязательному этой недели
/// (`required_extra_pocket_x`, «сломался рюкзак»), платится последней.
enum BillKind { petFood, food, rent, extra }

/// Откуда заплачен один счёт.
class BillPayment {
  const BillPayment({
    required this.kind,
    required this.amount,
    this.fromNeed = 0,
    this.fromFree = 0,
    this.fromWant = 0,
    this.fromGoal = 0,
    this.fromFamily = 0,
  });

  final BillKind kind;
  final int amount;
  final int fromNeed;
  final int fromFree;
  final int fromWant;
  final int fromGoal;

  /// Покрыто «семья помогает».
  final int fromFamily;

  /// Заплачено своими деньгами из карманов (без ЦЕЛИ и семьи).
  int get fromPockets => fromNeed + fromFree + fromWant;
}

/// Расчёт счетов конца недели по правилу нехватки
/// (`economy.json → shortfall_rule.order[]`, `docs/game/bills-shortfall.md`):
///
/// 1. `pet_food_first` — корм оплачивается первым;
/// 2. `downgrade_food` — карманов не хватает на домашнее меню → простое
///    блюдо (еда в счёте — только приёмы, которые Финни не съел посреди
///    недели: [meals] × цена блюда);
/// 3. `offer_savings_withdrawal` — из ЦЕЛИ, только с согласия ([takeFromGoal]);
/// 4. `family_help` — остаток покрывает семья, −😊, без очка роста.
///
/// Карманы тратятся в порядке НУЖНО → заработок → ХОЧУ. Ни один источник не
/// отдаёт больше, чем в нём есть, — поэтому баланс не уходит в минус.
///
/// Чистая функция: ничего не пишет. Записи в журнал делает `WorldGame`.
class WeekBills {
  factory WeekBills.compute({
    required WorldConfig config,
    required int need,
    required int want,
    required int free,
    required int goal,
    required int petFood,
    required String foodId,
    required int meals,
    required int rent,
    required bool takeFromGoal,
    int extra = 0,
  }) {
    final int pockets = need + want + free;
    final WorldFood? chosen = config.food(foodId);
    final WorldFood? simple = config.food(config.simpleFoodId);
    WorldFood? eaten = chosen;
    bool downgraded = false;
    if (chosen != null &&
        simple != null &&
        chosen.id != simple.id &&
        meals > 0 &&
        pockets < petFood + chosen.price * meals + rent + extra) {
      eaten = simple;
      downgraded = true;
    }

    // Источники в порядке списания; остаток каждого уменьшается по ходу.
    int leftNeed = need;
    int leftFree = free;
    int leftWant = want;
    int leftGoal = takeFromGoal ? goal : 0;

    final List<BillPayment> payments = <BillPayment>[];
    for (final BillKind kind in BillKind.values) {
      final int amount = switch (kind) {
        BillKind.petFood => petFood,
        BillKind.food => (eaten?.price ?? 0) * meals,
        BillKind.rent => rent,
        BillKind.extra => extra,
      };
      int due = amount;
      int take(int available) {
        final int t = available < due ? available : due;
        due -= t;
        return t;
      }

      final int n = take(leftNeed);
      leftNeed -= n;
      final int f = take(leftFree);
      leftFree -= f;
      final int w = take(leftWant);
      leftWant -= w;
      final int g = take(leftGoal);
      leftGoal -= g;
      payments.add(BillPayment(
        kind: kind,
        amount: amount,
        fromNeed: n,
        fromFree: f,
        fromWant: w,
        fromGoal: g,
        fromFamily: due,
      ));
    }
    return WeekBills._(
      payments: List<BillPayment>.unmodifiable(payments),
      chosenFoodId: foodId,
      eatenFood: eaten,
      homeMeals: meals,
      downgraded: downgraded,
    );
  }

  const WeekBills._({
    required this.payments,
    required this.chosenFoodId,
    required this.eatenFood,
    required this.homeMeals,
    required this.downgraded,
  });

  /// По одному на [BillKind], в порядке оплаты.
  final List<BillPayment> payments;
  final String chosenFoodId;

  /// Что Финни ел дома на самом деле (после понижения).
  final WorldFood? eatenFood;

  /// Сколько приёмов Финни съел дома в итогах: не выбранные посреди недели.
  final int homeMeals;

  /// Шаг `downgrade_food` сработал.
  final bool downgraded;

  int get total =>
      payments.fold<int>(0, (int a, BillPayment p) => a + p.amount);

  int get fromPockets =>
      payments.fold<int>(0, (int a, BillPayment p) => a + p.fromPockets);

  int get fromGoal =>
      payments.fold<int>(0, (int a, BillPayment p) => a + p.fromGoal);

  int get fromFamily =>
      payments.fold<int>(0, (int a, BillPayment p) => a + p.fromFamily);

  /// Не хватило своих карманов (до копилки и семьи) — то, что экран
  /// предлагает взять из накоплений.
  int get missingFromPockets => total - fromPockets;

  bool get familyHelped => fromFamily > 0;

  /// Сработал хоть один шаг правила нехватки.
  bool get hadShortfall => downgraded || missingFromPockets > 0;
}
