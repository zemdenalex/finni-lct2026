import 'dart:math' as math;

import '../ledger/ledger_entry.dart' show LedgerKind;
import 'contract.dart';
import 'skin_id.dart';
import 'world_config.dart';
import 'world_entry.dart';
import 'world_mood.dart';

/// Эффект события, который повторяется в начале недель [fromWeek]..[toWeek]
/// (`effects.recurring`). [effect] — сам эффект в форме `events.json`: он
/// записан в журнал при выборе, поэтому правка файла не меняет прошлое.
typedef ActiveRecurring = ({
  String eventId,
  String choiceId,
  int fromWeek,
  int toWeek,
  Map<String, Object?> effect,
});

/// Округление ⚡ до сотых — чтобы 10 − 3 − 3 − 2 давало ровно 2, а не 1,9999.
double roundEnergy(double v) => (v * 100).round() / 100;

/// Состояние мира, **свёрнутое** из журнала. Нигде не хранится.
///
/// 🔴 Единственный способ получить деньги, ⚡, 😊, фазу недели и владение —
/// [WorldState.fold]. Поэтому перезапуск = та же свёртка того же журнала
/// (ТЗ 2.5.13.1), а число не меняется без записи с причиной (ТЗ 2.5.4.3).
class WorldState {
  WorldState._(this.config)
      : happiness = config.happinessStart,
        happinessAtWeekStart = config.happinessStart,
        happinessAtDayStart = config.happinessStart,
        foodId = config.startFoodId,
        homeId = config.startHomeId,
        rentHomeId = config.startHomeId;

  final WorldConfig config;

  WeekPhase phase = WeekPhase.onboarding;
  int weekNo = 0;

  // ── деньги ──
  int need = 0;
  int want = 0;
  int goal = 0;
  int free = 0;
  int unallocated = 0;

  // ── ⚡ и 😊 ──
  double energy = 0;
  int happiness;
  int happinessAtWeekStart;

  /// 😊 на утро текущего дня (после ночного возврата к нейтральному) —
  /// для оплаты и ⚡ смены при `day_cycle.mood_pay_daily` (C6, вариант A).
  int happinessAtDayStart;

  // ── рост ──
  int growthPoints = 0;
  int experience = 0;

  // ── выборы и владение ──
  /// Домашнее меню: что Финни ест в итогах недели за невыбранные приёмы.
  String foodId;

  /// Где Финни живёт сейчас (последний купленный дом).
  String homeId;

  /// За какое жильё платим на этой неделе: дом на момент начала недели.
  String rentHomeId;
  String? activeGoalId;
  String? activePetId;

  /// id вещи → номер недели покупки.
  final Map<String, int> owned = <String, int>{};

  /// Вещи комнаты ([WorldLedgerKind.roomItemBought]): id → неделя покупки.
  /// Отдельно от [owned]: у них своё место — сетка, а не слот декора.
  final Map<String, int> roomOwned = <String, int>{};

  /// Вещь комнаты → левый верхний угол на сетке.
  final Map<String, RoomCell> roomPlaced = <String, RoomCell>{};

  /// Предмет комнаты → выбранный вариант ([WorldChoiceKind.skinChosen]).
  final Map<String, String> chosenSkins = <String, String>{};

  /// Демо «Открыть все профессии» ([WorldDemoKind.unlockAllJobs]): замки
  /// работ сняты. Владение не меняется — скидки транспорта и перков нет.
  bool allJobsUnlocked = false;

  // ── неделя ──
  WeekEnd? endedBy;
  bool billsPaid = false;
  int shiftsThisWeek = 0;
  final Map<String, int> shiftsByJob = <String, int>{};

  /// Взрослый открыл дополнительную смену на этой неделе
  /// ([WorldLedgerKind.parentBonus], ТЗ 2.5.12.3): +1 к лимиту смен недели и
  /// к лимиту каждой работы. Со следующей недели снова false.
  bool parentBonusThisWeek = false;
  int leisureHappinessThisWeek = 0;
  int snacksThisWeek = 0;

  /// Сколько раз Финни поел на этой неделе ([WorldLedgerKind.mealEaten]).
  int mealsThisWeek = 0;

  /// Окупаемость инструментов: id вещи → прибавка, заработанная сменами
  /// (`jobPayout.args.premium` с `args.tool`).
  final Map<String, int> toolPayback = <String, int>{};

  /// Урок после последней смены ждёт выбора: работа и оплата смены.
  String? lessonJobId;
  int lessonPay = 0;

  /// Какой по счёту урок работы ждёт (C8): номер смены с мини-игрой этой
  /// работы за всю игру, с 0. Уроки чередуются по кругу.
  int lessonIndex = 0;

  /// Смен с мини-игрой по работам за всю игру — для чередования уроков.
  final Map<String, int> lessonShiftsByJob = <String, int>{};
  int incomeThisWeek = 0;

  /// Заработок недели для проверки роста (P7): оплата смен и деньги событий,
  /// без стипендии.
  int earnedThisWeek = 0;

  /// Заработок прошлой недели; null — прошлой недели ещё не было.
  int? earnedLastWeek;

  /// Сколько целей куплено на этой неделе (питомец, транспорт, жильё).
  int goalsBoughtThisWeek = 0;

  /// Недель без роста подряд (P7): от него растёт штраф застоя.
  int flatWeeks = 0;

  /// Чистое отложенное за неделю: взносы в ЦЕЛЬ минус снятое из неё.
  int depositsThisWeek = 0;

  /// Ключи операций перевода из журнала ([World.transfer] `opId`): повтор
  /// с тем же ключом — отказ, в том числе после перезапуска.
  final Set<String> transferOps = <String>{};

  /// Переводов за всю игру.
  int transfersTotal = 0;

  /// ⚡, которые закрытая неделя передаёт следующей: сон + еда.
  double carryNextWeek = 0;

  /// Игровой день = число действий, тративших ⚡, за всю игру (T7).
  int day = 0;

  /// День по энергии: день недели (с 1) и сытость 0–100 (`day_cycle`).
  int dayInWeek = 1;

  /// Приёмов еды сегодня (день по энергии: не больше [mealsPerDay]).
  int mealsToday = 0;

  /// Смен сегодня (правило `day_cycle.max_shifts_per_day`).
  int shiftsToday = 0;

  /// Событий показано сегодня (правило `day_cycle.max_events_per_day`).
  int eventsShownToday = 0;

  /// Холодильник: блюдо → порций.
  final Map<String, int> fridge = <String, int>{};

  /// Дела текущего дня ([ResourceSnapshot.doneToday]).
  final Set<String> doneToday = <String>{};

  // ── награды (D3) ──
  int shiftsTotal = 0;

  /// Смен каждой работы за всю игру ([ResourceSnapshot.shiftsByJobTotal]):
  /// раунд её мини-игры. В отличие от [shiftsByJob] не обнуляется неделей.
  final Map<String, int> shiftsByJobTotal = <String, int>{};
  int goalsBoughtTotal = 0;
  int petsOwnedTotal = 0;
  int lessonsDone = 0;
  int weeksNoFamilyHelp = 0;
  int noFamilyStreak = 0;
  bool familyHelpThisWeek = false;
  int goalSavedMax = 0;

  /// Полученные награды: id → неделя получения.
  final Map<String, int> achievementsEarned = <String, int>{};

  /// День недели получения награды; нет — режим «неделя» или старое
  /// сохранение (до 17.10 поля `day` в записи не было).
  final Map<String, int> achievementsEarnedDay = <String, int>{};

  /// DEN-32: насколько предел ⚡ больше из-за наград (постоянный бафф).
  double energyMaxBonus = 0;

  /// DEN-32: временные баффы 😊 — сколько утр ещё прибавлять и сколько.
  final List<({int happiness, int mornings})> moodBuffs =
      <({int happiness, int mornings})>[];

  /// 😊, которые баффы наград добавят следующим утром.
  int get moodBuffMorning => moodBuffs.fold(
      0, (int s, ({int happiness, int mornings}) b) => s + b.happiness);

  int achievementProgress(AchievementMetric m) => switch (m) {
        AchievementMetric.shifts => shiftsTotal,
        AchievementMetric.goodShifts => experience,
        AchievementMetric.goalsBought => goalsBoughtTotal,
        AchievementMetric.weeksNoFamilyHelp => weeksNoFamilyHelp,
        AchievementMetric.noFamilyStreak => noFamilyStreak,
        AchievementMetric.goalSavedMax => goalSavedMax,
        AchievementMetric.lessonsDone => lessonsDone,
        AchievementMetric.petsOwned => petsOwnedTotal,
        AchievementMetric.stage => stage.index,
        AchievementMetric.distinctJobs => jobsTried.length,
        AchievementMetric.luckyShifts => luckyShifts,
        AchievementMetric.shiftChoices => shiftChoicesMade,
        AchievementMetric.daysPlayed => daysPlayed,
        AchievementMetric.workDays => workDays,
      };

  // Счётчики дневных наград (C7) — за всю игру, из журнала.
  final Set<String> jobsTried = <String>{};
  int luckyShifts = 0;
  int shiftChoicesMade = 0;
  int daysPlayed = 0;
  int workDays = 0;

  List<AchievementView> get achievementViews => <AchievementView>[
        for (final AchievementDef d in config.achievements)
          _view(d, achievementProgress(d.metric)),
      ];

  AchievementView _view(AchievementDef d, int p) {
    final int? week = achievementsEarned[d.id];
    return AchievementView(
      def: d,
      progress: week != null ? d.target : (p > d.target ? d.target : p),
      status: week != null
          ? AchievementStatus.earned
          : p > 0
              ? AchievementStatus.inProgress
              : AchievementStatus.locked,
      earnedWeek: week,
      earnedDay: achievementsEarnedDay[d.id],
    );
  }

  late int satiety = config.satietyStart;
  int lastTapDay = -1;

  /// Игровой день последнего +😊 за касание Финни.
  int lastFinniPetDay = -1;

  /// [day] в начале этой недели: игровых дней недели = [day] − это.
  int dayAtWeekStart = 0;

  // ── события недели (A10) ──

  /// Событие, которое ждёт выбора (показано и ещё не решено).
  String? pendingEventId;
  int eventsShownThisWeek = 0;

  /// id события → неделя последнего показа.
  final Map<String, int> eventLastShown = <String, int>{};

  /// id события → неделя показа **перед** последним (−1 — не было): от неё
  /// считается свежесть метки для вариантов показанного события.
  final Map<String, int> eventPrevShown = <String, int>{};

  /// Метка события → неделя, когда поставлена в последний раз.
  final Map<String, int> flagsSetWeek = <String, int>{};

  /// Повторяющиеся эффекты выборов (челлендж «Копилка»).
  final List<ActiveRecurring> recurring = <ActiveRecurring>[];

  /// Добавка событий к обязательному счёту этой недели (рюкзак).
  int extraBill = 0;

  /// Последнее, что изменило 😊 или закрыло неделю: код причины и на
  /// сколько — для причины настроения (A12, `moodReasonFor`).
  String? moodCauseCode;
  int moodCauseDelta = 0;

  /// Записи с неизвестным видом, пропущенные при чтении — не сюда: их
  /// считает загрузчик. Здесь только число свёрнутых записей.
  int entries = 0;

  int get available => need + want + free + unallocated;

  /// Сколько монет в карманах, из которых платятся счета (без ЦЕЛИ).
  int get pockets => need + want + free;

  WorldStage get stage => stageFor(growthPoints);

  /// Стадия при [points] очках: по очкам, а если стадия — аренда
  /// ([WorldConfig.stageByRent]), не выше стадии снятого жилья.
  WorldStage stageFor(int points) {
    final WorldStage byPoints = stageAt(points);
    if (!config.stageByRent) return byPoints;
    final WorldStage home = config.home(homeId)?.stage ?? WorldStage.village;
    return home.index < byPoints.index ? home : byPoints;
  }

  /// Стадия при [points] очках роста — и для «станет ли переезд» в итогах.
  WorldStage stageAt(int points) {
    WorldStage s = WorldStage.values.first;
    for (int i = 0; i < WorldStage.values.length; i++) {
      if (i < config.stageMinPoints.length &&
          points >= config.stageMinPoints[i]) {
        s = WorldStage.values[i];
      }
    }
    return s;
  }

  double get stageStep {
    final int i = stage.index;
    return i < config.stageSteps.length ? config.stageSteps[i] : 1;
  }

  bool get hasTransport => config.transports.keys.any(owned.containsKey);

  /// Есть ли у Финни техника с возможностью [ability] (`computer`…).
  bool hasAbility(String ability) => config.techs.any(
      (WorldTech t) => owned.containsKey(t.id) && t.unlocks.contains(ability));

  bool get hasAnyPet =>
      config.pets.any((WorldPet p) => owned.containsKey(p.id));

  /// Питомцы, которые едят и радуют на этой неделе: купленные раньше неё.
  Iterable<WorldPet> get feedingPets => config.pets
      .where((WorldPet p) => owned.containsKey(p.id) && owned[p.id]! < weekNo);

  int get petFoodBill =>
      feedingPets.fold<int>(0, (int a, WorldPet p) => a + p.foodPerWeek);

  /// Приёмов пищи до конца недели: их Финни съест дома в итогах.
  /// День по энергии: приёмы недели делятся на дни — неделю не съесть за утро.
  int get mealsPerDay => config.dayCycle.enabled
      ? (config.mealsPerWeek / config.daysPerWeek).ceil()
      : config.mealsPerWeek;

  int get mealsLeft => config.mealsPerWeek > mealsThisWeek
      ? config.mealsPerWeek - mealsThisWeek
      : 0;

  /// Еда в счёте недели: оставшиеся приёмы по цене домашнего меню. Блюда,
  /// съеденные посреди недели, уже оплачены.
  int get foodBill => (config.food(foodId)?.price ?? 0) * mealsLeft;

  int get rentBill => config.home(rentHomeId)?.weeklyCost ?? 0;

  int get weeklyBill => petFoodBill + foodBill + rentBill + extraBill;

  ResourceSnapshot get snapshot => ResourceSnapshot(
        weekNo: weekNo,
        need: need,
        want: want,
        goal: goal,
        free: free,
        unallocated: unallocated,
        energy: energy,
        happiness: happiness,
        growthPoints: growthPoints,
        stage: stage,
        experience: experience,
        shiftsThisWeek: shiftsThisWeek,
        weeklyBill: weeklyBill,
        owned: Set<String>.unmodifiable(owned.keys),
        activeGoalId: activeGoalId,
        activePetId: activePetId,
        endedBy: endedBy,
        moodReason: moodReasonFor(
          happiness: happiness,
          phase: phase,
          causeCode: moodCauseCode,
          causeDelta: moodCauseDelta,
        ),
        foodId: foodId,
        daysThisWeek: day - dayAtWeekStart,
        dayInWeek: dayInWeek,
        daysPerWeek: config.daysPerWeek,
        satiety: config.dayCycle.enabled ? satiety : null,
        satietyHungryAt: config.dayCycle.hungryAt,
        satietyFullAt: config.dayCycle.fullAt,
        fridge: Map<String, int>.unmodifiable(fridge),
        doneToday: Set<String>.unmodifiable(doneToday),
        shiftsTotal: shiftsTotal,
        shiftsByJobTotal: Map<String, int>.unmodifiable(shiftsByJobTotal),
        achievements: List<AchievementView>.unmodifiable(achievementViews),
        snacksThisWeek: snacksThisWeek,
        mealsThisWeek: mealsThisWeek,
        mealsPerWeek: config.mealsPerWeek,
        mealsCanEat: mealsCanEat,
        toolPayback: Map<String, int>.unmodifiable(toolPayback),
        roomOwned: Set<String>.unmodifiable(roomOwned.keys),
        roomPlaced: Map<String, RoomCell>.unmodifiable(roomPlaced),
        chosenSkins: Map<String, String>.unmodifiable(chosenSkins),
      );

  /// Дни: приёмы недели, но не больше «оставшиеся дни × в день − сегодня
  /// съедено»; неделя — приёмы недели.
  int get mealsCanEat {
    if (!config.dayCycle.enabled) return mealsLeft;
    final int byDays =
        (config.daysPerWeek - dayInWeek + 1) * mealsPerDay - mealsToday;
    return math.max(0, math.min(mealsLeft, byDays));
  }

  /// Свернуть журнал с нуля.
  static WorldState fold(Iterable<WorldEntry> journal, WorldConfig config) {
    final WorldState s = WorldState._(config);
    journal.forEach(s.apply);
    return s;
  }

  /// Применить одну запись. Вызывается только свёрткой и `WorldGame` сразу
  /// после записи в журнал — других путей изменить состояние нет.
  void apply(WorldEntry e) {
    entries++;
    need += e.need;
    want += e.want;
    goal += e.goal;
    free += e.free;
    unallocated += e.unallocated;
    energy = roundEnergy(energy + e.energy);
    if (goal > goalSavedMax) goalSavedMax = goal;
    final Object? sat = e.args['satiety'];
    if (sat is num) satiety = (satiety + sat.round()).clamp(0, 100);
    final String? done = switch (e.kind) {
      WorldLedgerKind.mealEaten => 'meal',
      WorldLedgerKind.finniPetted => 'pet',
      WorldLedgerKind.fridgeStocked => 'fridge',
      WorldLedgerKind.restAtHome => 'rest',
      WorldLedgerKind.jobPayout => 'job',
      _ => null,
    };
    if (done != null) doneToday.add(done);
    happiness += e.happiness;

    final Enum k = e.kind;
    final Map<String, Object?> a = e.args;
    // Причина настроения (A12): итоги недели и конец сил называются всегда,
    // остальное — если 😊 изменилось. `endedBy` здесь ещё той же недели.
    if (k == LedgerKind.periodClosed) {
      moodCauseCode = weekClosedMoodCause(
        fromFamily: a['fromFamily'] as int? ?? 0,
        fromGoal: a['fromGoal'] as int? ?? 0,
        downgraded: a['downgraded'] as bool? ?? false,
        endedBy: endedBy,
        growth: a['growth'] as String?,
      );
      moodCauseDelta = e.happiness;
    } else if (e.happiness != 0 || k == WorldLedgerKind.energyOut) {
      moodCauseCode = e.reasonCode;
      moodCauseDelta = e.happiness;
    }
    if (k == WorldLedgerKind.weekStarted || k == WorldLedgerKind.dayEnded) {
      daysPlayed++;
      // Утро: временные баффы наград тратят по дню (прибавка уже в записи).
      for (int i = moodBuffs.length - 1; i >= 0; i--) {
        final ({int happiness, int mornings}) b = moodBuffs[i];
        if (b.mornings <= 1) {
          moodBuffs.removeAt(i);
        } else {
          moodBuffs[i] = (happiness: b.happiness, mornings: b.mornings - 1);
        }
      }
    }
    if (k == WorldLedgerKind.weekStarted) {
      // Прошлая неделя для проверки роста — только если она была.
      earnedLastWeek = weekNo == 0 ? null : earnedThisWeek;
      earnedThisWeek = 0;
      goalsBoughtThisWeek = 0;
      weekNo = e.weekNo;
      phase = WeekPhase.planning;
      rentHomeId = homeId;
      happinessAtWeekStart = happiness;
      happinessAtDayStart = happiness;
      endedBy = null;
      billsPaid = false;
      shiftsThisWeek = 0;
      shiftsByJob.clear();
      parentBonusThisWeek = false;
      leisureHappinessThisWeek = 0;
      snacksThisWeek = 0;
      mealsThisWeek = 0;
      lessonJobId = null;
      depositsThisWeek = 0;
      incomeThisWeek = 0;
      carryNextWeek = 0;
      pendingEventId = null;
      eventsShownThisWeek = 0;
      extraBill = 0;
      dayAtWeekStart = day;
      dayInWeek = 1;
      mealsToday = 0;
      shiftsToday = 0;
      eventsShownToday = 0;
      doneToday.clear();
      familyHelpThisWeek = false;
    } else if (k == LedgerKind.pocketMoney) {
      incomeThisWeek += e.unallocated;
    } else if (k == LedgerKind.planConfirmed) {
      phase = WeekPhase.living;
      depositsThisWeek += e.goal;
    } else if (k == WorldLedgerKind.jobPayout) {
      // P1: опыт — только за хорошо сделанную смену. Записи до 27.09 без
      // флага `good` считаются как раньше (каждая смена — опыт).
      if (a['good'] as bool? ?? true) experience++;
      shiftsTotal++;
      shiftsThisWeek++;
      shiftsToday++;
      final String job = a['jobId']! as String;
      shiftsByJob[job] = (shiftsByJob[job] ?? 0) + 1;
      shiftsByJobTotal[job] = (shiftsByJobTotal[job] ?? 0) + 1;
      jobsTried.add(job);
      if (shiftsToday == 1) workDays++;
      if (a['choiceOption'] != null) shiftChoicesMade++;
      final Object? luckId = a['luck'];
      if (luckId is String &&
          config.dayCycle.luck.any((ShiftLuck l) => l.id == luckId && l.good)) {
        luckyShifts++;
      }
      incomeThisWeek += e.free;
      earnedThisWeek += e.free;
      day++;
      final Object? tool = a['tool'];
      if (tool is String) {
        toolPayback[tool] =
            (toolPayback[tool] ?? 0) + (a['premium'] as int? ?? 0);
      }
      // Урок — только после смены с мини-игрой, не после смены из события.
      if (e.reasonCode == 'job.payout') {
        lessonJobId = job;
        lessonPay = e.free;
        final int n = lessonShiftsByJob[job] ?? 0;
        lessonIndex = n;
        lessonShiftsByJob[job] = n + 1;
      }
    } else if (k == WorldLedgerKind.leisure) {
      leisureHappinessThisWeek += e.happiness;
      // Досуг события из копилки (`pay_from: savings`) — снятое из ЦЕЛИ.
      depositsThisWeek += e.goal;
      day++;
    } else if (k == WorldLedgerKind.eventShown) {
      final String id = a['eventId']! as String;
      eventPrevShown[id] = eventLastShown[id] ?? -1;
      eventLastShown[id] = e.weekNo;
      pendingEventId = id;
      eventsShownThisWeek++;
      eventsShownToday++;
    } else if (k == WorldLedgerKind.eventChoice) {
      incomeThisWeek += a['income'] as int? ?? 0;
      earnedThisWeek += a['income'] as int? ?? 0;
      depositsThisWeek += e.goal;
      // Повтор эффекта в начале недели — не выбор: событие не закрывает.
      if (e.reasonCode != 'event.recurring') {
        pendingEventId = null;
        final Object? flag = a['flag'];
        if (flag is String) flagsSetWeek[flag] = e.weekNo;
        extraBill += a['extraBill'] as int? ?? 0;
        carryNextWeek += (a['energyNextWeek'] as num? ?? 0).toDouble();
        if (e.energy < 0) day++;
        final Object? rec = a['recurring'];
        if (rec is Map) {
          recurring.add((
            eventId: a['eventId']! as String,
            choiceId: a['choiceId']! as String,
            fromWeek: e.weekNo + 1,
            toWeek: e.weekNo + (a['recurringWeeks'] as int? ?? 0),
            effect: rec.cast<String, Object?>(),
          ));
        }
      }
    } else if (k == WorldLedgerKind.goalSliderDeposit) {
      depositsThisWeek += e.goal;
    } else if (k == WorldLedgerKind.envelopeTransfer) {
      // 🟡 В5 (Насте, аудит 18.10): перевод в копилку и из неё сейчас НЕ
      // считается «отложили» — depositsThisWeek, очко «откладывал» и срок до
      // цели его не видят. Решит Настя — строка ниже меняется на
      // `depositsThisWeek += e.goal;`, как у goalSliderDeposit.
      transfersTotal++;
      final Object? op = a['opId'];
      if (op is String) transferOps.add(op);
    } else if (k == LedgerKind.savingsWithdraw) {
      // T1 «отложено ≥ 10 % дохода» — чистое отложенное: снятое из копилки
      // (вручную или на счета) вычитается, иначе «положил и снял» даёт очко.
      depositsThisWeek += e.goal;
    } else if (k == WorldLedgerKind.petTapHappiness) {
      lastTapDay = day;
    } else if (k == WorldLedgerKind.finniPetted) {
      lastFinniPetDay = day;
    } else if (k == LedgerKind.purchase) {
      if (a['itemId'] == config.snackId) snacksThisWeek++;
    } else if (k == WorldLedgerKind.lessonChoice) {
      lessonsDone++;
      lessonJobId = null;
      depositsThisWeek += e.goal;
    } else if (k == WorldLedgerKind.mealEaten) {
      // Не игровой день: `day` не растёт (Денис 938: «кушаем не так часто»).
      mealsThisWeek++;
      mealsToday++;
      if (a['fromFridge'] == true) {
        final String id = a['foodId']! as String;
        final int left = (fridge[id] ?? 0) - 1;
        if (left > 0) {
          fridge[id] = left;
        } else {
          fridge.remove(id);
        }
      }
    } else if (k == WorldLedgerKind.petBought ||
        k == WorldLedgerKind.transportBought ||
        k == WorldLedgerKind.homeBought ||
        k == WorldLedgerKind.techBought ||
        k == WorldLedgerKind.itemOwned) {
      final String id = a['itemId']! as String;
      owned[id] = e.weekNo;
      if (k != WorldLedgerKind.itemOwned) {
        goalsBoughtThisWeek++;
        goalsBoughtTotal++;
      }
      if (k == WorldLedgerKind.petBought) petsOwnedTotal++;
      if (k == WorldLedgerKind.petBought) activePetId ??= id;
      if (k == WorldLedgerKind.homeBought) homeId = id;
      if (activeGoalId == id) activeGoalId = null;
    } else if (k == WorldLedgerKind.roomItemBought) {
      roomOwned[a['itemId']! as String] = e.weekNo;
    } else if (k == WorldLedgerKind.roomItemPlaced) {
      roomPlaced[a['itemId']! as String] =
          (x: a['x']! as int, y: a['y']! as int);
    } else if (k == WorldLedgerKind.roomItemRemoved) {
      roomPlaced.remove(a['itemId']! as String);
    } else if (k == WorldLedgerKind.activePetChanged) {
      activePetId = a['petId']! as String;
    } else if (k == WorldChoiceKind.goalChosen) {
      activeGoalId = a['goalId']! as String;
    } else if (k == WorldChoiceKind.foodChosen) {
      foodId = a['foodId']! as String;
    } else if (k == WorldChoiceKind.skinChosen) {
      final String id = a['itemId']! as String;
      if (skinObject(id) case final String object) chosenSkins[object] = id;
    } else if (k == WorldLedgerKind.parentBonus) {
      parentBonusThisWeek = true;
      // Бонус монетами (DEN-27, A) — доход недели, но не заработок смен.
      incomeThisWeek += e.free;
    } else if (k == WorldDemoKind.unlockAllJobs) {
      allJobsUnlocked = true;
    } else if (k == WorldDemoKind.openCity) {
      // Демо «Открыть город»: как переезд (жильё снято), плюс очки до порога.
      final String id = a['homeId']! as String;
      owned[id] = e.weekNo;
      homeId = id;
      growthPoints += a['points'] as int? ?? 0;
    } else if (k == WorldDemoKind.showEvent) {
      // Демо «Показать событие»: ждёт выбора, как показанное по расписанию,
      // но расписание (последний показ, лимит недели) не трогается.
      pendingEventId = a['eventId']! as String;
    } else if (k == WorldLedgerKind.sleep) {
      phase = WeekPhase.review;
      endedBy = WeekEnd.sleep;
      carryNextWeek += (a['carry'] as num? ?? 0).toDouble();
    } else if (k == WorldLedgerKind.achievementEarned) {
      achievementsEarned[a['id']! as String] = e.weekNo;
      if (a['day'] case final int day) {
        achievementsEarnedDay[a['id']! as String] = day;
      }
      // DEN-32: бафф награды — по её правилу в конфиге (запись несёт только
      // id; 😊 «сразу» — в самой записи).
      for (final AchievementDef d in config.achievements) {
        if (d.id != a['id']) continue;
        switch (d.effect) {
          case EnergyMaxBuff(:final double value):
            energyMaxBonus += value;
          case MoodBuff(:final int happiness, :final int days) when days > 1:
            moodBuffs.add((happiness: happiness, mornings: days - 1));
          default:
        }
      }
    } else if (k == WorldLedgerKind.familyHelp) {
      familyHelpThisWeek = true;
    } else if (k == WorldLedgerKind.fridgeStocked) {
      final String id = a['foodId']! as String;
      fridge[id] = (fridge[id] ?? 0) + (a['count']! as int);
    } else if (k == WorldLedgerKind.dayEnded) {
      dayInWeek = a['dayInWeek']! as int;
      // Утро нового дня: 😊 уже с ночным возвратом (запись несёт его сдвиг).
      happinessAtDayStart = happiness;
      mealsToday = 0;
      shiftsToday = 0;
      eventsShownToday = 0;
      // Событие без ответа живёт до конца своего дня: утро приносит новое
      // (DEN-23 «до 1 в день»). Иначе одно непосещённое «!» держало очередь
      // всю неделю. Повтор не раньше `eventRepeatWeeks` — как у показанного.
      pendingEventId = null;
      doneToday.clear();
    } else if (k == WorldLedgerKind.energyOut) {
      phase = WeekPhase.review;
      endedBy = WeekEnd.energyOut;
    } else if (k == LedgerKind.periodClosed) {
      billsPaid = true;
      growthPoints += a['points'] as int? ?? 0;
      final Object? growth = a['growth'];
      if (growth == weekGrowthFlat) flatWeeks++;
      if (growth == weekGrowthUp) flatWeeks = 0;
      if (familyHelpThisWeek) {
        noFamilyStreak = 0;
      } else {
        weeksNoFamilyHelp++;
        noFamilyStreak++;
      }
      carryNextWeek += (a['foodEnergyNext'] as num? ?? 0).toDouble();
    }
  }
}
