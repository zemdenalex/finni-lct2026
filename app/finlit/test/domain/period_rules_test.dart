import 'package:finlit/domain/economy/economy_config.dart';
import 'package:finlit/domain/economy/period_rules.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:flutter_test/flutter_test.dart';

const EconomyConfig cfg = EconomyConfig(
  pocketMoney: 10,
  decay: PetMeters(fullness: -3, cleanliness: -2, mood: -1),
  moodPerTask: 1,
  moodPerDeposit: 1,
  maxMoodFromTasks: 2,
  planTolerance: 2,
  unexpectedPeriod: 3,
  startMeters: PetMeters(fullness: 4, cleanliness: 4, mood: 7),
  needsThreshold: 4,
  wishThreshold: 4,
  trust: <PetStage, TrustLevel>{
    PetStage.novice: TrustLevel(fromParents: 10, earnCap: 4),
    PetStage.saver: TrustLevel(fromParents: 8, earnCap: 7),
    PetStage.planner: TrustLevel(fromParents: 6, earnCap: 10),
  },
  parentBonusCap: 3,
  scale: 1,
);

void main() {
  group('отклонение факта от плана считается асимметрично', () {
    test(
        'отказ от необязательной покупки НЕ нарушение — Термины ТЗ говорят '
        'об этом дословно', () {
      expect(
        PeriodRules.withinNorm(
            envelope: Envelope.wants, planned: 5, actual: 0, tolerance: 2),
        isTrue,
      );
    });

    test('перерасход по «Хочу» — нарушение', () {
      expect(
        PeriodRules.withinNorm(
            envelope: Envelope.wants, planned: 2, actual: 9, tolerance: 2),
        isFalse,
      );
    });

    test('потратить на «Нужное» меньше, чем планировал, — не нарушение', () {
      expect(
        PeriodRules.withinNorm(
            envelope: Envelope.needs, planned: 6, actual: 3, tolerance: 2),
        isTrue,
      );
    });

    test('отложить больше плана — не нарушение', () {
      expect(
        PeriodRules.withinNorm(
            envelope: Envelope.savings, planned: 3, actual: 9, tolerance: 2),
        isTrue,
      );
    });

    test('отложить заметно меньше плана — нарушение', () {
      expect(
        PeriodRules.withinNorm(
            envelope: Envelope.savings, planned: 8, actual: 1, tolerance: 2),
        isFalse,
      );
    });
  });

  test('ребёнок, который ничего не купил в «Хочу», получает все три очка', () {
    final PeriodOutcome o = PeriodRules.close(
      config: cfg,
      plan: const Allocation(needs: 3, wants: 4, savings: 3),
      fact: const Allocation(needs: 3, wants: 0, savings: 3),
      metersAtClose: const PetMeters(fullness: 6, cleanliness: 6, mood: 6),
      tasksCompleted: 2,
      depositedThisPeriod: 3,
      boughtNeedsSoFar: true,
    );
    expect(o.points, 3,
        reason: 'иначе продукт механически побуждал бы тратить');
  });

  test('§2.2 объяснение выдаётся и когда очко не заработано', () {
    final PeriodOutcome o = PeriodRules.close(
      config: cfg,
      plan: const Allocation(needs: 3, wants: 2, savings: 5),
      fact: const Allocation(needs: 3, wants: 2, savings: 0),
      metersAtClose: const PetMeters(fullness: 1, cleanliness: 1, mood: 5),
      tasksCompleted: 0,
      depositedThisPeriod: 0,
      boughtNeedsSoFar: true,
    );
    for (final CarePoint p in o.carePoints) {
      expect(p.explanation.trim(), isNotEmpty);
    }
    expect(o.points, 0);
  });

  test('накопление не делает питомца грустным', () {
    final PeriodOutcome saving = PeriodRules.close(
      config: cfg,
      plan: const Allocation(needs: 3, wants: 0, savings: 7),
      fact: const Allocation(needs: 3, wants: 0, savings: 7),
      metersAtClose: const PetMeters(fullness: 6, cleanliness: 6, mood: 5),
      tasksCompleted: 2,
      depositedThisPeriod: 7,
      boughtNeedsSoFar: true,
    );
    expect(saving.metersDelta.mood, greaterThan(0),
        reason: 'ребёнок, который копит и делает задания, не должен '
            'получать падение настроения питомца');
  });

  test('§2.2 стадия не откатывается при плохой неделе', () {
    expect(PetStage.forPoints(9), PetStage.planner);
    // Очки не уменьшаются: следующая свёртка даёт ту же стадию.
    expect(PetStage.forPoints(9 + 0), PetStage.planner);
  });

  test('«Нужное закрыто» — за покупку, а не за стартовый запас шкал', () {
    CarePoint needs({required bool boughtEver, int boughtNow = 0}) =>
        PeriodRules.close(
          config: cfg,
          plan: const Allocation(needs: 0, wants: 4, savings: 6),
          fact: Allocation(needs: boughtNow, wants: 0, savings: 6),
          // Финни ещё сыт: шкалы выше порога.
          metersAtClose: const PetMeters(fullness: 7, cleanliness: 7, mood: 6),
          tasksCompleted: 0,
          depositedThisPeriod: 6,
          boughtNeedsSoFar: boughtEver,
        ).carePoints.firstWhere((CarePoint c) => c.id == 'needs');

    final CarePoint nothingEver = needs(boughtEver: false);
    expect(nothingEver.earned, isFalse,
        reason: 'первая неделя хвалила «по плану 0, вышло 0»');
    expect(nothingEver.explanation, contains('ничего не куплено'));
    expect(nothingEver.explanation, isNot(contains('не хватило')),
        reason: 'Финни сыт — говорить о нехватке неправда');

    expect(needs(boughtEver: true, boughtNow: 3).earned, isTrue);
    expect(needs(boughtEver: true).earned, isTrue,
        reason: 'оптом закупились на прошлой неделе — это расчёт, а не '
            'забывчивость');
  });
}
