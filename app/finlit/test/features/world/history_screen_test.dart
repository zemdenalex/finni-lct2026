import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Ловит (ТЗ 2.5.11.1, 2.5.3.2, 2.5.6.3): истории недель нет или она не из
/// журнала — смены, покупки, план и факт не совпадают с миром; недели не
/// новые первыми; неоплаченная неделя выглядит как «счета 0»; прогресс не
/// открывается из комнаты в один тап.
void main() {
  forEachWorld((WorldKind kind) {
    /// Неделя 1 сыграна до конца (цель, событие, смена, перекус, счета),
    /// неделя 2 идёт.
    World twoWeeks() {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 50, goal: 100));
      ok(w.chooseGoal('pet_fish'));
      // Событие недели 1 в обоих мирах — «понарошку», без денег.
      ok(w.resolveEvent('simulate'));
      ok(w.completeJob('gardener', score: 1));
      ok(w.buy('snack'));
      ok(w.sleep());
      ok(w.payBills());
      ok(w.startWeek());
      ok(w.plan(needs: 300, wants: 0, goal: 100));
      return w;
    }

    String textOf(WidgetTester tester, String key) => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey<String>(key)), matching: find.byType(Text)))
        .map((Text t) => t.data ?? t.textSpan!.toPlainText())
        .join('\n')
        .replaceAll(' ', ' ');

    testWidgets('недели новые первыми; смены, покупки и план — из мира',
        (WidgetTester tester) async {
      final World w = twoWeeks();
      final WeekPlanFact w1 = w.weekHistory.first;
      await pumpWorldScreen(tester, const HistoryScreen(), world: w);

      final Finder week1 = find.byKey(const ValueKey<String>('history:week:1'));
      final Finder week2 = find.byKey(const ValueKey<String>('history:week:2'));
      await tester.ensureVisible(week1);
      await tester.pump();
      expect(
          tester.getTopLeft(week2).dy, lessThan(tester.getTopLeft(week1).dy));

      final String one = textOf(tester, 'history:week:1');
      final WeekItem shift = w1.shifts.single;
      final WeekItem snack = w1.purchases.single;
      expect(one, contains('${shift.title} +${shift.amount}'));
      expect(one, contains('${snack.title} ${snack.amount}'));
      expect(one, contains('план 250 → счета ${w1.need.actual}'));
      expect(one, contains('план 50 → потратили ${snack.amount}'));
      expect(one, contains('план 100 → отложили ${w1.goal.actual}'));
      expect(one, contains('События: ${w1.events.single}'));
      expect(
          one,
          contains(
              'Цель «${w1.goalTitle}»: ${w1.savedAtEnd} из ${w1.goalPrice}'));

      expect(textOf(tester, 'history:w2:need'), contains('ещё не оплачен'),
          reason: 'неделя идёт — не «счета 0»');
    });

    testWidgets('«Прогресс» в комнате открывает историю в один тап',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: twoWeeks(), size: landscape);
        for (int i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      await tester.tap(find.byKey(const ValueKey<String>('room:nav:progress')));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('history:week:2')), findsOneWidget);
    });

    // Ловит (ревью df2164a): очков на переезд уже хватает, а ребёнок не
    // переехал — прогресс писал «До переезда: ещё −2». Та же строка — в
    // итогах недели (`WeekReviewScreen.moveLine`).
    testWidgets('очков хватает — «можно переезжать», без «ещё −N»',
        (WidgetTester tester) async {
      final World w = kind.make();
      for (int i = 0; i < 2; i++) {
        ok(w.startWeek());
        ok(w.plan(needs: 300, wants: 0, goal: 100));
        ok(w.completeJob('consultant', score: 0.5));
        ok(w.sleep());
        // Отложено ≥ 10 % — итог говорит, зачем (ревью df2164a §1.7).
        expect(ok(w.payBills()).reason, contains('к цели приходят раньше'));
      }
      ok(w.startWeek());
      expect(w.snapshot.growthPoints, greaterThanOrEqualTo(4));
      expect(w.snapshot.stage, WorldStage.village);
      await pumpWorldScreen(tester, const HistoryScreen(), world: w);
      final String summary = textOf(tester, 'history:summary');
      expect(summary, contains('Очков хватает — можно переезжать'));
      expect(summary, contains('В копилке'));
      expect(summary, isNot(matches(RegExp(r'ещё [−-]'))));
    });
  });
}
