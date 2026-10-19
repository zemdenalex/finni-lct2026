import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Вариант события не обещает сон, которого не будет (режим дней).
///
/// Защищает: подпись варианта и ответ Финни говорят про сон, только если
/// выбор и правда заканчивает день. Было (путь ребёнка rc-7d, D4): утром при
/// 10 силах «Устали, а на доске выгодная смена» → «Лечь спать пораньше» →
/// «выспались!», а день шёл дальше: тот же день, те же дела. Уронит: такой
/// вариант вернулся в events.json (в любое событие, не только в это).
final RegExp _sleep = RegExp(
    r'(?<![А-Яа-яЁё])(спать|сп[ия]т|выспал[а-яё]*|лечь|ложит[а-яё]*|'
    r'л[её]г|легл[а-яё]*|сон|сна|уснул[а-яё]*)(?![А-Яа-яЁё])',
    caseSensitive: false);

void main() {
  test('каждый вариант каждого события: про сон — только если день кончился',
      () {
    WorldGame living() {
      final WorldGame w = contentDayWorld();
      ok(w.startWeek());
      ok(w.plan(needs: 300, wants: 300, goal: 0));
      return w;
    }

    int checked = 0;
    for (final ({String id, String title}) e in living().demoEvents) {
      final WorldGame probe = living();
      // Уже ждёт выбора (утреннее событие недели) — показывать не надо.
      if (probe.pendingEvent?.id != e.id) ok(probe.demoShowEvent(e.id));
      for (final PendingEventChoice c in probe.pendingEvent!.choices) {
        final WorldGame w = living();
        if (w.pendingEvent?.id != e.id) ok(w.demoShowEvent(e.id));
        final int day = w.snapshot.dayInWeek;
        final WorldResult r = w.resolveEvent(c.id);
        if (!r.ok) continue;
        final bool slept = w.snapshot.dayInWeek != day;
        if (!slept) {
          expect(c.label, isNot(matches(_sleep)), reason: '${e.id}.${c.id}');
          expect(r.reason, isNot(matches(_sleep)), reason: '${e.id}.${c.id}');
        }
        checked++;
      }
    }
    expect(checked, greaterThan(30), reason: 'проверены варианты событий');
  });
}
