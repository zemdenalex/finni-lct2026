import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Везение на смене (Денис, DEN-23) и события каждое утро (до одного в день).
///
/// Защищает: в сборке у каждой из 7 работ 5 сценариев;
/// сценарий меняет оплату (× pay_x вверх до монеты) и возвращает ⚡; выбор
/// детерминирован номером записи журнала (тот же путь → тот же сценарий,
/// перезапуск — тот же итог); доля смен со сценарием ≈ chance; в режиме дней
/// событие приходит утром, не больше одного в день.
/// Уронит: сценарий не применяется или применяется к чужой работе; зерно от
/// времени (недетерминированно); события только в начале недели.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldConfig _withLuck(Map<String, Object?> luck,
    {Map<String, Object?> day = const <String, Object?>{}}) {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  eco['day_cycle'] = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
    // Без объяснений экрана: строка везения в `reason` (в сборке флаг
    // explain_ui включён — его случай проверяет отдельный тест через [day]).
    'explain_ui': false,
    'shift_luck': luck,
    ...day,
  };
  return worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  ));
}

WorldGame _living(WorldConfig c) {
  final WorldGame w = WorldGame(config: c);
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: 0, goal: 0));
  if (w.pendingEvent case final PendingEvent e) {
    ok(w.resolveEvent(
        e.choices.firstWhere((PendingEventChoice c) => c.available).id));
  }
  return w;
}

void main() {
  test('сборка: 7 работ × 5 сценариев (3 удачных, 2 неудачных)', () {
    final DayCycle dc = contentDayConfig.dayCycle;
    expect(dc.luckChance, 0.35);
    expect(dc.luck, hasLength(35));
    for (final String job in <String>{
      for (final ShiftLuck l in dc.luck) l.job
    }) {
      final List<ShiftLuck> mine =
          dc.luck.where((ShiftLuck l) => l.job == job).toList();
      expect(mine, hasLength(5), reason: job);
      expect(mine.where((ShiftLuck l) => l.good), hasLength(3), reason: job);
    }
  });

  test('сценарий: оплата × 1,1 вверх до монеты, ⚡ назад, строка в итоге', () {
    final WorldConfig c = _withLuck(<String, Object?>{
      'chance': 1,
      'scenarios': <Object?>[
        <String, Object?>{
          'id': 'test_good',
          'work': 'consultant',
          'kind': 'good',
          'pay_x': 1.1,
          'energy_back': 1,
          'text': 'Тестовая удача.',
        },
      ],
    });
    final WorldGame w = _living(c);
    final JobOffer o = w.offer('consultant')!;
    final double before = w.snapshot.energy;
    final WorldResult r = w.completeJob('consultant', score: 0);
    expect(r.coins, 154, reason: '140 (профиль mid) × 1,1');
    expect(r.reason, contains('Тестовая удача. +14.'));
    expect(before - w.snapshot.energy, closeTo(o.energyCost - 2, 1e-9),
        reason: 'energy_back 1 × energy_scale 2');
    final WorldEntry pay = w.journal
        .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout);
    expect(pay.args['luck'], 'test_good');
    expect(pay.args['luckPay'], 14);
  });

  // Экран с explain_ui сам рисует строку везения по args.luck (front3):
  // в reason её нет, иначе фраза читается дважды. Уронит: текст снова
  // дописан в reason или пропал id в журнале.
  test('explain_ui: строки везения нет в reason, id — в журнале', () {
    final WorldConfig c = _withLuck(<String, Object?>{
      'chance': 1,
      'scenarios': <Object?>[
        <String, Object?>{
          'id': 'test_good',
          'work': 'consultant',
          'kind': 'good',
          'pay_x': 1.1,
          'text': 'Тестовая удача.',
        },
      ],
    }, day: <String, Object?>{
      'explain_ui': true
    });
    final WorldGame w = _living(c);
    final WorldResult r = w.completeJob('consultant', score: 0);
    expect(r.coins, 154);
    expect(r.reason, isNot(contains('Тестовая удача')));
    expect(
        w.journal
            .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout)
            .args['luck'],
        'test_good');
  });

  test(
      'детерминировано: тот же путь — те же сценарии; перезапуск — те же монеты',
      () {
    List<Object?> play() {
      final WorldGame w = _living(contentDayConfig);
      final List<Object?> lucks = <Object?>[];
      for (int d = 0; d < 6; d++) {
        final JobOffer o = w.jobBoard.firstWhere((JobOffer j) => !j.blocked);
        ok(w.completeJob(o.jobId, variant: o.variant, score: 0));
        lucks.add(w.journal
            .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout)
            .args['luck']);
        ok(w.sleep());
        if (w.pendingEvent case final PendingEvent e) {
          ok(w.resolveEvent(
              e.choices.firstWhere((PendingEventChoice c) => c.available).id));
        }
      }
      final WorldGame r = WorldGame.fromJson(
          jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
          config: w.config);
      expect(r.snapshot.free, w.snapshot.free);
      return lucks;
    }

    expect(play(), play());
  });

  test('доля смен со сценарием ≈ 0,35 (200 смен)', () {
    int hit = 0;
    int all = 0;
    for (int k = 0; k < 40; k++) {
      final WorldGame w = _living(contentDayConfig);
      // Разные пути: k смен цели — k записей журнала (повторное «погладить»
      // записи не пишет, и все миры совпадали бы).
      for (int i = 0; i < k; i++) {
        ok(w.chooseGoal(i.isEven ? 'pet_fish' : 'pet_hamster'));
      }
      expect(w.journal.length, greaterThan(k));
      for (int d = 0; d < 5; d++) {
        final JobOffer? o = w.jobBoard
            .where((JobOffer j) => !j.blocked)
            .cast<JobOffer?>()
            .firstWhere((_) => true, orElse: () => null);
        if (o != null) {
          ok(w.completeJob(o.jobId, variant: o.variant, score: 0));
          all++;
          if (w.journal
                  .lastWhere(
                      (WorldEntry e) => e.kind == WorldLedgerKind.jobPayout)
                  .args['luck'] !=
              null) {
            hit++;
          }
        }
        ok(w.sleep());
        if (w.pendingEvent case final PendingEvent e) {
          ok(w.resolveEvent(
              e.choices.firstWhere((PendingEventChoice c) => c.available).id));
        }
      }
    }
    expect(all, greaterThanOrEqualTo(150));
    expect(hit / all, inInclusiveRange(0.25, 0.45));
  });

  test('события: 45 в сборке, утром — новое, не больше одного в день', () {
    expect(contentDayConfig.events, hasLength(52));
    final WorldGame w = _living(contentDayConfig);
    int shown = 0;
    for (int d = 0; d < 6; d++) {
      ok(w.sleep());
      final int today = w.journal
          .where((WorldEntry e) =>
              e.kind == WorldLedgerKind.eventShown &&
              e.weekNo == w.snapshot.weekNo)
          .length;
      if (w.pendingEvent case final PendingEvent e) {
        shown++;
        ok(w.resolveEvent(
            e.choices.firstWhere((PendingEventChoice c) => c.available).id));
        expect(w.pendingEvent, isNull, reason: 'одно в день');
      }
      expect(today, lessThanOrEqualTo(d + 2), reason: 'не больше дня + начало');
    }
    expect(shown, greaterThanOrEqualTo(3), reason: 'утренние события идут');
  });
}
