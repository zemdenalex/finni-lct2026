import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/xp_twins.dart';

/// Т6 А + решение Дениса 19.10 («1 + 2»: словами И монетами): прибавка за
/// опыт на карточке смены (доска) и в условиях смены (экран смены) — без
/// процентов: «за опыт оплата больше на пятую часть (+28 монет)».
///
/// Защищает: на детском экране нет «%» и «процент» у опыта (и вслух тоже);
/// число монет в строке равно тому, на сколько больше **реально начислили**
/// за смену из-за опыта (миры-близнецы `xp_twins.dart`, ожидание — из
/// начисления, не из формулы).
/// Уронит: вернули «опыт +N %», монеты посчитаны с другим округлением
/// (вниз, до десятка) или без настроения, строка без слов.
/// Почему не ловят прежние: `job_board_screen_test` сверял «опыт +N %»
/// с `experiencePercent`, то есть экран с полем, а не с начислением.
/// Итог смены (`job:result:*`) процентов не показывал и не меняется: там
/// «Опыт +1».

/// Слова доли: одна из форм решения 19.10.
final RegExp xpWords = RegExp(r'^за опыт оплата '
    r'(чуть больше'
    r'|больше (примерно )?на (десятую часть|пятую часть|четверть|треть)'
    r'|(примерно )?(в полтора раза|вдвое) больше)'
    r' \(\+(\d+) (монета|монеты|монет)\)$');

final RegExp percent = RegExp(r'%|процент');

String picText(WidgetTester tester, String key) => tester
    .widget<PicText>(find.descendant(
        of: find.byKey(ValueKey<String>(key)), matching: find.byType(PicText)))
    .text;

void main() {
  for (final Size size in const <Size>[portrait, landscape]) {
    testWidgets(
        'доска: прибавка за опыт словами и монетами, монеты = начислению · '
        '${size.width.toInt()}×${size.height.toInt()}',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final (WorldGame a, WorldGame b) = twins(1.2, 2);
      await pumpWorldScreen(tester, const JobBoardScreen(),
          world: a, size: size, textScale: 1.3);
      expect(tester.takeException(), isNull);
      // Карточки, которые видно и можно взять сейчас.
      final List<String> shown = <String>[
        for (final JobOffer o in a.jobBoard)
          if (o.variant == null &&
              o.blockReason == null &&
              find
                  .byKey(ValueKey<String>('jobs:exp:${o.jobId}'))
                  .evaluate()
                  .isNotEmpty)
            o.jobId,
      ];
      expect(shown, isNotEmpty);
      expect(find.bySemanticsLabel(RegExp('опыт.*(%|процент)')), findsNothing,
          reason: 'вслух — тоже без процентов');
      h.dispose();
      int checked = 0;
      for (final String id in shown) {
        if (a.canDo(WorldAction.job, id: id) != null) continue;
        // Строка — заново перед сменой: прошлая смена сдвинула настроение,
        // а с ним оплату (mood_pay_live).
        await pumpWorldScreen(tester, const JobBoardScreen(),
            world: a, size: size, textScale: 1.3);
        final Finder line = find.byKey(ValueKey<String>('jobs:exp:$id'));
        if (line.evaluate().isEmpty) continue;
        final String t = picText(tester, 'jobs:exp:$id');
        expect(t, isNot(matches(percent)), reason: '$id: $t');
        expect(t, matches(xpWords), reason: '$id: $t');
        final int coins = creditedXpCoins(a, b, id);
        expect(coins, greaterThan(0), reason: id);
        expect(t, endsWith('(+$coins ${coinsNom(coins)})'), reason: '$id: $t');
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  }

  // night4 #2 (кадры 0.1.2+3): после хорошей смены у консультанта было
  // «за опыт прибавки пока нет», у кассира «+1 монета», на 2-й день наоборот —
  // оклады разные, доля опыта одна, округление до монеты даёт 0 или 1.
  // Правило одно (доска = экран смены): надбавка ≥1 монеты — строка
  // «(+N монет)», 0 — строки нет. Уронит: доска снова пишет «пока нет» при
  // нуле или строка не совпадает с начислением.
  testWidgets(
      'доска: строка опыта есть ровно тогда, когда опыт реально прибавил '
      'монеты (сборка ×1,01, разные оклады)', (WidgetTester tester) async {
    final (WorldGame a, WorldGame b) = twins(1.01, 1);
    final List<String> ids = <String>[
      for (final JobOffer o in a.jobBoard)
        if (o.variant == null && o.blockReason == null) o.jobId,
    ];
    int zero = 0, plus = 0;
    final List<String> seen = <String>[];
    // Несколько уровней опыта: на каждом — по кругу все открытые работы.
    for (int level = 1; level <= 3 && (zero == 0 || plus == 0); level++) {
      if (level > 1) goodShift(a, b);
      for (final String id in ids) {
        if (!readyFor(a, b, id)) continue;
        await pumpWorldScreen(tester, const JobBoardScreen(), world: a);
        expect(tester.takeException(), isNull);
        final Finder line = find.byKey(ValueKey<String>('jobs:exp:$id'));
        final bool shown = line.evaluate().isNotEmpty;
        final String? t = shown ? picText(tester, 'jobs:exp:$id') : null;
        final int coins = creditedXpCoins(a, b, id);
        seen.add('$id:$coins');
        if (coins > 0) {
          plus++;
          expect(t, isNotNull, reason: '$id: +$coins, а строки нет');
          expect(t, endsWith('(+$coins ${coinsNom(coins)})'),
              reason: '$id: $t');
        } else {
          zero++;
          expect(shown, isFalse,
              reason: '$id: опыт не прибавил, а строка «$t»');
        }
      }
    }
    expect(zero, greaterThan(0),
        reason: 'нет работы с нулём — не проверено: $seen');
    expect(plus, greaterThan(0),
        reason: 'нет работы с +N — не проверено: $seen');
  });

  testWidgets('экран смены: условия без процентов, монеты = начислению',
      (WidgetTester tester) async {
    final (WorldGame a, WorldGame b) = twins(1.2, 3);
    if (a.canDo(WorldAction.job, id: 'consultant') != null) {
      both(<WorldGame>[a, b], (WorldGame w) => w.sleep());
    }
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('consultant')),
        world: a, textScale: 1.3);
    expect(tester.takeException(), isNull);
    final String terms = tester
        .widget<PicText>(find.byKey(const ValueKey<String>('job:offer:terms')))
        .text;
    expect(terms, isNot(matches(percent)), reason: terms);
    final int coins = creditedXpCoins(a, b, 'consultant');
    expect(coins, greaterThan(0));
    expect(terms, contains('за опыт оплата '), reason: terms);
    expect(terms, contains('(+$coins ${coinsNom(coins)})'), reason: terms);
  });
}
