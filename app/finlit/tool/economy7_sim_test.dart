// Экономика 7 дней на настоящем движке: стратегии игрока и их числа.
//
// Запуск (из app/finlit): flutter test tool/economy7_sim_test.dart
//   SIM_SEEDS=200  зёрен на стратегию (по умолчанию 10 — быстро)
//   SIM_WEEKS=10   недель
//   SIM_OUT=путь.json — сводка в файл (пишется после каждой стратегии)
//   SIM_CHOICE=none|random — мини-решения в смене: none (по умолчанию) —
//     смена без ответа, как до 663be31; random — случайный вариант, как ребёнок
//   SIM_SEED_FROM=0 — первое зерно (порции: 0 и 100 при SIM_SEEDS=100)
//   SIM_MERGE=a.json,b.json — склеить порции (поле raw) в SIM_OUT, без прогона
//   SIM_DOG_PRICE=4800 — цена собаки (pet_dog) поверх economy.json, только
//     в прогоне; «дней до собаки» считается до этой цены
// Зерно задаёт случайность игрока (оценка смены, выбор работы); случайность
// мира (события, везение) детерминирована журналом.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_fold.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();
int _envInt(String k, int d) => int.parse(Platform.environment[k] ?? '$d');

/// Цена собаки: SIM_DOG_PRICE или цена pet_dog из economy.json.
int get _dogPrice =>
    _envInt('SIM_DOG_PRICE', _petDog(_economyRaw())['price']! as int);

Map<String, Object?> _economyRaw() =>
    jsonDecode(_read('economy.json')) as Map<String, Object?>;

Map<String, Object?> _petDog(Map<String, Object?> e) =>
    ((e['pets']! as Map<String, Object?>)['roster']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((Map<String, Object?> p) => p['id'] == 'pet_dog');

/// SIM_PROFILE=soft|mid|strict — профиль баланса поверх файла;
/// SIM_DOG_PRICE — цена собаки поверх файла (продовые данные не меняются).
String _economy([String? profile]) {
  final String? p = profile ?? Platform.environment['SIM_PROFILE'];
  final String? dog = Platform.environment['SIM_DOG_PRICE'];
  final bool daily = Platform.environment['SIM_MOOD_DAILY'] == '1';
  final String? live = Platform.environment['SIM_MOOD_LIVE'];
  final bool ach = Platform.environment['SIM_ACH_DAYS'] == '1';
  // SIM_HOME_PRICES=5000,12000 — цены переездов (город, Москва) поверх файла.
  final String? homes = Platform.environment['SIM_HOME_PRICES'];
  if (p == null && dog == null && !daily && !ach && live == null &&
      homes == null) {
    return _read('economy.json');
  }
  final Map<String, Object?> e = _economyRaw();
  if (p != null) e['balance_profile'] = p;
  if (dog != null) _petDog(e)['price'] = int.parse(dog);
  // SIM_MOOD_DAILY=1 — C6 вариант A: оплата от настроения утра дня.
  if (daily) {
    e['day_cycle'] = <String, Object?>{
      ...(e['day_cycle']! as Map<String, Object?>),
      'mood_pay_daily': true,
    };
  }
  // SIM_MOOD_LIVE=0|1 — DEN-36 A (`mood_pay_live`) поверх файла.
  if (live != null) {
    e['day_cycle'] = <String, Object?>{
      ...(e['day_cycle']! as Map<String, Object?>),
      'mood_pay_live': live == '1',
    };
  }
  // SIM_ACH_DAYS=1 — награды дней с баффами (C7 + DEN-32) поверх файла.
  if (ach) e['achievements_days'] = true;
  if (homes != null) {
    final List<int> v = homes.split(',').map(int.parse).toList();
    for (final Object? h in ((e['homes']! as Map<String, Object?>)['options']!
        as List<Object?>)) {
      final Map<String, Object?> m = h! as Map<String, Object?>;
      if (m['id'] == 'home_flat') m['price'] = v[0];
      if (m['id'] == 'home_house') m['price'] = v[1];
    }
  }
  return jsonEncode(e);
}

WorldConfig _config([String? profile]) =>
    worldConfigFromContent(WorldContent.parse(
      economy: _economy(profile),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
    ));

/// Мини-решение в смене (SIM_CHOICE=random): ответ — случайный вариант.
/// Перехватывает и смены автопилота («правильный» не передаёт choice).
bool get _choiceRandom => Platform.environment['SIM_CHOICE'] == 'random';
math.Random _choiceRng = math.Random(0);

class _ChildWorld extends WorldGame {
  _ChildWorld({required super.config});

  int moodEnergyPlus = 0;
  int moodEnergyMinus = 0;

  @override
  WorldResult completeJob(String jobId,
      {String? variant, required double score, String? choice}) {
    String? c = choice;
    if (c == null && _choiceRandom) {
      // offer() не пишет в журнал — тот же вопрос, что возьмёт completeJob.
      final ShiftChoice? q = offer(jobId, variant: variant)?.choice;
      if (q != null) c = q.options[_choiceRng.nextInt(q.options.length)].id;
    }
    // DEN-36 A: сколько смен стоили ±1 ⚡ из-за настроения на момент смены.
    final double moodEnergy =
        offer(jobId, variant: variant)?.moodNow?.energyDelta ?? 0;
    final WorldResult r =
        super.completeJob(jobId, variant: variant, score: score, choice: c);
    if (r.ok && moodEnergy > 0) moodEnergyPlus++;
    if (r.ok && moodEnergy < 0) moodEnergyMinus++;
    _checkReach(this);
    return r;
  }

  // Порог «можно купить» проверяется после каждого хода с деньгами, а не
  // только утром: утро стратегии пропускает дни, которые движок закрыл сам.
  @override
  WorldResult resolveEvent(String choiceId) {
    final WorldResult r = super.resolveEvent(choiceId);
    _checkReach(this);
    return r;
  }

  @override
  WorldResult startWeek() {
    final WorldResult r = super.startWeek();
    _checkReach(this);
    return r;
  }

  @override
  WorldResult sleep() {
    final WorldResult r = super.sleep();
    _checkReach(this);
    return r;
  }
}

/// Статистика текущего прогона — для [_checkReach] из [_ChildWorld].
Stats? _runStats;

/// День, когда копилка + кошелёк дошли до цены рыбки (400) и собаки
/// ([_dog]) или питомец уже куплен. День — по календарю игры
/// ((неделя − 1) × дней в неделе + день недели), не по числу утр стратегии:
/// счётчик утр отставал в 2–3 раза (до 087b22c включительно).
void _checkReach(WorldGame w) {
  final Stats? st = _runStats;
  if (st == null) return;
  final ResourceSnapshot s = w.snapshot;
  final int day = (s.weekNo - 1) * w.config.daysPerWeek + s.dayInWeek;
  final int worth = s.goal + s.free + s.want;
  if (st.reachFish == null && (worth >= 400 || s.owned.contains('pet_fish'))) {
    st.reachFish = day;
  }
  // Переезды (цены 18.10): хватает монет (копилка + кошелёк) и открылось
  // очками роста (growth.stages[].min_points).
  for (final (String id, int stage) in <(String, int)>[
    ('home_flat', 1),
    ('home_house', 2),
  ]) {
    final int price = w.config.home(id)!.price;
    final bool flat = stage == 1;
    final bool money = worth >= price || s.owned.contains(id);
    final bool points = s.growthPoints >= w.config.stageMinPoints[stage];
    if (flat) {
      if (money) st.reachFlat ??= day;
      if (points) st.pointsFlat ??= day;
    } else {
      if (money) st.reachMoscow ??= day;
      if (points) st.pointsMoscow ??= day;
    }
  }
  if (st.reachDog == null && (worth >= _dog || s.owned.contains('pet_dog'))) {
    st.reachDog = day;
  }
}

/// Что стратегия делает в течение одного дня (до «Спать»).
typedef DayPlan = void Function(WorldGame w, math.Random rng);

JobOffer? _job(WorldGame w, math.Random rng) {
  final List<JobOffer> ok = w.jobBoard
      .where((JobOffer o) =>
          w.canDo(WorldAction.job, id: o.jobId, variant: o.variant) == null)
      .toList();
  if (ok.isEmpty) return null;
  // Самая выгодная по монетам за ⚡, при равенстве — случайная.
  ok.sort((JobOffer a, JobOffer b) =>
      (b.pay / b.energyCost).compareTo(a.pay / a.energyCost));
  final List<JobOffer> top = ok
      .where((JobOffer o) =>
          (o.pay / o.energyCost) >= ok.first.pay / ok.first.energyCost - 1e-9)
      .toList();
  return top[rng.nextInt(top.length)];
}

void _shift(WorldGame w, JobOffer o, math.Random rng) {
  // Ребёнок играет то хорошо, то средне: оценка 0,5–1.
  w.completeJob(o.jobId, variant: o.variant, score: 0.5 + rng.nextDouble() / 2);
  if (w.pendingLesson case final LessonOffer l) {
    // Урок — случайный доступный вариант (первый часто тратит 150 — при
    // оплате смены ~140 это смещало бы итог).
    final List<LessonChoiceView> av =
        l.choices.where((LessonChoiceView c) => c.available).toList();
    w.resolveLesson((av.isEmpty
            ? l.choices
            : av)[rng.nextInt(av.isEmpty ? l.choices.length : av.length)]
        .id);
  }
}

void _eat(WorldGame w) {
  final String? f = w.snapshot.foodId;
  if (f != null && w.canDo(WorldAction.eat, id: f) == null) w.eat(f);
}

/// Выбор в событии — случайный среди доступных (ребёнок, а не оптимизатор:
/// жадный выбор «больше монет» делал события главным доходом, ≈ 310 в неделю).
math.Random _eventRng = math.Random(0);

void _events(WorldGame w) {
  for (int i = 0; i < 3 && w.pendingEvent != null; i++) {
    final PendingEvent e = w.pendingEvent!;
    final List<PendingEventChoice> av =
        e.choices.where((PendingEventChoice c) => c.available).toList();
    if (av.isEmpty) return;
    w.resolveEvent(av[_eventRng.nextInt(av.length)].id);
  }
}

final Map<String, DayPlan> strategies = <String, DayPlan>{
  // Тратит всё: еда, смены, пока хватает ⚡.
  'spender': (WorldGame w, math.Random rng) {
    _eat(w);
    for (int i = 0; i < 6; i++) {
      final JobOffer? o = _job(w, rng);
      if (o == null) break;
      _shift(w, o, rng);
      _events(w);
      if (w.phase != WeekPhase.living) return;
    }
  },
  // Копит энергию: не работает, пока ⚡ < 18, потом — сколько выйдет.
  'hoarder': (WorldGame w, math.Random rng) {
    _eat(w);
    if (w.snapshot.energy + 1e-9 < 18) return;
    for (int i = 0; i < 6; i++) {
      final JobOffer? o = _job(w, rng);
      if (o == null) break;
      _shift(w, o, rng);
      _events(w);
      if (w.phase != WeekPhase.living) return;
    }
  },
  // Ленивый: только обязательное и «Спать».
  'lazy': (WorldGame w, math.Random rng) {},
};

class Stats {
  final Map<int, int> shiftsPerDay = <int, int>{};
  int days = 0;
  int hungryMornings = 0;
  int weeks = 0;
  int familyWeeks = 0;
  int minHappy = 100;
  int maxHappy = 0;
  double swingSum = 0;
  int swingN = 0;
  int finalSavings = 0;
  int finalStage = 0;
  int runs = 0;
  final List<int> week1Earned = <int>[];
  final List<int> bills = <int>[];
  double bedEnergySum = 0;
  int bedN = 0;
  // По прогону: день календаря, когда «можно купить» рыбку и собаку
  // ([_checkReach]).
  int? reachFish;
  int? reachDog;
  int? reachFlat;
  int? reachMoscow;
  int? pointsFlat;
  int? pointsMoscow;
  final List<int?> daysFlat = <int?>[];
  final List<int?> daysMoscow = <int?>[];
  final List<int?> daysPtsFlat = <int?>[];
  final List<int?> daysPtsMoscow = <int?>[];
  final List<int?> daysFish = <int?>[];
  final List<int?> daysDog = <int?>[];
  // C2: игровой день (с 1), когда опыт впервые дошёл до порога ступени 2 и 3
  // (`day_cycle.xp_stage_min`), по границам дней журнала.
  final List<int?> daysXp2 = <int?>[];
  final List<int?> daysXp3 = <int?>[];
  int shiftIncome = 0;
  int eventMoney = 0;
  int familyMoney = 0;
  int shifts = 0;
  int choiceShifts = 0;
  int choicePay = 0;
  int moodEnergyPlus = 0;
  int moodEnergyMinus = 0;
  // DEN-32: пик ⚡ за игру и предел ⚡ в конце (с баффом наград).
  double energyPeak = 0;
  double energyMaxEnd = 0;

  /// Всё, из чего считается сводка, — чтобы порции склеивались точно
  /// (медиану из медиан не получить).
  Map<String, Object?> toRaw() => <String, Object?>{
        'shiftsPerDay': <String, int>{
          for (final MapEntry<int, int> e in shiftsPerDay.entries)
            '${e.key}': e.value,
        },
        'days': days,
        'hungryMornings': hungryMornings,
        'weeks': weeks,
        'familyWeeks': familyWeeks,
        'minHappy': minHappy,
        'maxHappy': maxHappy,
        'swingSum': swingSum,
        'swingN': swingN,
        'finalSavings': finalSavings,
        'finalStage': finalStage,
        'runs': runs,
        'week1Earned': week1Earned,
        'bills': bills,
        'bedEnergySum': bedEnergySum,
        'bedN': bedN,
        'daysFish': daysFish,
        'daysDog': daysDog,
        'daysFlat': daysFlat,
        'daysMoscow': daysMoscow,
        'daysPtsFlat': daysPtsFlat,
        'daysPtsMoscow': daysPtsMoscow,
        'daysXp2': daysXp2,
        'daysXp3': daysXp3,
        'shiftIncome': shiftIncome,
        'eventMoney': eventMoney,
        'familyMoney': familyMoney,
        'shifts': shifts,
        'choiceShifts': choiceShifts,
        'choicePay': choicePay,
        'moodEnergyPlus': moodEnergyPlus,
        'moodEnergyMinus': moodEnergyMinus,
        'energyPeak': energyPeak,
        'energyMaxEnd': energyMaxEnd,
      };

  void addRaw(Map<String, Object?> r) {
    int i(String k) => (r[k]! as num).toInt();
    double d(String k) => (r[k]! as num).toDouble();
    List<int?> l(String k) => (r[k]! as List<Object?>)
        .map((Object? x) => (x as num?)?.toInt())
        .toList();
    (r['shiftsPerDay']! as Map<String, Object?>).forEach((String k, Object? v) {
      final int n = int.parse(k);
      shiftsPerDay[n] = (shiftsPerDay[n] ?? 0) + (v! as num).toInt();
    });
    days += i('days');
    hungryMornings += i('hungryMornings');
    weeks += i('weeks');
    familyWeeks += i('familyWeeks');
    minHappy = math.min(minHappy, i('minHappy'));
    maxHappy = math.max(maxHappy, i('maxHappy'));
    swingSum += d('swingSum');
    swingN += i('swingN');
    finalSavings += i('finalSavings');
    finalStage += i('finalStage');
    runs += i('runs');
    week1Earned.addAll(l('week1Earned').whereType<int>());
    bills.addAll(l('bills').whereType<int>());
    bedEnergySum += d('bedEnergySum');
    bedN += i('bedN');
    daysFish.addAll(l('daysFish'));
    daysDog.addAll(l('daysDog'));
    daysFlat.addAll(l('daysFlat'));
    daysMoscow.addAll(l('daysMoscow'));
    daysPtsFlat.addAll(l('daysPtsFlat'));
    daysPtsMoscow.addAll(l('daysPtsMoscow'));
    daysXp2.addAll(l('daysXp2'));
    daysXp3.addAll(l('daysXp3'));
    shiftIncome += i('shiftIncome');
    eventMoney += i('eventMoney');
    familyMoney += i('familyMoney');
    shifts += i('shifts');
    choiceShifts += i('choiceShifts');
    choicePay += i('choicePay');
    moodEnergyPlus += (r['moodEnergyPlus'] as num?)?.toInt() ?? 0;
    moodEnergyMinus += (r['moodEnergyMinus'] as num?)?.toInt() ?? 0;
    energyPeak =
        math.max(energyPeak, (r['energyPeak'] as num? ?? 0).toDouble());
    energyMaxEnd =
        math.max(energyMaxEnd, (r['energyMaxEnd'] as num? ?? 0).toDouble());
  }

  /// Доля прогонов, дошедших до цели не позже дня [d].
  static double _share(List<int?> xs, int d) => xs.isEmpty
      ? 0
      : _r(xs.where((int? x) => x != null && x <= d).length / xs.length);

  /// Доля, где к дню [d] есть и монеты, и очки (переезд возможен).
  static double _shareBoth(List<int?> a, List<int?> b, int d) {
    if (a.isEmpty) return 0;
    int n = 0;
    for (int i = 0; i < a.length && i < b.length; i++) {
      final int? x = a[i], y = b[i];
      if (x != null && y != null && x <= d && y <= d) n++;
    }
    return _r(n / a.length);
  }

  static Object? _median(List<int?> xs) {
    final List<int> got = xs.whereType<int>().toList()..sort();
    return <String, Object?>{
      'reached_share': got.length / xs.length,
      'median_days': got.isEmpty ? null : got[got.length ~/ 2],
    };
  }

  // Округление до 1e-4: суммы double в порциях складываются в другом
  // порядке — без него склейка отличалась бы в 15-м знаке.
  static double _r(num x) => (x * 10000).roundToDouble() / 10000;

  Map<String, Object?> toJson() => <String, Object?>{
        'runs': runs,
        'days': days,
        'shifts_per_day': <String, double>{
          for (final int k in (shiftsPerDay.keys.toList()..sort()))
            '$k': _r(shiftsPerDay[k]! / days),
        },
        'avg_shifts_per_day': _r(shiftsPerDay.entries
                .fold(0, (int a, MapEntry<int, int> e) => a + e.key * e.value) /
            days),
        'hungry_morning_share': _r(hungryMornings / days),
        'family_help_week_share': _r(familyWeeks / weeks),
        'happiness_min': minHappy,
        'happiness_max': maxHappy,
        'happiness_daily_swing_avg': swingN == 0 ? 0 : _r(swingSum / swingN),
        'bed_energy_avg': bedN == 0 ? 0 : _r(bedEnergySum / bedN),
        'avg_final_savings': _r(finalSavings / runs),
        'avg_final_stage': _r(finalStage / runs),
        'week1_earned_avg': week1Earned.isEmpty
            ? 0
            : _r(week1Earned.reduce((int a, int b) => a + b) /
                week1Earned.length),
        'shift_income_per_week': weeks == 0 ? 0 : _r(shiftIncome / weeks),
        'event_money_per_week': weeks == 0 ? 0 : _r(eventMoney / weeks),
        'family_money_per_week': weeks == 0 ? 0 : _r(familyMoney / weeks),
        'shift_choice_share': shifts == 0 ? 0 : _r(choiceShifts / shifts),
        'choice_money_per_week': weeks == 0 ? 0 : _r(choicePay / weeks),
        'mood_energy_plus_share': shifts == 0 ? 0 : _r(moodEnergyPlus / shifts),
        'mood_energy_minus_share':
            shifts == 0 ? 0 : _r(moodEnergyMinus / shifts),
        'energy_peak': energyPeak,
        'energy_max_end': energyMaxEnd,
        'days_to_fish_400': _median(daysFish),
        'days_to_dog': _median(daysDog),
        'days_to_flat_money': _median(daysFlat),
        'days_to_moscow_money': _median(daysMoscow),
        'days_to_flat_points': _median(daysPtsFlat),
        'days_to_moscow_points': _median(daysPtsMoscow),
        'reach_by_day': <String, Object?>{
          for (final int d in <int>[7, 14, 21])
            '$d': <String, double>{
              'dog': _share(daysDog, d),
              'flat_money': _share(daysFlat, d),
              'flat_move': _shareBoth(daysFlat, daysPtsFlat, d),
              'moscow_money': _share(daysMoscow, d),
              'moscow_move': _shareBoth(daysMoscow, daysPtsMoscow, d),
            },
        },
        'days_to_xp_stage2': _median(daysXp2),
        'days_to_xp_stage3': _median(daysXp3),
        'bill_avg': bills.isEmpty
            ? 0
            : _r(bills.reduce((int a, int b) => a + b) / bills.length),
      };
}

final int _dog = _dogPrice;

/// Утро дня в журнале: с него начинается игровой день.
bool _opensDay(WorldEntry e) =>
    e.kind == WorldLedgerKind.weekStarted || e.kind == WorldLedgerKind.dayEnded;

/// Прогон одной стратегии; возвращает мир (журнал — для проверки счётчиков).
WorldGame runStrategy(
    WorldConfig cfg, String name, int seed, int weeks, Stats st) {
  final math.Random rng = math.Random(seed);
  _eventRng = math.Random(seed * 31 + 7);
  _choiceRng = math.Random(seed * 53 + 11);
  final WorldGame w = _ChildWorld(config: cfg);
  st.runs++;
  st.reachFish = null;
  st.reachDog = null;
  st.reachFlat = null;
  st.reachMoscow = null;
  st.pointsFlat = null;
  st.pointsMoscow = null;
  _runStats = st;
  if (name == 'correct') {
    final WorldAutopilot ap = WorldAutopilot(w);
    int lastKey = -1;
    int guard = 0;
    while (w.weekHistory.length < weeks && guard++ < 4000) {
      final ResourceSnapshot s = w.snapshot;
      final int key = s.weekNo * 10 + s.dayInWeek;
      if (w.phase == WeekPhase.living && key != lastKey) {
        _checkReach(w);
        lastKey = key;
      }
      if (w.pendingLesson case final LessonOffer l) {
        final List<LessonChoiceView> av =
            l.choices.where((LessonChoiceView c) => c.available).toList();
        w.resolveLesson((av.isEmpty
                ? l.choices
                : av)[rng.nextInt(av.isEmpty ? l.choices.length : av.length)]
            .id);
        continue;
      }
      if (w.phase == WeekPhase.review &&
          w.canDo(WorldAction.payBills) == null) {
        st.bills.add(w.snapshot.weeklyBill);
      }
      ap.step();
    }
  } else {
    final DayPlan day = strategies[name]!;
    while (w.weekHistory.length < weeks) {
      if (w.phase == WeekPhase.onboarding || w.phase == WeekPhase.weekStart) {
        w.startWeek();
      }
      if (w.phase == WeekPhase.planning) {
        final ResourceSnapshot s = w.snapshot;
        final int need = math.min(s.unallocated, s.weeklyBill);
        w.plan(needs: need, wants: 0, goal: s.unallocated - need);
        if (s.activeGoalId == null) w.chooseGoal('pet_fish');
      }
      _events(w);
      // Дни недели.
      while (w.phase == WeekPhase.living) {
        _checkReach(w);
        day(w, rng);
        _events(w);
        if (w.phase != WeekPhase.living) break;
        st.bedEnergySum += w.snapshot.energy;
        st.bedN++;
        w.sleep();
        _events(w);
      }
      if (w.phase == WeekPhase.review) {
        st.bills.add(w.snapshot.weeklyBill);
        if (w.canDo(WorldAction.payBills) == null) w.payBills();
        w.startWeek();
      }
    }
  }
  // Смены, голод и 😊 по игровым дням — по журналу: день кончается записью
  // dayEnded (сон или ⚡ кончилась), неделя — weekStarted. Так считается и
  // тогда, когда движок сам закрыл день посреди хода стратегии. Утро дня —
  // состояние сразу после этой записи: сытость ниже порога — то голодное
  // утро, за которое движок снял ⚡ и 😊. До этой правки голод и 😊 брались
  // только на утрах, которые видела стратегия, а делились на все дни журнала.
  final WorldState fold = WorldState.fold(const <WorldEntry>[], cfg);
  int today = 0;
  bool open = false;
  bool hungry = false;
  int mood = 0;
  int prevMood = cfg.happinessStart;
  void closeDay() {
    if (!open) return;
    st.shiftsPerDay[today] = (st.shiftsPerDay[today] ?? 0) + 1;
    st.days++;
    if (hungry) st.hungryMornings++;
    st.minHappy = math.min(st.minHappy, mood);
    st.maxHappy = math.max(st.maxHappy, mood);
    st.swingSum += (mood - prevMood).abs();
    st.swingN++;
    prevMood = mood;
    today = 0;
  }

  int dayNo = 0;
  int? xp2, xp3;
  final List<int> xpMin = cfg.dayCycle.xpStageMin;
  for (final WorldEntry e in w.journal) {
    fold.apply(e);
    if (_opensDay(e)) {
      closeDay();
      open = true;
      dayNo++;
      final ResourceSnapshot s = fold.snapshot;
      hungry = s.hungry;
      mood = s.happiness;
    } else if (e.kind == WorldLedgerKind.sleep ||
        e.kind == WorldLedgerKind.energyOut) {
      closeDay();
      open = false;
    } else if (e.kind == WorldLedgerKind.jobPayout) {
      today++;
      final int xp = fold.snapshot.experience;
      if (xpMin.length > 1 && xp2 == null && xp >= xpMin[1]) xp2 = dayNo;
      if (xpMin.length > 2 && xp3 == null && xp >= xpMin[2]) xp3 = dayNo;
    }
  }
  st.daysXp2.add(xp2);
  st.daysXp3.add(xp3);
  if (Platform.environment['SIM_DUMP'] == name) {
    for (final WorldEntry e in w.journal) {
      if (e.weekNo > 2) break;
      final int money = e.need + e.want + e.goal + e.free + e.unallocated;
      if (money != 0) {
        stdout.writeln('DUMP w${e.weekNo} ${e.kind.name} ${e.reasonCode} '
            'need ${e.need} want ${e.want} goal ${e.goal} free ${e.free} '
            'un ${e.unallocated}');
      }
    }
  }
  st.weeks += w.weekHistory.length;
  st.daysFish.add(st.reachFish);
  st.daysDog.add(st.reachDog);
  if (w is _ChildWorld) {
    st.moodEnergyPlus += w.moodEnergyPlus;
    st.moodEnergyMinus += w.moodEnergyMinus;
  }
  // DEN-32: ⚡ по журналу ни разу не выше предела (с баффом — 21, не больше).
  double run = 0;
  for (final WorldEntry e in w.journal) {
    run += e.energy;
    st.energyPeak = math.max(st.energyPeak, run);
  }
  expect(st.energyPeak, lessThanOrEqualTo(w.energyMaxNow + 1e-6));
  expect(w.energyMaxNow, lessThanOrEqualTo(w.config.energyMax + 1));
  st.energyMaxEnd = math.max(st.energyMaxEnd, w.energyMaxNow);
  st.daysFlat.add(st.reachFlat);
  st.daysMoscow.add(st.reachMoscow);
  st.daysPtsFlat.add(st.pointsFlat);
  st.daysPtsMoscow.add(st.pointsMoscow);
  for (final WorldEntry e in w.journal) {
    if (e.kind == WorldLedgerKind.jobPayout) {
      st.shiftIncome += e.free;
      st.shifts++;
      if (e.args['choice'] != null) st.choiceShifts++;
      st.choicePay += (e.args['choicePay'] as num?)?.toInt() ?? 0;
    }
    if (e.kind == WorldLedgerKind.eventChoice) {
      st.eventMoney += e.need + e.want + e.goal + e.free;
    }
    if (e.kind == WorldLedgerKind.familyHelp) {
      st.familyMoney += e.need + e.want + e.goal + e.free;
    }
  }
  st.familyWeeks += <int>{
    for (final WorldEntry e in w.journal)
      if (e.kind == WorldLedgerKind.familyHelp) e.weekNo,
  }.length;
  if (w.weekHistory.isNotEmpty) {
    st.week1Earned.add(w.weekHistory.first.shifts
        .fold(0, (int a, WeekItem i) => a + i.amount));
  }
  st.finalSavings += w.snapshot.goal;
  st.finalStage += w.snapshot.stage.index;
  return w;
}

void main() {
  // Голод и 😊 — на каждом игровом дне, а не на утрах стратегии. Ожидание —
  // свёртка журнала с нуля до каждого утра (WorldState.fold), не тот же
  // проход, что в runStrategy. «Тратит всё» и «копит» в строгом: движок сам
  // закрывает день посреди серии смен, такие утра стратегия не видит.
  test('hunger and mood: every game day by the journal', () {
    final WorldConfig cfg = _config('strict');
    int energyOutHungry = 0;
    for (final String name in <String>['spender', 'hoarder']) {
      for (int seed = 0; seed < 4; seed++) {
        final Stats st = Stats();
        final List<WorldEntry> j = runStrategy(cfg, name, seed, 3, st).journal;
        final List<int> mornings = <int>[
          for (int i = 0; i < j.length; i++)
            if (j[i].kind == WorldLedgerKind.weekStarted ||
                j[i].kind == WorldLedgerKind.dayEnded)
              i,
        ];
        // Последнее утро (начало недели после последней) не закрыто — его
        // нет и в числе дней.
        mornings.removeLast();
        int hungry = 0;
        int lo = 100;
        int hi = 0;
        for (final int i in mornings) {
          final ResourceSnapshot s =
              WorldState.fold(j.sublist(0, i + 1), cfg).snapshot;
          if (s.hungry) {
            hungry++;
            if (j[i].reasonCode == 'day.energy_out') energyOutHungry++;
          }
          lo = math.min(lo, s.happiness);
          hi = math.max(hi, s.happiness);
        }
        final String at = '$name seed $seed';
        expect(st.days, mornings.length, reason: at);
        expect(st.hungryMornings, hungry, reason: at);
        expect(st.minHappy, lo, reason: at);
        expect(st.maxHappy, hi, reason: at);
      }
    }
    // Иначе проверка пустая: голодные утра после «силы кончились» есть.
    expect(energyOutHungry, greaterThan(0));
  });

  test('economy 7d sim', () {
    final WorldConfig cfg = _config();
    // Переопределение цены дошло до движка, а не только до порога.
    expect(cfg.pets.singleWhere((WorldPet p) => p.id == 'pet_dog').price, _dog);
    final int seeds = _envInt('SIM_SEEDS', 10);
    final int from = _envInt('SIM_SEED_FROM', 0);
    final int weeks = _envInt('SIM_WEEKS', 10);
    final String? path = Platform.environment['SIM_OUT'];
    final String? merge = Platform.environment['SIM_MERGE'];
    const List<String> names = <String>[
      'correct',
      'spender',
      'hoarder',
      'lazy'
    ];
    final Map<String, Object?> out = <String, Object?>{
      'params': <String, Object?>{
        'days': cfg.daysPerWeek,
        'energy_max': cfg.energyMax,
        'pocket': cfg.pocketMoney,
        'profile': Platform.environment['SIM_PROFILE'],
        'dog_price': _dog,
        'choice': _choiceRandom ? 'random' : 'none',
        'mood_pay_live': cfg.dayCycle.moodPayLive,
        'seeds': seeds,
        'seed_from': from,
        'weeks': weeks,
      },
    };
    final Map<String, Object?> raw = <String, Object?>{};
    void write() {
      out['raw'] = raw;
      if (path != null) {
        File(path)
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
      }
    }

    if (merge != null) {
      // Склейка порций: params — первой порции, зёрна — сумма.
      final List<Map<String, Object?>> parts = <Map<String, Object?>>[
        for (final String f in merge.split(','))
          jsonDecode(File(f).readAsStringSync()) as Map<String, Object?>,
      ];
      int total = 0;
      for (final Map<String, Object?> p in parts) {
        total += (p['params']! as Map<String, Object?>)['seeds']! as int;
      }
      out['params'] = <String, Object?>{
        ...parts.first['params']! as Map<String, Object?>,
        'seeds': total,
        'merged': merge.split(','),
      };
      for (final String name in names) {
        final Stats st = Stats();
        for (final Map<String, Object?> p in parts) {
          st.addRaw((p['raw']! as Map<String, Object?>)[name]!
              as Map<String, Object?>);
        }
        out[name] = st.toJson();
        raw[name] = st.toRaw();
      }
      write();
      return;
    }
    for (final String name in names) {
      final Stats st = Stats();
      for (int s = from; s < from + seeds; s++) {
        runStrategy(cfg, name, s, weeks, st);
      }
      out[name] = st.toJson();
      raw[name] = st.toRaw();
      stdout.writeln('$name: ${jsonEncode(st.toJson())}');
      write();
    }
  }, timeout: Timeout.none);
}
