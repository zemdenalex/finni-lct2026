import '../domain/world/achievements.dart' show AchievementDef;
import '../domain/world/world_config.dart';
import '../domain/world/world_events.dart';
import 'world_content.dart';

/// Числа из `content/economy.json` → [WorldConfig] для `WorldGame`.
///
/// 🔴 Слои: домен не импортирует `data` (`layering_test`), поэтому перенос
/// живёт здесь. Каждое число берётся из файла; где форма файла и домена
/// расходится, перевод назван прямо:
///
/// - перк `pay_mult` в файле — доля (`value: 0.1`), в домене — множитель
///   (`1 + value` = 1,1), и перемножается с остальными;
/// - транспорт в файле — `shift_energy_delta: −0.5, min_cost: 1`, в домене —
///   `transportDiscount = −value` и `transportMinJobEnergy = min_cost`;
///   порядок домена: база × 😊, скидка, минимум, потом +1 «на жизнь»;
/// - декор: id из файла как есть (`poster_city`…), 😊 — `happiness_once`
///   один раз при покупке;
/// - в игру идут только питомцы `tier: demo`, резерв — после 29.09;
/// - название уровня работы — «Работа · уровень» из `tiers[].name`;
/// - замок уровня (`tiers[].unlocked_by`) сильнее замка работы — сложные
///   задачи программиста открывает только мощный ноутбук;
/// - техника (`tech.options`) — цели с возможностями `unlocks`;
/// - события — `events.json → events[]` целиком ([parseWorldEvents]);
///   ошибка разбора события — тоже [WorldContentError] с путём.
///
/// Перк, который домен исполнить не умеет, у питомца `demo` — ошибка с
/// путём до поля, а не тихая потеря.
WorldConfig worldConfigFromContent(WorldContent content) {
  final EconomyContent e = content.economy;
  final DayCycle dc = e.dayCycle;
  // Профиль баланса (режим дней): монеты × pay_scale вверх до десятка — та
  // же шкала у оплаты смен и у трат уроков, иначе урок стоит больше смены.
  int coins(int n) =>
      dc.enabled && dc.payScale != 1 ? ceilTens(n * dc.payScale) : n;
  // Масштаб ⚡ режима дней ([DayCycle.energyScale]); в режиме «неделя» — 1.
  final double s = dc.enabled ? dc.energyScale : 1;

  ShortfallStep step(String id) {
    for (final ShortfallStep s in e.shortfallOrder) {
      if (s.step == id) return s;
    }
    throw WorldContentError(
        'economy.json', 'shortfall_rule.order', 'нет шага «$id»');
  }

  final String? simpleFoodId = step('downgrade_food').to;
  if (simpleFoodId == null) {
    throw const WorldContentError('economy.json',
        'shortfall_rule.order[downgrade_food].to', 'поле отсутствует');
  }
  final int? familyHelp = step('family_help').happiness;
  if (familyHelp == null) {
    throw const WorldContentError('economy.json',
        'shortfall_rule.order[family_help].happiness', 'поле отсутствует');
  }

  double transportDiscount = 0;
  double transportMin = 0;
  for (final TransportEffect t in e.transport.effects) {
    if (t.type != 'shift_energy_delta') continue;
    final double? value = t.value;
    final double? minCost = t.minCost;
    if (value == null || minCost == null) {
      throw const WorldContentError('economy.json', 'transport.effects',
          'у shift_energy_delta нужны value и min_cost');
    }
    transportDiscount = -value * s;
    transportMin = minCost * s;
  }

  final List<PetOption> pets =
      e.pets.where((PetOption p) => p.tier == 'demo').toList();
  final Map<String, int> sleepHappinessPerks = <String, int>{};
  final Map<String, double> sleepCarryPerks = <String, double>{};
  final Map<String, double> decayPerks = <String, double>{};
  final Map<String, ({String jobId, double mult})> payPerks =
      <String, ({String jobId, double mult})>{};
  for (final PetOption p in pets) {
    final PetPerk perk = p.perk;
    final double value = perk.value ?? 0;
    switch (perk.type) {
      case 'sleep_happiness_delta':
        sleepHappinessPerks[p.id] = value.round();
      case 'sleep_carry_delta':
        sleepCarryPerks[p.id] = value * s;
      case 'happiness_decay_delta':
        decayPerks[p.id] = value;
      case 'pay_mult':
        final String? job = perk.job;
        if (job == null) {
          throw WorldContentError('economy.json',
              'pets.roster[${p.id}].perk.job', 'поле отсутствует');
        }
        payPerks[p.id] = (jobId: job, mult: 1 + value);
      case 'unlocks_job':
      case 'collection_rare':
        // Работу открывает `jobs.<id>.unlocked_by`; редкий слот — без чисел.
        break;
      default:
        throw WorldContentError(
            'economy.json',
            'pets.roster[${p.id}].perk.type',
            '«${perk.type}» — домен такой перк не исполняет');
    }
  }

  final List<WorldJob> jobs = <WorldJob>[
    for (final JobRate rate in e.jobs.values)
      for (final JobTier t in rate.tiers)
        WorldJob(
          id: rate.id,
          variant: t.id.isEmpty ? null : t.id,
          title: t.id.isEmpty ? rate.name : '${rate.name} · ${t.name ?? t.id}',
          // Профиль баланса: оплата × pay_scale вверх до десятка (дни).
          pay: coins(t.pay),
          energy: t.energy * s,
          needs: t.unlockedBy ?? rate.unlockedBy,
          moodKind: rate.moodKind,
        ),
  ];

  return WorldConfig(
    pocketMoney: e.pocketMoney,
    startGift: e.startGiftAmount,
    energyBasePerWeek: e.energyBasePerWeek,
    // Режим дней со своим пределом ⚡ (DEN-18): 20 вместо недельных 14.
    energyMax: e.dayCycle.enabled && e.dayCycle.energyMax != null
        ? e.dayCycle.energyMax!
        : e.energyMaxPerWeek,
    livingDrainPerAction: e.livingDrainPerAction * s,
    sleepMinLeftForBonus: e.sleepMinLeftForBonus,
    sleepCarryNextWeek: e.sleepCarryNextWeek * s,
    sleepHappiness: e.sleepHappiness,
    exhaustedHappiness: e.exhaustedHappiness,
    happinessStart: e.happinessStart,
    happinessMin: e.happinessMin,
    happinessMax: e.happinessMax,
    happinessNeutral: e.happinessNeutral,
    payMultPerPoint: e.payMult.perPoint,
    payMultMin: e.payMult.min,
    payMultMax: e.payMult.max,
    energyCostMultPerPoint: e.energyCostMult.perPoint,
    energyCostMultMin: e.energyCostMult.min,
    energyCostMultMax: e.energyCostMult.max,
    weeklyDecayBase: e.decayBase,
    weeklyDecayK: e.decayK,
    happinessDayDrain: e.dayDrain,
    weekGrowthIncomeMinShare: e.weekGrowth.incomeMinShare,
    weekGrowthBonus: e.weekGrowth.growthBonus,
    stagnationStep: e.weekGrowth.stagnationStep,
    stagnationMax: e.weekGrowth.stagnationMax,
    leisureWeeklyCap: e.leisureWeeklyCap,
    goalReachedBonus: e.goalReachedBonus,
    petsHappinessCap: e.petsHappinessTotalCap,
    dayCycle: e.dayCycle,
    shareParent: e.shareParent,
    bankTransfer: e.bankTransfer,
    room: content.room,
    eventsPerWeekMax: dc.enabled ? dc.eventsPerWeek ?? 2 : 2,
    achievements: <AchievementDef>[
      ...e.achievements,
      if (dc.enabled && e.achievementsDays) ...e.achievementsDaysItems,
    ],
    achievementsDays: dc.enabled && e.achievementsDays,
    adultSection: e.adultSection,
    petTapHappiness: e.petDailyTouchHappiness,
    finniPetHappiness: e.finniPetHappiness,
    familyHelpHappiness: familyHelp,
    simpleFoodId: simpleFoodId,
    // Отдельного «стартового уровня еды» в файле нет: стартуем с той же
    // простой еды, на которую понижает правило нехватки.
    startFoodId: simpleFoodId,
    startHomeId: e.homeStart,
    mealsPerWeek:
        dc.enabled ? dc.mealsPerWeek ?? e.mealsPerWeek : e.mealsPerWeek,
    stageByRent: e.stageByRent,
    maxShiftsPerWeek: dc.enabled
        ? dc.maxShiftsPerWeek ?? e.maxShiftsPerWeek
        : e.maxShiftsPerWeek,
    maxShiftsPerJobPerWeek: dc.enabled
        ? dc.maxShiftsPerJobPerWeek ?? e.maxShiftsPerJobPerWeek
        : e.maxShiftsPerJobPerWeek,
    experienceGrowth: e.experienceMultPerShift,
    goodScoreMin: e.goodScoreMin,
    adultWeeklyBonus: e.adultWeeklyBonus,
    adultWeeklyBonusCoins: e.adultWeeklyBonusCoins,
    goodShiftEnergyExtra: e.goodShiftEnergyExtra * s,
    goodShiftHappiness: e.goodShiftHappiness,
    efficiencyShare: e.efficiencyBonusMaxShare,
    savedRegularlyMinShare: e.savedRegularlyMinShare,
    growthPointsPerReason: <String, int>{
      'required_covered': e.pointsRequiredCovered,
      'plan_kept': e.pointsPlanKept,
      'saved_regularly': e.pointsSavedRegularly,
    },
    stageMinPoints: e.stages.map((StageRule s) => s.minPoints).toList(),
    stageSteps: e.stages.map((StageRule s) => s.payStep).toList(),
    snackId: e.snackId,
    snackPrice: e.snackPrice,
    snackEnergyNow: e.snackEnergyNow * s,
    snackMaxPerWeek: e.snackMaxPerWeek,
    transportPrice: e.transport.price,
    transportDiscount: transportDiscount,
    transportMinJobEnergy: transportMin,
    foods: <WorldFood>[
      for (final FoodOption f in e.food)
        WorldFood(
          id: f.id,
          title: f.name,
          price: f.price,
          happiness: f.happiness,
          energyNow: f.energyNow * s,
          treat: f.treat,
          why: f.why,
        ),
    ],
    homes: <WorldHome>[
      for (final HomeOption h in e.homes)
        WorldHome(
          id: h.id,
          title: h.name,
          price: h.price,
          weeklyCost: h.weeklyCost,
          energyPerWeek: h.energyPerWeek * s,
          happinessPerWeek: h.happinessPerWeek,
          stage: h.stage,
        ),
    ],
    pets: <WorldPet>[
      for (final PetOption p in pets)
        WorldPet(
          id: p.id,
          title: p.name,
          price: p.price,
          foodPerWeek: p.foodPerWeek,
          happinessPerWeek: p.happinessPerWeek,
        ),
    ],
    transports: <String, String>{
      for (final NamedOption t in e.transport.options) t.id: t.name,
    },
    techs: <WorldTech>[
      for (final TechOption t in e.tech)
        WorldTech(id: t.id, title: t.name, price: t.price, unlocks: t.unlocks),
    ],
    clothes: <WorldItem>[
      for (final ClothingItem c in e.clothing)
        WorldItem(
            id: c.id, title: c.name, price: c.price, happinessByWeek: c.fade),
    ],
    decor: <WorldItem>[
      for (final DecorItem d in e.decor.items)
        WorldItem(
          id: d.id,
          title: d.name,
          price: d.price,
          happinessByWeek: <int>[e.decor.happinessOnce],
        ),
    ],
    leisure: <WorldLeisure>[
      for (final LeisureOption l in e.leisure)
        WorldLeisure(
          id: l.id,
          title: l.name,
          price: l.price,
          energy: l.energy * s,
          happiness: l.happiness,
          perExtraPet: l.perExtraPet ?? 0,
          requires: _leisureRequires(l),
        ),
    ],
    jobs: jobs,
    sleepHappinessPerks: sleepHappinessPerks,
    sleepCarryPerks: sleepCarryPerks,
    decayPerks: decayPerks,
    payPerks: payPerks,
    events: _events(content.events, s),
    lessons: <WorldLesson>[
      for (final WorldLesson l in content.lessons) _scaledLesson(l, coins),
    ],
  );
}

/// Урок с монетами в масштабе профиля: трата × [coins], в текстах
/// `{coins:N}` → [coins] от N (в «неделе» — само N). Числа без плейсхолдера
/// не трогаются: у кассира арифметика сдачи (30, 100, 70) масштаб не пережила
/// бы — после округления «сдача» перестала бы сходиться.
WorldLesson _scaledLesson(WorldLesson l, int Function(int) coins) {
  String text(String s) => s.replaceAllMapped(
      RegExp(r'\{coins:(\d+)\}'), (Match m) => '${coins(int.parse(m[1]!))}');
  return WorldLesson(
    id: l.id,
    jobId: l.jobId,
    topic: l.topic,
    title: text(l.title),
    situation: text(l.situation),
    understood: text(l.understood),
    word: l.word,
    wordTerm: l.wordTerm,
    choices: <WorldLessonChoice>[
      for (final WorldLessonChoice c in l.choices)
        WorldLessonChoice(
          id: c.id,
          label: text(c.label),
          finni: text(c.finni),
          goalShare: c.goalShare,
          needShare: c.needShare,
          spend: coins(c.spend),
          happiness: c.happiness,
        ),
    ],
  );
}

/// `leisure.options[].requires`: домен умеет только [WorldLeisure.anyPet];
/// другое условие — ошибка с путём, а не досуг без условия.
String? _leisureRequires(LeisureOption l) {
  final String? r = l.requires;
  if (r == null || r == WorldLeisure.anyPet) return r;
  throw WorldContentError('economy.json', 'leisure.options[${l.id}].requires',
      '«$r» — домен такое условие не исполняет');
}

/// События недели: эффекты разбирает домен ([parseWorldEvents]), его
/// [FormatException] («путь: что не так») становится [WorldContentError].
List<WorldEventSpec> _events(List<WorldEvent> events, double scale) {
  try {
    return parseWorldEvents(
        events.map((WorldEvent e) => _scaleEnergy(e.data, scale)));
  } on FormatException catch (e) {
    const String prefix = 'events.json → ';
    String message = e.message;
    if (message.startsWith(prefix)) message = message.substring(prefix.length);
    final int colon = message.indexOf(': ');
    if (colon < 0) throw WorldContentError('events.json', '', message);
    throw WorldContentError('events.json', message.substring(0, colon),
        message.substring(colon + 2));
  }
}

/// Копия события с ⚡ × [scale]: эффекты `energy`, `energy_next_week` и
/// условия `energy_min`/`energy_max` (режим дней, [DayCycle.energyScale]).
Object? _scaleEnergy(Object? v, double scale) {
  if (scale == 1) return v;
  if (v is Map<String, Object?>) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> e in v.entries)
        e.key: _energyKeys.contains(e.key) && e.value is num
            ? (e.value! as num) * scale
            : _scaleEnergy(e.value, scale),
    };
  }
  if (v is List<Object?>) {
    return <Object?>[for (final Object? x in v) _scaleEnergy(x, scale)];
  }
  return v;
}

const Set<String> _energyKeys = <String>{
  'energy',
  'energy_next_week',
  'energy_min',
  'energy_max',
};
