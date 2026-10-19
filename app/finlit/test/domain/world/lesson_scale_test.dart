import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Траты уроков в масштабе профиля баланса (finni 17.10): в режиме дней
/// оплата смены × `pay_scale` (mid 0,45), значит и трата урока × 0,45 вверх
/// до десятка — иначе наушники за 150 стоят больше смены (140). Числа в
/// текстах урока — `{coins:N}`, тот же масштаб.
///
/// Уронит: трата не масштабирована (урок дороже смены, текст «за 150», а
/// списано 70 — или наоборот); плейсхолдер `{coins:…}` дошёл до экрана.
WorldGame _afterShift(WorldConfig c, String job) {
  final WorldGame w = WorldGame(config: c);
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: 0, goal: 0));
  if (w.pendingEvent case final PendingEvent e) {
    ok(w.resolveEvent(
        e.choices.firstWhere((PendingEventChoice c) => c.available).id));
  }
  ok(w.completeJob(job, score: 0));
  return w;
}

void main() {
  for (final (String name, WorldConfig c, int spend, String situation)
      in <(String, WorldConfig, int, String)>[
    (
      'дни, профиль mid: 150 × 0,45 = 67,5 → 70',
      contentDayConfig,
      70,
      '70 монет вместо 90'
    ),
    ('«неделя»: как написано, 150', contentConfig, 150, '150 монет вместо 200'),
  ]) {
    test(name, () {
      final WorldGame w = _afterShift(c, 'consultant');
      final LessonOffer l = w.pendingLesson!;
      expect(l.situation, contains(situation));
      final LessonChoiceView buy =
          l.choices.firstWhere((LessonChoiceView v) => v.id == 'buy');
      expect(buy.label, 'Купить со скидкой за $spend монет');
      final WorldResult r = ok(w.resolveLesson('buy'));
      expect(r.coins, -spend);
      expect(r.reason, contains('Но $spend монет ушло'));
    });
  }

  test('плейсхолдер {coins:…} не доходит до текстов уроков', () {
    for (final WorldConfig c in <WorldConfig>[
      contentConfig,
      contentDayConfig
    ]) {
      for (final WorldLesson l in c.lessons) {
        final List<String> texts = <String>[
          l.title,
          l.situation,
          l.understood,
          for (final WorldLessonChoice ch in l.choices) ...<String>[
            ch.label,
            ch.finni
          ],
        ];
        for (final String t in texts) {
          // `{name}` — имя героя, его подставляет урок для экрана (BG-01,
          // hero_name_texts_test.dart); `{goal}`, `{need}`, `{pay}` — монеты
          // доли, их подставляет `lessonText` (NAS-5 A, lessons_test.dart).
          final String rest = <String>['{name}', '{goal}', '{need}', '{pay}']
              .fold(t, (String s, String p) => s.replaceAll(p, ''));
          expect(rest, isNot(contains('{')), reason: '${l.jobId}: $t');
        }
      }
    }
  });
}
