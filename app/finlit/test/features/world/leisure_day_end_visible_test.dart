import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/leisure/leisure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Отдых, после которого сил не хватает ни на одно дело: мир сам укладывает
/// Финни спать, и сразу утро (логика не меняется). Тот же приём, что на итоге
/// смены (D2): строка «Уже утро: день N из 7» закреплена под прокруткой, а в
/// итоге вместо «Силы кончились» при остатке — сколько сил осталось.
///
/// Защищает (путь ребёнка rc-7d, k43): «Парк — … Силы кончились — наступил
/// вечер… Наступило утро — день 7 из 7» при оставшихся силах, утро только
/// внутри абзаца итога (в альбомной — за краем колонки). Уронит: строка «Уже
/// утро» пропала или закрыла итог и кнопки «Пойти»; итог снова говорит
/// «Силы кончились», когда силы остались.
WorldGame _tiredWorld() {
  final WorldGame w = contentDayWorld();
  ok(w.startWeek());
  ok(w.plan(needs: 300, wants: 300, goal: 0));
  if (w.pendingEvent case final PendingEvent e) {
    ok(w.resolveEvent(
        e.choices.firstWhere((PendingEventChoice c) => c.available).id));
  }
  // Смена, потом парк, пока после следующего парка силы ещё останутся, но
  // меньше, чем на самое дешёвое дело: остаток не ноль.
  ok(w.completeJob('consultant', score: 0));
  if (w.pendingLesson case final LessonOffer l) {
    ok(w.resolveLesson(l.choices.first.id));
  }
  while (w.snapshot.energy - 4 >= w.cheapestActionEnergy) {
    ok(w.leisure('park'));
  }
  return w;
}

void main() {
  setUpAll(loadAppFonts);

  for (final (Size size, double scale) in <(Size, double)>[
    (const Size(360, 800), 1),
    (const Size(360, 640), 1.3),
    (const Size(640, 360), 1.3),
  ]) {
    final bool land = size.width > size.height;
    testWidgets(
        'парк закончил день, ${size.width.round()}×${size.height.round()} '
        '×$scale: «Уже утро» на экране, итог и кнопки не закрыты',
        (WidgetTester tester) async {
      final WorldGame w = _tiredWorld();
      final int day = w.snapshot.dayInWeek;
      await pumpWorldScreen(tester, const LeisureScreen(place: 'park'),
          world: w, size: size, textScale: scale);
      await tester.pumpAndSettle();
      final Finder go = find.byKey(const ValueKey<String>('leisure:go:park'));
      await tester.ensureVisible(go);
      await tester.pumpAndSettle();
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(w.snapshot.dayInWeek, day + 1, reason: 'отдых закончил день');
      // Как ребёнок видит экран после касания: прокрутка в начало.
      for (final Element e in find.byType(Scrollable).evaluate()) {
        await tester.drag(find.byWidget(e.widget), const Offset(0, 3000),
            warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      // Итог: остаток сил словами, без «Силы кончились».
      final String reason = tester
          .widget<RichText>(find.descendant(
              of: find.byKey(const ValueKey<String>('leisure:reason')),
              matching: find.byType(RichText)))
          .text
          .toPlainText();
      expect(reason, isNot(contains('Силы кончились')));
      expect(reason, contains('на дела не хватит'));
      expect(reason, isNot(contains('Сил осталось 0 ')),
          reason: 'сценарий с остатком сил');

      // «Уже утро» — на экране целиком, одной строкой.
      final Finder strip = find.byKey(const ValueKey<String>('leisure:night'));
      expect(strip, findsOneWidget);
      final Rect n = tester.getRect(strip);
      expect(n.top, greaterThanOrEqualTo(0));
      expect(n.bottom, lessThanOrEqualTo(size.height));
      expect(n.height, lessThan(64), reason: 'одна строка');

      // Строка не закрывает итог (портрет) и кнопки «Пойти» первого ряда.
      if (!land) {
        expect(
            tester
                .getRect(find.byKey(const ValueKey<String>('leisure:result')))
                .bottom,
            lessThanOrEqualTo(n.top));
      }
      if (land || scale == 1) {
        expect(tester.getRect(go).bottom, lessThanOrEqualTo(n.top));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
