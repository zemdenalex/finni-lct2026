import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart' show weekMode;

/// DEN-36 A (Денис 18.10): оплата и ⚡ смены — от настроения **на момент
/// смены**, в том числе испорченного событием до смены. Защищает: событие
/// снизило 😊 — та же смена тут же платит меньше и стоит больше ⚡, чем после
/// варианта без потерь; между 😊 20 и 80 оплата различается ≥ ±15 %, а ⚡ —
/// на ±1 целый; строка карточки ([JobOffer.moodNow]) совпадает с тем, что
/// заплатят; эффект самой смены (тип настроения) не влияет на её же оплату;
/// перезапуск из журнала даёт те же монеты и ⚡; без флага и в «неделе» —
/// как было. Уронит: оплата берётся от утра или начала недели (как C6/P7),
/// ⚡ дробится сотыми, флаг действует в «неделе». Почему не ловят прежние:
/// `mood_pay_daily_test` проверяет утро, а не середину дня.
const String _bad = 'test_bad_news';

Future<WorldGame> _world({bool live = true, bool week = false, int? start}) =>
    openWorldGame(
        read: (String p) async {
          final String s = await File(p).readAsString();
          if (p.endsWith('events.json')) {
            final Map<String, Object?> e =
                jsonDecode(s) as Map<String, Object?>;
            e['events'] = <Object?>[
              <String, Object?>{
                'id': _bad,
                'topic': 'planning',
                'building': 'home',
                'conditions': <String, Object?>{},
                'title': 'Плохая новость',
                'situation': 'Что-то пошло не так.',
                'options': <Object?>[
                  <String, Object?>{
                    'id': 'sad',
                    'label': 'Расстроиться',
                    'effects': <String, Object?>{'happiness': -40},
                    'finni': 'Грустно.',
                  },
                  <String, Object?>{
                    'id': 'fine',
                    'label': 'Не расстраиваться',
                    'effects': <String, Object?>{'happiness': 0},
                    'finni': 'Ничего.',
                  },
                ],
              },
            ];
            return jsonEncode(e);
          }
          if (!p.endsWith('economy.json')) return s;
          final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
          e['day_cycle'] = <String, Object?>{
            ...(e['day_cycle']! as Map<String, Object?>),
            'mood_pay_live': live,
            'shift_luck': <String, Object?>{
              ...((e['day_cycle']! as Map<String, Object?>)['shift_luck']!
                  as Map<String, Object?>),
              'chance': 0,
            },
          };
          if (start != null) {
            e['happiness'] = <String, Object?>{
              ...(e['happiness']! as Map<String, Object?>),
              'start': start,
            };
          }
          final String out = jsonEncode(e);
          return week ? weekMode(out) : out;
        },
        storage: MemoryStorage());

/// Неделя начата, план подтверждён, событие показано и решено [choice].
Future<WorldGame> _afterEvent(String choice,
    {bool live = true, bool week = false}) async {
  final WorldGame w = await _world(live: live, week: week);
  expect(w.startWeek().ok, isTrue);
  expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
  expect(w.pendingEvent?.id, _bad, reason: 'событие показано после плана');
  final WorldResult r = w.resolveEvent(choice);
  expect(r.ok, isTrue, reason: r.reason);
  return w;
}

void main() {
  test('сборка: флаг включён, шкалы в файле', () {
    final Map<String, Object?> e =
        jsonDecode(File('assets/content/world/economy.json').readAsStringSync())
            as Map<String, Object?>;
    final Map<String, Object?> dc = e['day_cycle']! as Map<String, Object?>;
    expect(dc['mood_pay_live'], isTrue);
    expect(dc['mood_live'], isA<Map<String, Object?>>());
  });

  test('событие испортило настроение — смена тут же платит меньше, ⚡ больше',
      () async {
    final WorldGame sad = await _afterEvent('sad');
    final WorldGame fine = await _afterEvent('fine');
    expect(sad.snapshot.happiness, lessThanOrEqualTo(30),
        reason: 'событие опустило настроение');
    expect(fine.snapshot.happiness, greaterThan(30));
    final JobOffer s = sad.offer('consultant')!;
    final JobOffer f = fine.offer('consultant')!;
    expect(s.pay, lessThan(f.pay));
    expect(s.energyCost, f.energyCost + 1, reason: 'ровно +1 ⚡, не сотые');
    // Строка карточки: монеты к обычной оплате — та же база у обоих.
    expect(s.moodNow!.payCoins, lessThan(0));
    expect(s.pay - s.moodNow!.payCoins, f.pay - f.moodNow!.payCoins);
    expect(s.moodNow!.energyDelta, 1);
    expect(s.moodNow!.mood, sad.snapshot.happiness);
    // Заплатили столько, сколько обещала карточка после события.
    final int before = sad.snapshot.available;
    final double e0 = sad.snapshot.energy;
    expect(sad.completeJob('consultant', score: 0).ok, isTrue);
    expect(sad.snapshot.available - before, s.pay);
    expect(e0 - sad.snapshot.energy, closeTo(s.energyCost, 1e-9));
  });

  test('между 😊 20 и 80: оплата ≥ ±15 %, ⚡ — ±1 целый', () async {
    // Старт недели сдвигает 😊 (возврат к 50), поэтому старт с запасом:
    // проверяется, что настроение дошло до 20 / 80 и дальше.
    final Map<int, JobOffer> at = <int, JobOffer>{};
    for (final (int mood, int start) in <(int, int)>[
      (20, 5),
      (50, 50),
      (80, 95)
    ]) {
      final WorldGame w = await _world(start: start);
      expect(w.startWeek().ok, isTrue);
      expect(
          w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
      expect(w.resolveEvent('fine').ok, isTrue);
      final int h = w.snapshot.happiness;
      expect(
          mood == 20
              ? h <= 20
              : mood == 80
                  ? h >= 80
                  : h == 50,
          isTrue,
          reason: 'настроение $h, нужно около $mood');
      at[mood] = w.offer('consultant')!;
    }
    final int mid = at[50]!.pay;
    expect(at[20]!.pay, lessThanOrEqualTo((mid * 0.85).floor() + 1));
    expect(at[80]!.pay, greaterThanOrEqualTo((mid * 1.15).floor()));
    expect(at[20]!.energyCost - at[50]!.energyCost, 1);
    expect(at[50]!.energyCost - at[80]!.energyCost, 1);
    expect(at[20]!.moodNow!.payPercent, lessThanOrEqualTo(-15));
    expect(at[80]!.moodNow!.payPercent, greaterThanOrEqualTo(15));
    expect(at[20]!.moodNow!.energyDelta, 1);
    expect(at[50]!.moodNow!.energyDelta, 0);
    expect(at[80]!.moodNow!.energyDelta, -1);
    expect(at[50]!.moodNow!.mood, 50);
    expect(at[20]!.moodNow!.mood, lessThanOrEqualTo(20));
  });

  // finni 18.10: пороги ⚡ 40 / 60 (при 30 / 70 игра их почти не достигала);
  // лицо Финни — своё, 30 / 70.
  test('пороги ⚡ сборки: 😊 ≤ 40 → +1, ≥ 60 → −1, между — 0', () async {
    final MoodLive live = (await _world()).config.dayCycle.moodLive;
    expect(live.energyDelta(40), 1);
    expect(live.energyDelta(41), 0);
    expect(live.energyDelta(59), 0);
    expect(live.energyDelta(60), -1);
    expect(live.energyDelta(0), 1);
    expect(live.energyDelta(100), -1);
  });

  test('тип настроения смены не меняет её собственную оплату', () async {
    final WorldGame w = await _afterEvent('fine');
    final JobOffer o = w.offer('cashier')!;
    final int before = w.snapshot.available;
    expect(w.completeJob('cashier', score: 0).ok, isTrue);
    expect(w.snapshot.available - before, o.pay,
        reason: 'нудная смена огорчает уже после оплаты');
  });

  test('перезапуск из журнала: те же монеты и ⚡', () async {
    final WorldGame w = await _afterEvent('sad');
    expect(w.completeJob('consultant', score: 0).ok, isTrue);
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.snapshot.available, w.snapshot.available);
    expect(r.snapshot.energy, w.snapshot.energy);
    expect(r.offer('consultant')!.pay, w.offer('consultant')!.pay);
  });

  test('без флага: событие посреди дня оплату не меняет', () async {
    final WorldGame sad = await _afterEvent('sad', live: false);
    final WorldGame fine = await _afterEvent('fine', live: false);
    expect(sad.offer('consultant')!.pay, fine.offer('consultant')!.pay);
    expect(sad.offer('consultant')!.moodNow, isNull);
  });

  test('режим «неделя»: флаг ничего не меняет', () async {
    final WorldGame w = await _world(week: true);
    expect(w.startWeek().ok, isTrue);
    expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
    for (final JobOffer o in w.jobBoard) {
      expect(o.moodNow, isNull, reason: o.jobId);
    }
  });
}
