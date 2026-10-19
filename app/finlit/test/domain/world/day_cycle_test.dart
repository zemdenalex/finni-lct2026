import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart' show LedgerKind;
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// День по энергии (решения Дениса D1, D2 и D7, 15.10): неделя делится на дни,
/// у дня своя ⚡ от сна «до уровня», рядом отдельная шкала сытости.
///
/// Защищает:
/// - «Спать» не в последний день недели заканчивает день, а не неделю;
/// - утро даёт уровень сна плюс ограниченный перенос остатка;
/// - еда наполняет сытость, дела и ночь её тратят, голод отнимает ⚡ и 😊;
/// - перезапуск из журнала даёт тот же день и ту же сытость;
/// - флаг `day_cycle.days_per_week = 1` возвращает прежнюю неделю.
/// Уронит: день кончается неделей (`sleep` по-старому), сытость только в
/// памяти, или флаг перестал выключать дни.
void main() {
  WorldConfig configWith(Map<String, Object?> dayCycle,
      {int? sleepCarryNextWeek}) {
    final Map<String, Object?> eco = jsonDecode(
            File('${WorldContentLoader.base}/economy.json').readAsStringSync())
        as Map<String, Object?>;
    if (sleepCarryNextWeek != null) {
      final Map<String, Object?> en = eco['energy']! as Map<String, Object?>;
      en['sleep'] = <String, Object?>{
        ...en['sleep']! as Map<String, Object?>,
        'carry_next_week': sleepCarryNextWeek,
      };
    }
    eco['day_cycle'] = <String, Object?>{
      ...(eco['day_cycle'] as Map<String, Object?>? ?? <String, Object?>{}),
      ...dayCycle,
    }..removeWhere((String k, Object? v) => v == null);
    String read(String f) =>
        File('${WorldContentLoader.base}/$f').readAsStringSync();
    return worldConfigFromContent(WorldContent.parse(
        economy: jsonEncode(eco),
        jobs: read('jobs.json'),
        events: read('events.json')));
  }

  /// Числа сборки как есть: `day_cycle` включён (харнесс тестов экранов держит
  /// режим «неделя», поэтому здесь свой конфиг из тех же файлов).
  final WorldConfig shipped = configWith(const <String, Object?>{});

  /// Прежний сон «до уровня + перенос» (3 дня, ⚡ без масштаба): путь мира,
  /// когда в `day_cycle` нет `sleep_rule`. Тесты этого пути держат его числа
  /// сами, а не берут из сборки (там с 17.10 — 7 дней и сон по таблице).
  const Map<String, Object?> legacy = <String, Object?>{
    'days_per_week': 3,
    'sleep_rule': null,
    'energy_max': null,
    'energy_scale': null,
    'meals_per_week': null,
    'max_shifts_per_week': null,
    'max_shifts_per_job_per_week': null,
    'max_events_per_day': null,
    'satiety_full_bonus': 1,
    'satiety_hungry_malus': 1,
    'satiety_meal_per_energy': 15,
    'shop_energy': 1,
    'rest_energy': 1,
  };
  final WorldConfig legacy3 = configWith(legacy);

  /// Мир, где неделя началась и план подтверждён: можно действовать.
  WorldGame living(WorldConfig c) {
    final WorldGame w = WorldGame(config: c);
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    return w;
  }

  test('по умолчанию день включён: в неделе больше одного дня', () {
    expect(shipped.daysPerWeek, greaterThan(1));
    final WorldGame w = living(shipped);
    expect(w.snapshot.dayInWeek, 1);
    expect(w.snapshot.daysPerWeek, shipped.daysPerWeek);
    expect(w.snapshot.satiety, shipped.satietyStart);
    expect(w.snapshot.hungry, isFalse);
    expect(w.snapshot.full, shipped.satietyStart >= shipped.dayCycle.fullAt);
  });

  test('«Спать» в первый день — новое утро той же недели, не итоги', () {
    final WorldGame w = living(shipped);
    final int week = w.snapshot.weekNo;
    final WorldResult r = w.sleep();
    expect(r.ok, isTrue);
    expect(r.reasonCode, 'day.next');
    expect(w.phase, WeekPhase.living, reason: 'неделя идёт дальше');
    expect(w.snapshot.weekNo, week);
    expect(w.snapshot.dayInWeek, 2);
  });

  test('утро: уровень сна + перенос остатка не больше предела', () {
    final WorldConfig c = configWith(<String, Object?>{
      ...legacy,
      'sleep_level': 4,
      'carry_max': 1,
      'satiety_full_bonus': 0,
      'satiety_hungry_malus': 0,
    });
    final WorldGame w = living(c);
    // Неделя началась с полной ⚡: остаток больше предела переноса.
    expect(w.snapshot.energy, greaterThan(1));
    ok(w.sleep());
    expect(w.snapshot.energy, closeTo(4 + 1, 1e-9),
        reason: 'сон «до уровня» 4 и перенос не больше 1');
  });

  test('сытость: еда поднимает, дела и ночь тратят, голод — −⚡ и −😊', () {
    final WorldConfig c = configWith(<String, Object?>{
      ...legacy,
      'satiety_start': 30,
      'satiety_per_action': 10,
      'satiety_night': 20,
      'satiety_hungry_at': 25,
      'satiety_hungry_malus': 1,
      'satiety_hungry_happiness': -2,
      'satiety_full_bonus': 0,
      'sleep_level': 4,
      'carry_max': 0,
      'home_meal_daily': false,
    });
    final WorldGame w = living(c);
    expect(w.snapshot.satiety, 30);
    ok(w.leisure('park'));
    expect(w.snapshot.satiety, 20, reason: 'дело тратит сытость');
    final int happy = w.snapshot.happiness;
    ok(w.sleep());
    expect(w.snapshot.satiety, 0, reason: 'ночь тратит сытость, не ниже 0');
    expect(w.snapshot.hungry, isTrue, reason: 'признак для экрана');
    expect(w.snapshot.satietyHungryAt, c.dayCycle.hungryAt);
    expect(w.snapshot.satietyFullAt, c.dayCycle.fullAt);
    expect(w.snapshot.energy, closeTo(4 - 1, 1e-9), reason: 'голод: −1 ⚡');
    expect(w.snapshot.happiness, lessThan(happy), reason: 'голод: −😊');
    final int before = w.snapshot.satiety!;
    final WorldResult meal = w.eat(c.foods.first.id);
    expect(meal.ok, isTrue);
    expect(w.snapshot.satiety, greaterThan(before), reason: 'еда насыщает');
  });

  // Защищает: день без своей еды Финни ест дома (как обещает магазин:
  // «Приёмы, которые ты не выберешь сам, Финни съест дома») — сданный
  // демо-путь не голодает к утру 3-го дня без видимой причины; счёт недели
  // тот же (домашняя еда в нём уже есть). Уронит: голод на демо-пути
  // (проход 16.10, day-energy-model §6а п. 2) или домашняя еда за деньги дважды.
  test('день без своей еды — Финни ест дома: утро 3-го дня не голодное', () {
    expect(shipped.dayCycle.homeMealDaily, isTrue);
    final WorldGame w = living(shipped);
    final int bill = w.snapshot.weeklyBill;
    final int coins = w.snapshot.available;
    ok(w.leisure('park'));
    ok(w.sleep());
    ok(w.sleep());
    expect(w.snapshot.dayInWeek, 3);
    expect(w.snapshot.satiety, greaterThanOrEqualTo(shipped.dayCycle.hungryAt),
        reason: 'сытость держит домашняя еда');
    expect(
        w.journal.where((WorldEntry e) =>
            e.kind == WorldLedgerKind.dayEnded && e.args['homeMeal'] == true),
        hasLength(2),
        reason: 'два вечера без своей еды — два домашних ужина');
    expect(w.snapshot.weeklyBill, bill, reason: 'счёт недели не меняется');
    expect(w.snapshot.available, coins - (w.catalogItem('park')?.price ?? 0),
        reason: 'домашняя еда не списывает монеты сейчас');
  });

  // Защищает правило «не больше N смен в день» (DEN-18, включается строкой
  // `day_cycle.max_shifts_per_day`): вторая смена дня отказывает с причиной на
  // доске и в вызове, утром снова можно; без строки — как раньше. Уронит:
  // флаг не ограничивает, ограничивает без флага или не сбрасывается утром.
  test('max_shifts_per_day: вторая смена дня — завтра', () {
    String cheapest(WorldGame w) => (w.jobBoard
            .where((JobOffer o) => o.blockReason == null)
            .toList()
          ..sort(
              (JobOffer a, JobOffer b) => a.energyCost.compareTo(b.energyCost)))
        .first
        .jobId;
    final WorldConfig c =
        configWith(<String, Object?>{'max_shifts_per_day': 1});
    expect(c.dayCycle.maxShiftsPerDay, 1);
    final WorldGame w = living(c);
    ok(w.completeJob(cheapest(w), score: 1));
    final JobOffer next = w.jobBoard.first;
    expect(
        w.canDo(WorldAction.job, id: next.jobId, variant: next.variant)?.code,
        'job.day_limit');
    expect(
        w.completeJob(next.jobId, variant: next.variant, score: 1).reasonCode,
        'job.day_limit');
    ok(w.sleep());
    expect(
        w.jobBoard.any((JobOffer o) => o.blockReason?.code == 'job.day_limit'),
        isFalse,
        reason: 'утром — снова можно');

    expect(shipped.dayCycle.maxShiftsPerDay, isNull,
        reason: 'по умолчанию нет');
    final WorldGame free = living(shipped);
    ok(free.completeJob(cheapest(free), score: 1));
    expect(
        free.jobBoard
            .any((JobOffer o) => o.blockReason?.code == 'job.day_limit'),
        isFalse);
  });

  // Защищает правило «не больше N событий в день» (DEN-23): после выбора в
  // событии в тот же день новое не приходит (было: slot_machine_sim →
  // сразу tired_but_good_shift, прогон front3 16.10); без строки — как раньше.
  test('max_events_per_day: после события в тот же день — без нового', () {
    WorldGame firstEvent(WorldConfig c) {
      final WorldGame w = living(c);
      expect(w.pendingEvent?.id, 'slot_machine_sim',
          reason: 'неделя открывается событием');
      final PendingEventChoice ch = w.pendingEvent!.choices
          .firstWhere((PendingEventChoice x) => x.available);
      ok(w.resolveEvent(ch.id));
      return w;
    }

    expect(firstEvent(legacy3).pendingEvent?.id, 'tired_but_good_shift',
        reason: 'без правила второе событие приходит в тот же день');
    final WorldConfig c =
        configWith(<String, Object?>{...legacy, 'max_events_per_day': 1});
    final WorldGame w = firstEvent(c);
    expect(w.snapshot.dayInWeek, 1);
    expect(w.pendingEvent, isNull, reason: 'одно событие в день');
  });

  // Защищает «событие каждое утро» (DEN-23 A: до 1 в день, «нам их нужно
  // побольше»): событие, к которому ребёнок не пошёл, не держит очередь всю
  // неделю — следующее утро приносит новое. Было (проход rc-7d 17.10, front3):
  // «!» у парка в день 1, дальше 6 утр без событий — `pendingEventId`
  // сбрасывался только выбором или новой неделей. Уронит: утро снова не
  // снимает вчерашнее событие. Перезапуск из журнала даёт то же событие.
  test('событие без ответа не держит очередь: утром приходит новое', () {
    final WorldGame w = living(shipped);
    final List<String?> mornings = <String?>[w.pendingEvent?.id];
    for (int d = 1; d < shipped.daysPerWeek; d++) {
      expect(w.sleep().reasonCode, 'day.next');
      mornings.add(w.pendingEvent?.id);
    }
    expect(mornings.first, 'slot_machine_sim');
    expect(mornings.whereType<String>().toSet(), hasLength(shipped.daysPerWeek),
        reason: 'каждое утро — новое событие: $mornings');
    final int shown = w.journal
        .where((WorldEntry e) => e.kind == WorldLedgerKind.eventShown)
        .length;
    expect(shown, shipped.daysPerWeek);
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.pendingEvent?.id, w.pendingEvent?.id);
  });

  // Защищает помощник тестов: на дневном мире один вызов доводит до итогов
  // (на нём стоят экранные тесты front3); на недельном — один сон, как было.
  test('sleepWeek: до итогов недели в обоих режимах', () {
    for (final WorldConfig c in <WorldConfig>[shipped, contentConfig]) {
      final WorldGame w = living(c);
      expect(sleepWeek(w).ok, isTrue);
      expect(w.phase, WeekPhase.review, reason: 'дней ${c.daysPerWeek}');
    }
  });

  // Защищает: «+1 ⚡ на следующую неделю» за сон с остатком (и всё, что
  // кладёт ⚡ в следующую неделю: перк, домашняя еда, события) в режиме дней
  // доходит до первого утра новой недели. Уронит: startWeek в днях берёт ⚡
  // только из сна и сытости и молча теряет перенос (найдено 16.10 при
  // описании формул §5.6).
  test('перенос ⚡ на следующую неделю доходит до первого утра', () {
    double week2Energy(int carry) {
      final WorldGame w = living(configWith(legacy, sleepCarryNextWeek: carry));
      expect(sleepWeek(w).reasonCode, 'sleep.bonus',
          reason: 'спим с остатком — бонус сна');
      ok(w.payBills());
      ok(w.startWeek());
      return w.snapshot.energy;
    }

    expect(week2Energy(1) - week2Energy(0), closeTo(1, 1e-9));
  });

  // Защищает «погладить раз в день» в режиме дней: после ночи без дел
  // поглаживание снова даёт 😊; второй раз за день — без 😊. Уронит: «день»
  // считается по делам (счётчик игровых дней), и после ночи без смены
  // поглаживание молчит.
  test('погладить Финни: раз в день недели, в том числе после ночи без дел',
      () {
    final WorldGame w = living(shipped);
    expect(w.petFinni().reasonCode, 'finni.pet');
    expect(w.petFinni().reasonCode, 'finni.pet_again');
    ok(w.sleep());
    expect(w.petFinni().reasonCode, 'finni.pet', reason: 'новый день');
  });

  test('последний день недели: «Спать» заканчивает неделю, как раньше', () {
    final WorldGame w = living(shipped);
    for (int d = 1; d < shipped.daysPerWeek; d++) {
      expect(w.sleep().reasonCode, 'day.next');
    }
    final WorldResult r = w.sleep();
    expect(r.reasonCode, startsWith('sleep.'));
    expect(w.phase, WeekPhase.review);
    ok(w.payBills());
    ok(w.startWeek());
    expect(w.snapshot.dayInWeek, 1, reason: 'новая неделя — снова день 1');
  });

  test('перезапуск из журнала: тот же день и та же сытость', () {
    final WorldGame w = living(shipped);
    ok(w.leisure('park'));
    ok(w.sleep());
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.unreadable, 0);
    expect(r.snapshot.dayInWeek, w.snapshot.dayInWeek);
    expect(r.snapshot.satiety, w.snapshot.satiety);
    expect(r.snapshot.energy, closeTo(w.snapshot.energy, 1e-9));
  });

  test('флаг days_per_week = 1: прежняя неделя, «Спать» — итоги', () {
    final WorldConfig c = configWith(<String, Object?>{'days_per_week': 1});
    expect(c.daysPerWeek, 1);
    final WorldGame w = living(c);
    final WorldResult r = w.sleep();
    expect(r.reasonCode, startsWith('sleep.'));
    expect(w.phase, WeekPhase.review);
  });

  // Защищает (17.10): в режиме дней «польза домашней еды» не уходит
  // на следующую неделю — вечерняя еда уже дала сытость, утро даёт сон по
  // таблице. Было: ⚡ блюда × несъеденные приёмы (до +7) в первое утро.
  // Уронит: foodEnergyNext снова считается по приёмам в днях.
  test('дни: домашняя еда не переносит ⚡ на следующую неделю', () {
    final WorldGame w = living(shipped);
    expect(sleepWeek(w).ok, isTrue);
    ok(w.payBills());
    final WorldEntry closed = w.journal
        .lastWhere((WorldEntry e) => e.kind == LedgerKind.periodClosed);
    expect(closed.args['foodEnergyNext'], 0.0);
  });
}
