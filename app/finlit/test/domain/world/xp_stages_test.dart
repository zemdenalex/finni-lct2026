import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart' show weekMode;

/// C2 / DEN-35 вариант A за флагом `day_cycle.xp_stages`: ступень сложности
/// работы — от опыта (хорошие смены), порогами `xp_stage_min`; наибольшая
/// открытая выбирается сама. Защищает: порог → ступень (≥ на границе), флаг
/// выключен / режим «неделя» / курьер и программист — ступени нет, ступень
/// пишется в журнал смены и переживает перезапуск, ступень 3 достижима на
/// 6-й день при одной хорошей смене в день (две в день — только с едой и
/// перекусами; это меряет симулятор `tool/economy7_sim_test.dart`). Уронит: ступень
/// не зависит от опыта, `>` вместо `≥`, флаг не учитывается, пороги подняли
/// так, что третья ступень за неделю не открывается. Почему не ловят прежние:
/// ступеней у этих работ раньше не было.
Map<String, Object?> _eco() =>
    jsonDecode(File('assets/content/world/economy.json').readAsStringSync())
        as Map<String, Object?>;

List<int> get _shippedMin => <int>[
      for (final Object? v in (_eco()['day_cycle']!
          as Map<String, Object?>)['xp_stage_min']! as List<Object?>)
        v! as int,
    ];

Future<WorldGame> _world({bool on = true, bool week = false}) => openWorldGame(
    read: (String p) async {
      final String s = await File(p).readAsString();
      if (!p.endsWith('economy.json')) return s;
      final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
      e['day_cycle'] = <String, Object?>{
        ...(e['day_cycle']! as Map<String, Object?>),
        'xp_stages': on,
      };
      final String out = jsonEncode(e);
      return week ? weekMode(out) : out;
    },
    storage: MemoryStorage());

void _living(WorldGame w) {
  expect(w.startWeek().ok, isTrue);
  final int have = w.snapshot.unallocated;
  // На перекусы — часть в «Хочу», остальное в «Нужное».
  expect(w.plan(needs: have - 200, wants: 200, goal: 0).ok, isTrue);
}

/// Хорошая смена кассира; если сил не хватает — перекус или еда дома.
void _goodShift(WorldGame w) {
  for (int tries = 0; tries < 3; tries++) {
    if (w.canDo(WorldAction.job, id: 'cashier') == null) break;
    final WorldCatalogItem snack = w.catalog.firstWhere(
        (WorldCatalogItem i) => i.category == WorldCatalogCategory.snack);
    if (w.buy(snack.id).ok) continue;
    break;
  }
  final WorldResult r = w.completeJob('cashier', score: 1);
  expect(r.ok, isTrue, reason: r.reason);
}

/// День за днём по [perDay] хороших смен; ступень кассира перед первой
/// сменой дня → список по дням (1…7).
Future<List<int?>> _stageByDay(int perDay) async {
  final WorldGame w = await _world();
  _living(w);
  final List<int?> out = <int?>[];
  for (int day = 1; day <= 7; day++) {
    out.add(w.xpStage('cashier'));
    for (int k = 0; k < perDay; k++) {
      _goodShift(w);
    }
    if (day < 7) expect(w.sleep().ok, isTrue);
  }
  return out;
}

void main() {
  test('пороги сборки: с нуля, по возрастанию, три ступени', () {
    final List<int> m = _shippedMin;
    expect(m, hasLength(3));
    expect(m.first, 0);
    expect(m[1], greaterThan(m[0]));
    expect(m[2], greaterThan(m[1]));
    expect((_eco()['day_cycle']! as Map<String, Object?>)['xp_stages'], isTrue,
        reason: 'в сборке флаг включён (DEN-35 B, Денис 18.10)');
  });

  test('одна хорошая смена в день: ступень 3 не позже 6-го дня, не в 1-й',
      () async {
    final List<int?> s = await _stageByDay(1);
    expect(s.first, 1);
    expect(s.indexOf(3), inInclusiveRange(1, 5), reason: '$s');
    // Не убывает.
    for (int i = 1; i < s.length; i++) {
      expect(s[i]!, greaterThanOrEqualTo(s[i - 1]!), reason: '$s');
    }
  });

  test('порог — включительно: опыт = порогу ступени 2 открывает её', () async {
    final WorldGame w = await _world();
    _living(w);
    final int need = _shippedMin[1];
    int day = 1;
    while (w.snapshot.experience < need) {
      if (w.snapshot.experience == need - 1) {
        expect(w.xpStage('cashier'), 1);
      }
      _goodShift(w);
      if (w.snapshot.experience < need && day < 7) {
        expect(w.sleep().ok, isTrue);
        day++;
      }
    }
    expect(w.snapshot.experience, need);
    expect(w.xpStage('cashier'), 2);
  });

  test('ступень пишется в журнал смены и переживает перезапуск', () async {
    final WorldGame w = await _world();
    _living(w);
    _goodShift(w);
    final WorldEntry pay = w.journal
        .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout);
    expect(pay.args['stage'], 1, reason: 'ступень на начало смены');
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.xpStage('cashier'), w.xpStage('cashier'));
  });

  test('ступеней нет: флаг выключен, режим «неделя», курьер и программист',
      () async {
    final WorldGame off = await _world(on: false);
    _living(off);
    expect(off.xpStage('cashier'), isNull);
    _goodShift(off);
    final WorldEntry pay = off.journal
        .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout);
    expect(pay.args.containsKey('stage'), isFalse);

    final WorldGame week = await _world(week: true);
    _living(week);
    expect(week.xpStage('cashier'), isNull);

    final WorldGame on = await _world();
    _living(on);
    for (final String job in <String>['courier', 'programmer']) {
      expect(on.xpStage(job), isNull, reason: job);
    }
    for (final String job in <String>[
      'cashier',
      'consultant',
      'accountant',
      'gardener'
    ]) {
      expect(on.xpStage(job), 1, reason: job);
    }
  });
}
