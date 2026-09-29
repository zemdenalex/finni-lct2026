import 'dart:math' as math;

import '../ledger/ledger_entry.dart' show LedgerKind;
import '../phrases.dart';
import 'contract.dart';
import 'lesson_rules.dart';
import 'onboarding_keeper.dart';
import 'week_history.dart';
import 'world_catalog.dart';
import 'world_config.dart';
import 'world_mood.dart';

/// Фейковый мир в памяти — чтобы экраны (поток B) строились до домена.
///
/// 🔴 Не источник истины. Числа — Настя v13 (27.09) и `open-questions` P1–P4,
/// вписаны константами ниже, потому что `content/economy.json` ещё хранит
/// старую шкалу (карманные 40), а домен не читает файлы (`layering_test`).
/// Когда A1 перенесёт v13 в JSON, а A2–A8 реализуют [World] на журнале,
/// фейк заменяется одной строкой и удаляется.
///
/// Рост оплаты (P1, пересмотр 27.09; P8), бонус за эффективность (P6), перк
/// котёнка, скидка транспорта, лимиты смен и вся модель радости (P7:
/// множители 😊, игровой день, остывание, проверка роста) читаются из
/// [config] — тех же значений по умолчанию, что у `WorldGame()`; тест
/// загрузчика сверяет их с `content/economy.json`. Остальные числа фейка —
/// константы ниже.
///
/// Упрощения фейка — не решения для домена:
/// - остывание 😊 считается от 😊 на начало недели, как в домене;
/// - опыт — число хорошо сделанных смен всех работ (P1);
/// - оплата фиксируется в момент [completeJob] (между карточкой и концом игры
///   ничего не меняется); в домене — запись `jobStarted`;
/// - счета платятся из НУЖНО → заработок → ХОЧУ без диалога;
/// - события недели (A10) — шесть из `content/events.json`, текстами оттуда,
///   по расписанию: неделя N берёт N-е по кругу, если подходят условия и оно
///   не было раньше чем 4 недели назад; одно событие в неделю, выбирается при
///   подтверждении плана. Здание с «!» задаёт фейк (в файле поля нет, Р4).
///   Доход события кладётся в кошелёк (в файле — выбор ребёнка);
/// - каталог (A11) строится из [config] — те же числа по умолчанию, что у
///   констант ниже; тест сверяет цены каталога со списанием в [buy].
class FakeWorld implements World {
  FakeWorld({
    this.config = const WorldConfig(),
    OnboardingProgress onboarding = const OnboardingProgress(),
    OnboardingSave? saveOnboarding,
  }) : _onboarding = OnboardingKeeper(onboarding, saveOnboarding);

  /// Числа роста оплаты, бонуса, перков и транспорта — общие с доменом.
  final WorldConfig config;

  // ─────────── числа v13 (перенос в economy.json — карточка A1) ───────────

  static const int _pocketMoney = 400;
  static const double _energyWeekStart = 10;
  static const double _energyMax = 14;
  static const double _livingDrain = 1;
  static const int _happinessStart = 50;
  static const int _sleepHappiness = 3;
  static const double _sleepMinLeft = 1;
  static const double _sleepCarry = 1;

  /// v13, слайд 16: «когда энергия закончилась — нет бонуса сна и нет штрафа
  /// −2». В файле пока −2 (open-questions Р1).
  static const int _exhaustedHappiness = 0;

  static const int _leisureWeeklyCap = 16;
  static const int _goalReachedBonus = 10;
  static const int _familyHelpHappiness = -6;
  static const int _petsHappinessCap = 14;
  static const int _petTapHappiness = 1;
  static const int _decorHappiness = 3;
  static const int _snackMaxPerWeek = 2;

  /// Блюда — из [config] (`food.options`), как у домена: цена, 😊 и ⚡ за
  /// приём. Простое блюдо — домашнее меню по умолчанию.
  static const String _simpleFood = 'food_simple';

  /// Жильё — из [config] (`homes.options`), как у домена: аренда, стадия.
  Map<String, _Home> get _homes => <String, _Home>{
        for (final WorldHome h in config.homes)
          h.id: _Home(h.title, h.price, h.weeklyCost, h.energyPerWeek,
              h.happinessPerWeek),
      };

  /// Рыбка 400 — решение 27.09 (docx Насти, P3); в слайдах v13 ещё 500.
  static const Map<String, _Pet> _pets = <String, _Pet>{
    'pet_fish': _Pet('Рыбка', 400, 40, 3),
    'pet_hamster': _Pet('Хомяк', 750, 60, 4),
    'pet_turtle': _Pet('Черепаха', 900, 50, 4),
    'pet_kitten': _Pet('Котёнок', 1800, 120, 6),
    'pet_dog': _Pet('Собака', 3200, 180, 7),
  };

  static const int _transportPrice = 1800;
  static const Map<String, String> _transports = <String, String>{
    'transport_bike': 'Велосипед',
    'transport_scooter': 'Самокат',
    'transport_skateboard': 'Скейт',
  };

  /// Одежда: 😊 угасает за три недели (`fade`).
  static const Map<String, _Cloth> _clothes = <String, _Cloth>{
    'cloth_cap': _Cloth('Кепка', 300, <int>[6, 3, 1]),
    'cloth_scarf': _Cloth('Шарф', 350, <int>[6, 3, 1]),
    'cloth_hoodie': _Cloth('Толстовка', 600, <int>[9, 5, 2]),
    'cloth_sneakers': _Cloth('Кроссовки', 800, <int>[11, 6, 3]),
  };

  /// Декор: +3 😊 один раз за новый предмет.
  static const Map<String, _Priced> _decor = <String, _Priced>{
    'poster_city': _Priced('Плакат «Город»', 200),
    'poster_pets': _Priced('Плакат «Питомцы»', 300),
    'poster_music': _Priced('Плакат «Музыка»', 450),
    'plant_cactus': _Priced('Кактус', 250),
    'plant_flower': _Priced('Цветок', 400),
    'plant_floor': _Priced('Напольное растение', 650),
    'light_bulb': _Priced('Лампочка', 300),
    'light_garland_short': _Priced('Короткая гирлянда', 500),
    'light_garland_long': _Priced('Длинная гирлянда', 750),
  };

  static const String _snackId = 'snack';
  static const int _snackPrice = 60;
  static const double _snackEnergy = 1;

  static const Map<String, _Leisure> _leisure = <String, _Leisure>{
    'park': _Leisure('Парк', 0, 1, 6),
    'cafe': _Leisure('Кафе с друзьями', 200, 1, 9),
    'cinema': _Leisure('Кино с друзьями', 150, 2, 10),
    'pet_play': _Leisure('Игра с питомцем', 0, 1, 4),
  };

  /// Работы: оплата и базовая ⚡ (без «на жизнь»). Ключ — `jobId` или
  /// `jobId/variant`.
  static const List<_Job> _jobs = <_Job>[
    _Job('consultant', null, 'Продавец-консультант', 300, 2),
    _Job('cashier', null, 'Кассир', 260, 2),
    _Job('accountant', null, 'Помощник бухгалтера', 280, 2),
    _Job('gardener', null, 'Садовник', 180, 1),
    _Job('programmer', 'easy', 'Программист · лёгкая', 280, 2,
        needs: 'computer'),
    _Job('programmer', 'medium', 'Программист · средняя', 400, 3,
        needs: 'computer'),
    _Job('programmer', 'hard', 'Программист · сложная', 480, 4,
        needs: 'computer_pro'),
    _Job('courier', 'near', 'Курьер · близко', 300, 2, needs: 'transport'),
    _Job('courier', 'district', 'Курьер · район', 400, 3, needs: 'transport'),
    _Job('courier', 'far', 'Курьер · далеко', 520, 4, needs: 'transport'),
    _Job('dog_walker', null, 'Выгульщик собак', 220, 1, needs: 'pet_dog'),
  ];

  // ───────────────────────────── состояние ─────────────────────────────

  WeekPhase _phase = WeekPhase.onboarding;
  int _weekNo = 0;
  int _need = 0;
  int _want = 0;
  int _goal = 0;
  int _free = 0;
  int _unallocated = 0;
  double _energy = 0;
  int _happiness = _happinessStart;
  int _happinessAtWeekStart = _happinessStart;
  int _growthPoints = 0;
  int _experience = 0;
  String _foodId = _simpleFood;
  String _homeId = 'home_room';
  String _rentHomeId = 'home_room';
  String? _activeGoalId;
  String? _activePetId;
  WeekEnd? _endedBy;
  bool _billsPaid = false;

  /// Что куплено и на какой неделе.
  final Map<String, int> _owned = <String, int>{};

  // Недельные счётчики.
  int _shiftsThisWeek = 0;
  final Map<String, int> _shiftsByJob = <String, int>{};

  /// Бонус взрослого (ТЗ 2.5.12.3) — у фейка флаг недели, у домена запись
  /// `parentBonus`.
  bool _parentBonusThisWeek = false;
  int _leisureHappinessThisWeek = 0;
  int _snacksThisWeek = 0;

  /// Сколько раз Финни поел на этой неделе ([eat]).
  int _mealsThisWeek = 0;

  /// Чему научился (как `WorldGame.learning`, но счётчиками).
  final Map<String, int> _topics = <String, int>{};
  final List<({String id, String term})> _words =
      <({String id, String term})>[];

  @override
  LearningSummary get learning => LearningSummary(
      topics: Map<String, int>.unmodifiable(_topics),
      words: List<({String id, String term})>.unmodifiable(_words));

  /// Урок после последней смены (как `WorldState.lessonJobId`).
  String? _lessonJobId;
  int _lessonPay = 0;
  int _incomeThisWeek = 0;
  int _depositsThisWeek = 0;

  // Проверка роста недели (P7), как в свёртке домена.
  int _earnedThisWeek = 0;
  int? _earnedLastWeek;
  int _goalsBoughtThisWeek = 0;
  int _flatWeeks = 0;
  int _day = 0;
  int _dayAtWeekStart = 0;
  int _lastTapDay = -1;

  // Переходит на следующую неделю.
  double _carryEnergy = 0;

  /// Добавка к обязательному счёту этой недели от события (рюкзак).
  int _extraBill = 0;

  // События (A10).
  String? _weekEventId;
  bool _eventResolved = false;
  final Map<String, int> _eventShownWeek = <String, int>{};
  final Set<String> _flags = <String>{};

  // Причина настроения (A12): последнее, что изменило 😊 или закрыло
  // неделю ([always] — называть и без изменения 😊, как в свёртке домена).
  String? _moodCode;
  int _moodDelta = 0;

  void _moodCause(String code, int delta, {bool always = false}) {
    if (delta == 0 && !always) return;
    _moodCode = code;
    _moodDelta = delta;
  }

  final OnboardingKeeper _onboarding;

  /// План против факта по неделям (C3): тот же [WeekTally], что у свёртки
  /// журнала домена. Текущая неделя — последняя.
  final List<WeekTally> _weeks = <WeekTally>[];

  WeekTally? get _week => _weeks.isEmpty ? null : _weeks.last;

  /// Живые числа текущей недели → её учёт.
  void _syncWeek() {
    final WeekTally? t = _week;
    if (t == null) return;
    final String? g = _activeGoalId;
    t
      ..saved = _depositsThisWeek
      ..savedAtEnd = _goal
      ..goalTitle = g == null ? null : _titleOf(g)
      ..goalPrice = g == null ? null : _priceOf(g);
  }

  @override
  List<WeekPlanFact> get weekHistory {
    _syncWeek();
    return <WeekPlanFact>[for (final WeekTally t in _weeks) t.build()];
  }

  /// Метки событий (`events.json → _flags`) — для отладки и раздела взрослого.
  Set<String> get flags => Set<String>.unmodifiable(_flags);

  final List<({String kind, String reason})> _log =
      <({String kind, String reason})>[];

  /// Журнал фейка — для отладки экранов. У домена журнал настоящий.
  List<({String kind, String reason})> get log =>
      List<({String kind, String reason})>.unmodifiable(_log);

  void _write(Enum kind, String reason) =>
      _log.add((kind: kind.name, reason: reason));

  // ─────────────────────────────── чтение ───────────────────────────────

  @override
  WeekPhase get phase => _phase;

  WorldStage get _stage => _stageFor(_growthPoints);

  /// Как `WorldState.stageFor`: стадия по очкам, не выше снятого жилья.
  WorldStage _stageFor(int points) {
    final WorldStage byPoints = _stageAt(points);
    if (!config.stageByRent) return byPoints;
    final WorldStage home = config.home(_homeId)?.stage ?? WorldStage.village;
    return home.index < byPoints.index ? home : byPoints;
  }

  BlockReason? _moveBlock(String homeId) {
    final WorldHome? h = config.home(homeId);
    final WorldStage? to = h?.stage;
    if (!config.stageByRent || h == null || to == null) return null;
    final int need = to.index < config.stageMinPoints.length
        ? config.stageMinPoints[to.index]
        : 0;
    if (_growthPoints >= need) return null;
    return BlockReason('buy.points',
        'Переезд откроется при $need очках роста — сейчас $_growthPoints.',
        nextStep: 'Очки роста — за счета своими деньгами, план и отложенное');
  }

  WorldStage _stageAt(int points) {
    WorldStage stage = WorldStage.village;
    for (final WorldStage s in WorldStage.values) {
      if (s.index < config.stageMinPoints.length &&
          points >= config.stageMinPoints[s.index]) {
        stage = s;
      }
    }
    return stage;
  }

  double get _stageStep => _stage.index < config.stageSteps.length
      ? config.stageSteps[_stage.index]
      : 1;

  bool get _hasTransport => _transports.keys.any(_owned.containsKey);

  /// Техника с возможностью [ability] уже есть (как `WorldState.hasAbility`).
  bool _hasAbility(String ability) => config.techs.any(
      (WorldTech t) => _owned.containsKey(t.id) && t.unlocks.contains(ability));

  /// Уже есть: вещь, транспорт вместо транспорта, техника с теми же
  /// возможностями (как `WorldGame._alreadyHas`).
  bool _alreadyHas(String id) {
    if (_owned.containsKey(id)) return true;
    if (_transports.containsKey(id)) return _hasTransport;
    final WorldStage? to = config.home(id)?.stage;
    if (config.stageByRent && to != null) {
      final WorldStage now = config.home(_homeId)?.stage ?? WorldStage.village;
      if (to.index <= now.index) return true;
    }
    final WorldTech? t = config.tech(id);
    return t != null && t.unlocks.every(_hasAbility);
  }

  /// Питомцы, которые едят и радуют на этой неделе: купленные раньше неё.
  Iterable<String> get _feedingPets => _pets.keys
      .where((String id) => _owned.containsKey(id) && _owned[id]! < _weekNo);

  int get _petFoodBill =>
      _feedingPets.fold<int>(0, (int a, String id) => a + _pets[id]!.food);

  WorldFood _food(String id) => config.food(id)!;

  /// Приёмов пищи до конца недели: их Финни съест дома в итогах.
  int get _mealsLeft => math.max(0, config.mealsPerWeek - _mealsThisWeek);

  /// Еда в счёте: оставшиеся приёмы по цене домашнего меню.
  int get _foodBill => _food(_foodId).price * _mealsLeft;

  int get _weeklyBill =>
      _petFoodBill + _foodBill + _homes[_rentHomeId]!.rent + _extraBill;

  @override
  ResourceSnapshot get snapshot => ResourceSnapshot(
        weekNo: _weekNo,
        need: _need,
        want: _want,
        goal: _goal,
        free: _free,
        unallocated: _unallocated,
        energy: _energy,
        happiness: _happiness,
        growthPoints: _growthPoints,
        stage: _stage,
        experience: _experience,
        shiftsThisWeek: _shiftsThisWeek,
        weeklyBill: _weeklyBill,
        owned: Set<String>.unmodifiable(_owned.keys),
        activeGoalId: _activeGoalId,
        activePetId: _activePetId,
        endedBy: _endedBy,
        moodReason: moodReasonFor(
          happiness: _happiness,
          phase: _phase,
          causeCode: _moodCode,
          causeDelta: _moodDelta,
        ),
        foodId: _foodId,
        daysThisWeek: _day - _dayAtWeekStart,
        snacksThisWeek: _snacksThisWeek,
        mealsThisWeek: _mealsThisWeek,
        mealsPerWeek: config.mealsPerWeek,
      );

  /// Множители — по 😊 на начало недели (P7), как в домене.
  double get _energyMult => (1 -
          config.energyCostMultPerPoint *
              (_happinessAtWeekStart - config.happinessNeutral))
      .clamp(config.energyCostMultMin, config.energyCostMultMax)
      .toDouble();

  double get _payMult => (1 +
          config.payMultPerPoint *
              (_happinessAtWeekStart - config.happinessNeutral))
      .clamp(config.payMultMin, config.payMultMax)
      .toDouble();

  /// P7: игровой день прошёл — −😊, как −1 ⚡ «на жизнь». Зовётся до
  /// изменения 😊 самим действием, чтобы причиной стало действие.
  void _dayPassed() {
    final int before = _happiness;
    _happiness = (_happiness - config.happinessDayDrain).clamp(0, 100);
    _moodCause('day.passed', _happiness - before);
    if (_happiness != before) {
      _write(
          WorldLedgerKind.dayPassed, 'День прошёл: ${_happiness - before} 😊');
    }
  }

  /// Округление ⚡ до сотых — чтобы 10 − 3 − 3 − 2 давало ровно 2, а не 1,9999.
  static double _r(double v) => (v * 100).round() / 100;

  /// База × настроение, затем скидка транспорта не ниже минимума, затем
  /// «на жизнь» — тот же порядок, что у домена.
  double _jobEnergy(_Job job) {
    double cost = job.energy * _energyMult;
    if (_hasTransport) {
      cost = math.max(
          config.transportMinJobEnergy, cost - config.transportDiscount);
    }
    return _r(cost + _livingDrain);
  }

  double _leisureEnergy(_Leisure l) =>
      _r(l.energy * _energyMult + _livingDrain);

  JobOffer _offerFor(_Job job) {
    final double growth =
        math.pow(config.experienceGrowth, _experience).toDouble();
    final double step = _stageStep;
    double perk = 1;
    config.payPerks.forEach((String owner, ({String jobId, double mult}) p) {
      if (p.jobId == job.id && _owned.containsKey(owner)) perk *= p.mult;
    });
    final int pay = roundTens(job.pay * growth * step * _payMult * perk);
    final int left = math.max(
        0,
        math.min(
            shiftsLimitThisWeek - _shiftsThisWeek,
            config.maxShiftsPerJobPerWeek +
                _parentExtra -
                (_shiftsByJob[job.id] ?? 0)));
    String? locked;
    if (_allJobsUnlocked) {
      // Демо «Открыть все профессии»: замков нет, владение прежнее.
    } else if (job.needs == 'transport' && !_hasTransport) {
      locked = 'Нужен транспорт: велосипед, самокат или скейт '
          '($_transportPrice) — копи в копилке';
    } else if (job.needs case final String needs
        when needs != 'transport' && !_hasAbility(needs)) {
      final WorldTech? tech = cheapestTechFor(config, needs);
      if (tech != null) {
        locked = 'Нужен ${tech.title.toLowerCase()} (${tech.price}) — копи в '
            'копилке';
      } else if (!_owned.containsKey(needs)) {
        locked = 'Откроется, когда появится ${_titleOf(needs).toLowerCase()} '
            '(${_priceOf(needs)})';
      }
    }
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

  /// A13: фаза → замок → лимит → ⚡, как у отказов [completeJob].
  BlockReason? _jobBlock(String? locked, int left, double energyCost) {
    if (_phase != WeekPhase.living) return _phaseBlock('job');
    if (locked != null) return BlockReason('job.locked', locked);
    if (left == 0) {
      return BlockReason(
          'job.limit',
          _shiftsThisWeek >= shiftsLimitThisWeek
              ? 'На этой неделе смен больше нет — хватит работать.'
              : 'На этой неделе смен здесь больше нет.',
          nextStep: 'Попробуй другую работу или отдохни');
    }
    if (_energy + _eps < energyCost) {
      return BlockReason('job.energy', energyShortText(energyCost, _energy),
          nextStep: 'Перекус, досуг подешевле или «Спать»');
    }
    return null;
  }

  @override
  List<JobOffer> get jobBoard => _jobs.map(_offerFor).toList();

  int get _parentExtra => _parentBonusThisWeek ? 1 : 0;

  @override
  int get shiftsLimitThisWeek => config.maxShiftsPerWeek + _parentExtra;

  @override
  bool get parentBonusThisWeek => _parentBonusThisWeek;

  @override
  WorldResult parentExtraShift() {
    final BlockReason? block = canDo(WorldAction.parentBonus);
    if (block != null) return block.refusal;
    _parentBonusThisWeek = true;
    _week?.parentBonus = true;
    _write(WorldLedgerKind.parentBonus, parentBonusReason);
    return WorldResult(
      ok: true,
      reasonCode: parentBonusCode,
      reason: '$parentBonusReason: смен можно $shiftsLimitThisWeek вместо '
          '${config.maxShiftsPerWeek}. Монеты, ⚡ и 😊 не менялись.',
      nextStep: 'Доска «Требуется…» (S6)',
    );
  }

  /// Демо «Открыть все профессии» (ТЗ 2.5.8.5) — у фейка флаг, у домена
  /// запись `demo.unlockAllJobs`.
  bool _allJobsUnlocked = false;

  @override
  bool get allJobsUnlocked => _allJobsUnlocked;

  @override
  WorldResult demoUnlockAllJobs() {
    if (_allJobsUnlocked) {
      return WorldResult.refused(
          'demo.jobs.done', 'Все профессии уже открыты.');
    }
    _allJobsUnlocked = true;
    return const WorldResult(
      ok: true,
      reasonCode: 'demo.jobs',
      reason: 'Все профессии открыты: программист, курьер и выгульщик — без '
          'покупок. '
          'Монеты, ⚡ и 😊 не менялись.',
      nextStep: 'Доска «Требуется…» (S6)',
    );
  }

  @override
  List<({String id, String title})> get demoEvents =>
      <({String id, String title})>[
        for (final _FakeEvent e in _events) (id: e.id, title: e.title),
      ];

  /// Демо «Показать событие» (ТЗ 2.5.8.5) — у фейка событие недели
  /// подменяется, у домена запись `demo.showEvent`.
  @override
  WorldResult demoShowEvent(String eventId) {
    if (_phase != WeekPhase.living) return _phaseBlock('event').refusal;
    _FakeEvent? e;
    for (final _FakeEvent x in _events) {
      if (x.id == eventId) e = x;
    }
    if (e == null) {
      return WorldResult.refused(
          'demo.event.unknown', 'Такого события нет: $eventId.');
    }
    if (_pending?.id == e.id) {
      return WorldResult.refused(
          'demo.event.pending', '«${e.title}» уже ждёт выбора.');
    }
    _weekEventId = e.id;
    _eventResolved = false;
    return WorldResult(
      ok: true,
      reasonCode: 'demo.event',
      reason: 'Событие недели: «${e.title}». Монеты, ⚡ и 😊 не менялись.',
      nextStep: 'Событие (S10)',
    );
  }

  @override
  JobOffer? offer(String jobId, {String? variant}) {
    for (final _Job j in _jobs) {
      if (j.id == jobId && j.variant == variant) return _offerFor(j);
    }
    return null;
  }

  @override
  double get cheapestActionEnergy => _cheapestAction;

  @override
  WeekBillParts get weeklyBillParts => (
        food: _foodBill,
        petFood: _petFoodBill,
        rent: _homes[_rentHomeId]!.rent,
        extra: _extraBill,
      );

  /// Самое дешёвое по ⚡ действие, доступное сейчас.
  double get _cheapestAction {
    double best = double.infinity;
    for (final MapEntry<String, _Leisure> e in _leisure.entries) {
      if (e.key == 'pet_play' && !_pets.keys.any(_owned.containsKey)) continue;
      best = math.min(best, _leisureEnergy(e.value));
    }
    for (final JobOffer o in jobBoard) {
      if (!o.locked && o.shiftsLeft > 0) best = math.min(best, o.energyCost);
    }
    return best;
  }

  static const double _eps = 1e-9;

  _Job? _job(String jobId, String? variant) {
    for (final _Job j in _jobs) {
      if (j.id == jobId && j.variant == variant) return j;
    }
    return null;
  }

  int get _petCount => _pets.keys.where(_owned.containsKey).length;

  /// Досуг: 😊 до недельного колпака, ⚡, запись. Деньги списывает вызывающий
  /// (из ХОЧУ и заработка — досуг, из копилки — событие).
  ({int raw, int gain}) _spendLeisure(String kind, _Leisure l) {
    // Цена в ⚡ — по 😊 **до** досуга, как у домена.
    final double cost = _leisureEnergy(l);
    final int raw = l.happiness + (kind == 'pet_play' ? _petCount - 1 : 0);
    final int gain = math.max(
        0, math.min(raw, _leisureWeeklyCap - _leisureHappinessThisWeek));
    _leisureHappinessThisWeek += gain;
    final int before = _happiness;
    _happiness = (_happiness + gain).clamp(0, 100);
    _moodCause('leisure.done', _happiness - before);
    _energy = _r(_energy - cost);
    _write(WorldLedgerKind.leisure, '${l.title}: +$gain 😊');
    return (raw: raw, gain: gain);
  }

  // ─────────────────── C2: A10–A14 (контракт 27.09) ───────────────────

  @override
  List<WorldCatalogItem> get catalog => catalogFromConfig(config,
      leisureEnergy: (WorldLeisure l) =>
          _r(l.energy * _energyMult + _livingDrain));

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

  @override
  BlockReason? canDo(WorldAction action, {String? id, String? variant}) {
    final String key = id ?? '';
    switch (action) {
      case WorldAction.startWeek:
        if (_phase == WeekPhase.review && !_billsPaid) {
          return const BlockReason(
              'week.bills_first', 'Сначала закроем счета этой недели.');
        }
        if (_phase != WeekPhase.onboarding && _phase != WeekPhase.review) {
          return _phaseBlock('startWeek');
        }
        return null;
      case WorldAction.plan:
        return _phase == WeekPhase.planning ? null : _phaseBlock('plan');
      case WorldAction.chooseGoal:
        if (!_isGoalItem(key)) {
          return BlockReason('goal.unknown', 'Такой цели нет: $key.');
        }
        if (_alreadyHas(key)) {
          return const BlockReason('goal.owned', 'Это у Финни уже есть.');
        }
        return null;
      case WorldAction.eat:
        return _eatBlock(key);
      case WorldAction.chooseFood:
        if (config.food(key) == null) {
          return BlockReason('food.unknown', 'Такой еды нет: $key.');
        }
        if (_phase != WeekPhase.planning && _phase != WeekPhase.living) {
          return _phaseBlock('chooseFood');
        }
        return null;
      case WorldAction.job:
        if (_phase != WeekPhase.living) return _phaseBlock('job');
        final _Job? job = _job(key, variant);
        if (job == null) {
          return BlockReason('job.unknown', 'Такой работы нет: $key.');
        }
        return _offerFor(job).blockReason;
      case WorldAction.buy:
        return _buyBlock(key);
      case WorldAction.leisure:
        return _leisureBlock(key);
      case WorldAction.sleep:
        return _phase == WeekPhase.living ? null : _phaseBlock('sleep');
      case WorldAction.payBills:
        if (_phase != WeekPhase.review) return _phaseBlock('payBills');
        if (_billsPaid) {
          return const BlockReason(
              'bills.paid', 'Счета этой недели уже закрыты.');
        }
        return null;
      case WorldAction.resolveEvent:
        if (_phase != WeekPhase.living) return _phaseBlock('event');
        final _FakeEvent? ev = _pending;
        if (ev == null) {
          return const BlockReason('event.none', 'Сейчас событий нет.');
        }
        if (id == null) return null;
        for (final _FakeChoice c in ev.choices) {
          if (c.id == id) return _choiceBlock(c);
        }
        return BlockReason('event.unknown', 'Такого варианта нет: $id.');
      case WorldAction.parentBonus:
        if (_phase != WeekPhase.living) return _phaseBlock('parentBonus');
        if (_parentBonusThisWeek) return parentBonusDone;
        return null;
    }
  }

  BlockReason? _buyBlock(String itemId) {
    if (_phase != WeekPhase.living) return _phaseBlock('buy');
    final int price = _priceOf(itemId);
    if (_isGoalItem(itemId)) {
      if (_alreadyHas(itemId)) {
        return const BlockReason('buy.owned', 'Это у Финни уже есть.');
      }
      final BlockReason? move = _moveBlock(itemId);
      if (move != null) return move;
      if (_goal < price) {
        return BlockReason(
            'buy.goal_short', 'Не хватает ${price - _goal} в копилке.',
            nextStep: 'Смена на работе или отложить с заработка');
      }
      return null;
    }
    if (itemId == _snackId) {
      if (_snacksThisWeek >= _snackMaxPerWeek) {
        return const BlockReason(
            'buy.snack_limit', 'Перекусов на этой неделе хватит.');
      }
      if (_want + _free < price) {
        return BlockReason('buy.short', 'Не хватает ${price - _want - _free}.');
      }
      return null;
    }
    if (!_clothes.containsKey(itemId) && !_decor.containsKey(itemId)) {
      return BlockReason('buy.unknown', 'Такого в магазине нет: $itemId.');
    }
    if (_owned.containsKey(itemId)) {
      return const BlockReason('buy.owned', 'Это у Финни уже есть.');
    }
    if (_want + _free < price) {
      return BlockReason('buy.short', 'Не хватает ${price - _want - _free}.',
          nextStep: 'Смена на работе или подождать неделю');
    }
    return null;
  }

  /// Те же отказы и порядок, что у домена.
  BlockReason? _eatBlock(String foodId) {
    final WorldFood? f = config.food(foodId);
    if (f == null) {
      return BlockReason('food.unknown', 'Такой еды нет: $foodId.');
    }
    if (_phase != WeekPhase.living) return _phaseBlock('eat');
    if (_mealsLeft == 0) {
      return BlockReason(
          'eat.limit',
          'На этой неделе Финни уже поел ${config.mealsPerWeek} '
              '${Phrases.timesWord(config.mealsPerWeek)} — он сыт.',
          nextStep: 'Новая неделя — новые обеды');
    }
    final int pockets = _need + _free + _want;
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
    if (_phase != WeekPhase.living) return _phaseBlock('leisure');
    final _Leisure? l = _leisure[kind];
    if (l == null) {
      return BlockReason('leisure.unknown', 'Такого отдыха нет: $kind.');
    }
    if (kind == 'pet_play' && _petCount == 0) {
      return const BlockReason('leisure.no_pet', 'Сначала нужен питомец.');
    }
    final double cost = _leisureEnergy(l);
    if (_energy + _eps < cost) {
      return BlockReason('leisure.energy', energyShortText(cost, _energy));
    }
    if (_want + _free < l.price) {
      return BlockReason(
          'leisure.short', 'Не хватает ${l.price - _want - _free}.');
    }
    return null;
  }

  // ─────────────────────────── события (A10) ───────────────────────────

  _FakeEvent? get _pending {
    if (_phase != WeekPhase.living || _eventResolved) return null;
    for (final _FakeEvent e in _events) {
      if (e.id == _weekEventId) return e;
    }
    return null;
  }

  /// Событие недели — при подтверждении плана, по расписанию: неделя N
  /// начинает с N-го по кругу и берёт первое подходящее.
  void _scheduleEvent() {
    _weekEventId = null;
    _eventResolved = false;
    final int n = _events.length;
    for (int i = 0; i < n; i++) {
      final _FakeEvent e = _events[(_weekNo - 1 + i) % n];
      if (_weekNo < e.minWeek) continue;
      if (e.needsPet && _petCount == 0) continue;
      final int? last = _eventShownWeek[e.id];
      if (last != null && _weekNo - last < config.eventRepeatWeeks) continue;
      _weekEventId = e.id;
      _eventShownWeek[e.id] = _weekNo;
      _write(WorldLedgerKind.eventShown, 'Событие: ${e.title}');
      return;
    }
  }

  int _pocketShare(double x) => (_pocketMoney * x).round();

  int _choicePrice(_FakeChoice c) {
    final String? buy = c.buy;
    if (buy != null) return (_priceOf(buy) * (1 - c.discount)).round();
    final String? kind = c.leisure;
    if (kind != null) return _leisure[kind]!.price;
    return 0;
  }

  BlockReason? _choiceBlock(_FakeChoice c) {
    final int price = _choicePrice(c);
    final String? kind = c.leisure;
    if (kind != null) {
      final double cost = _leisureEnergy(_leisure[kind]!);
      if (_energy + _eps < cost) {
        return BlockReason('leisure.energy', energyShortText(cost, _energy));
      }
      if (c.payFromGoal) {
        if (_goal < price) {
          return BlockReason(
              'event.goal_short', 'В копилке $_goal, а нужно $price.');
        }
      } else if (_want + _free < price) {
        return BlockReason(
            'leisure.short', 'Не хватает ${price - _want - _free}.');
      }
    }
    final String? buy = c.buy;
    if (buy != null) {
      if (_owned.containsKey(buy)) {
        return const BlockReason('buy.owned', 'Это у Финни уже есть.');
      }
      if (_want + _free < price) {
        return BlockReason('buy.short', 'Не хватает ${price - _want - _free}.');
      }
    }
    if (c.savingsX < 0 && _goal < _pocketShare(-c.savingsX)) {
      return BlockReason('event.goal_short',
          'В копилке $_goal, а нужно ${_pocketShare(-c.savingsX)}.');
    }
    if (c.moneyX < 0 && _want + _free < _pocketShare(-c.moneyX)) {
      return BlockReason('event.short',
          'Не хватает ${_pocketShare(-c.moneyX) - _want - _free}.');
    }
    if (c.energy < 0 && _energy + _eps < -c.energy) {
      return BlockReason('event.energy', energyShortText(-c.energy, _energy));
    }
    return null;
  }

  EffectPreview _preview(_FakeChoice c) {
    int coins = _pocketShare(c.moneyX);
    int goal = _pocketShare(c.savingsX);
    int happiness = c.happiness;
    double energy = c.energy;
    final int price = _choicePrice(c);
    final String? kind = c.leisure;
    if (kind != null) {
      final _Leisure l = _leisure[kind]!;
      if (c.payFromGoal) {
        goal -= price;
      } else {
        coins -= price;
      }
      energy -= _leisureEnergy(l);
      final int raw = l.happiness + (kind == 'pet_play' ? _petCount - 1 : 0);
      happiness += math.max(
          0, math.min(raw, _leisureWeeklyCap - _leisureHappinessThisWeek));
    }
    final String? buy = c.buy;
    if (buy != null) {
      coins -= price;
      happiness += _clothes[buy]?.fade.first ?? _decorHappiness;
    }
    // P7: выбор, который тратит ⚡, — игровой день.
    if (kind != null || c.energy < 0) happiness -= config.happinessDayDrain;
    return EffectPreview(
      coins: coins,
      goal: goal,
      energy: _r(energy),
      happiness: happiness,
      weeklyBill: _pocketShare(c.billX),
    );
  }

  /// Реплика Финни с ником. Ника ещё нет — обращение просто опускается.
  String _say(String text) {
    final String nick = _onboarding.progress.nickname;
    String s = text
        .replaceAll('{spent}', '${_slotSpins * _slotSpinPrice}')
        .replaceAll('{won}', '$_slotWon');
    if (nick.isNotEmpty) return s.replaceAll('{nick}', nick);
    s = s.replaceAll(', {nick}', '').replaceAll('{nick}, ', '');
    s = s.replaceAll('{nick}', '');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  PendingEvent? get pendingEvent {
    final _FakeEvent? e = _pending;
    if (e == null) return null;
    return PendingEvent(
      id: e.id,
      topic: e.topic,
      title: e.title,
      text: e.text,
      buildingId: e.buildingId,
      choices: <PendingEventChoice>[
        for (final _FakeChoice c in e.choices)
          PendingEventChoice(
            id: c.id,
            label: c.label,
            preview: _preview(c),
            blockReason: _choiceBlock(c),
          ),
      ],
    );
  }

  @override
  String? get eventBuildingId => _pending?.buildingId;

  @override
  WorldResult resolveEvent(String choiceId) {
    final BlockReason? block = canDo(WorldAction.resolveEvent, id: choiceId);
    if (block != null) return block.refusal;
    final _FakeEvent e = _pending!;
    final _FakeChoice c =
        e.choices.firstWhere((_FakeChoice x) => x.id == choiceId);
    final String topic = LearningSummary.topicOfEvent(e.topic);
    _topics[topic] = (_topics[topic] ?? 0) + 1;

    final int availableBefore = snapshot.available;
    final int goalBefore = _goal;
    final double energyBefore = _energy;
    final int happinessBefore = _happiness;
    bool spentEnergy = false;

    final int price = _choicePrice(c);
    final String? kind = c.leisure;
    // P7: выбор тратит ⚡ — сначала проходит игровой день, один раз.
    if (kind != null || c.energy < 0) _dayPassed();
    final int afterDay = _happiness;
    if (kind != null) {
      if (c.payFromGoal) {
        _goal -= price;
        _depositsThisWeek -= price;
      } else {
        _payFromWantThenFree(price);
      }
      _spendLeisure(kind, _leisure[kind]!);
      if (price > 0) {
        _week?.purchases.add(
            WeekItem(id: kind, title: _leisure[kind]!.title, amount: price));
      }
      spentEnergy = true;
    }
    final String? buy = c.buy;
    if (buy != null) {
      _payFromWantThenFree(price);
      _owned[buy] = _weekNo;
      _week?.purchases
          .add(WeekItem(id: buy, title: _titleOf(buy), amount: price));
      _happiness = (_happiness + (_clothes[buy]?.fade.first ?? _decorHappiness))
          .clamp(0, 100);
      _write(WorldLedgerKind.itemOwned, '${_titleOf(buy)} за $price');
    }
    final int money = _pocketShare(c.moneyX);
    if (money > 0) {
      _free += money;
      _incomeThisWeek += money;
      _earnedThisWeek += money;
    } else if (money < 0) {
      _payFromWantThenFree(-money);
    }
    final int saved = _pocketShare(c.savingsX);
    _goal += saved;
    _depositsThisWeek += saved;
    // Подарок в копилку — новые деньги: доход недели, как в свёртке домена
    // (`income`), иначе очко «откладывал» даётся легче, чем в настоящей игре.
    if (saved > 0) {
      _incomeThisWeek += saved;
      _earnedThisWeek += saved;
    }
    _extraBill += _pocketShare(c.billX);
    _happiness = (_happiness + c.happiness).clamp(0, 100);
    if (c.energy != 0) {
      _energy = _r(math.min(_energyMax, math.max(0, _energy + c.energy)));
      spentEnergy = spentEnergy || c.energy < 0;
    }
    final String? flag = c.flag;
    if (flag != null) _flags.add(flag);
    _eventResolved = true;
    _week?.events.add(e.title);
    _write(WorldLedgerKind.eventChoice, '${e.id}: ${c.id}');
    _moodCause('event.choice', _happiness - afterDay);

    // Действие потратило ⚡ — неделя могла кончиться (как у досуга).
    final String tail = spentEnergy ? _afterEnergySpent() : '';
    return WorldResult(
      ok: true,
      reasonCode: 'event.choice',
      reason: '${_say(c.finni)}$tail',
      nextStep: c.nextStep,
      coins: snapshot.available - availableBefore,
      goal: _goal - goalBefore,
      energy: _r(_energy - energyBefore),
      happiness: _happiness - happinessBefore,
    );
  }

  /// Симуляция автомата «понарошку» — итог фиксированный: 20 вращений по
  /// 10, выиграно бы 70 (не больше половины потраченного, `max_win_share`).
  static const int _slotSpins = 20;
  static const int _slotSpinPrice = 10;
  static const int _slotWon = 70;

  /// Шесть событий из `content/events.json` (тексты оттуда). Здание — выбор
  /// фейка: в файле поля нет (open-questions Р4).
  static const List<_FakeEvent> _events = <_FakeEvent>[
    _FakeEvent(
      'slot_machine_sim',
      'savings',
      'park',
      'Друг в парке зовёт испытать удачу',
      'В парке стоит автомат с призами. Друг зовёт попробовать, а Финни '
          'предлагает сначала посмотреть, как он работает, — понарошку.',
      1,
      <_FakeChoice>[
        _FakeChoice(
            'simulate',
            'Прокрутить понарошку 20 раз',
            '{nick}, смотри счёт: потрачено бы {spent}, выиграно бы {won}. '
                'Автомат всегда забирает больше, чем отдаёт.',
            flag: 'slot_sim_done'),
        _FakeChoice('just_play_park', 'Отказаться и погулять с другом',
            'Ну его, {nick}! Погуляли с другом — и монеты все на месте.',
            leisure: 'park'),
      ],
    ),
    _FakeEvent(
      'grandma_gift',
      'savings',
      'home',
      'Бабушка подарила деньги',
      'Бабушка приехала в гости и подарила деньги — столько же, сколько '
          'карманные за неделю.',
      2,
      <_FakeChoice>[
        _FakeChoice('all_to_goal', 'Всё в копилку',
            '{nick}, копилка прямо подпрыгнула! Смотри, до цели стало ближе.',
            savingsX: 1, happiness: 2),
        _FakeChoice('half_half', 'Половину в копилку, половину себе',
            'И на цель, и на радость, {nick}. Что купим на свою половину?',
            savingsX: 0.5, moneyX: 0.5, happiness: 4),
        _FakeChoice('treat', 'Потратить на что-нибудь классное',
            '{nick}, деньги в кошельке — выбирай, что хочется! Цель подождёт.',
            moneyX: 1,
            happiness: 3,
            nextStep: 'Можно перевести часть в копилку в любой момент на '
                'экране цели.'),
      ],
    ),
    _FakeEvent(
      'want_cafe_empty_want',
      'planning',
      'cinema',
      'В ХОЧУ пусто, а хочется в кафе',
      'Друзья зовут в кафе, но конверт ХОЧУ уже пустой. В копилке кое-что '
          'есть.',
      2,
      <_FakeChoice>[
        _FakeChoice(
            'from_savings',
            'Взять из копилки',
            'Посидели классно, {nick}! Цель чуть отодвинулась — на экране цели '
                'видно, на сколько.',
            leisure: 'cafe',
            payFromGoal: true,
            nextStep: 'В следующем плане можно положить в ХОЧУ побольше.'),
        _FakeChoice('park_free', 'Позвать в парк — там бесплатно',
            '{nick}, в парке тоже нормально потусили! И копилка целая.',
            leisure: 'park'),
        _FakeChoice(
            'next_week',
            'Подождать до новых карманных',
            'Окей, {nick}, на следующей неделе положим в ХОЧУ побольше — и в '
                'кафе!',
            flag: 'want_bigger_next_plan'),
      ],
    ),
    _FakeEvent(
      'backpack_broke',
      'planning',
      'grocery',
      'Сломался рюкзак',
      'У рюкзака оторвалась лямка. Без рюкзака в школу неудобно — это новая '
          'обязательная трата.',
      3,
      <_FakeChoice>[
        _FakeChoice(
            'cheap_one',
            'Купить простой рюкзак',
            '{nick}, новый рюкзак есть, и недорого. Минус из НУЖНО — значит, '
                'план немного поменялся.',
            billX: 0.4),
        _FakeChoice('good_from_savings', 'Купить хороший из копилки',
            'Классный рюкзак, {nick}! Копилка похудела, цель чуть отодвинулась.',
            savingsX: -0.8,
            happiness: 4,
            nextStep: 'Смена-другая — и копилка вернётся к прежнему.'),
        _FakeChoice('fix_it', 'Починить самим',
            'Мы его зашили, {nick}! Сил ушло, а монет ни одной.',
            energy: -2, happiness: 2),
      ],
    ),
    _FakeEvent(
      'clothes_sale',
      'planning',
      'grocery',
      'Распродажа в магазине одежды',
      'В магазине одежды распродажа: толстовка за полцены. Она не нужна '
          'прямо сейчас, но очень нравится.',
      3,
      <_FakeChoice>[
        _FakeChoice(
            'buy',
            'Купить толстовку',
            '{nick}, толстовка огонь! Радость от обновки через пару недель '
                'поутихнет, а вещь останется.',
            buy: 'cloth_hoodie',
            discount: 0.5,
            nextStep: 'Если на обязательное станет не хватать, выручит смена.'),
        _FakeChoice(
            'put_on_list',
            'Добавить в список «хочу потом»',
            'Записали, {nick}. Если через неделю всё ещё будет хотеться — '
                'значит, правда нужна.',
            flag: 'hoodie_wishlist'),
        _FakeChoice('skip', 'Не покупать',
            'Окей, {nick}, монеты остаются на то, что задумали.'),
      ],
    ),
    _FakeEvent(
      'cinema_vs_pet_food',
      'planning',
      'cinema',
      'Друзья зовут в кино',
      'Друзья идут в кино прямо сейчас. Билет недешёвый, а корм питомцу на '
          'эту неделю ещё не отложен.',
      2,
      <_FakeChoice>[
        _FakeChoice(
            'go',
            'Пойти в кино',
            'Кино было огонь, {nick}! Корм ещё не отложен — глянем в конце '
                'недели, хватает ли.',
            leisure: 'cinema',
            nextStep: 'Если на корм не хватит, можно взять смену до «Спать».'),
        _FakeChoice('park_instead', 'Позвать всех в парк',
            '{nick}, в парке тоже весело вышло! И на корм ничего не потратили.',
            leisure: 'park'),
        _FakeChoice(
            'later',
            'Сходить на следующей неделе',
            'Ладно, {nick}, запланируем кино на следующую неделю. Отложим на '
                'билет в ХОЧУ?',
            happiness: -2,
            flag: 'cinema_planned'),
      ],
      needsPet: true,
    ),
  ];

  // ────────────────────────────── действия ──────────────────────────────

  WorldResult _wrongPhase(String what) => _phaseBlock(what).refusal;

  BlockReason _phaseBlock(String what) => BlockReason(
        'phase.$what',
        switch (_phase) {
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
    final bool first = _phase == WeekPhase.onboarding;
    _syncWeek(); // прошлая неделя закрывается со своими числами
    _phase = WeekPhase.weekStart;
    _earnedLastWeek = first ? null : _earnedThisWeek;
    _earnedThisWeek = 0;
    _goalsBoughtThisWeek = 0;
    _weekNo++;
    _weeks.add(WeekTally(_weekNo));
    _rentHomeId = _homeId;
    _energy = _r(math.min(
        _energyMax, _energyWeekStart + _homes[_homeId]!.energy + _carryEnergy));
    _carryEnergy = 0;
    _happinessAtWeekStart = _happiness;
    _shiftsThisWeek = 0;
    _shiftsByJob.clear();
    _parentBonusThisWeek = false;
    _leisureHappinessThisWeek = 0;
    _snacksThisWeek = 0;
    _mealsThisWeek = 0;
    _lessonJobId = null;
    _dayAtWeekStart = _day;
    _depositsThisWeek = 0;
    _endedBy = null;
    _billsPaid = false;
    _extraBill = 0;
    _weekEventId = null;
    _eventResolved = false;
    int goalDelta = 0;
    if (first) {
      _goal += config.startGift;
      goalDelta = config.startGift;
      _write(WorldLedgerKind.startGift,
          'Подарок на новоселье: ${config.startGift} в копилку');
    }
    _unallocated += _pocketMoney;
    _incomeThisWeek = _pocketMoney;
    _write(WorldLedgerKind.weekStarted,
        'Неделя $_weekNo: стипендия $_pocketMoney, ⚡ ${energyShown(_energy)}');
    _phase = WeekPhase.planning;
    return WorldResult(
      ok: true,
      reasonCode: first ? 'week.first' : 'week.start',
      reason: first
          ? 'Финни переехал! Стипендия за учёбу — $_pocketMoney, и подарок '
              '${config.startGift} уже в копилке.'
          : 'Неделя $_weekNo. Пришла стипендия — $_pocketMoney.',
      nextStep: 'Счёт недели от $_weeklyBill — разложи монеты по конвертам',
      coins: _pocketMoney,
      goal: goalDelta,
      energy: _energy,
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
    final int total = needs + wants + goal;
    if (total > _unallocated) {
      return WorldResult.refused('plan.too_much',
          'Разложено $total, а есть $_unallocated. Убери ${total - _unallocated}.');
    }
    final int rest = _unallocated - total;
    _need += needs;
    _want += wants;
    _goal += goal;
    _free += rest;
    _unallocated = 0;
    _depositsThisWeek += goal;
    _week
      ?..planMade = true
      ..planNeed = needs
      ..planWant = wants
      ..planGoal = goal;
    _phase = WeekPhase.living;
    _scheduleEvent();
    _write(LedgerKind.planConfirmed,
        'План: нужно $needs, хочу $wants, цель $goal, в кошелёк $rest');
    return WorldResult(
      ok: true,
      reasonCode: 'plan.confirmed',
      reason: 'План готов: нужно $needs, хочу $wants, цель $goal.',
      nextStep: needs < _weeklyBill
          ? 'На счета не хватает ${_weeklyBill - needs} — можно взять смену'
          : null,
      coins: -goal,
      goal: goal,
    );
  }

  bool _isGoalItem(String id) =>
      _pets.containsKey(id) ||
      _transports.containsKey(id) ||
      config.tech(id) != null ||
      (_homes.containsKey(id) && _homes[id]!.price > 0);

  @override
  WorldResult chooseGoal(String goalId) {
    final BlockReason? block = canDo(WorldAction.chooseGoal, id: goalId);
    if (block != null) return block.refusal;
    _activeGoalId = goalId;
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
    final WorldFood food = _food(foodId);
    _foodId = foodId;
    return WorldResult(
      ok: true,
      reasonCode: 'food.chosen',
      reason: 'Дома Финни ест: ${food.title}, ${food.price} за приём. '
          'Счёт недели: $_weeklyBill.',
    );
  }

  @override
  LessonOffer? get pendingLesson {
    final String? job = _lessonJobId;
    final WorldLesson? l = job == null ? null : config.lesson(job);
    if (l == null) return null;
    return lessonOffer(l, pay: _lessonPay, free: _free, want: _want);
  }

  @override
  WorldResult resolveLesson(String choiceId) {
    final String? job = _lessonJobId;
    final WorldLesson? l = job == null ? null : config.lesson(job);
    if (l == null) {
      return const WorldResult.refused('lesson.none', 'Сейчас урока нет.');
    }
    final WorldLessonChoice? c = l.choice(choiceId);
    if (c == null) {
      return WorldResult.refused(
          'lesson.unknown', 'Такого варианта нет: $choiceId.');
    }
    final LessonMove m =
        lessonMove(c, pay: _lessonPay, free: _free, want: _want);
    if (m.block != null) return m.block!.refusal;
    final int coinsBefore = _need + _want + _free + _unallocated;
    _free -= m.toGoal + m.toNeed + m.fromFree;
    _want -= m.fromWant;
    _goal += m.toGoal;
    _need += m.toNeed;
    _depositsThisWeek += m.toGoal;
    final int hBefore = _happiness;
    _happiness = (_happiness + c.happiness).clamp(0, 100);
    _moodCause('lesson.choice', _happiness - hBefore);
    _lessonJobId = null;
    _topics[l.topic] = (_topics[l.topic] ?? 0) + 1;
    if (!_words.any((({String id, String term}) w) => w.id == l.word)) {
      _words.add((id: l.word, term: l.wordTerm));
    }
    _week
      ?..events.add('Урок: ${l.title}')
      ..saved += m.toGoal
      ..wantSpent += m.fromFree + m.fromWant;
    _write(WorldLedgerKind.lessonChoice, 'Урок: ${l.title} — ${c.label}');
    return WorldResult(
      ok: true,
      reasonCode: 'lesson.choice',
      reason: lessonReason(l, c),
      nextStep: 'Новое слово в Словарике: ${l.wordTerm}',
      coins: _need + _want + _free + _unallocated - coinsBefore,
      goal: m.toGoal,
      happiness: _happiness - hBefore,
    );
  }

  @override
  WorldResult eat(String foodId) {
    final BlockReason? block = canDo(WorldAction.eat, id: foodId);
    if (block != null) return block.refusal;
    final WorldFood f = _food(foodId);
    // НУЖНО → заработок → ХОЧУ, как счета недели.
    int left = f.price;
    final int n = math.min(_need, left);
    _need -= n;
    left -= n;
    final int fr = math.min(_free, left);
    _free -= fr;
    left -= fr;
    _want -= left;
    final double before = _energy;
    _energy =
        _r(math.max(_energy, math.min(_energyMax, _energy + f.energyNow)));
    final double gain = _r(_energy - before);
    final int hBefore = _happiness;
    _happiness = (_happiness + f.happiness).clamp(0, 100);
    final int dh = _happiness - hBefore;
    _moodCause('meal.eaten', dh);
    _mealsThisWeek++;
    _week
      ?..bills += f.price
      ..food += f.price
      ..treats += f.treat ? f.price : 0;
    _write(WorldLedgerKind.mealEaten, '${f.title} за ${f.price}');
    final String full =
        gain + _eps < f.energyNow ? ' (⚡ уже почти полная)' : '';
    return WorldResult(
      ok: true,
      reasonCode: 'meal.eaten',
      reason: '${f.title}: ⚡ +${energyShown(gain)}$full, '
          '😊 ${dh < 0 ? dh : '+$dh'}${f.why.isEmpty ? '' : ' — ${f.why}'}.',
      nextStep: _mealsLeft > 0
          ? 'Поесть на этой неделе можно ещё $_mealsLeft '
              '${Phrases.timesWord(_mealsLeft)}'
          : 'На этой неделе Финни наелся',
      coins: -f.price,
      energy: gain,
      happiness: dh,
    );
  }

  /// Проверка конца недели по ⚡ после действия, которое её тратит.
  String _afterEnergySpent() {
    _day++;
    if (_energy + _eps < _cheapestAction) {
      _phase = WeekPhase.review;
      _endedBy = WeekEnd.energyOut;
      final int before = _happiness;
      _happiness = (_happiness + _exhaustedHappiness).clamp(0, 100);
      _moodCause('week.energy_out', _happiness - before, always: true);
      _write(WorldLedgerKind.energyOut, 'Силы кончились — Финни лёг спать');
      return ' Силы кончились — Финни устал и лёг спать.';
    }
    return '';
  }

  @override
  WorldResult completeJob(String jobId,
      {String? variant, required double score}) {
    final BlockReason? block =
        canDo(WorldAction.job, id: jobId, variant: variant);
    if (block != null) return block.refusal;
    final JobOffer o = _offerFor(_job(jobId, variant)!);
    // P1: хорошая смена — бонус, +1 опыт, сверх карточки ⚡ (не больше, чем
    // осталось) и 😊; обычная — ровно ставка. Как в домене.
    final double s = score.clamp(0.0, 1.0);
    final bool good = o.isGoodScore(s);
    final int bonus = o.bonusFor(s);
    final int pay = o.pay + bonus;
    final double extra = good
        ? math.max(0.0, math.min(o.goodEnergyExtra, _energy - o.energyCost))
        : 0.0;
    final double spent = _r(o.energyCost + extra);
    final int start = _happiness;
    _dayPassed();
    final int before = _happiness;
    if (good) {
      _happiness = (_happiness + o.goodHappiness).clamp(0, 100);
      _experience++;
    }
    _free += pay;
    _incomeThisWeek += pay;
    _earnedThisWeek += pay;
    _energy = _r(_energy - spent);
    _shiftsThisWeek++;
    _shiftsByJob[jobId] = (_shiftsByJob[jobId] ?? 0) + 1;
    _week?.shifts.add(WeekItem(id: jobId, title: o.title, amount: pay));
    _lessonJobId = jobId;
    _lessonPay = pay;
    _moodCause('job.payout', _happiness - before);
    _write(WorldLedgerKind.jobStarted, '${o.title}: ставка ${o.pay}');
    _write(WorldLedgerKind.jobPayout,
        '${o.title}: +$pay${good ? ', хорошая смена' : ''}');
    final String tail = _afterEnergySpent();
    return WorldResult(
      ok: true,
      reasonCode: 'job.payout',
      reason: good
          ? '${o.title}: хорошая работа! Заплатили ${o.pay}'
              '${bonus > 0 ? ' и $bonus за эффективность' : ''}, опыт +1.$tail'
          : '${o.title}: заплатили ${o.pay}. Опыт и бонус — за хорошо '
              'сделанную смену.$tail',
      nextStep: _activeGoalId == null
          ? 'Выбери цель в Копилке — и сможешь откладывать с заработка'
          : 'Сколько отложить на цель?',
      coins: pay,
      energy: -spent,
      happiness: _happiness - start,
    );
  }

  @override
  WorldResult depositToGoal(int amount) {
    if (amount <= 0) {
      return const WorldResult.refused(
          'goal.deposit_zero', 'Ничего не отложено — это тоже выбор.');
    }
    if (amount > _free) {
      return WorldResult.refused(
          'goal.deposit_too_much', 'В кошельке только $_free.');
    }
    _free -= amount;
    _goal += amount;
    _depositsThisWeek += amount;
    _write(WorldLedgerKind.goalSliderDeposit, 'На цель: $amount');
    return WorldResult(
      ok: true,
      reasonCode: 'goal.deposit',
      reason: 'Отложено на цель $amount. В кошельке осталось $_free.',
      coins: -amount,
      goal: amount,
    );
  }

  String _titleOf(String id) =>
      _pets[id]?.title ??
      _transports[id] ??
      config.tech(id)?.title ??
      _homes[id]?.title ??
      _clothes[id]?.title ??
      _decor[id]?.title ??
      (id == _snackId ? 'Перекус' : id);

  int _priceOf(String id) =>
      _pets[id]?.price ??
      (_transports.containsKey(id) ? _transportPrice : null) ??
      config.tech(id)?.price ??
      _homes[id]?.price ??
      _clothes[id]?.price ??
      _decor[id]?.price ??
      (id == _snackId ? _snackPrice : 0);

  /// Платит из ХОЧУ, затем из заработка. Возвращает false, если не хватает.
  bool _payFromWantThenFree(int price) {
    if (_want + _free < price) return false;
    final int fromWant = math.min(_want, price);
    _want -= fromWant;
    _free -= price - fromWant;
    _week?.wantSpent += price;
    return true;
  }

  @override
  WorldResult buy(String itemId) {
    final BlockReason? block = canDo(WorldAction.buy, id: itemId);
    if (block != null) return block.refusal;
    final String title = _titleOf(itemId);
    final int price = _priceOf(itemId);

    if (_isGoalItem(itemId)) {
      _goal -= price;
      _owned[itemId] = _weekNo;
      _goalsBoughtThisWeek++;
      final int before = _happiness;
      _happiness = (_happiness + _goalReachedBonus).clamp(0, 100);
      _moodCause('buy.goal', _happiness - before);
      if (_pets.containsKey(itemId)) {
        _activePetId ??= itemId;
        _write(WorldLedgerKind.petBought, '$title за $price');
      } else if (_transports.containsKey(itemId)) {
        _write(WorldLedgerKind.transportBought, '$title за $price');
      } else if (config.tech(itemId) != null) {
        _write(WorldLedgerKind.techBought, '$title за $price');
      } else {
        final WorldStage stageBefore = _stage;
        _homeId = itemId;
        _write(WorldLedgerKind.homeBought, '$title за $price');
        if (_stage != stageBefore) {
          _write(WorldLedgerKind.stageChanged, 'Новая стадия: ${_stage.name}');
        }
      }
      if (_activeGoalId == itemId) _activeGoalId = null;
      _week
        ?..purchases.add(WeekItem(id: itemId, title: title, amount: price))
        ..goalsReached.add(title);
      final String food = _pets.containsKey(itemId)
          ? ' Корм +${_pets[itemId]!.food} к счёту со следующей недели.'
          : '';
      return WorldResult(
        ok: true,
        reasonCode: 'buy.goal',
        reason: config.home(itemId) != null && _stage.index > 0
            ? 'Финни переезжает: $title! Залог и первая неделя — $price. '
                'Дальше ${_homes[itemId]!.rent} в неделю: жизнь лучше и платят '
                'больше, но и всё дороже.'
            : 'Цель достигнута: $title!$food',
        goal: -price,
        happiness: _happiness - before,
      );
    }

    if (itemId == _snackId) {
      _payFromWantThenFree(price);
      _week?.purchases.add(WeekItem(id: itemId, title: title, amount: price));
      _snacksThisWeek++;
      final double before = _energy;
      _energy = _r(math.min(_energyMax, _energy + _snackEnergy));
      return WorldResult(
        ok: true,
        reasonCode: 'buy.snack',
        reason: 'Перекус: +${_r(_energy - before)} ⚡.',
        coins: -price,
        energy: _r(_energy - before),
      );
    }

    final bool cloth = _clothes.containsKey(itemId);
    _payFromWantThenFree(price);
    _week?.purchases.add(WeekItem(id: itemId, title: title, amount: price));
    _owned[itemId] = _weekNo;
    final int gain = cloth ? _clothes[itemId]!.fade.first : _decorHappiness;
    final int before = _happiness;
    _happiness = (_happiness + gain).clamp(0, 100);
    _moodCause('buy.item', _happiness - before);
    _write(WorldLedgerKind.itemOwned, '$title за $price');
    return WorldResult(
      ok: true,
      reasonCode: 'buy.item',
      reason: 'Куплено: $title.',
      coins: -price,
      happiness: _happiness - before,
    );
  }

  @override
  WorldResult leisure(String kind) {
    final BlockReason? block = canDo(WorldAction.leisure, id: kind);
    if (block != null) return block.refusal;
    final _Leisure l = _leisure[kind]!;
    final double cost = _leisureEnergy(l);
    _payFromWantThenFree(l.price);
    if (l.price > 0) {
      _week?.purchases.add(WeekItem(id: kind, title: l.title, amount: l.price));
    }
    final int before = _happiness;
    _dayPassed();
    final ({int raw, int gain}) h = _spendLeisure(kind, l);
    final int raw = h.raw;
    final int gain = h.gain;
    final String tail = _afterEnergySpent();
    return WorldResult(
      ok: true,
      reasonCode: 'leisure.done',
      reason: gain < raw
          ? '${l.title}. Весело, но на этой неделе отдых радует уже меньше.$tail'
          : '${l.title} — Финни отдохнул.$tail',
      coins: -l.price,
      energy: -cost,
      happiness: _happiness - before,
    );
  }

  @override
  WorldResult petTap(String petId) {
    if (!_owned.containsKey(petId) || !_pets.containsKey(petId)) {
      return const WorldResult.refused('pet.none', 'Такого питомца пока нет.');
    }
    if (_lastTapDay == _day) {
      return WorldResult(
        ok: true,
        reasonCode: 'pet.tap_again',
        reason: '${_pets[petId]!.title} рад тебе!',
      );
    }
    _lastTapDay = _day;
    final int before = _happiness;
    _happiness = (_happiness + _petTapHappiness).clamp(0, 100);
    _moodCause('pet.tap', _happiness - before);
    _write(WorldLedgerKind.petTapHappiness, '${_pets[petId]!.title}: +1 😊');
    return WorldResult(
      ok: true,
      reasonCode: 'pet.tap',
      reason: '${_pets[petId]!.title} рад тебе — Финни веселее.',
      happiness: _happiness - before,
    );
  }

  @override
  WorldResult sleep() {
    final BlockReason? block = canDo(WorldAction.sleep);
    if (block != null) return block.refusal;
    final bool bonus = _energy + _eps >= _sleepMinLeft;
    int gain = 0;
    if (bonus) {
      gain = _sleepHappiness + (_owned.containsKey('pet_hamster') ? 2 : 0);
      _carryEnergy = _sleepCarry + (_owned.containsKey('pet_turtle') ? 1 : 0);
    }
    final int before = _happiness;
    _happiness = (_happiness + gain).clamp(0, 100);
    _moodCause(bonus ? 'sleep.bonus' : 'sleep.plain', _happiness - before);
    _phase = WeekPhase.review;
    _endedBy = WeekEnd.sleep;
    _write(WorldLedgerKind.sleep, bonus ? 'Спать раньше: бонус' : 'Спать');
    final int money = _need + _want + _free;
    return WorldResult(
      ok: true,
      reasonCode: bonus ? 'sleep.bonus' : 'sleep.plain',
      reason: bonus
          ? 'Финни выспался: +$gain 😊 и +${energyShown(_carryEnergy)} ⚡ на следующую неделю.'
          : 'Финни лёг спать.',
      nextStep: money < _weeklyBill
          ? 'На счета не хватает ${_weeklyBill - money} — посмотрим, что можно сделать'
          : null,
      happiness: _happiness - before,
    );
  }

  /// Списать [amount] из карманов по порядку: НУЖНО → заработок → ХОЧУ.
  void _spend(int amount) {
    int left = amount;
    final int n = math.min(_need, left);
    _need -= n;
    left -= n;
    final int f = math.min(_free, left);
    _free -= f;
    left -= f;
    final int w = math.min(_want, left);
    _want -= w;
    left -= w;
    assert(left == 0, 'списано больше, чем было');
  }

  @override
  WorldResult payBills({bool takeFromGoal = false}) {
    final BlockReason? block = canDo(WorldAction.payBills);
    if (block != null) return block.refusal;
    final int money = _need + _want + _free;
    final int petFood = _petFoodBill;
    // Добавка события (рюкзак) — обязательная, платится вместе с жильём.
    final int rent = _homes[_rentHomeId]!.rent + _extraBill;
    String eatenFood = _foodId;
    final List<String> steps = <String>[];
    final int meals = _mealsLeft;

    // 1. Корм питомцам — первым: питомцу навредить нельзя (ТЗ §2).
    // 2. На домашнее меню не хватает — простое блюдо.
    if (meals > 0 &&
        money < petFood + _food(eatenFood).price * meals + rent &&
        eatenFood != _simpleFood) {
      eatenFood = _simpleFood;
      steps.add('взяли простую еду');
    }
    final int foodDue = _food(eatenFood).price * meals;
    final int due = petFood + foodDue + rent;
    int missing = math.max(0, due - money);
    final int fromPockets = due - missing;
    _spend(fromPockets);

    // 3. Из накоплений — только с согласия.
    int withdrawn = 0;
    if (missing > 0 && takeFromGoal && _goal > 0) {
      withdrawn = math.min(missing, _goal);
      _goal -= withdrawn;
      missing -= withdrawn;
      // Очко «откладывал» — за чистое отложенное, как в домене.
      _depositsThisWeek -= withdrawn;
      steps.add('$withdrawn из копилки');
    }

    // 4. Остаток — «семья помогает».
    final bool familyHelped = missing > 0;
    final int before = _happiness;
    if (familyHelped) {
      steps.add('семья помогла с $missing');
      _write(WorldLedgerKind.familyHelp, 'Семья помогла: $missing');
    }
    _write(WorldLedgerKind.billPaid,
        'Счета: корм $petFood, еда $foodDue, жильё $rent');

    // Очки роста (T1) — до 😊: от них зависит «переезд» в проверке роста.
    final WorldStage stageBefore = _stage;
    int points = 0;
    final List<String> why = <String>[];
    int pointsFor(String reason) => config.growthPointsPerReason[reason] ?? 0;
    if (!familyHelped) {
      points += pointsFor('required_covered');
      why.add('обязательное закрыто своими деньгами');
    }
    if (steps.isEmpty) {
      points += pointsFor('plan_kept');
      why.add('без нехватки');
    }
    final bool savedRegularly = _depositsThisWeek > 0 &&
        _depositsThisWeek >= _incomeThisWeek * config.savedRegularlyMinShare;
    if (savedRegularly) {
      points += pointsFor('saved_regularly');
      why.add('отложено не меньше '
          '${(config.savedRegularlyMinShare * 100).round()} % дохода — так к цели приходят раньше');
    }

    // Рост недели к прошлой (P7) — то же правило, что у домена.
    String? growth;
    int growthDelta = 0;
    final int? earnedBefore = _earnedLastWeek;
    if (earnedBefore != null) {
      final bool up = (_earnedThisWeek > 0 &&
              _earnedThisWeek >=
                  earnedBefore * (1 + config.weekGrowthIncomeMinShare) -
                      _eps) ||
          savedRegularly ||
          _goalsBoughtThisWeek > 0 ||
          _stageFor(_growthPoints + points) != stageBefore;
      if (up) {
        growth = weekGrowthUp;
        growthDelta = config.weekGrowthBonus;
        _flatWeeks = 0;
      } else {
        growth = weekGrowthFlat;
        _flatWeeks++;
        growthDelta =
            -math.min(config.stagnationMax, config.stagnationStep * _flatWeeks);
      }
    }

    // Недельное 😊: еда, питомцы, дом, одежда, рост, остывание, помощь семьи.
    int weekly = _food(eatenFood).happiness * meals + growthDelta;
    weekly += math.min(
        _petsHappinessCap,
        _feedingPets.fold<int>(
            0, (int a, String id) => a + _pets[id]!.happiness));
    weekly += _homes[_rentHomeId]!.happiness;
    for (final MapEntry<String, _Cloth> c in _clothes.entries) {
      final int? bought = _owned[c.key];
      if (bought == null) continue;
      final int age = _weekNo - bought;
      if (age >= 1 && age < c.value.fade.length) weekly += c.value.fade[age];
    }
    final double decay = config.weeklyDecayBase +
        config.weeklyDecayK *
            (_happinessAtWeekStart - config.happinessNeutral) +
        (_feedingPets.contains('pet_fish') ? -1 : 0);
    weekly -= decay.round();
    if (familyHelped) weekly += _familyHelpHappiness;
    _happiness = (_happiness + weekly).clamp(0, 100);
    _moodCause(
        weekClosedMoodCause(
          fromFamily: missing,
          fromGoal: withdrawn,
          downgraded: eatenFood != _foodId,
          endedBy: _endedBy,
          growth: growth,
        ),
        _happiness - before,
        always: true);

    _growthPoints += points;
    final bool grew = _stage != stageBefore;
    if (grew) {
      _write(WorldLedgerKind.stageChanged, 'Новая стадия: ${_stage.name}');
    }

    _carryEnergy += _r(_food(eatenFood).energyNow * meals);
    _billsPaid = true;
    _week
      ?..bills += due
      ..food += foodDue
      ..treats += _food(eatenFood).treat ? foodDue : 0
      ..billsPaid = true;

    final String shortfall =
        steps.isEmpty ? '' : ' Не хватало: ${steps.join(', ')}.';
    return WorldResult(
      ok: true,
      reasonCode: familyHelped ? 'bills.family_help' : 'bills.paid',
      reason: 'Счета недели — $due.$shortfall Очки роста: +$points'
          '${why.isEmpty ? '' : ' (${why.join(', ')})'}.'
          '${growth == weekGrowthUp ? ' Неделя роста: +$growthDelta 😊.' : ''}'
          '${growth == weekGrowthFlat ? ' Неделя без роста: $growthDelta 😊.' : ''}'
          '${grew ? ' Финни переезжает дальше!' : ''}',
      nextStep: 'Новая неделя',
      coins: -fromPockets,
      goal: -withdrawn,
      happiness: _happiness - before,
    );
  }

  @override
  WorldResult withdrawFromGoal(int amount) {
    if (_phase == WeekPhase.onboarding) return _wrongPhase('withdraw');
    if (amount <= 0 || amount > _goal) {
      return WorldResult.refused(
          'goal.withdraw_bad', 'В копилке $_goal — столько снять не выйдет.');
    }
    _goal -= amount;
    _free += amount;
    // Чистое отложенное: положил и снял в ту же неделю — очка нет (как домен).
    _depositsThisWeek -= amount;
    _write(LedgerKind.savingsWithdraw, 'Снято из копилки: $amount');
    return WorldResult(
      ok: true,
      reasonCode: 'goal.withdraw',
      reason: 'Снято из копилки $amount. Было ${_goal + amount}, стало $_goal.',
      coins: amount,
      goal: -amount,
    );
  }
}

class _Home {
  const _Home(this.title, this.price, this.rent, this.energy, this.happiness);
  final String title;
  final int price;
  final int rent;
  final double energy;
  final int happiness;
}

class _Pet {
  const _Pet(this.title, this.price, this.food, this.happiness);
  final String title;
  final int price;
  final int food;
  final int happiness;
}

class _Priced {
  const _Priced(this.title, this.price);
  final String title;
  final int price;
}

class _Cloth {
  const _Cloth(this.title, this.price, this.fade);
  final String title;
  final int price;
  final List<int> fade;
}

class _Leisure {
  const _Leisure(this.title, this.price, this.energy, this.happiness);
  final String title;
  final int price;
  final double energy;
  final int happiness;
}

class _Job {
  const _Job(this.id, this.variant, this.title, this.pay, this.energy,
      {this.needs});
  final String id;
  final String? variant;
  final String title;
  final int pay;
  final double energy;

  /// Что нужно, чтобы открыть: `transport` или id питомца.
  final String? needs;
}

/// Событие фейка — подмножество `events.json → events[]`.
class _FakeEvent {
  const _FakeEvent(this.id, this.topic, this.buildingId, this.title, this.text,
      this.minWeek, this.choices,
      {this.needsPet = false});
  final String id;
  final String topic;
  final String buildingId;
  final String title;
  final String text;
  final int minWeek;
  final List<_FakeChoice> choices;
  final bool needsPet;
}

/// Вариант события: эффекты из `_effects_schema` (доли — от карманных).
class _FakeChoice {
  const _FakeChoice(this.id, this.label, this.finni,
      {this.nextStep,
      this.leisure,
      this.payFromGoal = false,
      this.moneyX = 0,
      this.savingsX = 0,
      this.billX = 0,
      this.happiness = 0,
      this.energy = 0,
      this.buy,
      this.discount = 0,
      this.flag});
  final String id;
  final String label;
  final String finni;
  final String? nextStep;
  final String? leisure;
  final bool payFromGoal;
  final double moneyX;
  final double savingsX;
  final double billX;
  final int happiness;
  final double energy;
  final String? buy;
  final double discount;
  final String? flag;
}
