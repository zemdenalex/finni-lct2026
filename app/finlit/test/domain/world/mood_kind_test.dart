import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Настроение по типу работы (Денис, DEN-18): интересная финансовая (+4),
/// нудная финансовая (−3), весёлая (+2), нудная (−6) — числа и строки в
/// `economy.json` → `day_cycle.mood_kinds`; утром 😊 проходит 20 % пути к 50
/// (`mood_revert`), поэтому настроение скачет, но не копится. Режим «неделя»
/// типа работы не знает.
///
/// Уронит: тип не применился (консультант = садовник), строка итога пропала,
/// утро не возвращает к нейтральному (снежный ком), «неделя» вдруг меняется.
WorldGame _living(WorldGame w) {
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: 0, goal: 0));
  return w;
}

void main() {
  test('консультант (интересная финансовая): +4, минус день; строка итога', () {
    final WorldGame w = _living(contentDayWorld());
    expect(w.snapshot.happiness, 50);
    final WorldResult r = w.completeJob('consultant', score: 0);
    expect(r.happiness, 4 - 1, reason: '+4 за тип, −1 за игровой день');
    expect(
        r.reason, contains('с ценами и монетами — интересно, настроение выше'));
  });

  test('садовник (нудная): −6, минус день', () {
    final WorldGame w = _living(contentDayWorld());
    final WorldResult r = w.completeJob('gardener', score: 0);
    expect(r.happiness, -6 - 1);
    expect(r.reason, contains('настроение заметно ниже'));
  });

  test('утро: 😊 на 20 % ближе к 50 — 53 → 52', () {
    final WorldGame w = _living(contentDayWorld());
    ok(w.completeJob('consultant', score: 0));
    expect(w.snapshot.happiness, 53);
    ok(w.sleep());
    expect(w.snapshot.hungry, isFalse, reason: 'без голода — только возврат');
    expect(w.snapshot.happiness, 52, reason: '(50 − 53) × 0,2 = −0,6 → −1');
  });

  test('режим «неделя»: тип работы не влияет', () {
    final WorldGame w = _living(contentWorld());
    final WorldResult r = w.completeJob('consultant', score: 0);
    expect(r.happiness, -1, reason: 'только игровой день, как сдано');
    expect(r.reason, isNot(contains('настроение выше')));
  });
}
