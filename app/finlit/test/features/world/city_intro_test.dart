import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/onboarding/city_intro_gate.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Подсказки первого выхода в город (Денис 20.10: «надо добавить онбординг
/// при первом выходе в город»).
///
/// Защищает: маршрут города в первый раз показывает 2–3 подсказки облачком
/// Финни (монеты, силы, цель), «Дальше» листает, «Понятно» закрывает, во
/// второй раз их нет, после сброса мира — снова. Облачко с кнопками 48 dp
/// целиком на экране при шрифте 1,3. Реплика про настроение обводит чип
/// настроения в строке сверху (Настя 20.10), другие — нет.
///
/// Уронит: маршрут города без [CityIntroGate], флаг `city.intro` не
/// запоминается (подсказки при каждом выходе) или запоминается навсегда,
/// облачко за краем на 360×640 или 640×360.
///
/// Почему не ловят другие тесты: `first_path_test` проходит подсказки, но
/// без сброса и без проверки раскладки облачка.
WorldGame _living() {
  final WorldGame w = contentDayWorld(
      onboarding: const OnboardingProgress(
          step: OnboardingProgress.stepDone, finniName: 'Бублик'));
  if (w.phase == WeekPhase.weekStart || w.phase == WeekPhase.onboarding) {
    ok(w.startWeek());
  }
  if (w.phase == WeekPhase.planning) {
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  }
  return w;
}

Future<WorldState> _city(WidgetTester tester, World w, Size size) async {
  late WorldState ws;
  await tester.runAsync(() async {
    ws = await pumpWorldScreen(
        tester,
        Builder(builder: (BuildContext c) => worldRoutes[WorldRoutes.city]!(c)),
        world: w,
        size: size,
        textScale: 1.3);
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 400));
  return ws;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  final Finder next = find.byKey(const ValueKey<String>('city:intro:next'));

  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('первый выход в город: подсказки облачком, один раз · ${o.key}',
        (WidgetTester tester) async {
      final WorldGame w = _living();
      expect(w.seen(cityIntroSeen), isFalse);
      final WorldState ws = await _city(tester, w, o.value);
      expect(find.byType(CityScreen), findsOneWidget);
      expect(next, findsOneWidget, reason: 'первый выход — подсказки');
      final StringBuffer said = StringBuffer();
      int beats = 0;
      int moodBeats = 0;
      for (; beats < 6 && next.evaluate().isNotEmpty; beats++) {
        final Finder bubble = find.byKey(ValueKey<String>('city:intro:$beats'));
        expect(bubble, findsOneWidget, reason: 'подсказка $beats');
        final Rect b = tester.getRect(bubble);
        expect(b.left, greaterThanOrEqualTo(0), reason: '$b');
        expect(b.top, greaterThanOrEqualTo(0), reason: '$b');
        expect(b.right, lessThanOrEqualTo(o.value.width), reason: '$b');
        expect(b.bottom, lessThanOrEqualTo(o.value.height), reason: '$b');
        final Rect n = tester.getRect(next);
        expect(n.height, greaterThanOrEqualTo(48));
        expect(b.contains(n.center), isTrue, reason: '«Дальше» в облачке');
        final String line = find
            .descendant(of: bubble, matching: find.byType(RichText))
            .evaluate()
            .map((Element e) => (e.widget as RichText).text.toPlainText())
            .join(' ');
        said.write(line);
        // Реплика про настроение — рамка у чипа настроения сверху (Настя
        // 20.10, тема 11); в других репликах рамки нет.
        await tester.pump();
        final Finder ring =
            find.byKey(const ValueKey<String>('city:intro:hud'));
        if (line.contains('настроени')) {
          moodBeats++;
          expect(ring, findsOneWidget, reason: 'рамка у настроения: $line');
          expect(
              tester.getRect(ring).contains(tester.getCenter(find
                  .byKey(const ValueKey<String>('hud:happiness'))
                  .first)),
              isTrue,
              reason: 'рамка вокруг чипа настроения');
        } else {
          expect(ring, findsNothing, reason: 'не про настроение: $line');
        }
        await tester.tap(next);
        await tester.pump();
      }
      expect(beats, inInclusiveRange(2, 4));
      expect(moodBeats, 1, reason: 'одна реплика про настроение');
      expect(next, findsNothing, reason: '«Понятно» закрыло подсказки');
      for (final String word in <String>['монет', 'сил', 'цел']) {
        expect(said.toString(), contains(word), reason: 'детское слово $word');
      }
      await tester.pump();
      expect(w.seen(cityIntroSeen), isTrue, reason: 'показано — запомнено');

      // Второй выход — без подсказок.
      await _city(tester, w, o.value);
      expect(next, findsNothing, reason: 'второй выход — без подсказок');

      // Сброс мира — новое знакомство и снова подсказки.
      await ws.reset();
      expect(ws.world.seen(cityIntroSeen), isFalse);
    });
  }

  testWidgets('«Пропустить» закрывает подсказки сразу и тоже запоминает',
      (WidgetTester tester) async {
    final WorldGame w = _living();
    await _city(tester, w, portrait);
    await tester.tap(find.byKey(const ValueKey<String>('city:intro:skip')));
    await tester.pump();
    expect(next, findsNothing);
    expect(w.seen(cityIntroSeen), isTrue);
  });
}
