import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Ловит (ТЗ 2.5.5.3, 2.5.11.1): план против факта считается не из того —
/// «ХОЧУ убыло» вместо «потрачено на ХОЧУ» (счета тоже едят ХОЧУ), подарок
/// или покупка цели засчитаны как «отложено», счета без помощи семьи; или
/// история недель теряется при перезапуске (живёт не в журнале).
void main() {
  forEachWorld((WorldKind kind) {
    test('план X, траты Y → факт по конвертам; неделя 2 начинается пустой', () {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 200, wants: 150, goal: 50));
      ok(w.chooseFood('food_simple')); // простую еду не понизить: счёт = счёт
      ok(w.chooseGoal('pet_fish'));
      final int before = w.snapshot.free;
      ok(w.completeJob('consultant', score: 0.5));
      final int pay = w.snapshot.free - before;
      final WorldCatalogItem poster = w.catalogItem('poster_city')!;
      ok(w.buy('poster_city'));
      ok(w.depositToGoal(30));
      ok(w.sleep());
      final int bill = w.snapshot.weeklyBill;
      ok(w.payBills());

      final WeekPlanFact f = w.weekHistory.single;
      expect(f.weekNo, 1);
      expect(f.planMade, isTrue);
      expect(f.billsPaid, isTrue);
      expect((f.need.planned, f.need.actual), (200, bill),
          reason: 'НУЖНО на деле — весь счёт недели');
      expect((f.want.planned, f.want.actual), (150, poster.price),
          reason: 'ХОЧУ на деле — покупка, а не то, что съели счета');
      expect((f.goal.planned, f.goal.actual), (50, 80),
          reason: 'ЦЕЛЬ на деле — план + взнос, без стартового подарка');
      expect(f.shifts.map((WeekItem s) => s.amount), <int>[pay]);
      expect(f.purchases.map((WeekItem p) => p.title), <String>[poster.title]);
      expect(f.goalTitle, w.catalogItem('pet_fish')!.title);
      expect(f.savedAtEnd, w.snapshot.goal);

      ok(w.startWeek());
      final List<WeekPlanFact> h = w.weekHistory;
      expect(h.map((WeekPlanFact x) => x.weekNo), <int>[1, 2]);
      expect(h.last.planMade, isFalse);
      expect(h.last.billsPaid, isFalse);
      expect(h.first.want.actual, poster.price, reason: 'прошлая неделя та же');

      if (w is WorldGame) {
        // Нет своего хранилища: перезапуск — та же свёртка журнала.
        final List<WeekPlanFact> again =
            WorldGame.fromJson(w.toJson(), config: w.config).weekHistory;
        String dump(List<WeekPlanFact> l) => l
            .map((WeekPlanFact x) => '${x.weekNo} ${x.need.actual} '
                '${x.want.actual} ${x.goal.actual} ${x.shifts.length} '
                '${x.purchases.length} ${x.savedAtEnd}')
            .join(';');
        expect(dump(again), dump(h));
      }
    });
  });
}
