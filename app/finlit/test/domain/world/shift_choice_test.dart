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

/// Мини-решения внутри смены (finni 17.10): вопрос с 2 вариантами на смене.
///
/// Защищает: в сборке 28 вопросов, по 4 на каждую из 7 работ; вопрос на
/// карточке и в `completeJob` один и тот же (зерно — журнал и работа), путь
/// повторяется; вариант меняет оплату (× pay_x вверх до монеты), ⚡ (сверх
/// цены, не больше оставшегося) и 😊; чужой id — отказ без списаний; без
/// вопроса `choice` не учитывается; в «неделе» вопросов нет; доля ≈ chance.
/// Уронит: вопрос не выпадает или выпадает всегда; pay_x/energy не
/// применяются; вариант ищется во всех вопросах, а не в вопросе смены.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Сборка с днями, свой раздел `shift_choices`, везение выключено (оно
/// умножает ту же оплату и спутало бы числа).
WorldConfig _withChoices(Map<String, Object?> choices) {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  // Награды дней дают баффы настроения (DEN-32) — ответ на вопрос выдал бы
  // «Своё решение» и сдвинул 😊 той же смены; здесь проверяется сам ответ.
  eco['achievements_days'] = false;
  eco['day_cycle'] = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
    // Без объяснений экрана: строка ответа в `reason` (в сборке RC флаг
    // explain_ui включён — его случай проверяет отдельный тест ниже).
    'explain_ui': false,
    'shift_luck': <String, Object?>{'chance': 0, 'scenarios': <Object?>[]},
    'shift_choices': choices,
  };
  return worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  ));
}

Map<String, Object?> _q(String id, List<Map<String, Object?>> options) =>
    <String, Object?>{
      'id': id,
      'work': 'consultant',
      'question': 'Тестовый вопрос $id.',
      'options': options,
    };

final Map<String, Object?> _takeOrder = <String, Object?>{
  'chance': 1,
  'items': <Object?>[
    _q('test_extra', <Map<String, Object?>>[
      <String, Object?>{
        'id': 'take',
        'label': 'Взять заказ',
        'pay_x': 1.25,
        'energy': 1.5,
        'happiness': -1,
      },
      <String, Object?>{'id': 'one', 'label': 'Сначала этот'},
    ]),
  ],
};

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

WorldEntry _payout(WorldGame w) =>
    w.journal.lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout);

void main() {
  test('сборка: 28 вопросов, по 4 на каждую из 7 работ, ⚡ × energy_scale', () {
    final DayCycle dc = contentDayConfig.dayCycle;
    expect(dc.shiftChoiceChance, 0.5);
    expect(dc.shiftChoices, hasLength(28));
    final Set<String> jobs = <String>{
      for (final WorldJob j in contentDayConfig.jobs) j.id
    };
    expect(jobs, hasLength(7));
    for (final String job in jobs) {
      expect(
          dc.shiftChoices.where((ShiftChoice q) => q.work == job), hasLength(4),
          reason: job);
    }
    final ShiftChoice courier =
        dc.shiftChoices.firstWhere((ShiftChoice q) => q.id == 'courier_extra');
    expect(courier.option('take')!.payX, 1.25);
    expect(courier.option('take')!.energy, 3, reason: '1,5 × energy_scale 2');
  });

  // Уронит: парсер не читает effect_hint — подсказка-последствие не дойдёт
  // до кнопки варианта (finni 17.10: показываем до выбора).
  test('сборка: у каждого варианта есть effect_hint, без поля — null', () {
    for (final ShiftChoice q in contentDayConfig.dayCycle.shiftChoices) {
      for (final ShiftChoiceOption o in q.options) {
        expect(o.effectHint, isNotNull, reason: '${q.id}.${o.id}');
        expect(o.effectHint!.trim(), isNotEmpty, reason: '${q.id}.${o.id}');
      }
    }
    final ShiftChoice courier = contentDayConfig.dayCycle.shiftChoices
        .firstWhere((ShiftChoice q) => q.id == 'courier_extra');
    expect(courier.option('take')!.effectHint,
        'намного больше монет, устанешь намного сильнее');
    final ShiftChoice test =
        _withChoices(_takeOrder).dayCycle.shiftChoices.single;
    expect(test.option('take')!.effectHint, isNull);
  });

  test('«неделя»: вопросов нет', () {
    final WorldGame w = _living(contentConfig);
    expect(w.jobBoard.where((JobOffer o) => o.choice != null), isEmpty);
  });

  test('«взять заказ»: 340 × 1,25 = 425 монет, ⚡ +3, 😊 −1 к той же смене', () {
    final WorldConfig c = _withChoices(_takeOrder);
    final WorldGame plain = _living(c);
    final WorldGame chose = _living(c);
    final JobOffer o = chose.offer('consultant')!;
    expect(o.choice?.id, 'test_extra');
    final WorldResult r0 = plain.completeJob('consultant', score: 0);
    final WorldResult r1 =
        chose.completeJob('consultant', score: 0, choice: 'take');
    ok(r0);
    ok(r1);
    expect(r0.coins, 340, reason: 'профиль mid; без ответа — как без вопроса');
    expect(r1.coins, 425);
    expect(r1.reason, contains('Взять заказ: +85.'));
    expect(r1.energy - r0.energy, closeTo(-3, 1e-9));
    expect(r1.happiness - r0.happiness, -1);
    expect(_payout(chose).args['choice'], 'test_extra');
    expect(_payout(chose).args['choiceOption'], 'take');
    expect(_payout(chose).args['choicePay'], 85);
    expect(_payout(plain).args.containsKey('choice'), isFalse);
  });

  // Экран с explain_ui сам рисует строку ответа по args.choice (front3): в
  // reason её нет, иначе фраза читается дважды. Уронит: подпись варианта
  // снова в reason или пропали id в журнале.
  test('explain_ui: ответа нет в reason, id вопроса и варианта — в журнале',
      () {
    final Map<String, Object?> eco =
        jsonDecode(_read('economy.json')) as Map<String, Object?>;
    eco['day_cycle'] = <String, Object?>{
      ...(eco['day_cycle']! as Map<String, Object?>),
      'shift_luck': <String, Object?>{'chance': 0, 'scenarios': <Object?>[]},
      'shift_choices': _takeOrder,
      'explain_ui': true,
    };
    final WorldGame w = _living(worldConfigFromContent(WorldContent.parse(
      economy: jsonEncode(eco),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
    )));
    final WorldResult r = w.completeJob('consultant', score: 0, choice: 'take');
    expect(r.coins, 425);
    expect(r.reason, isNot(contains('Взять заказ')));
    expect(_payout(w).args['choice'], 'test_extra');
    expect(_payout(w).args['choiceOption'], 'take');
  });

  test('⚡ варианта — не больше, чем осталось после смены', () {
    final WorldConfig c = _withChoices(<String, Object?>{
      'chance': 1,
      'items': <Object?>[
        _q('test_heavy', <Map<String, Object?>>[
          <String, Object?>{'id': 'heavy', 'label': 'Тяжело', 'energy': 50},
          <String, Object?>{'id': 'light', 'label': 'Легко'},
        ]),
      ],
    });
    final WorldGame w = _living(c);
    final double before = w.snapshot.energy;
    final WorldResult r =
        w.completeJob('consultant', score: 0, choice: 'heavy');
    ok(r);
    expect(-r.energy, closeTo(before, 1e-9),
        reason: 'всё, что было, не больше');
  });

  test('чужой id — отказ job.choice_unknown, ничего не списано', () {
    final WorldGame w = _living(_withChoices(_takeOrder));
    final int len = w.journal.length;
    final int free = w.snapshot.free;
    final double energy = w.snapshot.energy;
    final WorldResult r = w.completeJob('consultant', score: 0, choice: 'nope');
    expect(r.ok, isFalse);
    expect(r.reasonCode, 'job.choice_unknown');
    expect(w.journal.length, len);
    expect(w.snapshot.free, free);
    expect(w.snapshot.energy, energy);
  });

  // Для front3: вопрос зависит от журнала. Ответ на вопрос, который уже
  // сменился, не применяется к новому вопросу.
  test('журнал вырос и вопрос сменился — старый вариант отклонён', () {
    final WorldGame w = _living(_withChoices(<String, Object?>{
      'chance': 1,
      'items': <Object?>[
        _q('test_a', <Map<String, Object?>>[
          <String, Object?>{'id': 'a1', 'label': 'А1', 'pay_x': 2},
          <String, Object?>{'id': 'a2', 'label': 'А2'},
        ]),
        _q('test_b', <Map<String, Object?>>[
          <String, Object?>{'id': 'b1', 'label': 'Б1', 'pay_x': 2},
          <String, Object?>{'id': 'b2', 'label': 'Б2'},
        ]),
      ],
    }));
    final String first = w.offer('consultant')!.choice!.id;
    for (int i = 0; i < 40 && w.offer('consultant')!.choice!.id == first; i++) {
      ok(w.chooseGoal(i.isEven ? 'pet_fish' : 'pet_hamster'));
    }
    final ShiftChoice now = w.offer('consultant')!.choice!;
    expect(now.id, isNot(first), reason: 'за 40 записей вопрос сменился');
    final String stale = first == 'test_a' ? 'a1' : 'b1';
    final WorldResult r = w.completeJob('consultant', score: 0, choice: stale);
    expect(r.reasonCode, 'job.choice_unknown');
  });

  test('без вопроса choice не учитывается', () {
    final WorldGame w = _living(_withChoices(<String, Object?>{
      'chance': 0,
      'items': (_takeOrder['items']! as List<Object?>),
    }));
    expect(w.offer('consultant')!.choice, isNull);
    final WorldResult r = w.completeJob('consultant', score: 0, choice: 'take');
    ok(r);
    expect(r.coins, 340);
    expect(_payout(w).args.containsKey('choice'), isFalse);
  });

  test('тот же путь — те же вопросы; перезапуск — те же монеты', () {
    List<Object?> play() {
      final WorldGame w = _living(contentDayConfig);
      final List<Object?> asked = <Object?>[];
      for (int d = 0; d < 6; d++) {
        final JobOffer o = w.jobBoard.firstWhere((JobOffer j) => !j.blocked);
        final ShiftChoice? q = w.offer(o.jobId, variant: o.variant)!.choice;
        ok(w.completeJob(o.jobId,
            variant: o.variant, score: 0, choice: q?.options.first.id));
        asked.add(_payout(w).args['choice']);
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
      expect(r.snapshot.energy, w.snapshot.energy);
      return asked;
    }

    final List<Object?> a = play();
    expect(a.whereType<String>(), isNotEmpty, reason: 'вопросы были');
    expect(play(), a);
  });

  test('доля смен с вопросом ≈ 0,5 (200 смен)', () {
    int hit = 0;
    int all = 0;
    for (int k = 0; k < 40; k++) {
      final WorldGame w = _living(contentDayConfig);
      // Разные пути: k смен цели — k записей журнала.
      for (int i = 0; i < k; i++) {
        ok(w.chooseGoal(i.isEven ? 'pet_fish' : 'pet_hamster'));
      }
      for (int d = 0; d < 5; d++) {
        final JobOffer? o = w.jobBoard
            .where((JobOffer j) => !j.blocked)
            .cast<JobOffer?>()
            .firstWhere((_) => true, orElse: () => null);
        if (o != null) {
          all++;
          if (o.choice != null) hit++;
          ok(w.completeJob(o.jobId,
              variant: o.variant, score: 0, choice: o.choice?.options.last.id));
        }
        ok(w.sleep());
        if (w.pendingEvent case final PendingEvent e) {
          ok(w.resolveEvent(
              e.choices.firstWhere((PendingEventChoice c) => c.available).id));
        }
      }
    }
    expect(all, greaterThanOrEqualTo(150));
    expect(hit / all, inInclusiveRange(0.38, 0.62));
  });
}
