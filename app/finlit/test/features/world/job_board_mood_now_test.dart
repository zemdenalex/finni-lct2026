import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/board/job_offer_card.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// DEN-36 A: на карточке смены — что настроение **сейчас** делает с оплатой
/// и силами («Настроение 25 сейчас: плата −21 монетка, сил уйдёт на 1
/// больше»; без процентов — Т6 А, Настя 19.10). Защищает: строка стоит на каждой карточке режима дней, числа в
/// ней — из [JobOffer.moodNow] мира, влезает при шрифте 1,3 в обеих
/// ориентациях; знак и слова «больше/меньше» не перепутаны; в «неделе»
/// строки нет. Уронит: строка не показана, знак процента или монет
/// потерян, «сил больше» при хорошем настроении. Почему не ловят прежние:
/// `job_board_mood_test` — про тип работы (C5), а не про настроение сейчас.
void main() {
  test('строка: грустный, радостный, обычный', () {
    expect(
        moodNowText(const MoodPayNow(
            mood: 25, payPercent: -15, energyDelta: 1, payCoins: -21)),
        'Настроение 25 сейчас: плата −21 монетка, '
        'сил уйдёт на 1 больше');
    expect(
        moodNowText(const MoodPayNow(
            mood: 80, payPercent: 18, energyDelta: -1, payCoins: 26)),
        'Настроение 80 сейчас: плата +26 монеток, '
        'сил уйдёт на 1 меньше');
    expect(
        moodNowText(const MoodPayNow(
            mood: 50, payPercent: 0, energyDelta: 0, payCoins: 0)),
        'Настроение 50 сейчас: плата обычная, силы как обычно');
  });

  for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
    testWidgets(
        'доска: строка настроения сейчас на каждой карточке, шрифт 1,3 · '
        '${size.width.toInt()}×${size.height.toInt()}',
        (WidgetTester tester) async {
      final WorldGame w = contentDayWorld();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await pumpWorldScreen(tester, const JobBoardScreen(),
          world: w, size: size, textScale: 1.3, explain: explainFor(w));
      expect(tester.takeException(), isNull);
      final Map<String, JobOffer> byKey = <String, JobOffer>{
        for (final JobOffer o in w.jobBoard) offerKey(o): o,
      };
      int seen = 0;
      for (final MapEntry<String, JobOffer> e in byKey.entries) {
        final Finder line =
            find.byKey(ValueKey<String>('jobs:mood_now:${e.key}'));
        if (line.evaluate().isEmpty) continue; // карточка за краем списка
        seen++;
        final PicText shown = tester.widget<PicText>(
            find.descendant(of: line, matching: find.byType(PicText)));
        expect(shown.text, moodNowText(e.value.moodNow!), reason: e.key);
        expect(shown.text, contains('${w.snapshot.happiness}'),
            reason: 'настроение то же, что в снимке');
      }
      expect(seen, greaterThan(0));
    });
  }

  testWidgets('режим «неделя»: строки настроения сейчас нет',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    await pumpWorldScreen(tester, const JobBoardScreen(),
        world: w, explain: explainFor(w));
    expect(
        find.byWidgetPredicate((Widget x) =>
            x.key is ValueKey<String> &&
            (x.key! as ValueKey<String>).value.startsWith('jobs:mood_now:')),
        findsNothing);
  });
}
