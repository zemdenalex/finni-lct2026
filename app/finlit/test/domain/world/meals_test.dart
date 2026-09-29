import 'dart:convert';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/review/plan_fact_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Еда — приёмы пищи (Денис 29.09, 938): ребёнок сам выбирает блюдо, ⚡ и 😊
/// сразу, едим несколько раз в неделю; невыбранные приёмы Финни ест дома в
/// итогах недели по цене домашнего меню. Правило — `docs/sdacha/06-formuly.md`,
/// «Еда».
void main() {
  forEachWorld((WorldKind kind) {
    World living({int needs = 400, int wants = 0}) {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: needs, wants: wants, goal: 0));
      return w;
    }

    WorldCatalogItem dish(World w, String id) => w.catalogItem(id)!;

    // Защищает: «Съесть» — трата из НУЖНО с ⚡ и 😊 сразу, и она не
    // игровой день. Уронит: еда платится из ХОЧУ раньше НУЖНО, ⚡ приходит
    // на следующую неделю, еда съедает −1 😊 дня или считается днём.
    test('«Съесть»: НУЖНО платит, ⚡ и 😊 сразу, игровой день не проходит', () {
      final World w = living(needs: 300, wants: 100);
      final WorldCatalogItem fish = dish(w, 'food_fish');
      ok(w.leisure('park')); // ⚡ ниже максимума, чтобы польза вошла целиком
      final ResourceSnapshot before = w.snapshot;
      final WorldResult r = ok(w.eat('food_fish'));
      final ResourceSnapshot after = w.snapshot;
      expect(after.need, before.need - fish.price);
      expect(after.want, before.want,
          reason: 'ХОЧУ не трогаем, пока есть НУЖНО');
      expect(after.energy, closeTo(before.energy + fish.energy, 1e-9));
      expect(after.happiness, before.happiness + fish.happiness);
      expect(after.daysThisWeek, before.daysThisWeek,
          reason: 'не игровой день');
      expect(after.mealsThisWeek, 1);
      expect((r.coins, r.energy, r.happiness),
          (-fish.price, fish.energy, fish.happiness));
    });

    // Защищает: невыбранные приёмы — в счёте недели по домашнему меню, а
    // съеденный приём из счёта уходит. Уронит: счёт по-прежнему «еда за
    // неделю» целиком, съеденное оплачено дважды, счёт не по меню.
    test('счёт недели: домашнее меню × невыбранные приёмы', () {
      final World w = living();
      final int home = dish(w, 'food_simple').price;
      final int meals = w.snapshot.mealsPerWeek;
      expect(w.weeklyBillParts.food, home * meals);
      ok(w.eat('food_soup'));
      expect(w.weeklyBillParts.food, home * (meals - 1));
      ok(w.chooseFood('food_regular'));
      expect(
          w.weeklyBillParts.food, dish(w, 'food_regular').price * (meals - 1));
      final int parts = w.weeklyBillParts.food +
          w.weeklyBillParts.petFood +
          w.weeklyBillParts.rent +
          w.weeklyBillParts.extra;
      expect(w.snapshot.weeklyBill, parts);
    });

    // Защищает: едим «не так часто» — лимит приёмов недели, отказ с
    // причиной, новая неделя снова открывает приёмы. Уронит: лимита нет,
    // отказ без текста, счётчик не сбрасывается.
    test('приёмов в неделю не больше лимита; новая неделя — снова можно', () {
      final World w = living(needs: 400, wants: 0);
      final int meals = w.snapshot.mealsPerWeek;
      for (int i = 0; i < meals; i++) {
        ok(w.eat('food_simple'));
      }
      final BlockReason? b = w.canDo(WorldAction.eat, id: 'food_simple');
      expect(b?.code, 'eat.limit');
      final WorldResult r = w.eat('food_simple');
      expect((r.ok, r.reasonCode), (false, 'eat.limit'));
      expect(w.weeklyBillParts.food, 0, reason: 'всё съедено — дома не едим');

      ok(w.sleep());
      ok(w.payBills());
      ok(w.startWeek());
      expect(w.snapshot.mealsThisWeek, 0);
      expect(w.canDo(WorldAction.eat, id: 'food_simple')?.code,
          isNot('eat.limit'));
    });

    // Защищает: ТЗ 2.5.6.4 — не хватает денег: отказ, ничего не списано,
    // и сказано, что можно подешевле. Уронит: баланс ушёл в минус, отказ
    // без подсказки, подсказано блюдо, на которое тоже не хватает.
    test('не хватает — отказ с блюдом подешевле, ничего не списано', () {
      final World w = living(needs: 100, wants: 0);
      // Остаток плана ушёл в заработок: тратим его, чтобы в карманах было 100.
      final int spare = w.snapshot.free;
      if (spare > 0) ok(w.depositToGoal(spare));
      expect(w.snapshot.need + w.snapshot.want + w.snapshot.free, 100);
      final ResourceSnapshot before = w.snapshot;
      final WorldResult r = w.eat('food_fish');
      expect((r.ok, r.reasonCode), (false, 'eat.short'));
      expect(r.reason, contains('${dish(w, 'food_fish').price - 100}'));
      // Самое дорогое блюдо меню, на которое хватает 100 (по каталогу).
      final WorldCatalogItem best = w.catalog
          .where((WorldCatalogItem i) =>
              i.category == WorldCatalogCategory.food && i.price <= 100)
          .reduce((WorldCatalogItem a, WorldCatalogItem b) =>
              b.price > a.price ? b : a);
      expect(r.nextStep, contains('${best.title}, ${best.price}'),
          reason: 'самое дорогое блюдо, на которое хватает 100');
      expect(w.snapshot.available, before.available);
      expect(w.snapshot.mealsThisWeek, 0);
    });
  });

  // Защищает: приём пищи — запись журнала и переживает перезапуск (ТЗ
  // 2.5.13.1, 2.5.4.3). Уронит: вид записи не читается из JSON (запись
  // пропала бы как «нечитаемая»), счётчик приёмов не восстанавливается.
  test('приём пищи — одна запись журнала, перезапуск её помнит', () {
    final WorldGame w = contentWorld()..startWeek();
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    final int before = w.journal.length;
    ok(w.eat('food_syrniki'));
    final List<WorldEntry> added = w.journal.sublist(before);
    expect(
        added.map((WorldEntry e) => e.kind), <Enum>[WorldLedgerKind.mealEaten]);
    expect(added.single.args['foodId'], 'food_syrniki');

    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: contentConfig);
    expect(r.unreadable, 0);
    expect(r.snapshot.mealsThisWeek, 1);
    expect(r.snapshot.need, w.snapshot.need);
    expect(r.snapshot.energy, w.snapshot.energy);
    expect(r.weeklyBillParts.food, w.weeklyBillParts.food);
  });

  // Защищает: итоги недели видят всю еду (посреди недели и дома) и долю
  // «вкусного без пользы» (ревью 174d885, критерий §2 п. 8). Уронит: еда
  // посреди недели не попала в факт еды (3 × рыба → «еда 0»), пицца не
  // посчитана как вкусное, домашний приём потерян.
  test('итоги недели: вся еда и доля вкусного без пользы', () {
    final WorldGame w = contentWorld()..startWeek();
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    int price(String id) => w.catalogItem(id)!.price;
    ok(w.completeJob('consultant', score: 0.5)); // денег на пиццу и рыбу
    ok(w.eat('food_tasty'));
    ok(w.eat('food_fish'));
    ok(w.sleep());
    ok(w.payBills()); // третий приём — дома, простое блюдо
    final WeekPlanFact week = w.weekHistory.last;
    final int food =
        price('food_tasty') + price('food_fish') + price('food_simple');
    expect(week.food, food);
    expect(week.treats, price('food_tasty'));
    expect(week.need.actual, greaterThanOrEqualTo(food));
    final String line = foodTakeaway(week)!;
    expect(line, contains('$food'));
    expect(line, contains('${(price('food_tasty') * 100 / food).round()} %'));
  });

  // Защищает: план против факта — еда посреди недели идёт в факт НУЖНО, как
  // счёт. Уронит: история недели показывает «потрачено меньше плана»,
  // хотя деньги ушли на еду.
  test('план против факта: еда посреди недели — факт НУЖНО', () {
    final WorldGame w = contentWorld()..startWeek();
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    final int meal = w.catalogItem('food_regular')!.price;
    ok(w.eat('food_regular'));
    final int bill = w.snapshot.weeklyBill;
    ok(w.sleep());
    ok(w.payBills());
    final WeekPlanFact week = w.weekHistory.last;
    expect(week.need.actual, meal + bill);
  });
}
