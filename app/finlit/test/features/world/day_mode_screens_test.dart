import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Ключевые экраны на мире **с днями** — так, как идёт в релиз (контракт back
/// §1–§5). Харнесс экранов по умолчанию держит неделю (`weekMode`), поэтому
/// дневной путь проверяется здесь отдельно; `FINNI_DAY=1 flutter test …`
/// гоняет ещё и все `forEachWorld`-тесты на дневном мире.
///
/// Уронит: «Спать» в последний день не ведёт в итоги; диалог сна не говорит,
/// сколько дней до итогов; итоги или «Прогресс» после дневной недели не
/// влезают в 360 × 640 при шрифте 1,3; второй приём еды за день не гаснет.
void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  World living() {
    final World w = contentDayWorld()..startWeek();
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    return w;
  }

  /// Вся неделя дней через кровать комнаты, до итогов.
  Future<void> sleepWeek(WidgetTester tester, World w) async {
    final int days = w.snapshot.daysPerWeek;
    for (int d = 1; d <= days; d++) {
      // Утреннее сообщение (4 с) в этой ветке лежит поверх кровати —
      // ждём, пока уйдёт (в front-ui-fixes касания проходят сквозь него).
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey<String>('room:bed')));
      await settle(tester);
      expect(
          find.textContaining(d < days
              ? 'Итоги недели — после дня $days'
              : 'последний день недели'),
          findsOneWidget,
          reason: 'день $d из $days');
      await tester.tap(find.byKey(const ValueKey<String>('sleep:confirm')));
      await settle(tester);
      if (d < days) {
        expect(w.phase, WeekPhase.living, reason: 'после дня $d — утро');
        expect(w.snapshot.dayInWeek, d + 1);
      }
    }
    expect(w.phase, WeekPhase.review);
  }

  for (final (String name, Size size) in <(String, Size)>[
    ('портрет', portrait),
    ('альбомная', landscape),
  ]) {
    testWidgets('$name: дни → итоги → оплата → новая неделя, шрифт 1,3',
        (WidgetTester tester) async {
      final World w = living();
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: w, size: size, textScale: 1.3);
      });
      await settle(tester);
      await sleepWeek(tester, w);
      await tester.tap(find.byKey(const ValueKey<String>('sleep:next')));
      await settle(tester);
      expect(find.byType(WeekReviewScreen), findsOneWidget);
      final Finder pay = find.byKey(const ValueKey<String>('review:pay'));
      await tester.ensureVisible(pay);
      await tester.pump();
      await tester.tap(pay);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(w.weekHistory.last.billsPaid, isTrue);
      final Finder next = find.byKey(const ValueKey<String>('review:new_week'));
      await tester.ensureVisible(next);
      await tester.pump();
      await tester.tap(next);
      await settle(tester);
      expect(w.phase, WeekPhase.planning);
    });

    testWidgets('$name: «Прогресс» после дневной недели, шрифт 1,3',
        (WidgetTester tester) async {
      final World w = living();
      for (int d = 0; d < w.snapshot.daysPerWeek; d++) {
        ok(w.sleep());
      }
      ok(w.payBills());
      ok(w.startWeek());
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const HistoryScreen(),
            world: w, size: size, textScale: 1.3);
      });
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(
          find.byKey(const ValueKey<String>('history:week:1')), findsOneWidget);
    });
  }

  testWidgets('еда: второй приём за день гаснет с причиной мира',
      (WidgetTester tester) async {
    final World w = living();
    late WorldState ws;
    await tester.runAsync(() async {
      ws = await pumpWorldScreen(tester, const WorldShopScreen(), world: w);
    });
    await settle(tester);
    final String food = w.catalog
        .firstWhere(
            (WorldCatalogItem i) => i.category == WorldCatalogCategory.food)
        .id;
    ok(ws.act((World x) => x.eat(food)));
    await settle(tester);
    final BlockReason? block = w.canDo(WorldAction.eat, id: food);
    expect(block?.code, 'eat.day_limit');
    final Finder eat = find.byKey(ValueKey<String>('eat:$food'));
    await tester.ensureVisible(eat);
    expect(tester.widget<OutlinedButton>(eat).onPressed, isNull);
    expect(find.textContaining(block!.text), findsWidgets);
  });
}
