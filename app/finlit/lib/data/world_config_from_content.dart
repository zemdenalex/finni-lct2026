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
    transportDiscount = -value;
    transportMin = minCost;
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
        sleepCarryPerks[p.id] = value;
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
          pay: t.pay,
          energy: t.energy,
          needs: t.unlockedBy ?? rate.unlockedBy,
        ),
  ];

  return WorldConfig(
    pocketMoney: e.pocketMoney,
    startGift: e.startGiftAmount,
    energyBasePerWeek: e.energyBasePerWeek,
    energyMax: e.energyMaxPerWeek,
    livingDrainPerAction: e.livingDrainPerAction,
    sleepMinLeftForBonus: e.sleepMinLeftForBonus,
    sleepCarryNextWeek: e.sleepCarryNextWeek,
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
    petTapHappiness: e.petDailyTouchHappiness,
    familyHelpHappiness: familyHelp,
    simpleFoodId: simpleFoodId,
    // Отдельного «стартового уровня еды» в файле нет: стартуем с той же
    // простой еды, на которую понижает правило нехватки.
    startFoodId: simpleFoodId,
    startHomeId: e.homeStart,
    mealsPerWeek: e.mealsPerWeek,
    stageByRent: e.stageByRent,
    maxShiftsPerWeek: e.maxShiftsPerWeek,
    maxShiftsPerJobPerWeek: e.maxShiftsPerJobPerWeek,
    experienceGrowth: e.experienceMultPerShift,
    goodScoreMin: e.goodScoreMin,
    goodShiftEnergyExtra: e.goodShiftEnergyExtra,
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
    snackEnergyNow: e.snackEnergyNow,
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
          energyNow: f.energyNow,
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
          energyPerWeek: h.energyPerWeek,
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
          energy: l.energy,
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
    events: _events(content.events),
    lessons: content.lessons,
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
List<WorldEventSpec> _events(List<WorldEvent> events) {
  try {
    return parseWorldEvents(events.map((WorldEvent e) => e.data));
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
