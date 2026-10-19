import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Путь ребёнка 16.10, дефекты 1 и 6: смена консультанта на 360×640.
/// После сканера экран оставался внизу — вопрос покупателя не виден; ответ
/// на выбор рюкзака появлялся ниже края; итог смены открывался прокрученным
/// вниз, урок — под шапкой.
///
/// Защищает: то, что появилось после действия ребёнка, — на экране.
/// Уронит: прокрутка одного этапа переходит на следующий, нет прокрутки к
/// покупателю или к ответу.
void main() {
  setUpAll(loadAppFonts);

  const Size screen = Size(360, 640);

  Future<void> tap(WidgetTester tester, String key) async {
    final Finder f = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  void onScreen(WidgetTester tester, String key) {
    final Rect r = tester.getRect(find.byKey(ValueKey<String>(key)));
    expect(r.top, greaterThanOrEqualTo(0), reason: '$key: верх на экране');
    expect(r.bottom, lessThanOrEqualTo(screen.height),
        reason: '$key: низ на экране');
  }

  testWidgets('консультант: покупатель, ответ и итог — на экране',
      (WidgetTester tester) async {
    final World world = worldKinds.last.make();
    ok(world.startWeek());
    ok(world.plan(needs: 100, wants: 100, goal: 0));
    ok(world.demoUnlockAllJobs());
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('consultant')),
        world: world, size: screen);
    await tap(tester, 'job:start');
    // Рюкзаки по полкам верно (набор раунда 0 — backpacks), сканер внизу.
    await tap(tester, 'consultant:shelf:bp_1:0');
    await tap(tester, 'consultant:shelf:bp_2:1');
    await tap(tester, 'consultant:shelf:bp_3:2');
    await tap(tester, 'consultant:scan');
    onScreen(tester, 'consultant:customer');

    // Неверный выбор: ответ «выбери другой» — на экране, не ниже края.
    await tap(tester, 'consultant:pick:bp_3');
    onScreen(tester, 'consultant:feedback');

    await tap(tester, 'consultant:pick:bp_2');
    onScreen(tester, 'consultant:done');
    await tap(tester, 'consultant:done');

    onScreen(tester, 'job:result:title');
    if (world.pendingLesson != null) {
      expect(
          tester
              .getRect(find.byKey(const ValueKey<String>('lesson:title')))
              .top,
          lessThan(screen.height / 2));
    }
  });
}
