import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/shop/shop_kit.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

// Ловит (консультация экспертов 16.10, замечание 1): на карточках еды
// состояние «Едим дома» и кнопка «Есть дома» читались одинаково — ребёнок не
// понимал, что выбрано. Выбранное — отметка и сколько в холодильнике;
// остальные — кнопка с другим глаголом.
void main() {
  forEachWorld((WorldKind kind) {
    testWidgets('выбранное домашнее блюдо — отметка, остальные — кнопка',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const WorldShopScreen(), world: w);
      });
      await tester.pump();
      final WorldCatalogItem home = chosenFood(w)!;
      final WorldCatalogItem other = catalogOf(w, WorldCatalogCategory.food)
          .firstWhere((WorldCatalogItem f) => f.id != home.id);

      final Finder mark = find.byKey(ValueKey<String>('food:home:${home.id}'));
      await tester.ensureVisible(mark);
      expect(find.descendant(of: mark, matching: find.text('Дома едим это')),
          findsOneWidget);
      final int left = w.snapshot.mealsLeft;
      expect(
          find.descendant(
              of: mark, matching: find.textContaining('В холодильнике: $left')),
          findsOneWidget);
      expect(find.byKey(ValueKey<String>('home:${home.id}')), findsNothing,
          reason: 'у выбранного кнопки нет');

      final Finder button = find.byKey(ValueKey<String>('home:${other.id}'));
      await tester.ensureVisible(button);
      expect(find.descendant(of: button, matching: find.text('Готовить дома')),
          findsOneWidget);
      expect(find.text('Едим дома'), findsNothing);
      expect(find.text('Есть дома'), findsNothing);
    });
  });
}
