import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart' show weekMode;

/// C7 / DEN-6 за флагом `achievements_days`: награды под 7 дней и работы.
/// С флагом в режиме дней к 12 наградам добавляются дневные: разные работы,
/// «Везёт!» (первое везение на смене), «Своё решение» (первый ответ на
/// вопрос в смене), прожитые дни, рабочие дни. Защищает: число наград (≥ 16),
/// известные метрики и уникальные id; каждая метрика считается из журнала и
/// даёт награду один раз; без флага и в «неделе» — прежние 12. Уронит:
/// метрика не считается (награда недостижима), считает не то (везение
/// невезения), награда пишется дважды, флаг не учитывается.
Future<WorldGame> _world(
        {bool on = true,
        bool week = false,
        bool alwaysGoodLuck = false,
        bool alwaysBadLuck = false,
        bool alwaysChoice = false}) =>
    openWorldGame(
        read: (String p) async {
          final String s = await File(p).readAsString();
          if (!p.endsWith('economy.json')) return s;
          final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
          e['achievements_days'] = on;
          final Map<String, Object?> dc = <String, Object?>{
            ...(e['day_cycle']! as Map<String, Object?>),
          };
          if (alwaysGoodLuck || alwaysBadLuck) {
            final Map<String, Object?> sl =
                dc['shift_luck']! as Map<String, Object?>;
            dc['shift_luck'] = <String, Object?>{
              ...sl,
              'chance': 1,
              'scenarios': <Object?>[
                for (final Object? x in sl['scenarios']! as List<Object?>)
                  if ((x! as Map<String, Object?>)['kind'] ==
                      (alwaysGoodLuck ? 'good' : 'bad'))
                    x,
              ],
            };
          } else {
            dc['shift_luck'] = <String, Object?>{
              ...(dc['shift_luck']! as Map<String, Object?>),
              'chance': 0,
            };
          }
          dc['shift_choices'] = <String, Object?>{
            ...(dc['shift_choices']! as Map<String, Object?>),
            'chance': alwaysChoice ? 1 : 0,
          };
          e['day_cycle'] = dc;
          final String out = jsonEncode(e);
          return week ? weekMode(out) : out;
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

int _progress(WorldGame w, String id) => w.snapshot.achievements
    .firstWhere((AchievementView a) => a.def.id == id)
    .progress;

void main() {
  test(
      'сборка: флаг включён (DEN-6 A); с флагом — не меньше 16 наград, id разные',
      () async {
    final Map<String, Object?> e =
        jsonDecode(File('assets/content/world/economy.json').readAsStringSync())
            as Map<String, Object?>;
    expect(e['achievements_days'], isTrue);
    final WorldGame off = await _world(on: false);
    expect(off.config.achievements, hasLength(12));
    final WorldGame on = await _world();
    expect(on.config.achievements.length, greaterThanOrEqualTo(16));
    expect(on.config.achievements.map((AchievementDef d) => d.id).toSet(),
        hasLength(on.config.achievements.length));
    final WorldGame week = await _world(week: true);
    expect(week.config.achievements, hasLength(12),
        reason: 'в «неделе» дневных наград нет');
  });

  test('разные работы, рабочие и прожитые дни — из журнала', () async {
    final WorldGame w = await _world();
    _living(w);
    expect(_progress(w, 'days_7'), 1, reason: 'первое утро');
    expect(w.completeJob('cashier', score: 1).ok, isTrue);
    expect(_progress(w, 'work_days_5'), 1);
    expect(w.sleep().ok, isTrue);
    expect(_progress(w, 'days_7'), 2);
    expect(_progress(w, 'work_days_5'), 1, reason: 'второй день без смены');
    expect(w.completeJob('consultant', score: 1).ok, isTrue);
    expect(_progress(w, 'work_days_5'), 2);
    expect(w.sleep().ok, isTrue);
    expect(_progress(w, 'jobs_3'), 2);
    expect(w.completeJob('cashier', score: 1).ok, isTrue);
    expect(_progress(w, 'jobs_3'), 2, reason: 'та же работа — не новая');
    expect(_earned(w, 'jobs_3'), 0);
    expect(w.sleep().ok, isTrue);
    expect(w.completeJob('gardener', score: 1).ok, isTrue);
    expect(_earned(w, 'jobs_3'), 1, reason: 'третья разная работа');
    expect(w.sleep().ok, isTrue);
    expect(w.completeJob('gardener', score: 1).ok, isTrue);
    expect(_earned(w, 'jobs_3'), 1, reason: 'один раз');

    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(_progress(r, 'jobs_3'), _progress(w, 'jobs_3'));
    expect(_progress(r, 'days_7'), _progress(w, 'days_7'));
    expect(_progress(r, 'work_days_5'), _progress(w, 'work_days_5'));
  });

  test('«Везёт!» — за удачу на смене, невезение не считается', () async {
    final WorldGame bad = await _world(alwaysBadLuck: true);
    _living(bad);
    expect(bad.completeJob('cashier', score: 1).ok, isTrue);
    expect(
        bad.journal
            .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout)
            .args['luck'],
        isNotNull,
        reason: 'невезение выпало');
    expect(_earned(bad, 'lucky'), 0, reason: 'невезение — не удача');

    final WorldGame w = await _world(alwaysGoodLuck: true);
    _living(w);
    expect(w.completeJob('cashier', score: 1).ok, isTrue);
    expect(_earned(w, 'lucky'), 1);
  });

  test('«Своё решение» — за ответ на вопрос в смене', () async {
    final WorldGame w = await _world(alwaysChoice: true);
    _living(w);
    expect(w.completeJob('cashier', score: 1).ok, isTrue, reason: 'без ответа');
    expect(_earned(w, 'own_choice'), 0);
    expect(w.sleep().ok, isTrue);
    final ShiftChoice q = w.offer('cashier')!.choice!;
    expect(w.completeJob('cashier', score: 1, choice: q.options.first.id).ok,
        isTrue);
    expect(_earned(w, 'own_choice'), 1);
  });
}
