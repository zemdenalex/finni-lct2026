import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Итоги недели (кадры 0.1.3, n5 #3): «Не хватало: 30 из копилки. Звёзды: +1
/// (обязательное закрыто своими монетами)». Ребёнок читает это как
/// противоречие: монет не хватило, но «закрыто своими монетами», и рядом
/// «+1», похожее на монету.
///
/// Защищает: когда на счета взяли из копилки (семья не помогала), итог
/// говорит, что взяли из копилки, звезда объяснена без «своих монет», и
/// звёзды названы так, что их не спутать с монетами (они — для переезда).
/// Уронит: формулировка «закрыто своими монетами» рядом со снятием из
/// копилки или «Звёзды: +N» без слова о том, зачем они.
/// Почему не ловили: тесты проверяли `why` в журнале и число в начале строки
/// (`week_bill_total_test`), а не то, как читается фраза о звёздах.
void main() {
  for (final (String name, WorldGame Function() make)
      in <(String, WorldGame Function())>[
    ('неделя', contentWorld),
    ('дни, как в релизе', contentDayWorld),
  ]) {
    test('$name: копилка помогла со счетами — звёзды не «своими монетами»', () {
      final WorldGame w = make();
      ok(w.startWeek());
      // Всё — в копилку: в кошельке на счета не останется.
      ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
      final WorldResult end = sleepWeek(w);
      expect(end.ok, isTrue, reason: '$end');
      final WorldResult r = ok(w.payBills(takeFromGoal: true));
      // Предусловия кадра: из копилки взяли, семья не помогала.
      expect(r.goal, lessThan(0), reason: 'из копилки не взяли: ${r.reason}');
      expect(r.reasonCode, 'bills.paid', reason: r.reason);
      final int took = -r.goal;

      expect(r.reason, contains('$took'), reason: r.reason);
      expect(r.reason, contains('из копилки'), reason: r.reason);
      expect(r.reason, isNot(contains('своими монетами')), reason: r.reason);
      expect(r.reason, matches(RegExp('Звёзды[^.]*переезд')),
          reason: 'звёзды — для переезда, не монеты: ${r.reason}');
      expect(r.reason, isNot(matches(RegExp('%|процент|конверт'))),
          reason: r.reason);
    });
  }
}
