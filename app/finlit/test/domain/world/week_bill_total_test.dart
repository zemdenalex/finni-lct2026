import 'package:finlit/domain/world/contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Итоги недели (кадры 0.1.2+3, night4 #4): строка плана «Нужно: план 740
/// → счета 790» и итог оплаты «Счета недели — 670» на одном экране.
/// Причина: строка плана — свёртка журнала (счета в конце недели + еда,
/// съеденная посреди недели), а итог оплаты называл только остаток, который
/// платится в конце (`bills.total`). 790 − 670 = 120 — еда посреди недели.
///
/// Защищает: «Счета недели» в итоге оплаты — то же число, что факт «Нужно»
/// в плане против факта (один источник — журнал). Уронит: итог снова
/// называет только остаток в конце недели.
/// Почему не ловили: `meals_test` сверял факт НУЖНО с журналом, а текст
/// итога оплаты с ним не сравнивал никто.
void main() {
  forEachWorld((WorldKind kind) {
    test('«Счета недели» в итоге оплаты = факт «Нужно» недели', () {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 400, wants: 0, goal: 0));
      final int meal = w.catalogItem('food_regular')!.price;
      ok(w.eat('food_regular'));
      final WorldResult end = sleepWeek(w);
      expect(end.ok, isTrue, reason: '$end');
      final WorldResult r = ok(w.payBills());
      final WeekPlanFact week = w.weekHistory.last;
      expect(meal, greaterThan(0));
      expect(week.need.actual, greaterThan(meal),
          reason: 'еда посреди недели и счёт в конце');
      expect(r.reason, startsWith('Счета недели — ${week.need.actual}'),
          reason: r.reason);
    });
  });
}
