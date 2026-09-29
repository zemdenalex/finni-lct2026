import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fridge_stock.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Холодильник — видимый запас еды недели (фидбек дизайнера 28.09, п. 7,
/// этап 4). Правило — `docs/sdacha/06-formuly.md`, «Холодильник».
void main() {
  // Защищает: само правило запаса. Уронит: приём пищи не забирает порцию,
  // запас уходит в минус, до первой недели холодильник полон, число приёмов
  // в неделю зашито в код, перекус не ложится на полку.
  group('правило', () {
    const List<(String, int, int, int, int, int)> rows =
        <(String, int, int, int, int, int)>[
      // что, неделя, съедено, перекусов → еды, перекусов
      ('до первой недели — пусто', 0, 0, 0, 0, 0),
      ('до первой недели и с перекусом — пусто', 0, 0, 1, 0, 0),
      ('начало недели — полный', 1, 0, 0, 3, 0),
      ('поел — минус порция', 1, 1, 0, 2, 0),
      ('все приёмы съедены', 2, 3, 0, 0, 0),
      ('перекус — плюс порция', 1, 0, 1, 3, 1),
      ('поел и купил перекусы', 1, 2, 2, 1, 2),
      ('съедено больше приёмов — ноль, не минус', 1, 5, 0, 0, 0),
      ('отрицательное «съедено» не добавляет еды', 1, -3, 0, 3, 0),
    ];
    for (final (
          String what,
          int week,
          int eaten,
          int snacks,
          int food,
          int left
        ) in rows) {
      test(what, () {
        final FridgeStock s = fridgeStock(
            weekNo: week,
            foodId: 'food_regular',
            mealsPerWeek: 3,
            mealsEaten: eaten,
            snacksThisWeek: snacks);
        expect((s.food, s.snacks), (food, left));
        expect(s.portions, food + left);
        expect(s.portions, greaterThanOrEqualTo(0));
      });
    }
  });

  // Защищает: запас выводится из журнала мира — одинаково у фейка и у
  // движка, на которых строятся экраны. Уронит: «Съесть» не забирает
  // порцию, игровой день снова ест еду, неделя не наполняет холодильник
  // заново, смена домашнего меню посреди недели наполняет его снова,
  // перекус не ложится на полку.
  forEachWorld((WorldKind kind) {
    test('неделя: полный → приёмы едят → перекус → новая неделя полная', () {
      final World w = kind.make();
      final int meals = w.snapshot.mealsPerWeek;
      expect(meals, greaterThan(1));
      expect(fridgeOf(w.snapshot), FridgeStock.empty);
      ok(w.startWeek());
      ok(w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0));
      FridgeStock f = fridgeOf(w.snapshot);
      expect(f.food, meals);
      expect(f.snacks, 0);
      expect(f.foodId, 'food_simple');

      ok(w.leisure('park'));
      expect(fridgeOf(w.snapshot).food, meals,
          reason: 'игровой день еду не ест — ест только «Съесть»');
      ok(w.eat('food_soup'));
      expect(fridgeOf(w.snapshot).food, meals - 1);

      // Смена домашнего меню посреди недели меняет картинку, а не число.
      ok(w.chooseFood('food_tasty'));
      f = fridgeOf(w.snapshot);
      expect((f.foodId, f.food), ('food_tasty', meals - 1));

      ok(w.buy('snack'));
      expect(fridgeOf(w.snapshot).snacks, 1);
      expect(fridgeOf(w.snapshot).portions, meals - 1 + 1);

      ok(w.sleep());
      // Итоги недели: остаток на полках до новой недели.
      expect(fridgeOf(w.snapshot).portions, meals);
      ok(w.payBills());
      ok(w.startWeek());
      f = fridgeOf(w.snapshot);
      expect((f.foodId, f.food, f.snacks), ('food_tasty', meals, 0));
    });
  });

  // Защищает: запас после перезапуска тот же (ТЗ 2.5.13.1) — он выводится из
  // журнала, а не из памяти экрана. Не простая еда и съеденный приём — иначе
  // значения по умолчанию совпали бы и без журнала.
  test('сохранили → восстановили → тот же холодильник', () {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0));
    ok(w.chooseFood('food_tasty'));
    ok(w.leisure('park'));
    ok(w.completeJob('cashier', score: 0.5));
    ok(w.eat('food_regular'));
    ok(w.buy('snack'));
    final FridgeStock before = fridgeOf(w.snapshot);
    expect(before, const FridgeStock(foodId: 'food_tasty', food: 2, snacks: 1));

    final WorldGame again =
        WorldGame.fromJson(w.toJson(), config: contentConfig);
    expect(fridgeOf(again.snapshot), before);
    expect(again.snapshot.foodId, 'food_tasty');
  });
}
