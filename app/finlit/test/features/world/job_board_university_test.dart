import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Доска «Требуется…» и вуз Финни (Денис 29.09, 941 п. 5; критерии ночи §3).
///
/// Ловит: доска не говорит, почему открыты финансовые работы (Финни учится
/// на экономиста); карточек вуза нет или без источника; замок программиста
/// без вещи и цены; блок не влезает в 360 × 640 при шрифте 1,3.
void main() {
  forEachWorld((WorldKind kind) {
    testWidgets('вуз: Финни-экономист, советы с источником, замок с ценой',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await pumpWorldScreen(tester, const JobBoardScreen(),
          world: w, textScale: 1.3);

      final Finder finni = find.byKey(const ValueKey<String>('jobs:finni'));
      expect(finni, findsOneWidget);
      // Первая работа видна без прокрутки и при шрифте 1,3 (ревью 28d9a1f).
      final Rect first = tester
          .getRect(find.byKey(const ValueKey<String>('jobs:card:consultant')));
      expect(first.top, lessThan(640));
      expect(
          find.descendant(
              of: finni, matching: find.textContaining('экономист')),
          findsOneWidget);

      final Finder lock =
          find.byKey(const ValueKey<String>('jobs:blocked:programmer/easy'));
      await tester.scrollUntilVisible(lock, 200,
          scrollable: find.byType(Scrollable).first);
      final String price = '${w.catalogItem('tech_laptop')!.price}';
      expect(find.descendant(of: lock, matching: find.textContaining(price)),
          findsWidgets);

      final Finder title =
          find.byKey(const ValueKey<String>('jobs:university'));
      await tester.scrollUntilVisible(title, 200,
          scrollable: find.byType(Scrollable).first);
      expect(title, findsOneWidget);
      // Работы с замками — выше вуза (ревью 2b58bdb §3.3).
      expect(tester.getRect(lock).top, lessThan(tester.getRect(title).top));
      final Finder card =
          find.byKey(const ValueKey<String>('jobs:uni:three_envelopes'));
      await tester.scrollUntilVisible(card, 200,
          scrollable: find.byType(Scrollable).first);
      expect(
          find.descendant(
              of: card, matching: find.textContaining('Источник: Банк России')),
          findsOneWidget);
      expect(find.textContaining('http'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // Ловит (ревью 2b58bdb §3.3): до плана недели замок писал только
    // «Сначала план недели» — ребёнок не видел, что купить, чтобы работа
    // открылась.
    testWidgets('до плана недели замок всё равно называет вещь и цену',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      expect(w.phase, WeekPhase.planning);
      await pumpWorldScreen(tester, const JobBoardScreen(), world: w);
      final JobOffer programmer = w.offer('programmer', variant: 'easy')!;
      final Finder lock =
          find.byKey(const ValueKey<String>('jobs:lock:programmer/easy'));
      await tester.scrollUntilVisible(lock, 200,
          scrollable: find.byType(Scrollable).first);
      expect(
          find.descendant(
              of: lock, matching: find.text(programmer.lockedReason!)),
          findsOneWidget);
      expect(programmer.lockedReason,
          contains('${w.catalogItem('tech_laptop')!.price}'));
      // Подсказка про план — отдельной строкой в той же плашке.
      final Finder blocked =
          find.byKey(const ValueKey<String>('jobs:blocked:programmer/easy'));
      expect(
          find.descendant(
              of: blocked,
              matching: find.textContaining(programmer.blockReason!.text)),
          findsOneWidget);
      expect(programmer.blockReason!.text,
          isNot(contains(programmer.lockedReason!)));
    });
  });
}
