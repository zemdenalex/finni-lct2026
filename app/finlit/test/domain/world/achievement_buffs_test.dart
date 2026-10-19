import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';

/// DEN-32 (Денис 18.10): награды дают баффы, цены от 100 без потолка.
/// Защищает: в сборке у наград дней есть эффекты, постоянный (+1 к пределу
/// ⚡) — ровно один; временный даёт +😊 сразу и ещё столько же каждое утро,
/// всего `days` дней, а потом перестаёт; постоянный поднимает предел ⚡ и
/// потолок сна (20 → 21), ⚡ выше нового предела не бывает; перезапуск из
/// журнала даёт то же; загрузчик не пускает бафф вне границ; декор от 100 до
/// 5000+. Уронит: бафф не применился или не кончился, предел вырос, а сон
/// не добирает до него (или наоборот — ⚡ выше предела), бафф считается
/// дважды после перезапуска. Почему не ловят прежние: `achievements_days_test`
/// проверяет, что награда выдаётся, а не что она даёт.
Map<String, Object?> _economy() =>
    jsonDecode(File('assets/content/world/economy.json').readAsStringSync())
        as Map<String, Object?>;

Future<WorldGame> _world({bool effects = true, bool alwaysChoice = false}) =>
    openWorldGame(
        read: (String p) async {
          final String s = await File(p).readAsString();
          if (!p.endsWith('economy.json')) return s;
          final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
          e['achievements_days'] = true;
          if (!effects) {
            for (final Object? a in e['achievements_days_items']! as List) {
              (a! as Map<String, Object?>).remove('effect');
            }
          }
          final Map<String, Object?> dc = <String, Object?>{
            ...(e['day_cycle']! as Map<String, Object?>),
            // Без ночного возврата 😊 и без везения — разница только в баффе.
            'mood_revert': 0,
          };
          dc['shift_luck'] = <String, Object?>{
            ...(dc['shift_luck']! as Map<String, Object?>),
            'chance': 0,
          };
          dc['shift_choices'] = <String, Object?>{
            ...(dc['shift_choices']! as Map<String, Object?>),
            'chance': alwaysChoice ? 1 : 0,
          };
          e['day_cycle'] = dc;
          return jsonEncode(e);
        },
        storage: MemoryStorage());

void _living(WorldGame w) {
  expect(w.startWeek().ok, isTrue);
  expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
}

int _earned(WorldGame w, String id) => w.journal
    .where((WorldEntry e) =>
        e.kind == WorldLedgerKind.achievementEarned && e.args['id'] == id)
    .length;

void main() {
  test('сборка: эффекты у наград дней, постоянный — один', () {
    final Map<String, Object?> e = _economy();
    final List<Map<String, Object?>> items =
        (e['achievements_days_items']! as List<Object?>)
            .cast<Map<String, Object?>>();
    final List<Map<String, Object?>> fx = <Map<String, Object?>>[
      for (final Map<String, Object?> i in items)
        if (i['effect'] case final Map<String, Object?> f) f,
    ];
    expect(fx.length, greaterThanOrEqualTo(4));
    expect(fx.where((Map<String, Object?> f) => f['type'] == 'energy_max'),
        hasLength(1),
        reason: 'предел ⚡ растёт на одну награду, не без конца');
    expect(
        fx.where((Map<String, Object?> f) => f['type'] == 'mood'), isNotEmpty);
  });

  test('цены декора: от 100, премиум до 5000 и выше', () {
    final List<int> prices = <int>[
      for (final Object? i in ((_economy()['decor']!
          as Map<String, Object?>)['items']! as List<Object?>))
        (i! as Map<String, Object?>)['price']! as int,
    ];
    expect(prices.reduce((int a, int b) => a < b ? a : b),
        greaterThanOrEqualTo(100));
    expect(prices.reduce((int a, int b) => a > b ? a : b),
        greaterThanOrEqualTo(5000));
    // Зеркало в коде совпадает с файлом (по умолчанию без файла — те же цены).
    for (final WorldItem i in const WorldConfig().decor) {
      expect(i.price, greaterThanOrEqualTo(100), reason: i.id);
    }
  });

  test('временный бафф: +😊 сразу и каждое утро, всего days дней', () async {
    final WorldGame on = await _world(alwaysChoice: true);
    final WorldGame off = await _world(alwaysChoice: true, effects: false);
    final MoodBuff b = on.config.achievements
        .singleWhere((AchievementDef d) => d.id == 'own_choice')
        .effect! as MoodBuff;
    for (final WorldGame w in <WorldGame>[on, off]) {
      _living(w);
      final ShiftChoice q = w.offer('cashier')!.choice!;
      expect(w.completeJob('cashier', score: 1, choice: q.options.first.id).ok,
          isTrue);
      expect(_earned(w, 'own_choice'), 1);
    }
    int gap() => on.snapshot.happiness - off.snapshot.happiness;
    expect(gap(), b.happiness, reason: 'сразу');
    for (int day = 2; day <= b.days + 2; day++) {
      expect(on.sleep().ok, isTrue);
      expect(off.sleep().ok, isTrue);
      final int want = b.happiness * (day <= b.days ? day : b.days);
      expect(gap(), want, reason: 'утро дня $day');
    }
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(on.toJson())) as List<Object?>,
        config: on.config);
    expect(r.snapshot.happiness, on.snapshot.happiness);
  });

  test('постоянный бафф: предел ⚡ и потолок сна 20 → 21', () async {
    final WorldGame on = await _world();
    final WorldGame off = await _world(effects: false);
    for (final WorldGame w in <WorldGame>[on, off]) {
      _living(w);
      expect(w.energyMaxNow, w.config.energyMax);
      // Семь утр: начало недели и шесть снов — награда «Семь дней».
      for (int i = 0; i < 6; i++) {
        expect(w.sleep().ok, isTrue);
      }
      expect(_earned(w, 'days_7'), 1);
    }
    expect(on.energyMaxNow, on.config.energyMax + 1);
    expect(off.energyMaxNow, off.config.energyMax);
    // Новая неделя: утро добирает до нового предела, не выше.
    for (final WorldGame w in <WorldGame>[on, off]) {
      expect(w.sleep().ok, isTrue, reason: 'итоги недели');
      expect(w.payBills().ok, isTrue);
      _living(w);
      expect(w.snapshot.energy, lessThanOrEqualTo(w.energyMaxNow + 1e-9));
    }
    expect(on.snapshot.energy, greaterThan(off.snapshot.energy));
    expect(on.snapshot.energy, closeTo(on.energyMaxNow, 1e-9),
        reason: 'неделю не тратили — сон добрал до 21');
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(on.toJson())) as List<Object?>,
        config: on.config);
    expect(r.energyMaxNow, on.energyMaxNow, reason: 'бафф не удвоился');
  });

  test('сон: потолок вырастает на бафф', () {
    const SleepRule s = SleepRule();
    expect(s.after(20), 20);
    expect(s.after(20, capBonus: 1), 21);
    expect(s.after(21, capBonus: 1), 21);
  });

  test('загрузчик: бафф вне границ — ошибка с путём', () {
    String with_(Map<String, Object?> fx) {
      final Map<String, Object?> e = _economy();
      ((e['achievements_days_items']! as List<Object?>).first!
          as Map<String, Object?>)['effect'] = fx;
      return jsonEncode(e);
    }

    String read(String f) => File('assets/content/world/$f').readAsStringSync();
    for (final Map<String, Object?> bad in <Map<String, Object?>>[
      <String, Object?>{'type': 'mood', 'happiness': 0, 'days': 2},
      <String, Object?>{'type': 'mood', 'happiness': 3, 'days': 9},
      <String, Object?>{'type': 'energy_max', 'value': 5},
      <String, Object?>{'type': 'coins', 'value': 1},
    ]) {
      expect(
          () => WorldContent.parse(
              economy: with_(bad),
              jobs: read('jobs.json'),
              events: read('events.json'),
              roomItems: read('room_items.json')),
          throwsA(isA<WorldContentError>()),
          reason: '$bad');
    }
  });
}
