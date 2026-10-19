import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart' show weekMode;

/// C6 / DEN-36, вариант A за флагом `day_cycle.mood_pay_daily`: в режиме
/// дней оплата и ⚡ смены — от настроения утра этого дня. Защищает: флаг
/// включён — после дня нудных смен утро ниже, и смена следующего дня платит
/// меньше и стоит дороже, чем без флага; в первый день разницы нет; флаг
/// выключен или режим «неделя» — как было (начало недели); перезапуск из
/// журнала даёт ту же оплату. Уронит: настроение утра не записалось в свёртку
/// (флаг ничего не меняет), берётся до ночного возврата, флаг действует в
/// «неделе» или включён в сборке. Почему не ловят прежние: тесты P7 считают
/// множитель от начала недели, а `mood_kind_test` — только сдвиг 😊.
Future<WorldGame> _world(
        {bool daily = true, bool week = false, double? revert}) =>
    openWorldGame(
        read: (String p) async {
          final String s = await File(p).readAsString();
          if (!p.endsWith('economy.json')) return s;
          final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
          e['day_cycle'] = <String, Object?>{
            ...(e['day_cycle']! as Map<String, Object?>),
            'mood_pay_daily': daily,
            // DEN-36 A (`mood_pay_live`) сильнее C6 — здесь проверяется C6.
            'mood_pay_live': false,
            if (revert != null) 'mood_revert': revert,
          };
          final String out = jsonEncode(e);
          return week ? weekMode(out) : out;
        },
        storage: MemoryStorage());

/// День нудной работы: садовник дважды с оценкой 0 (без опыта), затем сон.
Future<WorldGame> _afterDullDay(
    {bool daily = true, bool week = false, double? revert}) async {
  final WorldGame w = await _world(daily: daily, week: week, revert: revert);
  expect(w.startWeek().ok, isTrue);
  expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
  for (int i = 0; i < 2; i++) {
    final WorldResult r = w.completeJob('gardener', score: 0);
    expect(r.ok, isTrue, reason: r.reason);
  }
  return w;
}

void main() {
  test('первый день: оплата с флагом и без — одинаковая', () async {
    final WorldGame on = await _world();
    final WorldGame off = await _world(daily: false);
    for (final WorldGame w in <WorldGame>[on, off]) {
      expect(w.startWeek().ok, isTrue);
      expect(
          w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
    }
    expect(on.offer('consultant')!.pay, off.offer('consultant')!.pay);
    expect(on.offer('consultant')!.energyCost,
        off.offer('consultant')!.energyCost);
  });

  test('после дня нудных смен: утро ниже — платят меньше, ⚡ дороже', () async {
    final WorldGame on = await _afterDullDay();
    final WorldGame off = await _afterDullDay(daily: false);
    final int weekMood = on.snapshot.happiness;
    expect(on.sleep().ok, isTrue);
    expect(off.sleep().ok, isTrue);
    expect(on.snapshot.weekNo, off.snapshot.weekNo);
    expect(on.snapshot.happiness, off.snapshot.happiness,
        reason: 'настроение одинаковое — разница только в правиле оплаты');
    expect(on.snapshot.happiness, lessThan(50),
        reason: 'нудный день: $weekMood');
    expect(on.offer('consultant')!.pay, lessThan(off.offer('consultant')!.pay));
    expect(on.offer('consultant')!.energyCost,
        greaterThan(off.offer('consultant')!.energyCost));
  });

  // Уронит: берётся настроение вечера (до ночного возврата к 50): тогда
  // утро с возвратом и без возврата платило бы одинаково.
  test('утро — после ночного возврата: с возвратом платят больше, чем без',
      () async {
    final WorldGame back = await _afterDullDay(revert: 0.5);
    final WorldGame none = await _afterDullDay(revert: 0);
    expect(back.sleep().ok, isTrue);
    expect(none.sleep().ok, isTrue);
    expect(back.snapshot.happiness, greaterThan(none.snapshot.happiness));
    expect(back.offer('consultant')!.pay,
        greaterThan(none.offer('consultant')!.pay));
  });

  test('без флага: оплата следующего дня — как в первый (начало недели)',
      () async {
    final WorldGame w = await _world(daily: false);
    expect(w.startWeek().ok, isTrue);
    expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
    final int day1 = w.offer('consultant')!.pay;
    expect(w.completeJob('gardener', score: 0).ok, isTrue);
    expect(w.completeJob('gardener', score: 0).ok, isTrue);
    expect(w.sleep().ok, isTrue);
    expect(w.offer('consultant')!.pay, day1);
  });

  test('режим «неделя»: флаг ничего не меняет', () async {
    final WorldGame on = await _afterDullDay(week: true);
    final WorldGame off = await _afterDullDay(daily: false, week: true);
    expect(on.offer('consultant')!.pay, off.offer('consultant')!.pay);
  });

  test('перезапуск из журнала: та же оплата утра', () async {
    final WorldGame w = await _afterDullDay();
    expect(w.sleep().ok, isTrue);
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.offer('consultant')!.pay, w.offer('consultant')!.pay);
    expect(
        r.offer('consultant')!.energyCost, w.offer('consultant')!.energyCost);
  });

  test('сборка: флаг выключен', () {
    final Map<String, Object?> e =
        jsonDecode(File('assets/content/world/economy.json').readAsStringSync())
            as Map<String, Object?>;
    expect(
        (e['day_cycle']! as Map<String, Object?>)['mood_pay_daily'], isFalse);
  });
}
