import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Регрессия 18.10 (R-03, регрессионный прогон): у события всегда есть вариант,
/// который можно выбрать, пока день идёт. Иначе ребёнок видит «!», а все
/// кнопки погашены до утра (симулятор, 10 недель: «событие day_off: все
/// варианты погашены» у random и noeat, ⚡ 4, монеты есть). Окно: 😊 на начало
/// недели ниже 50 — досуг дороже 4 ⚡ (парк 4,19), а смена садовника
/// при 😊 > 40 стоит 4 ⚡, поэтому день не кончается.
/// Уронит: событие, где каждый вариант — досуг или трата ⚡ и монет.
/// Почему не ловит тест выше: он проверяет монеты при полной ⚡; симулятор
/// 21 дня до `day_off` (49-е по кругу) не доходит.
WorldGame _tiredWorld() {
  final WorldGame w = contentDayWorld();
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  // Неделя 1 сменами без отдыха: Финни грустный к началу недели 2.
  while (w.phase == WeekPhase.living) {
    w.completeJob('gardener', score: 0);
    if (w.phase == WeekPhase.living) ok(w.sleep());
  }
  ok(w.payBills());
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  final double park =
      -w.catalog.firstWhere((WorldCatalogItem i) => i.id == 'park').energy;
  // Смены, пока ⚡ ≥ 8; 😊 держим не ниже 60 (смена дешевле, день идёт).
  while (w.snapshot.energy >= 8) {
    while (w.snapshot.happiness < 60) {
      ok(w.demoShowEvent('found_wallet'));
      ok(w.resolveEvent('return'));
    }
    ok(w.completeJob('gardener', score: 0));
  }
  // Шаги по 1 ⚡, пока на парк не хватает.
  while (w.snapshot.energy + 1e-9 >= park) {
    ok(w.demoShowEvent('two_bakeries'));
    ok(w.resolveEvent('walk'));
  }
  if (w.snapshot.free > 0) ok(w.depositToGoal(w.snapshot.free));
  return w;
}

/// В каждом событии есть вариант, доступный без монет (`events.json → _note`:
/// «неправильных вариантов нет, есть последствия»). Иначе ребёнок без денег
/// не может закрыть событие — оно висит до конца недели. Найдено симулятором
/// 17.10: `headphones_broke` (оба варианта платные).
/// Уронит: новое событие только с платными вариантами.
void main() {
  test('каждое событие: без монет хотя бы один вариант доступен', () {
    final WorldConfig c = contentDayConfig;
    final List<String> stuck = <String>[];
    for (final WorldEventSpec e in c.events) {
      final WorldGame w = WorldGame(config: c);
      ok(w.startWeek());
      // Все карманные — в копилку: в НУЖНО, ХОЧУ и заработке по нулям.
      ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
      if (w.pendingEvent case final PendingEvent first) {
        ok(w.resolveEvent(first.choices
            .firstWhere((PendingEventChoice x) => x.available)
            .id));
      }
      expect(w.snapshot.want + w.snapshot.free + w.snapshot.need, 0);
      if (w.pendingEvent?.id == e.id) continue;
      ok(w.demoShowEvent(e.id));
      final PendingEvent p = w.pendingEvent!;
      if (!p.choices.any((PendingEventChoice x) => x.available)) {
        stuck.add(e.id);
      }
    }
    expect(stuck, isEmpty);
  });

  test('усталый Финни без монет: у каждого события есть доступный вариант', () {
    final WorldGame probe = _tiredWorld();
    final ResourceSnapshot s = probe.snapshot;
    // Окно, в котором досуг погашен, а день не кончился.
    expect(probe.phase, WeekPhase.living);
    expect(s.dayInWeek, 1, reason: 'день не кончился от нехватки ⚡');
    expect(s.energy + 1e-9, greaterThanOrEqualTo(probe.cheapestActionEnergy));
    expect(
        probe.canDo(WorldAction.leisure, id: 'park')?.code, 'leisure.energy');
    expect(s.want + s.free, 0, reason: 'монет в кармане нет');

    final List<String> grey = <String>[];
    for (final WorldEventSpec e in contentDayConfig.events) {
      final WorldGame w = _tiredWorld();
      ok(w.demoShowEvent(e.id));
      final PendingEvent p = w.pendingEvent!;
      if (!p.choices.any((PendingEventChoice c) => c.available)) {
        grey.add(
            '${e.id} (${p.choices.map((PendingEventChoice c) => '${c.id}: ${c.blockReason?.code}').join(', ')})');
      }
    }
    expect(grey, isEmpty, reason: 'все варианты погашены');
  });
}
