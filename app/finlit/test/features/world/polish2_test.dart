import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Путь ребёнка 16.10, дефекты 11 и 18.
///
/// 11: у целей нет срока — «Собака 3200» выглядит так же близкой, как
/// «Рыбка 400». Защищает: при выборе цели виден срок тем же расчётом, что
/// в копилке; до первого взноса — объяснение вместо срока.
/// 18: «Продавец-консультант» в шапке смены обрезался на 360 dp.
/// Уронит: срок пропал из списка целей; название в шапке снова с «…».
void main() {
  setUpAll(loadAppFonts);

  testWidgets('шапка смены: название целиком на 360 dp',
      (WidgetTester tester) async {
    final World w = worldKinds.last.make();
    ok(w.startWeek());
    ok(w.plan(needs: 100, wants: 100, goal: 0));
    ok(w.demoUnlockAllJobs());
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('consultant')),
        world: w, textScale: 1.3);
    final RenderParagraph p = tester.renderObject<RenderParagraph>(
        find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Продавец-консультант')));
    expect(p.didExceedMaxLines, isFalse, reason: 'без «…»');
    expect(tester.getRect(find.text('Продавец-консультант')).right,
        lessThanOrEqualTo(360));
  });

  testWidgets('копилка: у цели срок, если откладывали',
      (WidgetTester tester) async {
    final World w = worldKinds.last.make();
    ok(w.startWeek());
    ok(w.plan(needs: 300, wants: 50, goal: 50));
    // Срок — по законченной неделе с взносом (вариант A, 17.10).
    ok(sleepWeek(w));
    ok(w.payBills());
    ok(w.startWeek());
    ok(w.plan(needs: 300, wants: 50, goal: 0));
    final ResourceSnapshot s = w.snapshot;
    // Отложено за прошлую неделю 50; срок = ⌈(цена − в копилке) ÷ 50⌉.
    final WorldCatalogItem bike = w.catalogItem('transport_bike')!;
    final int weeks = ((bike.price - s.goal) + 49) ~/ 50;
    await pumpWorldScreen(tester, const PiggyScreen(), world: w);
    final Finder eta =
        find.byKey(const ValueKey<String>('row:eta:transport_bike'));
    await tester.scrollUntilVisible(eta, 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Text>(eta).data, startsWith('примерно $weeks '));
  });
}
