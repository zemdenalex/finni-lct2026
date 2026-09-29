import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// P7 (Денис 28.09) на границе [World] — один сценарий на фейке и домене.
///
/// Защищает: неделя «как прошлая» (заработок не вырос, в копилку ничего,
/// целей и переезда нет) огорчает Финни, и тем сильнее, чем дольше длится;
/// неделя роста радует. Уронит: штраф застоя не начислили или не растёт
/// подряд, рост не распознан (заработок или копилка), бонус не с тем знаком,
/// причина настроения не называет застой или рост.
///
/// Стадии отключены порогами 100 и 200: переезд — тоже рост, и он бы
/// смешался с проверкой заработка. Домашнее меню — котлета с картошкой
/// (😊 +1 за приём, три приёма дома — +3 в итогах): с простой кашей
/// (😊 0) неделя роста остывала бы в ноль и причина «рост» не называлась бы.
void weekGrowthScenario(World Function(WorldConfig config) newWorld) {
  const WorldConfig noStages = WorldConfig(stageMinPoints: <int>[0, 100, 200]);

  test(
      'P7: неделя как прошлая — 😊 падает, штраф застоя растёт с каждой такой '
      'неделей подряд', () {
    final World w = newWorld(noStages);
    _week(w);
    expect(w.snapshot.happiness, 48,
        reason: '50 − 2 дня + 3 сон + 3 еда дома − 6 остывание; неделя 1 — '
            'без проверки роста');

    _week(w);
    expect(w.snapshot.moodReason.code, 'mood.stagnation');
    expect(w.snapshot.happiness, 44,
        reason:
            '48 − 2 + 3 + 3 − 3 застой − 5 остывание (6 + 0,7 × (48 − 50))');

    _week(w);
    expect(w.snapshot.happiness, 40,
        reason: 'вторая неделя застоя подряд: −6; остывание при 😊 44 — 2');
  });

  test('P7: неделя роста — заработал больше или отложил на цель — радует', () {
    final World flat = newWorld(noStages);
    _week(flat);
    _week(flat);

    final World earned = newWorld(noStages);
    _week(earned);
    _week(earned, jobs: const <String>['consultant', 'consultant', 'gardener']);
    expect(earned.snapshot.moodReason.code, 'mood.growth');
    expect(earned.snapshot.happiness, 48,
        reason: '48 − 3 дня + 3 сон + 3 еда + 2 рост − 5 остывание');

    final World saved = newWorld(noStages);
    _week(saved);
    _week(saved, goal: 100); // 100 из 990 дохода недели — больше 10 %
    expect(saved.snapshot.moodReason.code, 'mood.growth');
    expect(saved.snapshot.happiness, flat.snapshot.happiness + 5,
        reason: '+2 за рост вместо −3 за застой');
  });
}

/// Неделя: план (стипендия — в НУЖНО, кроме [goal]), обычные смены [jobs],
/// «Спать», счета своими деньгами.
void _week(World w,
    {List<String> jobs = const <String>['consultant', 'consultant'],
    int goal = 0}) {
  final WorldResult start = w.startWeek();
  expect(start.ok, isTrue, reason: start.reason);
  expect(w.chooseFood('food_regular').ok, isTrue);
  expect(w.plan(needs: 400 - goal, wants: 0, goal: goal).ok, isTrue);
  for (final String job in jobs) {
    final WorldResult r = w.completeJob(job, score: 0);
    expect(r.ok, isTrue, reason: r.reason);
  }
  final WorldResult sleep = w.sleep();
  expect(sleep.ok, isTrue, reason: sleep.reason);
  final WorldResult bills = w.payBills();
  expect(bills.ok, isTrue, reason: bills.reason);
}
