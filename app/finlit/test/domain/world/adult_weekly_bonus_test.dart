import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart' show weekMode;

/// DEN-27, вариант A (рекомендованный, за флагом): бонус взрослого в режиме
/// дней — монеты раз в игровую неделю, когда взрослый зашёл в раздел и
/// подтвердил. Флаг и сумма — `economy.json → adult`.
/// Защищает: +N один раз за неделю из 7 дней; без подтверждения — 0; флаг
/// выключен — прежний отказ `parent.no_limit`. Уронит: бонус начисляется
/// дважды за неделю, не сбрасывается с новой неделей, идёт мимо журнала
/// (перезапуск даёт другие монеты) или включается без флага. Почему не
/// ловят прежние: `parent_bonus_test` проверяет вариант «+1 смена» в
/// недельном режиме, где монеты бонус не меняет вовсе.
Future<WorldGame> _world({bool on = true, int coins = 20, bool week = false}) =>
    openWorldGame(
        read: (String p) async {
          final String s = await File(p).readAsString();
          if (!p.endsWith('economy.json')) return s;
          final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
          final Map<String, Object?> adult =
              (e['adult'] as Map<String, Object?>?) ?? <String, Object?>{};
          e['adult'] = <String, Object?>{
            ...adult,
            'weekly_bonus': on,
            'weekly_bonus_coins': coins,
          };
          return week ? weekMode(jsonEncode(e)) : jsonEncode(e);
        },
        storage: MemoryStorage());

void _living(WorldGame w) {
  expect(w.startWeek().ok, isTrue);
  expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
  expect(w.phase, WeekPhase.living);
}

List<WorldEntry> _bonuses(WorldGame w) => w.journal
    .where((WorldEntry e) => e.kind == WorldLedgerKind.parentBonus)
    .toList();

void main() {
  test('флаг включён, взрослый не заходил — монет от бонуса нет', () async {
    final WorldGame w = await _world();
    expect(w.config.dayCycle.daysPerWeek, 7);
    WorldAutopilot(w).playWeeks(2);
    expect(_bonuses(w), isEmpty);
  });

  test('взрослый подтвердил — +20 в кошелёк одной записью с причиной',
      () async {
    final WorldGame w = await _world();
    _living(w);
    final int before = w.snapshot.free;
    final WorldResult r = w.parentExtraShift();
    expect(r.ok, isTrue, reason: r.reason);
    expect(r.reasonCode, 'parent.weekly_coins');
    expect(w.snapshot.free, before + 20);
    final List<WorldEntry> b = _bonuses(w);
    expect(b, hasLength(1));
    expect(b.single.free, 20);
    expect(b.single.args['coins'], 20);
    expect(b.single.args['reason'], isNotNull);
  });

  test('сумма — из economy.json, не из кода', () async {
    final WorldGame w = await _world(coins: 35);
    _living(w);
    final int before = w.snapshot.free;
    expect(w.parentExtraShift().ok, isTrue);
    expect(w.snapshot.free, before + 35);
  });

  test('повторный вход в ту же неделю — отказ, монеты те же', () async {
    final WorldGame w = await _world();
    _living(w);
    expect(w.parentExtraShift().ok, isTrue);
    final int after = w.snapshot.free;
    expect(w.canDo(WorldAction.parentBonus)?.code, 'parent.bonus.done');
    final WorldResult again = w.parentExtraShift();
    expect(again.ok, isFalse);
    expect(w.snapshot.free, after);
    expect(_bonuses(w), hasLength(1));
  });

  test('граница недели: дни 2–7 той же недели — отказ, новая неделя — снова',
      () async {
    final WorldGame w = await _world();
    _living(w);
    expect(w.parentExtraShift().ok, isTrue);
    final int week = w.snapshot.weekNo;
    // «Спать» в дни 1–6: та же неделя, бонус уже взят.
    for (int day = 1; day < 7; day++) {
      expect(w.sleep().ok, isTrue);
      expect(w.snapshot.weekNo, week);
      expect(w.canDo(WorldAction.parentBonus)?.code, 'parent.bonus.done',
          reason: 'день ${day + 1}');
    }
    // Автопилот доводит неделю до итогов и открывает следующую.
    final WorldAutopilot a = WorldAutopilot(w);
    while (w.snapshot.weekNo == week) {
      expect(a.step().result.ok, isTrue);
    }
    _livingNext(w);
    final int before = w.snapshot.free;
    expect(w.parentExtraShift().ok, isTrue);
    expect(w.snapshot.free, before + 20);
    expect(_bonuses(w), hasLength(2));
  });

  test('перезапуск из журнала: те же монеты, бонус недели взят', () async {
    final WorldGame w = await _world();
    _living(w);
    expect(w.parentExtraShift().ok, isTrue);
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.snapshot.free, w.snapshot.free);
    expect(r.canDo(WorldAction.parentBonus)?.code, 'parent.bonus.done');
  });

  test('флаг выключен — прежний отказ parent.no_limit, монет нет', () async {
    final WorldGame w = await _world(on: false);
    _living(w);
    final int before = w.snapshot.free;
    expect(w.canDo(WorldAction.parentBonus)?.code, 'parent.no_limit');
    expect(w.parentExtraShift().ok, isFalse);
    expect(w.snapshot.free, before);
    expect(_bonuses(w), isEmpty);
  });

  test('флаг выключен, запасная неделя — прежняя «+1 смена», монет нет',
      () async {
    final WorldGame w = await _world(on: false, week: true);
    _living(w);
    final int before = w.snapshot.free;
    final int limit = w.shiftsLimitThisWeek;
    final WorldResult r = w.parentExtraShift();
    expect(r.ok, isTrue, reason: r.reason);
    expect(r.reasonCode, parentBonusCode);
    expect(w.shiftsLimitThisWeek, limit + 1);
    expect(w.snapshot.free, before);
  });

  test('флаг включён в запасной неделе — монеты, лимит смен прежний', () async {
    final WorldGame w = await _world(week: true);
    _living(w);
    final int limit = w.shiftsLimitThisWeek;
    final int before = w.snapshot.free;
    expect(w.parentExtraShift().ok, isTrue);
    expect(w.snapshot.free, before + 20);
    expect(w.shiftsLimitThisWeek, limit);
  });

  test('сборка: флаг выключен по умолчанию, сумма 20', () {
    final Map<String, Object?> e =
        jsonDecode(File('assets/content/world/economy.json').readAsStringSync())
            as Map<String, Object?>;
    final Map<String, Object?> adult = e['adult']! as Map<String, Object?>;
    expect(adult['weekly_bonus'], isFalse);
    expect(adult['weekly_bonus_coins'], 20);
  });
}

/// Новая неделя открыта автопилотом (фаза плана) — план, и неделя идёт.
void _livingNext(WorldGame w) {
  if (w.phase == WeekPhase.planning) {
    expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
  }
  expect(w.phase, WeekPhase.living);
}
