import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Все подписи узла TalkBack и его потомков.
String _spoken(SemanticsNode n) {
  final StringBuffer b = StringBuffer(n.label);
  n.visitChildren((SemanticsNode c) {
    b
      ..write(' ')
      ..write(_spoken(c));
    return true;
  });
  return b.toString();
}

// Защищает: TalkBack проходит магазин по карточке, а не читает весь отдел
// одной подписью (проход RC 17.10, находка 9: «Каша… Суп… Котлета…» —
// 1000+ знаков в одном узле). Уронит: у карточки снова нет своей ветки
// семантики, и её текст сливается с соседними.
void main() {
  testWidgets('магазин, еда: у каждой карточки своя ветка TalkBack',
      (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final World w = worldKinds.first.make();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const WorldShopScreen(), world: w);
    });
    await tester.pump(const Duration(seconds: 1));
    final List<WorldCatalogItem> foods = w.catalog
        .where((WorldCatalogItem i) => i.category == WorldCatalogCategory.food)
        .toList();
    expect(foods.length, greaterThan(1));
    // Ключ карточки — на отступе снаружи; узел — у её содержимого.
    final String first = _spoken(tester.getSemantics(find
        .descendant(
            of: find.byKey(ValueKey<String>('card:${foods[0].id}')),
            matching: find.byType(Column))
        .first));
    expect(first, contains(foods[0].title));
    expect(first, isNot(contains(foods[1].title)));
    h.dispose();
  });

  // Ловит (ревью 17.10): точки цвета мебели — цель касания 40×40,
  // меньше 48 dp ТЗ. Уронит: цель снова меньше 48.
  testWidgets('магазин, «Мебель»: точки цвета — цели касания ≥ 48 dp',
      (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final World w = worldKinds.last.make();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const WorldShopScreen(initialTab: 3),
          world: w);
    });
    await tester.pump(const Duration(seconds: 1));
    final Finder dots = find.byWidgetPredicate((Widget x) =>
        x.key is ValueKey<String> &&
        (x.key! as ValueKey<String>).value.startsWith('color:'));
    // Нижнее меню (стиль Алины) забрало 60 dp: первая карточка с цветами —
    // ниже первого экрана, ленивый список её не строит. Докрутить, чтобы
    // правило 48 dp проверяло сами точки на экране, а не карточки над ними.
    final Finder list = find
        .descendant(
            of: find.byType(WorldShopScreen),
            matching: find.byWidgetPredicate((Widget s) =>
                s is Scrollable && s.axisDirection == AxisDirection.down))
        .first;
    for (int i = 0; i < 30 && dots.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -200));
      await tester.pump();
    }
    expect(dots, findsWidgets, reason: 'вкладка «Мебель» с цветами');
    await tester.ensureVisible(dots.first);
    await tester.pump();
    final Rect dot = tester.getRect(dots.first);
    expect(
        dot.bottom,
        lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey<String>('dock'))).top),
        reason: 'точка над нижним меню: $dot');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    h.dispose();
  });
}
