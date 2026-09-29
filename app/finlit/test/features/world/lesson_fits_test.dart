import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

// Ревью 2b58bdb §4.7: на 360×640 урок после смены лежал под таблицей оплаты,
// а при шрифте 1,3 — целиком за экраном; ребёнок видел только «Оплата +N».
// Проверяется геометрия с настоящим шрифтом (квадраты Ahem вдвое шире
// букв): без прокрутки заголовок урока — в верхней половине экрана, первая
// кнопка решения — целиком на экране. Ситуация выгульщика (99 знаков) —
// типичная длина: у остальных уроков 84–105.
void main() {
  setUpAll(loadAppFonts);

  for (final double scale in <double>[1.0, 1.3]) {
    testWidgets('урок после смены виден без прокрутки: 360×640, шрифт ×$scale',
        (WidgetTester tester) async {
      final World world = worldKinds.last.make(); // мир из content/
      ok(world.startWeek());
      ok(world.plan(needs: 100, wants: 100, goal: 0));
      ok(world.demoUnlockAllJobs());
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('dog_walker')),
          world: world, textScale: scale);
      final Finder start = find.byKey(const ValueKey<String>('job:start'));
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey<String>('game:placeholder:do')));
      await tester.pumpAndSettle();

      final LessonOffer lesson = world.pendingLesson!;
      expect(
          tester
              .getRect(find.byKey(const ValueKey<String>('lesson:title')))
              .top,
          lessThan(320));
      final Rect first = tester.getRect(
          find.byKey(ValueKey<String>('lesson:${lesson.choices.first.id}')));
      expect(first.bottom, lessThanOrEqualTo(640));
      expect(first.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  }
}
