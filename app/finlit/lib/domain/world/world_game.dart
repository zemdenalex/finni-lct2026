import 'dart:math' as math;

import '../ledger/ledger_entry.dart' show LedgerKind;
import '../phrases.dart';
import 'contract.dart';
import 'lesson_rules.dart';
import 'onboarding_keeper.dart';
import 'week_bills.dart';
import 'week_history.dart';
import 'world_catalog.dart';
import 'world_config.dart';
import 'world_entry.dart';
import 'world_events.dart';
import 'world_fold.dart';
import 'world_mood.dart';

/// Мир Финни на журнале (карточки A2–A4).
///
/// 🔴 Хранится только append-only [journal]. Деньги, ⚡, 😊, фаза недели,
/// владение — свёртка журнала ([WorldState.fold]). Любое действие = одна
/// или несколько записей с причиной; других способов изменить число нет.
///
/// Числа — из [WorldConfig] (по умолчанию Настя v13). Загрузчик контента (A1)
/// передаёт конфиг снаружи: домен файлов не читает.
///
/// Работа, покупки, досуг и очки роста здесь — паритет с `FakeWorld`, чтобы
/// поток B видел то же поведение. Их доводят карточки A5–A8.
///
/// Работа (P1, пересмотр 27.09): ставка известна до игры; хорошая смена
/// (оценка ≥ `goodScoreMin`) — бонус до 20 % (P6), +1 опыт, сверх карточки
/// +0,5 ⚡ и −1 😊; обычная — ровно ставка без опыта. Числа — `WorldConfig`.
///
/// Радость (P7, Денис 28.09): каждый игровой день тратит немного 😊, как ⚡
/// «на жизнь» ([_dayPassed]); в итогах недели — проверка роста к прошлой
/// неделе: рост радует, застой огорчает, и тем сильнее, чем дольше длится
/// ([_growthCheck]). Цены недели — ⚡ действий и множитель оплаты — считаются
/// от 😊 на **начало** недели: день за днём радость тает, а карточки стоят
/// одинаково, и скрытые сотые ⚡ не закрывают неделю неожиданно.
class WorldGame implements World {
  WorldGame({
    this.config = const WorldConfig(),
    Iterable<WorldEntry> journal = const <WorldEntry>[],
    OnboardingProgress onboarding = const OnboardingProgress(),
    OnboardingSave? saveOnboarding,
    this.onJournalChanged,
  })  : _journal = List<WorldEntry>.of(journal),
        _onboarding = OnboardingKeeper(onboarding, saveOnboarding) {
    _state = WorldState.fold(_journal, config);
  }

  /// Восстановить мир из сохранённого журнала (перезапуск, ТЗ 2.5.13.1).
  /// Записи неизвестного вида пропускаются — их число в [unreadable].
  factory WorldGame.fromJson(
    List<Object?> json, {
    WorldConfig config = const WorldConfig(),
    OnboardingProgress onboarding = const OnboardingProgress(),
    OnboardingSave? saveOnboarding,
    void Function()? onJournalChanged,
  }) {
    final List<WorldEntry> entries = <WorldEntry>[];
    int bad = 0;
    for (final Object? raw in json) {
      final WorldEntry? e =
          raw is Map ? WorldEntry.fromJson(raw.cast<String, Object?>()) : null;
      if (e == null) {
        bad++;
      } else {
        entries.add(e);
      }
    }
    return WorldGame(
        config: config,
        journal: entries,
        onboarding: onboarding,
        saveOnboarding: saveOnboarding,
        onJournalChanged: onJournalChanged)
      ..unreadable = bad;
  }

  final WorldConfig config;

  /// Журнал пополнился (ТЗ 2.5.13.1). Зовётся на **каждую** запись, в том
  /// числе посреди действия из нескольких записей, поэтому сохранять журнал
  /// прямо отсюда нельзя — только отметить и сохранить позже, когда действие
  /// закончилось (`lib/data/world_save.dart`). Отказ записей не пишет — и не
  /// зовёт. Домен про диск не знает.
  final void Function()? onJournalChanged;
  final List<WorldEntry> _journal;
  late WorldState _state;

  /// Онбординг (A14) — профиль, не деньги: живёт вне журнала, в своём ключе
  /// `Storage`.
  final OnboardingKeeper _onboarding;

  /// Сколько записей не удалось прочитать при восстановлении.
  int unreadable = 0;

  static const double _eps = 1e-9;

  /// Журнал — только для чтения. Писать может лишь сам мир.
  List<WorldEntry> get journal => List<WorldEntry>.unmodifiable(_journal);

  List<Map<String, Object?>> toJson() =>
      _journal.map((WorldEntry e) => e.toJson()).toList();

  /// Свёрнутое состояние — для итогов недели и отладки. Свежая свёртка, а не
  /// живой объект: правка снаружи не должна менять мир мимо журнала.
  WorldState get state => WorldState.fold(_journal, config);

  void _write(
    Enum kind,
    String reasonCode, {
    int need = 0,
    int want = 0,
    int goal = 0,
    int free = 0,
    int unallocated = 0,
    double energy = 0,
    int happiness = 0,
    Map<String, Object?> args = const <String, Object?>{},
    int? weekNo,
  }) {
    final WorldEntry e = WorldEntry(
      seq: _journal.length,
      weekNo: weekNo ?? _state.weekNo,
      kind: kind,
      reasonCode: reasonCode,
      need: need,
      want: want,
      goal: goal,
      free: free,
      unallocated: unallocated,
      energy: energy,
      happiness: happiness,
      args: args,
    );
    _journal.add(e);
    _state.apply(e);
    onJournalChanged?.call();
  }

  /// Изменение 😊, которое реально случится с учётом границ 0–100.
  int _happinessDelta(int raw) =>
      (_state.happiness + raw).clamp(config.happinessMin, config.happinessMax) -
      _state.happiness;

  /// P7: игровой день прошёл — −😊, как −1 ⚡ «на жизнь». Пишется **перед**
  /// записью самого действия: если действие само меняет 😊 (досуг, хорошая
  /// смена), причиной настроения станет оно, а не день. Один раз на действие
  /// ребёнка, даже если событие пишет несколько записей. На нуле 😊 — ничего.
  void _dayPassed() {
    final int dh = _happinessDelta(-config.happinessDayDrain);
    if (dh == 0) return;
    _write(WorldLedgerKind.dayPassed, 'day.passed',
        happiness: dh, args: <String, Object?>{'day': _state.day + 1});
  }

  // ─────────────────────────────── чтение ───────────────────────────────

  @override
  ResourceSnapshot get snapshot => _state.snapshot;

  @override
  List<WeekPlanFact> get weekHistory => foldWeekHistory(_journal, (
        item: _titleOf,
        price: _priceOf,
        job: (String id, String? variant) =>
            config.job(id, variant)?.title ?? id,
        leisure: (String kind) => config.leisureKind(kind)?.title ?? kind,
        event: (String id) => config.event(id)?.title ?? id,
        treat: (String id) => config.food(id)?.treat ?? false,
      ));

  @override
  WeekPhase get phase => _state.phase;

  /// Множитель цены в ⚡ — по 😊 на начало недели (P7).
  double get _energyMult {
    final double m = 1 -
        config.energyCostMultPerPoint *
            (_state.happinessAtWeekStart - config.happinessNeutral);
    return m.clamp(config.energyCostMultMin, config.energyCostMultMax);
  }

  /// Множитель оплаты — по 😊 на начало недели (P7).
  double get _payMult {
    final double m = 1 +
        config.payMultPerPoint *
            (_state.happinessAtWeekStart - config.happinessNeutral);
    return m.clamp(config.payMultMin, config.payMultMax);
  }

  /// Цена работы в ⚡ целиком: база × настроение − транспорт + «на жизнь».
  double _jobEnergy(WorldJob job) {
    double cost = job.energy * _energyMult;
    if (_state.hasTransport) {
      cost = math.max(
          config.transportMinJobEnergy, cost - config.transportDiscount);
    }
    return roundEnergy(cost + config.livingDrainPerAction);
  }

  double _leisureEnergy(WorldLeisure l) =>
      roundEnergy(l.energy * _energyMult + config.livingDrainPerAction);

  double _payPerk(String jobId) {
    double m = 1;
    config.payPerks.forEach((String owner, ({String jobId, double mult}) p) {
      if (p.jobId == jobId && _state.owned.containsKey(owner)) m *= p.mult;
    });
    return m;
  }

  String? _lockedReason(WorldJob job) {
    final String? needs = job.needs;
    if (needs == null || _state.allJobsUnlocked) return null;
    if (needs == 'transport') {
      return _state.hasTransport
          ? null
          : 'Нужен транспорт: велосипед, самокат или скейт '
              '(${config.transportPrice}) — копи в копилке';
    }
    if (_state.hasAbility(needs)) return null;
    final WorldTech? tech = cheapestTechFor(config, needs);
    if (tech != null) {
      return 'Нужен ${tech.title.toLowerCase()} (${tech.price}) — копи в '
          'копилке';
    }
    if (_state.owned.containsKey(needs)) return null;
    return 'Откроется, когда появится ${_titleOf(needs).toLowerCase()} '
        '(${_priceOf(needs)})';
  }

  JobOffer _offerFor(WorldJob job) {
    final double growth =
        math.pow(config.experienceGrowth, _state.experience).toDouble();
    final double step = _state.stageStep;
    final int pay =
        roundTens(job.pay * growth * step * _payMult * _payPerk(job.id));
    final int left = math.max(
        0,
        math.min(
            shiftsLimitThisWeek - _state.shiftsThisWeek,
            config.maxShiftsPerJobPerWeek +
                _parentExtra -
                (_state.shiftsByJob[job.id] ?? 0)));
    final String? locked = _lockedReason(job);
    final double energyCost = _jobEnergy(job);
    return JobOffer(
      jobId: job.id,
      variant: job.variant,
      title: job.title,
      basePay: job.pay,
      experiencePercent: ((growth - 1) * 100).round(),
      stageStep: step,
      pay: pay,
      efficiencyBonusMax: roundTens(pay * config.efficiencyShare),
      energyCost: energyCost,
      shiftsLeft: left,
      goodScoreMin: config.goodScoreMin,
      goodEnergyExtra: config.goodShiftEnergyExtra,
      goodHappiness: config.goodShiftHappiness,
      lockedReason: locked,
      blockReason: _jobBlock(locked, left, energyCost),
    );
  }

  /// Почему смену нельзя взять сейчас (A13): фаза → замок → лимит → ⚡ — тот
  /// же порядок и те же коды, что у отказов [completeJob].
  BlockReason? _jobBlock(String? locked, int left, double energyCost) {
    if (_state.phase != WeekPhase.living) return _phaseBlock('job');
    if (locked != null) return BlockReason('job.locked', locked);
    if (left == 0) {
      return BlockReason(
          'job.limit',
          _state.shiftsThisWeek >= shiftsLimitThisWeek
              ? 'На этой неделе смен больше нет — хватит работать.'
              : 'На этой неделе смен здесь больше нет.',
          nextStep: 'Попробуй другую работу или отдохни');
    }
    if (_state.energy + _eps < energyCost) {
      return BlockReason(
          'job.energy', energyShortText(energyCost, _state.energy),
          nextStep: 'Перекус, досуг подешевле или «Спать»');
    }
    return null;
  }

  @override
  List<JobOffer> get jobBoard => config.jobs.map(_offerFor).toList();

  /// Бонус взрослого (ТЗ 2.5.12.3): 1 на неделе, когда он открыт, иначе 0.
  int get _parentExtra => _state.parentBonusThisWeek ? 1 : 0;

  @override
  int get shiftsLimitThisWeek => config.maxShiftsPerWeek + _parentExtra;

  @override
  bool get parentBonusThisWeek => _state.parentBonusThisWeek;

  @override
  WorldResult parentExtraShift() {
    final BlockReason? block = canDo(WorldAction.parentBonus);
    if (block != null) return block.refusal;
    _write(WorldLedgerKind.parentBonus, parentBonusCode,
        args: <String, Object?>{
          'extraShifts': 1,
          'reason': parentBonusReason,
        });
    return WorldResult(
      ok: true,
      reasonCode: parentBonusCode,
      reason: '$parentBonusReason: смен можно $shiftsLimitThisWeek вместо '
          '${config.maxShiftsPerWeek}. Монеты, ⚡ и 😊 не менялись.',
      nextStep: 'Доска «Требуется…» (S6)',
    );
  }

  @override
  bool get allJobsUnlocked => _state.allJobsUnlocked;

  @override
  WorldResult demoUnlockAllJobs() {
    if (_state.allJobsUnlocked) {
      return WorldResult.refused(
          'demo.jobs.done', 'Все профессии уже открыты.');
    }
    _write(WorldDemoKind.unlockAllJobs, 'demo.jobs');
    return const WorldResult(
      ok: true,
      reasonCode: 'demo.jobs',
      reason: 'Все профессии открыты: программист, курьер и выгульщик — без '
          'покупок. Монеты, ⚡ и 😊 не менялись.',
      nextStep: 'Доска «Требуется…» (S6)',
    );
  }

  @override
  List<({String id, String title})> get demoEvents =>
      <({String id, String title})>[
        for (final WorldEventSpec e in config.events)
          (id: e.id, title: e.title),
      ];

  @override
  WorldResult demoShowEvent(String eventId) {
    if (_state.phase != WeekPhase.living) {
      return _phaseBlock('event').refusal;
    }
    final WorldEventSpec? e = config.event(eventId);
    if (e == null) {
      return WorldResult.refused(
          'demo.event.unknown', 'Такого события нет: $eventId.');
    }
    if (_state.pendingEventId == e.id) {
      return WorldResult.refused(
          'demo.event.pending', '«${e.title}» уже ждёт выбора.');
    }
    _write(WorldDemoKind.showEvent, 'demo.event',
        args: <String, Object?>{'eventId': e.id});
    return WorldResult(
      ok: true,
      reasonCode: 'demo.event',
      reason: 'Событие недели: «${e.title}». Монеты, ⚡ и 😊 не менялись.',
      nextStep: 'Событие (S10)',
    );
  }

  @override
  JobOffer? offer(String jobId, {String? variant}) {
    final WorldJob? job = config.job(jobId, variant);
    return job == null ? null : _offerFor(job);
  }

  @override
  WeekBillParts get weeklyBillParts => (
        food: _state.foodBill,
        petFood: _state.petFoodBill,
        rent: _state.rentBill,
        extra: _state.extraBill,
      );

  @override
  double get cheapestActionEnergy {
    double best = double.infinity;
    for (final WorldLeisure l in config.leisure) {
      if (l.needsPet && !_state.hasAnyPet) continue;
      best = math.min(best, _leisureEnergy(l));
    }
    for (final JobOffer o in jobBoard) {
      if (!o.locked && o.shiftsLeft > 0) best = math.min(best, o.energyCost);
    }
    return best;
  }

  /// Что будет со счетами, если закрыть неделю сейчас. Экран показывает
  /// это до «Спать» и в диалоге «взять из копилки?» (превью «было / станет»).
  WeekBills billsPreview({bool takeFromGoal = false}) => WeekBills.compute(
        config: config,
        need: _state.need,
        want: _state.want,
        free: _state.free,
        goal: _state.goal,
        petFood: _state.petFoodBill,
        foodId: _state.foodId,
        meals: _state.mealsLeft,
        rent: _state.rentBill,
        extra: _state.extraBill,
        takeFromGoal: takeFromGoal,
      );

  int get _petCount =>
      config.pets.where((WorldPet p) => _state.owned.containsKey(p.id)).length;

  // ─────────────────── C2: A10–A14 (контракт 27.09) ───────────────────

  // ───────────────────── A10: события недели на журнале ─────────────────────
  //
  // Всё состояние событий — свёртка журнала (`WorldState`): какое ждёт
  // выбора, сколько показано за неделю, когда показано каждое, метки и
  // повторяющиеся эффекты. Здесь только правила.
  //
  // Расписание (`_rules.frequency`, решение 23.09 «по расписанию, не
  // случайно»; порядок среди подходящих — Р3, пока так):
  // - в начале недели (план подтверждён) — первое подходящее: сначала
  //   продолжения (`flag_any`), потом по кругу с (неделя − 1)-го события;
  // - внутри недели — только «реактивные» (условие по ⚡ или метке), после
  //   действий, которые меняют ⚡; после продолжения — ещё одно по кругу;
  // - не больше [WorldConfig.eventsPerWeekMax] за неделю, одно и то же — не
  //   чаще раза в [WorldConfig.eventRepeatWeeks] недель.

  WorldEventSpec? get _pendingSpec {
    if (_state.phase != WeekPhase.living) return null;
    final String? id = _state.pendingEventId;
    return id == null ? null : config.event(id);
  }

  @override
  PendingEvent? get pendingEvent {
    final WorldEventSpec? e = _pendingSpec;
    if (e == null) return null;
    return PendingEvent(
      id: e.id,
      topic: e.topic,
      title: e.title,
      text: e.situation,
      buildingId: e.buildingId,
      choices: <PendingEventChoice>[
        for (final WorldEventOptionSpec o in _visibleOptions(e))
          PendingEventChoice(
            id: o.id,
            label: o.label,
            preview: _preview(o),
            blockReason: _choiceBlock(o),
          ),
      ],
    );
  }

  @override
  String? get eventBuildingId => _pendingSpec?.buildingId;

  /// Метка свежая: поставлена раньше этой недели и после прошлого показа
  /// события [e]. [shown] — событие уже показано на этой неделе (тогда
  /// «прошлый показ» — тот, что был до нынешнего).
  bool _flagFresh(String flag, WorldEventSpec e, {required bool shown}) {
    final int? set = _state.flagsSetWeek[flag];
    if (set == null || set >= _state.weekNo) return false;
    final int since = shown
        ? _state.eventPrevShown[e.id] ?? -1
        : _state.eventLastShown[e.id] ?? -1;
    return set > since;
  }

  /// Варианты показанного события: у варианта с `conditions.flag` — только
  /// при свежей метке.
  List<WorldEventOptionSpec> _visibleOptions(WorldEventSpec e) =>
      <WorldEventOptionSpec>[
        for (final WorldEventOptionSpec o in e.options)
          if (o.conditions.flag == null ||
              _flagFresh(o.conditions.flag!, e, shown: true))
            o,
      ];

  /// Цель, о которой говорит событие: `transport` — активная цель, если это
  /// транспорт, иначе первый транспорт каталога.
  String _eventGoalItem(String goal) {
    if (goal != 'transport') return goal;
    final String? active = _state.activeGoalId;
    if (active != null && config.transports.containsKey(active)) return active;
    return config.transports.keys.isEmpty ? goal : config.transports.keys.first;
  }

  bool _eligible(WorldEventSpec e) {
    final EventConditions c = e.conditions;
    final int w = _state.weekNo;
    final int? last = _state.eventLastShown[e.id];
    if (last != null && w - last < config.eventRepeatWeeks) return false;
    if (c.minWeek != null && w < c.minWeek!) return false;
    if (c.hasPet != null && _state.hasAnyPet != c.hasPet) return false;
    if (c.noTransport != null && _state.hasTransport == c.noTransport) {
      return false;
    }
    final String? goal = c.savingsGoal;
    if (goal != null) {
      final String item = _eventGoalItem(goal);
      if (_alreadyHas(item)) return false;
      if (_state.goal + _eps < _priceOf(item) * (c.savingsShare ?? 0)) {
        return false;
      }
    }
    if (c.energyMin != null && _state.energy + _eps < c.energyMin!) {
      return false;
    }
    if (c.energyMax != null && _state.energy - _eps > c.energyMax!) {
      return false;
    }
    if (c.flagAny.isNotEmpty &&
        !c.flagAny.any((String f) => _flagFresh(f, e, shown: false))) {
      return false;
    }
    return true;
  }

  /// Порядок проверки: продолжения, потом по кругу с (неделя − 1)-го.
  List<WorldEventSpec> get _eventOrder {
    final List<WorldEventSpec> all = config.events;
    final int n = all.length;
    if (n == 0) return const <WorldEventSpec>[];
    final int start = (math.max(1, _state.weekNo) - 1) % n;
    final List<WorldEventSpec> ring = <WorldEventSpec>[
      for (int i = 0; i < n; i++) all[(start + i) % n],
    ];
    return <WorldEventSpec>[
      ...ring.where((WorldEventSpec e) => e.conditions.flagAny.isNotEmpty),
      ...ring.where((WorldEventSpec e) => e.conditions.flagAny.isEmpty),
    ];
  }

  /// Показать событие, если пора: запись `eventShown`. [weekOpening] —
  /// план только что подтверждён; иначе — только реактивные, а
  /// [allowRing] разрешает ещё одно по кругу (после продолжения).
  void _maybeShowEvent({required bool weekOpening, bool allowRing = false}) {
    if (_state.phase != WeekPhase.living || _state.pendingEventId != null) {
      return;
    }
    if (_state.eventsShownThisWeek >= config.eventsPerWeekMax) return;
    for (final WorldEventSpec e in _eventOrder) {
      if (!weekOpening && !allowRing && !e.conditions.reactive) continue;
      if (!_eligible(e)) continue;
      _write(WorldLedgerKind.eventShown, 'event.shown', args: <String, Object?>{
        'eventId': e.id,
        'topic': e.topic,
        'building': e.buildingId,
      });
      return;
    }
  }

  int _pocketShare(double x) => (config.pocketMoney * x).round();

  int _eventBuyPrice(EventEffects f) =>
      (_priceOf(f.buy!) * (1 - f.discount)).round();

  int _eventGoalPrice(EventEffects f, String item) =>
      (_priceOf(item) * (1 - f.goalDiscountShare)).round();

  /// 😊 досуга до недельного потолка: база + `per_extra_pet` за каждого
  /// питомца сверх первого.
  int _leisureRaw(WorldLeisure l) =>
      l.happiness + l.perExtraPet * math.max(0, _petCount - 1);

  int _leisureGain(WorldLeisure l) {
    final int raw = _leisureRaw(l);
    return math.max(
        0,
        math.min(
            raw, config.leisureWeeklyCap - _state.leisureHappinessThisWeek));
  }

  /// Почему вариант недоступен (`_rules.affordability`, ТЗ 2.5.6.4) — те же
  /// коды, что у досуга, покупки и смены; остальное — `event.*`.
  BlockReason? _choiceBlock(WorldEventOptionSpec o) {
    final EventEffects f = o.effects;
    final int pockets = _state.want + _state.free;
    int wallet = 0;
    int goal = 0;
    double energy = 0;

    final String? kind = f.leisure;
    if (kind != null) {
      final WorldLeisure? l = config.leisureKind(kind);
      if (l == null) {
        return BlockReason('leisure.unknown', 'Такого отдыха нет: $kind.');
      }
      if (l.needsPet && _petCount == 0) {
        return const BlockReason('leisure.no_pet', 'Сначала нужен питомец.');
      }
      final double cost = _leisureEnergy(l);
      if (_state.energy + _eps < cost) {
        return BlockReason(
            'leisure.energy', energyShortText(cost, _state.energy));
      }
      if (f.payFromSavings) {
        if (_state.goal < l.price) {
          return BlockReason('event.goal_short',
              'В копилке ${_state.goal}, а нужно ${l.price}.');
        }
        goal += l.price;
      } else {
        if (pockets < l.price) {
          return BlockReason(
              'leisure.short', 'Не хватает ${l.price - pockets}.');
        }
        wallet += l.price;
      }
      energy += cost;
    }

    final String? item = f.buy;
    if (item != null) {
      if ((config.cloth(item) ?? config.decorItem(item)) == null) {
        return BlockReason('buy.unknown', 'Такого в магазине нет: $item.');
      }
      if (_state.owned.containsKey(item)) {
        return const BlockReason('buy.owned', 'Это у Финни уже есть.');
      }
      final int price = _eventBuyPrice(f);
      if (pockets < price) {
        return BlockReason('buy.short', 'Не хватает ${price - pockets}.');
      }
      wallet += price;
    }

    final String? jobId = f.shift;
    if (jobId != null) {
      final WorldJob? job = config.job(jobId, null);
      if (job == null) {
        return BlockReason('job.unknown', 'Такой работы нет: $jobId.');
      }
      final JobOffer offer = _offerFor(job);
      if (offer.blockReason != null) return offer.blockReason;
      energy += offer.energyCost;
    }

    final String? goalRef = f.goalDiscountGoal;
    if (goalRef != null) {
      final String target = _eventGoalItem(goalRef);
      if (!_isGoalItem(target)) {
        return BlockReason('goal.unknown', 'Такой цели нет: $target.');
      }
      if (_alreadyHas(target)) {
        return const BlockReason('buy.owned', 'Это у Финни уже есть.');
      }
      goal += _eventGoalPrice(f, target);
    }

    if (f.savingsX < 0) goal += _pocketShare(-f.savingsX);
    if (f.savingsX > 0 && f.savingsFrom != SavingsSource.gift) {
      wallet += _pocketShare(f.savingsX);
    }
    if (f.moneyX < 0) wallet += _pocketShare(-f.moneyX);
    if (f.energy < 0) energy -= f.energy;

    if (_state.goal < goal) {
      return BlockReason(
          'event.goal_short', 'В копилке ${_state.goal}, а нужно $goal.');
    }
    if (pockets < wallet) {
      return BlockReason('event.short', 'Не хватает ${wallet - pockets}.');
    }
    if (_state.energy + _eps < energy) {
      return BlockReason(
          'event.energy', energyShortText(energy, _state.energy));
    }
    return null;
  }

  /// Что изменится — до выбора. 😊 — примерно (до границ 0–100).
  EffectPreview _preview(WorldEventOptionSpec o) {
    final EventEffects f = o.effects;
    int coins = _pocketShare(f.moneyX);
    int goal = 0;
    double energy = f.energy;
    int happiness = f.happiness;

    final int saved = _pocketShare(f.savingsX);
    goal += saved;
    if (saved > 0 && f.savingsFrom != SavingsSource.gift) coins -= saved;

    final String? kind = f.leisure;
    final WorldLeisure? l = kind == null ? null : config.leisureKind(kind);
    if (l != null) {
      if (f.payFromSavings) {
        goal -= l.price;
      } else {
        coins -= l.price;
      }
      energy -= _leisureEnergy(l);
      happiness += _leisureGain(l);
    }
    final String? item = f.buy;
    final WorldItem? thing =
        item == null ? null : config.cloth(item) ?? config.decorItem(item);
    if (thing != null) {
      coins -= _eventBuyPrice(f);
      happiness += thing.happinessByWeek.first;
    }
    final WorldJob? job = f.shift == null ? null : config.job(f.shift!, null);
    if (job != null) {
      final JobOffer offer = _offerFor(job);
      coins += offer.pay;
      energy -= offer.energyCost;
    }
    final String? goalRef = f.goalDiscountGoal;
    if (goalRef != null) {
      goal -= _eventGoalPrice(f, _eventGoalItem(goalRef));
      happiness += config.goalReachedBonus;
    }
    // P7: выбор, который тратит ⚡, — игровой день (как в [resolveEvent]).
    if (f.energy < 0 || l != null || job != null) {
      happiness -= config.happinessDayDrain;
    }
    return EffectPreview(
      coins: coins,
      goal: goal,
      energy: roundEnergy(energy),
      happiness: _happinessDelta(happiness),
      weeklyBill: _pocketShare(f.requiredExtraX),
    );
  }

  static String _sourceName(SavingsSource s) => switch (s) {
        SavingsSource.gift => 'gift',
        SavingsSource.wallet => 'wallet',
        SavingsSource.pocketMoney => 'pocket_money',
      };

  /// Эффект `recurring` в форме `events.json` — пишется в журнал выбора.
  static Map<String, Object?> _recurringJson(EventEffects r) =>
      <String, Object?>{
        if (r.moneyX != 0) 'money_pocket_x': r.moneyX,
        if (r.savingsX != 0) 'savings_pocket_x': r.savingsX,
        if (r.savingsX != 0) 'savings_from': _sourceName(r.savingsFrom),
        if (r.happiness != 0) 'happiness': r.happiness,
      };

  @override
  WorldResult resolveEvent(String choiceId) {
    final BlockReason? block = canDo(WorldAction.resolveEvent, id: choiceId);
    if (block != null) return block.refusal;
    final WorldEventSpec e = _pendingSpec!;
    final WorldEventOptionSpec o = e.option(choiceId)!;
    final EventEffects f = o.effects;
    final ResourceSnapshot before = _state.snapshot;
    final Map<String, Object?> base = <String, Object?>{
      'eventId': e.id,
      'choiceId': o.id,
    };

    // Симуляция «понарошку»: счёт считается один раз и пишется в журнал.
    final SlotSimSpec? simSpec = f.simulation == null ? null : e.simulation;
    final ({int spent, int won, int? accessorySpin})? sim =
        simSpec?.run(_journal.length);
    final String say = finniLine(
      o.finni,
      _onboarding.progress.nickname,
      sim == null
          ? const <String, String>{}
          : <String, String>{'spent': '${sim.spent}', 'won': '${sim.won}'},
    );

    // 1. Сам выбор: прямые деньги, копилка, ⚡, 😊, метка, добавка к счёту.
    int want = 0;
    int free = 0;
    int goal = 0;
    int income = 0;
    int wantLeft = _state.want;
    void spend(int amount) {
      final int w = math.min(wantLeft, amount);
      wantLeft -= w;
      want -= w;
      free -= amount - w;
    }

    final int money = _pocketShare(f.moneyX);
    if (money > 0) {
      free += money;
      income += money;
    } else if (money < 0) {
      spend(-money);
    }
    final int saved = _pocketShare(f.savingsX);
    goal += saved;
    if (saved > 0) {
      if (f.savingsFrom == SavingsSource.gift) {
        income += saved;
      } else {
        spend(saved);
      }
    }
    final double de = roundEnergy(f.energy < 0
        ? -math.min(-f.energy, _state.energy)
        : math.min(f.energy, math.max(0.0, config.energyMax - _state.energy)));
    final int extra = _pocketShare(f.requiredExtraX);
    final EventEffects? rec = f.recurring;
    // Цены досуга и смены — как на кнопке, до записи выбора: 😊 выбора
    // меняет множитель ⚡, и проверка «хватает ли» должна совпасть с тратой.
    final String? kind = f.leisure;
    final WorldLeisure? l = kind == null ? null : config.leisureKind(kind);
    final double leisureCost = l == null ? 0 : _leisureEnergy(l);
    final int leisureGain = l == null ? 0 : _leisureGain(l);
    final String? jobId = f.shift;
    final JobOffer? shift =
        jobId == null ? null : _offerFor(config.job(jobId, null)!);
    // P7: выбор, который тратит ⚡, — игровой день; один раз на выбор.
    if (de < 0 || l != null || shift != null) _dayPassed();
    _write(WorldLedgerKind.eventChoice, 'event.choice',
        want: want,
        free: free,
        goal: goal,
        energy: de,
        happiness: _happinessDelta(f.happiness),
        args: <String, Object?>{
          ...base,
          'topic': e.topic,
          'reason': say,
          if (f.flag != null) 'flag': f.flag,
          if (extra != 0) 'extraBill': extra,
          if (f.energyNextWeek != 0) 'energyNextWeek': f.energyNextWeek,
          if (income > 0) 'income': income,
          if (rec != null) 'recurring': _recurringJson(rec),
          if (rec != null) 'recurringWeeks': f.recurringWeeks,
        });

    // 2. Последствия — каждое своей записью с причиной `event.*`.
    bool spentEnergy = de < 0;
    if (l != null) {
      final ({int want, int free}) pay =
          f.payFromSavings ? (want: 0, free: 0) : _fromWantThenFree(l.price)!;
      _write(WorldLedgerKind.leisure, 'event.leisure',
          want: -pay.want,
          free: -pay.free,
          goal: f.payFromSavings ? -l.price : 0,
          energy: -math.min(leisureCost, _state.energy),
          happiness: _happinessDelta(leisureGain),
          args: <String, Object?>{
            ...base,
            'kind': kind,
            'price': l.price,
            if (f.payFromSavings) 'fromGoal': true,
          });
      spentEnergy = true;
    }
    final String? item = f.buy;
    if (item != null) {
      final WorldItem thing = (config.cloth(item) ?? config.decorItem(item))!;
      final int price = _eventBuyPrice(f);
      final ({int want, int free}) pay = _fromWantThenFree(price)!;
      _write(WorldLedgerKind.itemOwned, 'event.buy',
          want: -pay.want,
          free: -pay.free,
          happiness: _happinessDelta(thing.happinessByWeek.first),
          args: <String, Object?>{
            ...base,
            'itemId': item,
            'price': price,
            'discount': f.discount,
          });
    }
    if (shift != null) {
      // Смена из события — обычная (без мини-игры): ставка карточки, без
      // опыта и бонуса, засчитывается в лимиты смен.
      final Map<String, Object?> job = <String, Object?>{
        ...base,
        'jobId': jobId,
        'pay': shift.pay,
      };
      _write(WorldLedgerKind.jobStarted, 'event.shift', args: job);
      _write(WorldLedgerKind.jobPayout, 'event.shift',
          free: shift.pay,
          energy: -math.min(shift.energyCost, _state.energy),
          args: <String, Object?>{
            ...job,
            'bonus': 0,
            'score': 0.0,
            'good': false,
          });
      spentEnergy = true;
    }
    final String? goalRef = f.goalDiscountGoal;
    if (goalRef != null) {
      final String target = _eventGoalItem(goalRef);
      final int price = _eventGoalPrice(f, target);
      final WorldLedgerKind bought = config.pet(target) != null
          ? WorldLedgerKind.petBought
          : config.transports.containsKey(target)
              ? WorldLedgerKind.transportBought
              : config.tech(target) != null
                  ? WorldLedgerKind.techBought
                  : WorldLedgerKind.homeBought;
      _write(bought, 'event.goal_discount',
          goal: -price,
          happiness: _happinessDelta(config.goalReachedBonus),
          args: <String, Object?>{
            ...base,
            'itemId': target,
            'price': price,
            'discount': f.goalDiscountShare,
          });
    }
    if (sim != null) {
      _write(WorldLedgerKind.simulationRun, 'event.simulation',
          args: <String, Object?>{
            ...base,
            'simulation': simSpec!.id,
            'spent': sim.spent,
            'won': sim.won,
            if (sim.accessorySpin != null) 'accessory': simSpec.accessoryName,
            if (sim.accessorySpin != null) 'accessorySpin': sim.accessorySpin,
          });
    }

    final String tail = spentEnergy ? _afterEnergySpent() : '';
    _maybeShowEvent(
        weekOpening: false, allowRing: e.conditions.flagAny.isNotEmpty);
    final ResourceSnapshot after = _state.snapshot;
    return WorldResult(
      ok: true,
      reasonCode: 'event.choice',
      reason: '$say$tail',
      nextStep: o.nextStep,
      coins: after.available - before.available,
      goal: after.goal - before.goal,
      energy: roundEnergy(after.energy - before.energy),
      happiness: after.happiness - before.happiness,
    );
  }

  /// Повтор эффектов выбора в начале недели (`recurring`): запись
  /// `eventChoice` с причиной `event.recurring` на каждый действующий.
  /// Автоматический: не хватает — берётся сколько есть, без отказа.
  ({int coins, int goal}) _applyRecurring() {
    int coins = 0;
    int goal = 0;
    final int w = _state.weekNo;
    final List<ActiveRecurring> due = _state.recurring
        .where((ActiveRecurring r) => r.fromWeek <= w && w <= r.toWeek)
        .toList();
    for (final ActiveRecurring r in due) {
      final EventEffects f = EventEffects.fromJson(
          r.effect, 'recurring ${r.eventId}/${r.choiceId}',
          recurring: true);
      int unallocated = 0;
      int want = 0;
      int free = 0;
      int g = 0;
      int income = 0;
      int unallocLeft = _state.unallocated;
      int wantLeft = _state.want;
      int freeLeft = _state.free;
      int take(int amount, {required bool pocketFirst}) {
        int left = amount;
        if (pocketFirst) {
          final int u = math.min(unallocLeft, left);
          unallocLeft -= u;
          unallocated -= u;
          left -= u;
        }
        final int a = math.min(wantLeft, left);
        wantLeft -= a;
        want -= a;
        left -= a;
        final int b = math.min(freeLeft, left);
        freeLeft -= b;
        free -= b;
        left -= b;
        return amount - left;
      }

      final int money = _pocketShare(f.moneyX);
      if (money > 0) {
        free += money;
        income += money;
      } else if (money < 0) {
        take(-money, pocketFirst: true);
      }
      final int saved = _pocketShare(f.savingsX);
      if (saved > 0) {
        switch (f.savingsFrom) {
          case SavingsSource.gift:
            g += saved;
            income += saved;
          case SavingsSource.pocketMoney:
            final int u = math.min(unallocLeft, saved);
            unallocLeft -= u;
            unallocated -= u;
            g += u;
          case SavingsSource.wallet:
            g += take(saved, pocketFirst: false);
        }
      } else if (saved < 0) {
        g -= math.min(-saved, _state.goal);
      }
      final int dh = _happinessDelta(f.happiness);
      if (unallocated == 0 && want == 0 && free == 0 && g == 0 && dh == 0) {
        continue;
      }
      _write(WorldLedgerKind.eventChoice, 'event.recurring',
          unallocated: unallocated,
          want: want,
          free: free,
          goal: g,
          happiness: dh,
          args: <String, Object?>{
            'eventId': r.eventId,
            'choiceId': r.choiceId,
            'week': w - r.fromWeek + 1,
            'weeks': r.toWeek - r.fromWeek + 1,
            if (income > 0) 'income': income,
          });
      coins += unallocated + want + free;
      goal += g;
    }
    return (coins: coins, goal: goal);
  }

  @override
  List<WorldCatalogItem> get catalog =>
      catalogFromConfig(config, leisureEnergy: _leisureEnergy);

  @override
  WorldCatalogItem? catalogItem(String id) => findCatalogItem(catalog, id);

  @override
  OnboardingProgress get onboarding => _onboarding.progress;

  @override
  Future<WorldResult> setNickname(String nickname) =>
      _onboarding.setNickname(nickname);

  @override
  Future<WorldResult> setFinniLook(
          {String? species, FinniGender? gender, int? look}) =>
      _onboarding.setFinniLook(species: species, gender: gender, look: look);

  @override
  Future<WorldResult> setFinniName(String name) =>
      _onboarding.setFinniName(name);

  @override
  Future<WorldResult> setOnboardingStep(int step) => _onboarding.setStep(step);

  /// A13. Правила отказа — одни на проверку заранее и на само действие:
  /// действия начинаются с `canDo`, поэтому расхождения быть не может.
  @override
  BlockReason? canDo(WorldAction action, {String? id, String? variant}) {
    final WeekPhase p = _state.phase;
    final String key = id ?? '';
    switch (action) {
      case WorldAction.startWeek:
        if (p == WeekPhase.review && !_state.billsPaid) {
          return const BlockReason(
              'week.bills_first', 'Сначала закроем счета этой недели.');
        }
        if (p != WeekPhase.onboarding && p != WeekPhase.review) {
          return _phaseBlock('startWeek');
        }
        return null;
      case WorldAction.plan:
        return p == WeekPhase.planning ? null : _phaseBlock('plan');
      case WorldAction.chooseGoal:
        if (!_isGoalItem(key)) {
          return BlockReason('goal.unknown', 'Такой цели нет: $key.');
        }
        if (_alreadyHas(key)) {
          return const BlockReason('goal.owned', 'Это у Финни уже есть.');
        }
        return null;
      case WorldAction.chooseFood:
        if (config.food(key) == null) {
          return BlockReason('food.unknown', 'Такой еды нет: $key.');
        }
        if (p != WeekPhase.planning && p != WeekPhase.living) {
          return _phaseBlock('chooseFood');
        }
        return null;
      case WorldAction.eat:
        return _eatBlock(key);
      case WorldAction.job:
        if (p != WeekPhase.living) return _phaseBlock('job');
        final WorldJob? job = config.job(key, variant);
        if (job == null) {
          return BlockReason('job.unknown', 'Такой работы нет: $key.');
        }
        return _offerFor(job).blockReason;
      case WorldAction.buy:
        return _buyBlock(key);
      case WorldAction.leisure:
        return _leisureBlock(key);
      case WorldAction.sleep:
        return p == WeekPhase.living ? null : _phaseBlock('sleep');
      case WorldAction.payBills:
        if (p != WeekPhase.review) return _phaseBlock('payBills');
        if (_state.billsPaid) {
          return const BlockReason(
              'bills.paid', 'Счета этой недели уже закрыты.');
        }
        return null;
      case WorldAction.resolveEvent:
        if (p != WeekPhase.living) return _phaseBlock('event');
        final WorldEventSpec? ev = _pendingSpec;
        if (ev == null) {
          return const BlockReason('event.none', 'Сейчас событий нет.');
        }
        if (id == null) return null;
        for (final WorldEventOptionSpec o in _visibleOptions(ev)) {
          if (o.id == id) return _choiceBlock(o);
        }
        return BlockReason('event.unknown', 'Такого варианта нет: $id.');
      case WorldAction.parentBonus:
        if (p != WeekPhase.living) return _phaseBlock('parentBonus');
        if (_state.parentBonusThisWeek) return parentBonusDone;
        return null;
    }
  }

  BlockReason? _buyBlock(String itemId) {
    if (_state.phase != WeekPhase.living) return _phaseBlock('buy');
    final int price = _priceOf(itemId);
    if (_isGoalItem(itemId)) {
      if (_alreadyHas(itemId)) {
        return const BlockReason('buy.owned', 'Это у Финни уже есть.');
      }
      final BlockReason? move = _moveBlock(itemId);
      if (move != null) return move;
      if (_state.goal < price) {
        return BlockReason(
            'buy.goal_short', 'Не хватает ${price - _state.goal} в копилке.',
            nextStep: 'Смена на работе или отложить с заработка');
      }
      return null;
    }
    if (itemId == config.snackId) {
      if (_state.snacksThisWeek >= config.snackMaxPerWeek) {
        return const BlockReason(
            'buy.snack_limit', 'Перекусов на этой неделе хватит.');
      }
      if (_fromWantThenFree(price) == null) {
        return BlockReason(
            'buy.short', 'Не хватает ${price - _state.want - _state.free}.');
      }
      return null;
    }
    if ((config.cloth(itemId) ?? config.decorItem(itemId)) == null) {
      return BlockReason('buy.unknown', 'Такого в магазине нет: $itemId.');
    }
    if (_state.owned.containsKey(itemId)) {
      return const BlockReason('buy.owned', 'Это у Финни уже есть.');
    }
    if (_fromWantThenFree(price) == null) {
      return BlockReason(
          'buy.short', 'Не хватает ${price - _state.want - _state.free}.',
          nextStep: 'Смена на работе или подождать неделю');
    }
    return null;
  }

  /// Почему сейчас нельзя поесть [foodId]: фаза → блюдо → приёмы недели →
  /// деньги. Не хватает — называем, что можно подешевле (ТЗ 2.5.6.4).
  BlockReason? _eatBlock(String foodId) {
    final WorldFood? f = config.food(foodId);
    if (f == null) {
      return BlockReason('food.unknown', 'Такой еды нет: $foodId.');
    }
    if (_state.phase != WeekPhase.living) return _phaseBlock('eat');
    if (_state.mealsLeft == 0) {
      return BlockReason(
          'eat.limit',
          'На этой неделе Финни уже поел ${config.mealsPerWeek} '
              '${Phrases.timesWord(config.mealsPerWeek)} — он сыт.',
          nextStep: 'Новая неделя — новые обеды');
    }
    final int pockets = _state.pockets;
    if (pockets < f.price) {
      WorldFood? cheaper;
      for (final WorldFood o in config.foods) {
        if (o.price <= pockets &&
            (cheaper == null || o.price > cheaper.price)) {
          cheaper = o;
        }
      }
      return BlockReason('eat.short', 'Не хватает ${f.price - pockets}.',
          nextStep: cheaper == null
              ? 'Смена на работе — или Финни поест дома в конце недели'
              : 'Можно подешевле: ${cheaper.title}, ${cheaper.price}');
    }
    return null;
  }

  BlockReason? _leisureBlock(String kind) {
    if (_state.phase != WeekPhase.living) return _phaseBlock('leisure');
    final WorldLeisure? l = config.leisureKind(kind);
    if (l == null) {
      return BlockReason('leisure.unknown', 'Такого отдыха нет: $kind.');
    }
    if (l.needsPet && _petCount == 0) {
      return const BlockReason('leisure.no_pet', 'Сначала нужен питомец.');
    }
    final double cost = _leisureEnergy(l);
    if (_state.energy + _eps < cost) {
      return BlockReason(
          'leisure.energy', energyShortText(cost, _state.energy));
    }
    if (_fromWantThenFree(l.price) == null) {
      return BlockReason('leisure.short',
          'Не хватает ${l.price - _state.want - _state.free}.');
    }
    return null;
  }

  // ────────────────────────────── действия ──────────────────────────────

  WorldResult _wrongPhase(String what) => _phaseBlock(what).refusal;

  BlockReason _phaseBlock(String what) => BlockReason(
        'phase.$what',
        switch (_state.phase) {
          WeekPhase.onboarding => 'Сначала начнём первую неделю.',
          WeekPhase.weekStart ||
          WeekPhase.planning =>
            'Сначала план недели: разложи карманные по конвертам.',
          WeekPhase.living => 'Неделя ещё идёт.',
          WeekPhase.review => 'Неделя уже кончилась — посмотрим итоги.',
        },
      );

  @override
  WorldResult startWeek() {
    final BlockReason? block = canDo(WorldAction.startWeek);
    if (block != null) return block.refusal;
    final WeekPhase p = _state.phase;
    final bool first = p == WeekPhase.onboarding;
    final int weekNo = _state.weekNo + 1;
    final double homeEnergy = config.home(_state.homeId)?.energyPerWeek ?? 0;
    final double energy = roundEnergy(math.min(config.energyMax,
        config.energyBasePerWeek + homeEnergy + _state.carryNextWeek));
    _write(WorldLedgerKind.weekStarted, first ? 'week.first' : 'week.start',
        weekNo: weekNo,
        energy: roundEnergy(energy - _state.energy),
        args: <String, Object?>{'energyStart': energy});
    _write(LedgerKind.pocketMoney, 'week.pocket_money',
        unallocated: config.pocketMoney,
        args: <String, Object?>{'amount': config.pocketMoney});
    if (first && config.startGift > 0) {
      _write(WorldLedgerKind.startGift, 'week.start_gift',
          goal: config.startGift,
          args: <String, Object?>{'amount': config.startGift});
    }
    final int gift = first ? config.startGift : 0;
    final ({int coins, int goal}) rec = _applyRecurring();
    return WorldResult(
      ok: true,
      reasonCode: first ? 'week.first' : 'week.start',
      reason: (first
              ? 'Финни переехал! Стипендия за учёбу — ${config.pocketMoney}'
                  '${gift > 0 ? ', и подарок $gift уже в копилке' : ''}.'
              : 'Неделя $weekNo. Пришла стипендия — ${config.pocketMoney}.') +
          (rec.goal > 0 ? ' По челленджу в копилку ушло ${rec.goal}.' : ''),
      nextStep:
          'Счёт недели от ${_state.weeklyBill} — разложи монеты по конвертам',
      coins: config.pocketMoney + rec.coins,
      goal: gift + rec.goal,
      energy: energy,
    );
  }

  @override
  WorldResult plan(
      {required int needs, required int wants, required int goal}) {
    final BlockReason? block = canDo(WorldAction.plan);
    if (block != null) return block.refusal;
    if (needs < 0 || wants < 0 || goal < 0) {
      return const WorldResult.refused(
          'plan.negative', 'В конверт нельзя положить меньше нуля.');
    }
    final int have = _state.unallocated;
    final int total = needs + wants + goal;
    if (total > have) {
      return WorldResult.refused('plan.too_much',
          'Разложено $total, а есть $have. Убери ${total - have}.');
    }
    final int rest = have - total;
    _write(LedgerKind.planConfirmed, 'plan.confirmed',
        unallocated: -have,
        need: needs,
        want: wants,
        goal: goal,
        free: rest,
        args: <String, Object?>{
          'need': needs,
          'want': wants,
          'goal': goal,
          'free': rest,
        });
    _maybeShowEvent(weekOpening: true);
    final int bill = _state.weeklyBill;
    return WorldResult(
      ok: true,
      reasonCode: 'plan.confirmed',
      reason: 'План готов: нужно $needs, хочу $wants, цель $goal.',
      nextStep: needs < bill
          ? 'На счета не хватает ${bill - needs} — можно взять смену'
          : null,
      coins: -goal,
      goal: goal,
    );
  }

  bool _isGoalItem(String id) =>
      config.pet(id) != null ||
      config.transports.containsKey(id) ||
      config.tech(id) != null ||
      (config.home(id)?.isGoal ?? false);

  /// Какой инструмент «работает» на этой смене и сколько он принёс сверх
  /// лучшей работы, открытой с первого дня (её ставка сейчас, с теми же
  /// опытом, стадией и 😊). null — работа без инструмента или открыта демо.
  ({String tool, int premium})? _toolCredit(WorldJob job, int pay) {
    final String? needs = job.needs;
    if (needs == null) return null;
    String? tool;
    if (needs == 'transport') {
      for (final String id in config.transports.keys) {
        if (_state.owned.containsKey(id)) tool ??= id;
      }
    } else {
      for (final WorldTech t in config.techs) {
        if (t.unlocks.contains(needs) && _state.owned.containsKey(t.id)) {
          tool ??= t.id;
        }
      }
    }
    if (tool == null) return null;
    int base = 0;
    for (final WorldJob j in config.jobs) {
      if (j.needs != null) continue;
      final int p = _offerFor(j).pay;
      if (p > base) base = p;
    }
    return (tool: tool, premium: math.max(0, pay - base));
  }

  /// Переезд = аренда (Денис 941 п. 3): жильё стадии выше нынешней
  /// открывается очками роста (решения за несколько недель, ТЗ 2.5.10.2).
  BlockReason? _moveBlock(String homeId) {
    final WorldHome? h = config.home(homeId);
    final WorldStage? to = h?.stage;
    if (!config.stageByRent || h == null || to == null) return null;
    final int need = to.index < config.stageMinPoints.length
        ? config.stageMinPoints[to.index]
        : 0;
    if (_state.growthPoints >= need) return null;
    return BlockReason(
        'buy.points',
        'Переезд откроется при $need очках роста — сейчас '
            '${_state.growthPoints}.',
        nextStep: 'Очки роста — за счета своими деньгами, план и отложенное');
  }

  /// Уже есть: сама вещь, любой транспорт вместо транспорта, техника, чьи
  /// возможности уже даёт купленная (мощный ноутбук вместо простого).
  bool _alreadyHas(String id) {
    if (_state.owned.containsKey(id)) return true;
    if (config.transports.containsKey(id)) return _state.hasTransport;
    // Жильё не хуже нынешнего — «уже есть»: назад переезжать незачем.
    final WorldStage? to = config.home(id)?.stage;
    if (config.stageByRent && to != null) {
      final WorldStage now =
          config.home(_state.homeId)?.stage ?? WorldStage.village;
      if (to.index <= now.index) return true;
    }
    final WorldTech? t = config.tech(id);
    return t != null && t.unlocks.every(_state.hasAbility);
  }

  @override
  WorldResult chooseGoal(String goalId) {
    final BlockReason? block = canDo(WorldAction.chooseGoal, id: goalId);
    if (block != null) return block.refusal;
    _write(WorldChoiceKind.goalChosen, 'goal.chosen',
        args: <String, Object?>{'goalId': goalId});
    return WorldResult(
      ok: true,
      reasonCode: 'goal.chosen',
      reason: 'Копим на цель: ${_titleOf(goalId)}, ${_priceOf(goalId)}.',
    );
  }

  @override
  WorldResult chooseFood(String foodId) {
    final BlockReason? block = canDo(WorldAction.chooseFood, id: foodId);
    if (block != null) return block.refusal;
    final WorldFood food = config.food(foodId)!;
    _write(WorldChoiceKind.foodChosen, 'food.chosen',
        args: <String, Object?>{'foodId': foodId});
    return WorldResult(
      ok: true,
      reasonCode: 'food.chosen',
      reason: 'Дома Финни ест: ${food.title}, ${food.price} за приём. '
          'Счёт недели: ${_state.weeklyBill}.',
    );
  }

  /// Конец недели по ⚡ после действия, которое её тратит: ⚡ не хватает ни
  /// на одно действие (`economy.json → week._note`). Ровно 0 — тоже сюда.
  String _afterEnergySpent() {
    if (_state.energy + _eps >= cheapestActionEnergy) return '';
    _write(WorldLedgerKind.energyOut, 'week.energy_out',
        happiness: _happinessDelta(config.exhaustedHappiness));
    return ' Силы кончились — Финни устал и лёг спать.';
  }

  @override
  WorldResult completeJob(String jobId,
      {String? variant, required double score}) {
    final BlockReason? block =
        canDo(WorldAction.job, id: jobId, variant: variant);
    if (block != null) return block.refusal;
    final JobOffer o = _offerFor(config.job(jobId, variant)!);
    final int happinessBefore = _state.happiness;
    _dayPassed();
    // P1: хорошая смена — бонус (P6), +1 опыт и чуть дороже: сверх карточки
    // ⚡ и 😊. ⚡ сверху — не больше, чем осталось: игра уже сыграна, смену
    // не отменяем и в минус не уходим. Обычная — ровно ставка.
    final double s = score.clamp(0.0, 1.0);
    final bool good = o.isGoodScore(s);
    final int bonus = o.bonusFor(s);
    final int pay = o.pay + bonus;
    final double extra = good
        ? math.max(
            0.0, math.min(o.goodEnergyExtra, _state.energy - o.energyCost))
        : 0.0;
    final double spent = roundEnergy(o.energyCost + extra);
    final int dh = good ? _happinessDelta(o.goodHappiness) : 0;
    final Map<String, Object?> args = <String, Object?>{
      'jobId': jobId,
      if (variant != null) 'variant': variant,
      'pay': o.pay,
    };
    final ({String tool, int premium})? credit =
        _toolCredit(config.job(jobId, variant)!, o.pay);
    final int paidBefore =
        credit == null ? 0 : _state.toolPayback[credit.tool] ?? 0;
    _write(WorldLedgerKind.jobStarted, 'job.started', args: args);
    _write(WorldLedgerKind.jobPayout, 'job.payout',
        free: pay,
        energy: -spent,
        happiness: dh,
        args: <String, Object?>{
          ...args,
          'bonus': bonus,
          'score': score,
          'good': good,
          if (credit != null) 'tool': credit.tool,
          if (credit != null) 'premium': credit.premium,
        });
    String paidBack = '';
    if (credit != null) {
      final int price = _priceOf(credit.tool);
      final int now = _state.toolPayback[credit.tool] ?? 0;
      if (paidBefore < price && now >= price) {
        paidBack = ' ${_titleOf(credit.tool)} окупился! Смены на нём принесли '
            '$now сверх работы без него — больше, чем он стоил ($price).';
      }
    }
    final String tail = paidBack + _afterEnergySpent();
    _maybeShowEvent(weekOpening: false);
    return WorldResult(
      ok: true,
      reasonCode: 'job.payout',
      reason: good
          ? '${o.title}: хорошая работа! Заплатили ${o.pay}'
              '${bonus > 0 ? ' и $bonus за эффективность' : ''}, опыт +1.$tail'
          : '${o.title}: заплатили ${o.pay}. Опыт и бонус — за хорошо '
              'сделанную смену.$tail',
      nextStep: _state.activeGoalId == null
          ? 'Выбери цель в Копилке — и сможешь откладывать с заработка'
          : 'Сколько отложить на цель?',
      coins: pay,
      energy: -spent,
      happiness: _state.happiness - happinessBefore,
    );
  }

  @override
  LearningSummary get learning {
    final Map<String, int> topics = <String, int>{};
    final List<({String id, String term})> words =
        <({String id, String term})>[];
    for (final WorldEntry e in _journal) {
      if (e.kind == WorldLedgerKind.lessonChoice) {
        final String? t = e.args['topic'] as String?;
        if (t != null) topics[t] = (topics[t] ?? 0) + 1;
        final String? id = e.args['word'] as String?;
        final String? term = e.args['wordTerm'] as String?;
        if (id != null &&
            term != null &&
            !words.any((({String id, String term}) w) => w.id == id)) {
          words.add((id: id, term: term));
        }
      } else if (e.kind == WorldLedgerKind.eventChoice &&
          e.reasonCode == 'event.choice') {
        final String? t = e.args['topic'] as String?;
        if (t != null) {
          final String topic = LearningSummary.topicOfEvent(t);
          topics[topic] = (topics[topic] ?? 0) + 1;
        }
      }
    }
    return LearningSummary(topics: topics, words: words);
  }

  @override
  LessonOffer? get pendingLesson {
    final String? job = _state.lessonJobId;
    final WorldLesson? l = job == null ? null : config.lesson(job);
    if (l == null) return null;
    return lessonOffer(l,
        pay: _state.lessonPay, free: _state.free, want: _state.want);
  }

  @override
  WorldResult resolveLesson(String choiceId) {
    final String? job = _state.lessonJobId;
    final WorldLesson? l = job == null ? null : config.lesson(job);
    if (l == null) {
      return const WorldResult.refused('lesson.none', 'Сейчас урока нет.');
    }
    final WorldLessonChoice? c = l.choice(choiceId);
    if (c == null) {
      return WorldResult.refused(
          'lesson.unknown', 'Такого варианта нет: $choiceId.');
    }
    final LessonMove m = lessonMove(c,
        pay: _state.lessonPay, free: _state.free, want: _state.want);
    if (m.block != null) return m.block!.refusal;
    final ResourceSnapshot before = _state.snapshot;
    _write(WorldLedgerKind.lessonChoice, 'lesson.choice',
        free: -(m.toGoal + m.toNeed + m.fromFree),
        want: -m.fromWant,
        goal: m.toGoal,
        need: m.toNeed,
        happiness: _happinessDelta(c.happiness),
        args: <String, Object?>{
          'jobId': l.jobId,
          'choiceId': c.id,
          'title': l.title,
          'topic': l.topic,
          'word': l.word,
          'wordTerm': l.wordTerm,
        });
    final ResourceSnapshot after = _state.snapshot;
    return WorldResult(
      ok: true,
      reasonCode: 'lesson.choice',
      reason: lessonReason(l, c),
      nextStep: 'Новое слово в Словарике: ${l.wordTerm}',
      coins: after.available - before.available,
      goal: after.goal - before.goal,
      happiness: after.happiness - before.happiness,
    );
  }

  @override
  WorldResult eat(String foodId) {
    final BlockReason? block = canDo(WorldAction.eat, id: foodId);
    if (block != null) return block.refusal;
    final WorldFood f = config.food(foodId)!;
    // Еда — обязательная трата: сначала НУЖНО, потом заработок, потом ХОЧУ
    // (тот же порядок, что у счетов недели).
    int left = f.price;
    final int fromNeed = math.min(_state.need, left);
    left -= fromNeed;
    final int fromFree = math.min(_state.free, left);
    left -= fromFree;
    final int fromWant = left;
    final double gain = roundEnergy(math.max(
        0.0,
        math.min(config.energyMax, _state.energy + f.energyNow) -
            _state.energy));
    final int dh = _happinessDelta(f.happiness);
    _write(WorldLedgerKind.mealEaten, 'meal.eaten',
        need: -fromNeed,
        free: -fromFree,
        want: -fromWant,
        energy: gain,
        happiness: dh,
        args: <String, Object?>{
          'foodId': f.id,
          'price': f.price,
          'energyNow': f.energyNow,
        });
    _maybeShowEvent(weekOpening: false);
    final int mealsLeft = _state.mealsLeft;
    final String full =
        gain + _eps < f.energyNow ? ' (⚡ уже почти полная)' : '';
    return WorldResult(
      ok: true,
      reasonCode: 'meal.eaten',
      reason: '${f.title}: ⚡ +${energyShown(gain)}$full, '
          '😊 ${dh < 0 ? dh : '+$dh'}${f.why.isEmpty ? '' : ' — ${f.why}'}.',
      nextStep: mealsLeft > 0
          ? 'Поесть на этой неделе можно ещё $mealsLeft '
              '${Phrases.timesWord(mealsLeft)}'
          : 'На этой неделе Финни наелся',
      coins: -f.price,
      energy: gain,
      happiness: dh,
    );
  }

  @override
  WorldResult depositToGoal(int amount) {
    if (_state.phase == WeekPhase.onboarding) return _wrongPhase('deposit');
    if (amount <= 0) {
      return const WorldResult.refused(
          'goal.deposit_zero', 'Ничего не отложено — это тоже выбор.');
    }
    if (amount > _state.free) {
      return WorldResult.refused(
          'goal.deposit_too_much', 'В кошельке только ${_state.free}.');
    }
    _write(WorldLedgerKind.goalSliderDeposit, 'goal.deposit',
        free: -amount, goal: amount, args: <String, Object?>{'amount': amount});
    return WorldResult(
      ok: true,
      reasonCode: 'goal.deposit',
      reason: 'Отложено на цель $amount. В кошельке осталось ${_state.free}.',
      coins: -amount,
      goal: amount,
    );
  }

  String _titleOf(String id) =>
      config.pet(id)?.title ??
      config.transports[id] ??
      config.tech(id)?.title ??
      config.home(id)?.title ??
      config.cloth(id)?.title ??
      config.decorItem(id)?.title ??
      (id == config.snackId ? 'Перекус' : id);

  int _priceOf(String id) =>
      config.pet(id)?.price ??
      (config.transports.containsKey(id) ? config.transportPrice : null) ??
      config.tech(id)?.price ??
      config.home(id)?.price ??
      config.cloth(id)?.price ??
      config.decorItem(id)?.price ??
      (id == config.snackId ? config.snackPrice : 0);

  /// Разбивка цены на ХОЧУ, затем заработок. null — не хватает.
  ({int want, int free})? _fromWantThenFree(int price) {
    if (_state.want + _state.free < price) return null;
    final int w = math.min(_state.want, price);
    return (want: w, free: price - w);
  }

  @override
  WorldResult buy(String itemId) {
    final BlockReason? block = canDo(WorldAction.buy, id: itemId);
    if (block != null) return block.refusal;
    final String title = _titleOf(itemId);
    final int price = _priceOf(itemId);

    if (_isGoalItem(itemId)) {
      final WorldLedgerKind kind = config.pet(itemId) != null
          ? WorldLedgerKind.petBought
          : config.transports.containsKey(itemId)
              ? WorldLedgerKind.transportBought
              : config.tech(itemId) != null
                  ? WorldLedgerKind.techBought
                  : WorldLedgerKind.homeBought;
      final int dh = _happinessDelta(config.goalReachedBonus);
      final WorldStage stageBefore = _state.stage;
      _write(kind, 'buy.goal',
          goal: -price,
          happiness: dh,
          args: <String, Object?>{'itemId': itemId, 'price': price});
      final WorldHome? home = config.home(itemId);
      if (home != null && _state.stage != stageBefore) {
        _write(WorldLedgerKind.stageChanged, 'stage.changed',
            args: <String, Object?>{'stage': _state.stage.name});
        return WorldResult(
          ok: true,
          reasonCode: 'buy.goal',
          reason: 'Финни переезжает: ${home.title}! Залог и первая неделя — '
              '$price. Дальше ${home.weeklyCost} в неделю: жизнь лучше и платят '
              'больше, но и всё дороже.',
          goal: -price,
          happiness: dh,
        );
      }
      final WorldPet? pet = config.pet(itemId);
      final String food = pet != null
          ? ' Корм +${pet.foodPerWeek} к счёту со следующей недели.'
          : '';
      return WorldResult(
        ok: true,
        reasonCode: 'buy.goal',
        reason: 'Цель достигнута: $title!$food',
        goal: -price,
        happiness: dh,
      );
    }

    if (itemId == config.snackId) {
      final ({int want, int free}) pay = _fromWantThenFree(price)!;
      final double gain = roundEnergy(
          math.min(config.energyMax, _state.energy + config.snackEnergyNow) -
              _state.energy);
      _write(LedgerKind.purchase, 'buy.snack',
          want: -pay.want,
          free: -pay.free,
          energy: gain,
          args: <String, Object?>{'itemId': itemId, 'price': price});
      _maybeShowEvent(weekOpening: false);
      return WorldResult(
        ok: true,
        reasonCode: 'buy.snack',
        reason: 'Перекус: +$gain ⚡.',
        coins: -price,
        energy: gain,
      );
    }

    final WorldItem item = (config.cloth(itemId) ?? config.decorItem(itemId))!;
    final ({int want, int free}) pay = _fromWantThenFree(price)!;
    final int dh = _happinessDelta(item.happinessByWeek.first);
    _write(WorldLedgerKind.itemOwned, 'buy.item',
        want: -pay.want,
        free: -pay.free,
        happiness: dh,
        args: <String, Object?>{'itemId': itemId, 'price': price});
    return WorldResult(
      ok: true,
      reasonCode: 'buy.item',
      reason: 'Куплено: $title.',
      coins: -price,
      happiness: dh,
    );
  }

  @override
  WorldResult leisure(String kind) {
    final BlockReason? block = canDo(WorldAction.leisure, id: kind);
    if (block != null) return block.refusal;
    final WorldLeisure l = config.leisureKind(kind)!;
    final double cost = _leisureEnergy(l);
    final ({int want, int free}) pay = _fromWantThenFree(l.price)!;
    final int raw = _leisureRaw(l);
    final int capped = _leisureGain(l);
    final int happinessBefore = _state.happiness;
    _dayPassed();
    final int dh = _happinessDelta(capped);
    _write(WorldLedgerKind.leisure, 'leisure.done',
        want: -pay.want,
        free: -pay.free,
        energy: -cost,
        happiness: dh,
        args: <String, Object?>{'kind': kind, 'price': l.price});
    final String tail = _afterEnergySpent();
    _maybeShowEvent(weekOpening: false);
    return WorldResult(
      ok: true,
      reasonCode: 'leisure.done',
      reason: capped < raw
          ? '${l.title}. Весело, но на этой неделе отдых радует уже меньше.$tail'
          : '${l.title} — Финни отдохнул.$tail',
      coins: -l.price,
      energy: -cost,
      happiness: _state.happiness - happinessBefore,
    );
  }

  @override
  WorldResult petTap(String petId) {
    final WorldPet? pet = config.pet(petId);
    if (pet == null || !_state.owned.containsKey(petId)) {
      return const WorldResult.refused('pet.none', 'Такого питомца пока нет.');
    }
    if (_state.lastTapDay == _state.day) {
      return WorldResult(
          ok: true,
          reasonCode: 'pet.tap_again',
          reason: '${pet.title} рад тебе!');
    }
    final int dh = _happinessDelta(config.petTapHappiness);
    _write(WorldLedgerKind.petTapHappiness, 'pet.tap',
        happiness: dh, args: <String, Object?>{'petId': petId});
    return WorldResult(
      ok: true,
      reasonCode: 'pet.tap',
      reason: '${pet.title} рад тебе — Финни веселее.',
      happiness: dh,
    );
  }

  @override
  WorldResult sleep() {
    final BlockReason? block = canDo(WorldAction.sleep);
    if (block != null) return block.refusal;
    final bool bonus = _state.energy + _eps >= config.sleepMinLeftForBonus;
    int gain = 0;
    double carry = 0;
    if (bonus) {
      gain = config.sleepHappiness;
      carry = config.sleepCarryNextWeek;
      config.sleepHappinessPerks.forEach((String owner, int d) {
        if (_state.owned.containsKey(owner)) gain += d;
      });
      config.sleepCarryPerks.forEach((String owner, double d) {
        if (_state.owned.containsKey(owner)) carry += d;
      });
    }
    final int dh = _happinessDelta(gain);
    _write(WorldLedgerKind.sleep, bonus ? 'sleep.bonus' : 'sleep.plain',
        happiness: dh, args: <String, Object?>{'bonus': bonus, 'carry': carry});
    final int money = _state.pockets;
    final int bill = _state.weeklyBill;
    return WorldResult(
      ok: true,
      reasonCode: bonus ? 'sleep.bonus' : 'sleep.plain',
      reason: bonus
          ? 'Финни выспался: +$dh 😊 и +${energyShown(carry)} ⚡ на следующую неделю.'
          : 'Финни лёг спать.',
      nextStep: money < bill
          ? 'На счета не хватает ${bill - money} — посмотрим, что можно сделать'
          : null,
      happiness: dh,
    );
  }

  @override
  WorldResult payBills({bool takeFromGoal = false}) {
    final BlockReason? block = canDo(WorldAction.payBills);
    if (block != null) return block.refusal;
    final int happinessBefore = _state.happiness;
    final WeekBills bills = billsPreview(takeFromGoal: takeFromGoal);
    final List<String> steps = <String>[];

    if (bills.downgraded) steps.add('взяли простую еду');

    // Шаг 3: из накоплений — одной записью, с согласия ребёнка.
    final int withdrawn = bills.fromGoal;
    if (withdrawn > 0) {
      _write(LedgerKind.savingsWithdraw, 'bills.from_goal',
          goal: -withdrawn,
          free: withdrawn,
          args: <String, Object?>{'amount': withdrawn, 'reason': 'bills'});
      steps.add('$withdrawn из копилки');
    }

    // Шаги 1–2: по записи на счёт, корм первым.
    for (final BillPayment p in bills.payments) {
      if (p.amount == 0) continue;
      _write(WorldLedgerKind.billPaid, 'bills.${p.kind.name}',
          need: -p.fromNeed,
          free: -(p.fromFree + p.fromGoal),
          want: -p.fromWant,
          args: <String, Object?>{
            'bill': p.kind.name,
            'amount': p.amount,
            'fromPockets': p.fromPockets,
            'fromGoal': p.fromGoal,
            'fromFamily': p.fromFamily,
            if (p.kind == BillKind.food) 'foodId': bills.eatenFood?.id,
            if (p.kind == BillKind.food) 'meals': bills.homeMeals,
            if (p.kind == BillKind.rent) 'homeId': _state.rentHomeId,
          });
    }

    // Шаг 4: остаток — «семья помогает».
    final int family = bills.fromFamily;
    if (family > 0) {
      _write(WorldLedgerKind.familyHelp, 'bills.family_help',
          happiness: _happinessDelta(config.familyHelpHappiness),
          args: <String, Object?>{'amount': family});
      steps.add('семья помогла с $family');
    }

    // Очки роста (T1).
    final List<String> why = <String>[];
    if (!bills.familyHelped) why.add('required_covered');
    if (!bills.hadShortfall) why.add('plan_kept');
    final int deposits = _state.depositsThisWeek;
    final bool savedRegularly = deposits > 0 &&
        deposits >= _state.incomeThisWeek * config.savedRegularlyMinShare;
    if (savedRegularly) why.add('saved_regularly');
    final int points = why.fold<int>(
        0, (int a, String w) => a + (config.growthPointsPerReason[w] ?? 0));
    final WorldStage stageBefore = _state.stage;

    // Рост недели к прошлой (P7) и недельное 😊: еда, питомцы, дом, одежда,
    // рост или застой − остывание.
    final _WeekGrowth g = _growthCheck(
      savedRegularly: savedRegularly,
      stageUp: _state.stageFor(_state.growthPoints + points) != stageBefore,
    );
    final int weekly =
        _weeklyHappiness(bills.eatenFood, bills.homeMeals) + g.delta;
    _write(LedgerKind.periodClosed, 'week.closed',
        happiness: _happinessDelta(weekly),
        args: <String, Object?>{
          'points': points,
          'why': why,
          if (g.verdict != null) 'growth': g.verdict,
          if (g.verdict != null) 'growthWhy': g.why,
          if (g.verdict != null) 'growthDelta': g.delta,
          'earned': _state.earnedThisWeek,
          if (_state.earnedLastWeek != null)
            'earnedBefore': _state.earnedLastWeek,
          'due': bills.total,
          'fromPockets': bills.fromPockets,
          'fromGoal': withdrawn,
          'fromFamily': family,
          'downgraded': bills.downgraded,
          'foodEnergyNext':
              roundEnergy((bills.eatenFood?.energyNow ?? 0) * bills.homeMeals),
        });
    final bool grew = _state.stage != stageBefore;
    if (grew) {
      _write(WorldLedgerKind.stageChanged, 'stage.changed',
          args: <String, Object?>{'stage': _state.stage.name});
    }

    final Map<String, String> whyText = <String, String>{
      'required_covered': 'обязательное закрыто своими деньгами',
      'plan_kept': 'без нехватки',
      'saved_regularly': 'отложено не меньше '
          '${(config.savedRegularlyMinShare * 100).round()} % дохода — так к цели приходят раньше',
    };
    final String shortfall =
        steps.isEmpty ? '' : ' Не хватало: ${steps.join(', ')}.';
    const Map<String, String> growthText = <String, String>{
      'income': 'заработано больше',
      'saved': 'отложено на цель',
      'goal': 'цель достигнута',
      'stage': 'переезд',
    };
    final String growthLine = switch (g.verdict) {
      weekGrowthUp => ' Неделя роста '
          '(${g.why.map((String w) => growthText[w]).join(', ')}): '
          '+${g.delta} 😊.',
      weekGrowthFlat => ' Неделя без роста: ${g.delta} 😊. Заработай '
          'больше, чем на прошлой неделе, или отложи на цель.',
      _ => '',
    };
    return WorldResult(
      ok: true,
      reasonCode: bills.familyHelped ? 'bills.family_help' : 'bills.paid',
      reason: 'Счета недели — ${bills.total}.$shortfall '
          'Очки роста: +$points'
          '${why.isEmpty ? '' : ' (${why.map((String w) => whyText[w]).join(', ')})'}.'
          '$growthLine'
          '${grew ? ' Финни переезжает дальше!' : ''}'
          '${_moveReadyLine()}',
      nextStep: 'Новая неделя',
      coins: -bills.fromPockets,
      goal: -withdrawn,
      happiness: _state.happiness - happinessBefore,
    );
  }

  /// Очков хватает на переезд, а Финни ещё не переехал — одна фраза в итогах
  /// недели (стадия = аренда): переезд — выбор ребёнка, не автомат.
  String _moveReadyLine() {
    if (!config.stageByRent) return '';
    for (final WorldHome h in config.homes) {
      final WorldStage? to = h.stage;
      if (to == null || _alreadyHas(h.id) || _moveBlock(h.id) != null) continue;
      // Ревью 2b58bdb §8.3: «копи», когда в копилке уже хватает, — неправда.
      return _state.goal >= h.price
          ? ' Очков роста хватает на переезд: ${h.title} — залог '
              '${h.price}, и в копилке уже хватает. Переехать — '
              'в копилке, если захочешь.'
          : ' Очков роста хватает на переезд: ${h.title} — залог '
              '${h.price}, копи в копилке.';
    }
    return '';
  }

  /// P7: выросла ли неделя по сравнению с прошлой. Неделя 1 — сравнивать не с
  /// чем: ни бонуса, ни штрафа. Рост — хотя бы одно из:
  /// - `income`: заработок недели (смены и деньги событий, без стипендии)
  ///   больше нуля и не меньше прошлонедельного × (1 + `income_min_share`);
  /// - `saved`: отложено ≥ 10 % дохода недели (то же условие, что у очка
  ///   `saved_regularly`);
  /// - `goal`: на этой неделе куплена цель;
  /// - `stage`: очки этой недели переводят Финни на новую стадию.
  ///
  /// Рост: +`growth_bonus`. Без роста: −`stagnation_step` × недель без роста
  /// подряд (с этой), но не больше `stagnation_max`.
  _WeekGrowth _growthCheck(
      {required bool savedRegularly, required bool stageUp}) {
    final int? before = _state.earnedLastWeek;
    if (before == null) return const _WeekGrowth(null, <String>[], 0);
    final int earned = _state.earnedThisWeek;
    final List<String> why = <String>[
      if (earned > 0 &&
          earned >= before * (1 + config.weekGrowthIncomeMinShare) - _eps)
        'income',
      if (savedRegularly) 'saved',
      if (_state.goalsBoughtThisWeek > 0) 'goal',
      if (stageUp) 'stage',
    ];
    if (why.isNotEmpty) {
      return _WeekGrowth(weekGrowthUp, why, config.weekGrowthBonus);
    }
    final int penalty = math.min(
        config.stagnationMax, config.stagnationStep * (_state.flatWeeks + 1));
    return _WeekGrowth(weekGrowthFlat, why, -penalty);
  }

  /// Недельное изменение 😊 в итогах. Остывание — от 😊 на **начало** недели:
  /// так сходится пример Насти «неделя 1 → 😊 64» (v13, слайд 17; с P7 — 61:
  /// три игровых дня по −1).
  int _weeklyHappiness(WorldFood? eaten, int homeMeals) {
    int weekly = (eaten?.happiness ?? 0) * homeMeals;
    final List<WorldPet> feeding = _state.feedingPets.toList();
    weekly += math.min(config.petsHappinessCap,
        feeding.fold<int>(0, (int a, WorldPet p) => a + p.happinessPerWeek));
    weekly += config.home(_state.rentHomeId)?.happinessPerWeek ?? 0;
    for (final WorldItem c in config.clothes) {
      final int? bought = _state.owned[c.id];
      if (bought == null) continue;
      final int age = _state.weekNo - bought;
      if (age >= 1 && age < c.happinessByWeek.length) {
        weekly += c.happinessByWeek[age];
      }
    }
    double decay = config.weeklyDecayBase +
        config.weeklyDecayK *
            (_state.happinessAtWeekStart - config.happinessNeutral);
    for (final WorldPet p in feeding) {
      decay += config.decayPerks[p.id] ?? 0;
    }
    return weekly - decay.round();
  }

  @override
  WorldResult withdrawFromGoal(int amount) {
    if (_state.phase == WeekPhase.onboarding) return _wrongPhase('withdraw');
    if (amount <= 0 || amount > _state.goal) {
      return WorldResult.refused('goal.withdraw_bad',
          'В копилке ${_state.goal} — столько снять не выйдет.');
    }
    final int before = _state.goal;
    _write(LedgerKind.savingsWithdraw, 'goal.withdraw',
        goal: -amount, free: amount, args: <String, Object?>{'amount': amount});
    return WorldResult(
      ok: true,
      reasonCode: 'goal.withdraw',
      reason: 'Снято из копилки $amount. Было $before, стало ${_state.goal}.',
      coins: amount,
      goal: -amount,
    );
  }
}

/// Итог проверки роста недели (P7): [verdict] — `up`, `flat` или null
/// (неделя 1), [why] — что выросло, [delta] — изменение 😊.
class _WeekGrowth {
  const _WeekGrowth(this.verdict, this.why, this.delta);

  final String? verdict;
  final List<String> why;
  final int delta;
}
