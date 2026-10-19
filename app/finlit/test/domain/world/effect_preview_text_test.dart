import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Подпись последствия варианта (`EffectPreview.text`) у переводов в копилку.
///
/// Защищает: монеты, которые уходят в копилку, не показаны тратой. Было
/// (путь ребёнка rc-7d, D8): «Не покупать — наушники есть (−60 💰 · +60 в
/// копилку)» — ребёнок читал «отдам 60 и ещё 60 отложу». Уронит: подпись
/// снова ставит минус переводу или теряет настоящую трату сверх перевода.
void main() {
  test('перевод в копилку — без минуса; трата сверх перевода — с минусом', () {
    expect(const EffectPreview(coins: -60, goal: 60).text, '+60 в копилку');
    expect(const EffectPreview(coins: -40, goal: 40, happiness: 1).text,
        '+40 в копилку · +1 😊');
    // Потрачено больше, чем легло в копилку: минус — только у разницы.
    expect(const EffectPreview(coins: -100, goal: 60).text,
        '−40 💰 · +60 в копилку');
    // Обычная трата и доход — как раньше.
    expect(
        const EffectPreview(coins: -70, happiness: 4).text, '−70 💰 · +4 😊');
    expect(const EffectPreview(coins: 30, goal: 20).text,
        '+30 💰 · +20 в копилку');
    expect(const EffectPreview(goal: -200).text, '−200 из копилки');
  });

  // Тот же случай на настоящих уроках из content/: у варианта, который
  // кладёт монеты в копилку, подпись без «−».
  test('уроки после смены из content: «отложить» без минуса', () {
    int checked = 0;
    for (final String job in <String>['consultant', 'cashier', 'gardener']) {
      for (int i = 0; i < 6 && checked < 2; i++) {
        final WorldGame w = contentDayWorld();
        ok(w.startWeek());
        ok(w.plan(needs: 0, wants: 300, goal: 0));
        if (w.pendingEvent case final PendingEvent e) {
          ok(w.resolveEvent(
              e.choices.firstWhere((PendingEventChoice c) => c.available).id));
        }
        for (int d = 0; d < i; d++) {
          w.depositToGoal(1);
        }
        if (!w.completeJob(job, score: 1).ok) continue;
        final LessonOffer? l = w.pendingLesson;
        if (l == null) continue;
        for (final LessonChoiceView c in l.choices) {
          if (c.preview.goal <= 0 || c.preview.coins >= 0) continue;
          expect(c.preview.text, isNot(contains('−${-c.preview.coins} 💰')),
              reason: '$job.${c.id}: ${c.preview.text}');
          expect(c.preview.text, contains('+${c.preview.goal} в копилку'));
          checked++;
        }
      }
    }
    expect(checked, greaterThan(0), reason: 'нашёлся урок с переводом');
  });
}
