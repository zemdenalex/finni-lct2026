import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Смена на 360×800, 360×640 и 640×360 (путь ребёнка rc-7d, D2; баг-прогон
/// 18.10, BG-04), настоящий шрифт, масштаб 1 и 1,3.
///
/// Защищает: (1) оба варианта каждого вопроса смены видны целиком без
/// прокрутки — было: на 360×800 второй («Вежливо отказаться») виднелся на
/// 21 px, ребёнок жал первый, и именно он кончал день; на 360×640 оба
/// варианта были ниже края (числа смены и «Как это считается» над ними); (2) если смена закончила день (силы ниже самого
/// дешёвого дела — мир сам укладывает Финни, и сразу утро), строка про утро
/// видна сразу под итогом смены — было: последняя фраза длинного абзаца,
/// только после прокрутки, а шапка уже показывала утренние силы.
/// Уронит: условия или числа смены снова над вариантами; строка про утро снова только
/// внутри абзаца внизу итога. Логику авто-сна тест не трогает.
const Size _screen = Size(360, 800);

WorldGame _living() {
  final WorldGame w = contentDayWorld();
  ok(w.startWeek());
  ok(w.plan(needs: 300, wants: 300, goal: 0));
  if (w.pendingEvent case final PendingEvent e) {
    ok(w.resolveEvent(
        e.choices.firstWhere((PendingEventChoice c) => c.available).id));
  }
  return w;
}

void main() {
  setUpAll(loadAppFonts);

  // 360×640 и 640×360 — экраны ТЗ (BG-04: на 360×640 варианты уходили под
  // край, y ≈ 680, при шрифте 1,3 — 870), 1,3 — крупный шрифт системы.
  for (final (Size size, double scale) in <(Size, double)>[
    (_screen, 1),
    (const Size(360, 640), 1),
    (const Size(360, 640), 1.3),
    (const Size(640, 360), 1),
    (const Size(640, 360), 1.3),
  ]) {
    testWidgets(
        'карточка смены ${size.width.round()}×${size.height.round()} ×$scale: '
        'оба варианта каждого вопроса на экране целиком',
        (WidgetTester tester) async {
      // Вопрос у смены выпадает по журналу (`shift_choices.chance`): взносы
      // по 1 монете двигают журнал. Каждая работа, каждый встреченный вопрос
      // — самый длинный вопрос и подсказки тоже.
      final Set<String> seen = <String>{};
      for (int i = 0; i < 40; i++) {
        final WorldGame w = _living();
        ok(w.demoUnlockAllJobs());
        for (int d = 0; d < i; d++) {
          w.depositToGoal(1);
        }
        for (final JobOffer job in w.jobBoard) {
          final ShiftChoice? q = w.offer(job.jobId)?.choice;
          if (q == null || !seen.add(q.id)) continue;
          await pumpWorldScreen(
              tester, JobPlayScreen(args: JobPlayArgs(job.jobId)),
              world: w, size: size, textScale: scale);
          await tester.pumpAndSettle();
          // Видимое кончается над нижним меню (стиль Алины), а не у края
          // экрана: вариант под меню ребёнок тоже не видит.
          final Finder dock = find.byKey(const ValueKey<String>('dock'));
          final double bottom =
              dock.evaluate().isEmpty ? size.height : tester.getRect(dock).top;
          for (final ShiftChoiceOption o in q.options) {
            final Rect r = tester
                .getRect(find.byKey(ValueKey<String>('job:choice:${o.id}')));
            expect(r.bottom, lessThanOrEqualTo(bottom),
                reason: '${job.jobId} «${q.question}» → ${o.label}: $r');
          }
          expect(tester.takeException(), isNull);
        }
      }
      expect(seen.length, greaterThanOrEqualTo(10),
          reason: 'встреченные вопросы: $seen');
    });
  }

  for (final (Size size, double scale) in <(Size, double)>[
    (_screen, 1),
    (const Size(800, 360), 1),
    (const Size(360, 640), 1.3),
    (const Size(640, 360), 1.3),
  ]) {
    final bool land = size.width > size.height;
    testWidgets(
        'смена закончила день, ${size.width.round()}×${size.height.round()} '
        '×$scale: строка про утро видна без прокрутки',
        (WidgetTester tester) async {
      final WorldGame w = _living();
      // Парк, пока после смены выгульщика сил не останется на самое дешёвое
      // дело: тогда мир сам закончит день.
      final double cost = w.offer('dog_walker')!.energyCost;
      while (w.snapshot.energy - cost >= w.cheapestActionEnergy &&
          w.snapshot.energy - 4 >= cost) {
        ok(w.leisure('park'));
      }
      final int day = w.snapshot.dayInWeek;
      ok(w.demoUnlockAllJobs());
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('dog_walker')),
          world: w,
          size: size,
          textScale: scale,
          games: contentJobGamesDogStub);
      await tester.pumpAndSettle();
      final Finder start = find.byKey(const ValueKey<String>('job:start'));
      final Finder pick = start.evaluate().isNotEmpty
          ? start
          : find.byKey(ValueKey<String>(
              'job:choice:${w.offer('dog_walker')!.choice!.options.last.id}'));
      await tester.ensureVisible(pick);
      await tester.pumpAndSettle();
      await tester.tap(pick);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey<String>('game:placeholder:do')));
      await tester.pumpAndSettle();
      expect(w.snapshot.dayInWeek, day + 1, reason: 'смена закончила день');

      // Итог смены — первым, вверху.
      expect(
          tester
              .getRect(find.byKey(const ValueKey<String>('job:result:title')))
              .top,
          lessThan(size.height / 2));
      // Утро — на экране без прокрутки: хотя бы одна строка про утро видна.
      final List<Rect> morning = <Rect>[
        for (final Element e in find.textContaining('утро').evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      expect(morning.any((Rect r) => r.top >= 0 && r.bottom <= size.height),
          isTrue,
          reason: 'строки про утро: $morning');
      // Почему утро — в итоге словами, без «Силы кончились» при остатке.
      expect(find.textContaining('на дела не хватит'), findsOneWidget);
      expect(find.textContaining('Силы кончились'), findsNothing);
      // Строка про утро не закрывает урок (он обязателен): в портрете первый
      // вариант — над ней.
      if (!land) {
        final LessonOffer l = w.pendingLesson!;
        expect(
            tester
                .getRect(find
                    .byKey(ValueKey<String>('lesson:${l.choices.first.id}')))
                .bottom,
            lessThanOrEqualTo(tester
                .getRect(find.byKey(const ValueKey<String>('job:result:night')))
                .top));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
