import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart' show contentDayConfig, ok;

/// Сон по таблице Дениса (DEN-20 / DEN-26): после сна =
/// max(10, x + ⌈(20 − x)/5⌉), потолок 20. Защищает таблицу значений и то,
/// что мир берёт утро из неё (а не «до уровня + перенос»), когда в
/// `day_cycle` есть `sleep_rule`. Уронит: ⌈⌉ заменили на округление вниз,
/// потерян ε (15 → 17), пол не применился, мир игнорирует правило.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Мир дней с правилом сна; бонус сытости и голод выключены, чтобы утро
/// было ровно сном.
WorldGame _world() {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  eco['day_cycle'] = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
    'days_per_week': 7,
    'energy_max': 20,
    'sleep_rule': <String, Object?>{'floor': 10, 'cap': 20, 'fraction': 0.2},
    'satiety_full_bonus': 0,
    'satiety_hungry_malus': 0,
  };
  final WorldConfig cfg = worldConfigFromContent(
    WorldContent.parse(
      economy: jsonEncode(eco),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
    ),
  );
  return WorldGame(config: cfg);
}

void main() {
  // Таблица Дениса (чат 1866, подтверждено): 0–7 → 10; 8 → 11; 9 → 12;
  // 10–14 → +2; 15–19 → +1; 20 → 20. Плюс дробные (⚡ шагом 0,5).
  test('таблица сна x = 0…20: до → после', () {
    const SleepRule r = SleepRule();
    final Map<double, double> table = <double, double>{
      for (int x = 0; x <= 7; x++) x.toDouble(): 10,
      8: 11,
      9: 12,
      for (int x = 10; x <= 14; x++) x.toDouble(): x + 2.0,
      for (int x = 15; x <= 19; x++) x.toDouble(): x + 1.0,
      20: 20,
      9.5: 12.5,
      14.5: 16.5,
    };
    expect(table, hasLength(23));
    table.forEach((double before, double after) {
      expect(r.after(before), after, reason: 'до сна $before');
    });
  });

  test('сборка: сон по таблице включён, числа — в economy.json', () {
    final SleepRule? r = contentDayConfig.dayCycle.sleepRule;
    expect(r, isNotNull, reason: 'флаг включён по умолчанию (Денис 1866)');
    expect((r!.floor, r.cap, r.fraction), (10.0, 20.0, 0.2));
    expect(contentDayConfig.daysPerWeek, 7);
    expect(contentDayConfig.energyMax, 20);
  });

  test('мир дней: первое утро 10, утро после сна — по таблице, предел 20', () {
    final WorldGame w = _world();
    expect(w.config.energyMax, 20);
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    expect(w.snapshot.energy, 10, reason: 'первое утро: сон с нуля → 10');
    ok(w.sleep()); // день 1 → 2, вечером было 10
    expect(w.snapshot.dayInWeek, 2);
    expect(w.snapshot.energy, 12, reason: '10 → 12');
    ok(w.sleep()); // 12 → 12 + ⌈8/5⌉ = 14
    expect(w.snapshot.energy, 14);
    for (int d = 3; d < 7; d++) {
      ok(w.sleep()); // 14 → 16 → 17 → 18 → 19 (15–19: +1)
    }
    expect(w.snapshot.dayInWeek, 7);
    expect(w.snapshot.energy, 19, reason: 'копится, но всё медленнее');
  });
}
