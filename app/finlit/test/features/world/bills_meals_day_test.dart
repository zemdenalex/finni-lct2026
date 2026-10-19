import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Проход демо front3 (17.10): (1) «Счета недели» в итогах — то же число,
/// что в плане (жильё + еда по плану); съеденное самим показано отдельно;
/// (2) «поесть ещё N раз» в режиме дней считается по оставшимся дням одним
/// правилом — в справке магазина и в итоге еды.
///
/// Уронит: итоги снова показывают остаток счёта (460 → 390) без объяснения;
/// «ещё N» берёт приёмы недели и обещает больше, чем осталось дней.
Finder _text(String s) => find.textContaining(s, findRichText: true);

void main() {
  setUp(rootBundle.clear);

  testWidgets('итоги: счета недели = как в плане, съеденное — отдельно', (
    WidgetTester tester,
  ) async {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    final int planBill = w.snapshot.weeklyBill;
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    final String home = w.snapshot.foodId!;
    final int price = w.catalogItem(home)!.price;
    ok(w.eat(home));
    expect(w.snapshot.weeklyBill, planBill - price, reason: 'остаток счёта');
    ok(sleepWeek(w));
    expect(w.phase, WeekPhase.review);
    await pumpWorldScreen(tester, const WeekReviewScreen(), world: w);
    final Finder box = find.byKey(const ValueKey<String>('review:bills'));
    expect(find.descendant(of: box, matching: _text('Счета недели: $planBill')),
        findsOneWidget);
    expect(
        find.descendant(
            of: box,
            // Пол героя не выбран — без рода (правило 5Б, иначе «поел сам»
            // / «поела сама»: hero_gender_lines_test).
            matching: _text('Еда на $price уже съедена и оплачена. '
                'Осталось ${planBill - price}')),
        findsOneWidget);
  });

  test('«ещё N раз» — по оставшимся дням: день 5 без еды → 3, после — 2', () {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    for (int d = 1; d < 5; d++) {
      ok(w.sleep());
      if (w.pendingEvent case final PendingEvent e) {
        ok(w.resolveEvent(
            e.choices.firstWhere((PendingEventChoice c) => c.available).id));
      }
    }
    expect(w.snapshot.dayInWeek, 5);
    expect(w.snapshot.mealsLeft, 7, reason: 'сам не ел: недельных 7');
    expect(w.snapshot.mealsAvailable, 3, reason: 'дни 5, 6, 7');
    final WorldResult r = w.eat(w.snapshot.foodId!);
    expect(r.nextStep, 'Поесть на этой неделе можно ещё 2 раза');
  });

  testWidgets('магазин, день 1 после еды: «ещё 6 раз»', (
    WidgetTester tester,
  ) async {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    ok(w.eat(w.snapshot.foodId!));
    await pumpWorldScreen(tester, const WorldShopScreen(), world: w);
    expect(_text('Поесть на этой неделе можно ещё 6 раз'), findsOneWidget);
  });
}
