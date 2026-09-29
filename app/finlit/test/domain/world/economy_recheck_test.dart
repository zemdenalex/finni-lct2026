import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Перепроверка экономики 29.09 (критерии ночи §1; разведка
/// `ekonomika-realizm.md`): соотношения, которые правка не должна сломать, и
/// видимая окупаемость инструмента (Денис 1001). Числа — из `economy.json`.
void main() {
  final WorldConfig c = contentConfig;

  // Защищает: исправленные соотношения §1 п. 1 и п. 8. Уронит: кино снова
  // дороже кафе, рост за опыт быстрее ×1,01, Москва дешевле ×2 города,
  // программист выше ×1,85 кассира.
  test('соотношения после перепроверки', () {
    int leisure(String id) => c.leisureKind(id)!.price;
    expect(leisure('cinema'), lessThanOrEqualTo(leisure('cafe')));
    expect(c.experienceGrowth, inInclusiveRange(1.005, 1.01));
    expect(c.home('home_house')!.weeklyCost,
        greaterThanOrEqualTo(2 * c.home('home_flat')!.weeklyCost));
    final int cashier = c.job('cashier', null)!.pay;
    for (final String v in <String>['easy', 'medium', 'hard']) {
      expect(c.job('programmer', v)!.pay / cashier, inInclusiveRange(1.0, 1.85),
          reason: v);
    }
    expect(c.snackPrice, lessThan(c.food('food_soup')!.price),
        reason: 'перекус дешевле супа, но не копейки');
    // Через 10 недель доход не ×2 от опыта: 30 хороших смен.
    expect(
        List<double>.filled(30, c.experienceGrowth)
            .fold<double>(1, (double a, double b) => a * b),
        lessThan(1.4));
  });

  // Защищает: вложение окупается на глазах (Денис 1001): смены на
  // велосипеде копят прибавку к лучшей работе без него, и один раз звучит
  // «окупился!». Уронит: окупаемость не копится, звучит каждый раз или
  // никогда.
  test('велосипед окупается курьерскими сменами — один раз «окупился!»', () {
    final WorldGame w = WorldGame(
        config: WorldConfig(
            startGift: c.transportPrice,
            jobs: c.jobs,
            techs: c.techs,
            lessons: const <WorldLesson>[]));
    ok(w.startWeek());
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    ok(w.buy('transport_bike'));
    int told = 0;
    for (int week = 0; week < 12; week++) {
      for (int i = 0; i < 2; i++) {
        if (w.canDo(WorldAction.job, id: 'courier', variant: 'far') != null) {
          break;
        }
        final WorldResult r =
            ok(w.completeJob('courier', variant: 'far', score: 0.5));
        if (r.reason.contains('окупился')) told++;
      }
      if (w.phase == WeekPhase.living) ok(w.sleep());
      ok(w.payBills());
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    }
    final int paid = w.snapshot.toolPayback['transport_bike'] ?? 0;
    expect(paid, greaterThanOrEqualTo(c.transportPrice));
    expect(told, 1);
  });
}
