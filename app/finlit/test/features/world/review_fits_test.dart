import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

// Ловит (координатор, 29.09): в портрете 360×640 «Что мы поняли» в итогах
// недели лежало под сгибом — ниже «почему кончилась неделя» и счетов.
// С настоящим шрифтом, без прокрутки: «чек» ▲/▼ и вывод недели видны над
// прибитой кнопкой «Новая неделя».
void main() {
  setUpAll(loadAppFonts);

  for (final double scale in <double>[1.0, 1.3]) {
    testWidgets('итоги: «чек» и «Что мы поняли» без прокрутки, ×$scale', (
      WidgetTester tester,
    ) async {
      final World w = worldKinds.last.make(); // мир из content/
      ok(w.startWeek());
      ok(w.plan(needs: 300, wants: 50, goal: 50));
      ok(w.completeJob('consultant', score: 0.5));
      ok(w.sleep());
      ok(w.payBills());
      await pumpWorldScreen(
        tester,
        const WeekReviewScreen(),
        world: w,
        textScale: scale,
      );

      final Rect check = tester.getRect(
        find.byKey(const ValueKey<String>('review:planfact:goal')),
      );
      final Rect takeaway = tester.getRect(
        find.byKey(const ValueKey<String>('review:takeaway')),
      );
      final Rect newWeek = tester.getRect(
        find.byKey(const ValueKey<String>('review:new_week')),
      );
      expect(check.top, greaterThan(0));
      expect(
        takeaway.top,
        greaterThan(check.top),
        reason: 'вывод — сразу под «чеком»',
      );
      expect(takeaway.bottom, lessThanOrEqualTo(newWeek.top));
      expect(tester.takeException(), isNull);
    });
  }
}
