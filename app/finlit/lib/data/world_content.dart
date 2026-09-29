import 'dart:convert';

import '../domain/world/contract.dart';
import 'content_loader.dart' show ReadAsset;
import '../domain/world/world_config.dart' show WorldLesson, WorldLessonChoice;

/// Контент нового мира Финни: `economy.json`, `jobs.json`, `events.json`
/// из корня репозитория `content/`, копия — в `assets/content/world/`.
///
/// Код читает ключи и не пишет чисел (ТЗ 3.2.3). Значений по умолчанию нет:
/// пропущенное или неверного типа поле — [WorldContentError] с полным путём
/// до поля (`economy.json → jobs.courier.tiers[1].pay`), до сборки, а не на
/// демонстрации. Ключи, начинающиеся с `_`, — комментарии, их не читаем.
///
/// Живёт рядом со старым [ContentLoader] (миграция добавлением): старый
/// `assets/content/economy.json` и его модели не трогаются, пока экраны не
/// переключены на новый мир.
class WorldContentLoader {
  const WorldContentLoader(this.read);

  final ReadAsset read;

  static const String base = 'assets/content/world';

  Future<WorldContent> load() async => WorldContent.parse(
        economy: await read('$base/economy.json'),
        jobs: await read('$base/jobs.json'),
        events: await read('$base/events.json'),
      );
}

/// Ошибка схемы контента: какой файл, какое поле и что с ним не так.
class WorldContentError implements Exception {
  const WorldContentError(this.file, this.path, this.problem);

  final String file;

  /// Путь до поля: `jobs.courier.tiers[1].pay`. Пусто — файл целиком.
  final String path;

  final String problem;

  @override
  String toString() =>
      'WorldContentError: $file${path.isEmpty ? '' : ' → $path'}: $problem';
}

// ------------------------------------------------------------------ economy

class FoodOption {
  const FoodOption({
    required this.id,
    required this.name,
    required this.price,
    required this.happiness,
    required this.energyNow,
    this.treat = false,
    this.why = '',
  });

  final String id;
  final String name;

  /// «Вкусное без пользы» (`treat`): итоги недели считают его долю в еде.
  final bool treat;

  /// Почему так вышло — фраза после «Съесть» (`why`).
  final String why;

  /// Монет за один приём пищи.
  final int price;

  /// Вкус: 😊 сразу, когда Финни поел.
  final int happiness;

  /// Польза: ⚡ сразу, когда Финни поел (`energy_now`).
  final double energyNow;
}

class HomeOption {
  const HomeOption({
    required this.id,
    required this.name,
    required this.price,
    required this.weeklyCost,
    required this.energyPerWeek,
    required this.happinessPerWeek,
    required this.isGoal,
    this.stage,
  });

  final String id;
  final String name;

  /// Где это жильё (`stage`): переезд сюда меняет стадию.
  final WorldStage? stage;

  /// Цена переезда (цель накопления). У стартового жилья 0.
  final int price;
  final int weeklyCost;
  final double energyPerWeek;
  final int happinessPerWeek;
  final bool isGoal;
}

/// Перк питомца. Поля, кроме [type], есть не у каждого вида перка.
class PetPerk {
  const PetPerk({required this.type, this.value, this.job, this.leisure});

  final String type;
  final double? value;
  final String? job;
  final String? leisure;
}

class PetOption {
  const PetOption({
    required this.id,
    required this.name,
    required this.price,
    required this.foodPerWeek,
    required this.happinessPerWeek,
    required this.tier,
    required this.perk,
  });

  final String id;
  final String name;
  final int price;
  final int foodPerWeek;
  final int happinessPerWeek;

  /// `demo` — в игре к 29.09, `reserve` — после.
  final String tier;
  final PetPerk perk;
}

class TransportEffect {
  const TransportEffect({
    required this.type,
    this.job,
    this.value,
    this.minCost,
  });

  final String type;
  final String? job;
  final double? value;
  final double? minCost;
}

class NamedOption {
  const NamedOption({required this.id, required this.name});

  final String id;
  final String name;
}

class TransportRule {
  const TransportRule({
    required this.price,
    required this.isGoal,
    required this.effects,
    required this.options,
  });

  final int price;
  final bool isGoal;
  final List<TransportEffect> effects;
  final List<NamedOption> options;
}

/// Техника — цель накопления (`tech.options[]`): ноутбук открывает
/// программиста (Денис 29.09, 941 п. 5). [unlocks] — возможности, на
/// которые ссылаются `jobs.*.unlocked_by` и `tiers[].unlocked_by`.
class TechOption {
  const TechOption({
    required this.id,
    required this.name,
    required this.price,
    required this.unlocks,
  });

  final String id;
  final String name;
  final int price;
  final List<String> unlocks;
}

class ClothingItem {
  const ClothingItem({
    required this.id,
    required this.name,
    required this.price,
    required this.fade,
  });

  final String id;
  final String name;
  final int price;

  /// 😊 от вещи по неделям: `fade[0]` в неделю покупки, дальше угасает.
  final List<int> fade;
}

class DecorItem {
  const DecorItem({
    required this.id,
    required this.name,
    required this.price,
    required this.group,
  });

  final String id;
  final String name;
  final int price;
  final String group;
}

class DecorRule {
  const DecorRule({
    required this.happinessOnce,
    required this.groups,
    required this.items,
  });

  /// 😊 за каждый новый предмет, один раз.
  final int happinessOnce;
  final List<NamedOption> groups;
  final List<DecorItem> items;
}

class LeisureOption {
  const LeisureOption({
    required this.id,
    required this.name,
    required this.price,
    required this.energy,
    required this.happiness,
    this.perExtraPet,
    this.requires,
  });

  final String id;
  final String name;
  final int price;

  /// Базовая цена в ⚡, без 1 ⚡ «на жизнь» (её добавляет домен).
  final double energy;
  final int happiness;
  final int? perExtraPet;
  final String? requires;
}

class JobTier {
  const JobTier({
    required this.id,
    required this.pay,
    required this.energy,
    this.name,
    this.unlockedBy,
  });

  final String id;

  /// Название уровня для доски («лёгкая», «близко»); у работы без уровней — null.
  final String? name;

  /// Замок уровня (`tiers[].unlocked_by`) — сильнее замка работы: сложные
  /// задачи программиста открывает только мощный ноутбук.
  final String? unlockedBy;
  final int pay;

  /// Базовая цена в ⚡, без 1 ⚡ «на жизнь» (её добавляет домен).
  final double energy;
}

/// Ставка работы. У курьера и программиста — [tiers], у остальных — один
/// уровень с `id == null`.
class JobRate {
  const JobRate({
    required this.id,
    required this.name,
    required this.unlocked,
    required this.tiers,
    this.unlockedBy,
  });

  final String id;
  final String name;
  final bool unlocked;

  /// `transport`, id питомца или возможность техники (`computer`), если
  /// работа закрыта со старта.
  final String? unlockedBy;
  final List<JobTier> tiers;

  bool get hasVariants => tiers.length > 1 || tiers.single.id.isNotEmpty;

  /// Уровень по id; для работы без уровней — `variant == null`.
  JobTier? tier(String? variant) {
    for (final JobTier t in tiers) {
      if (t.id == (variant ?? '')) return t;
    }
    return null;
  }
}

class ShortfallStep {
  const ShortfallStep({
    required this.step,
    this.to,
    this.requiresConfirmation,
    this.happiness,
  });

  /// `pet_food_first` · `downgrade_food` · `offer_savings_withdrawal` ·
  /// `family_help`.
  final String step;
  final String? to;
  final bool? requiresConfirmation;
  final int? happiness;
}

class StageRule {
  const StageRule({
    required this.id,
    required this.name,
    required this.stage,
    required this.minPoints,
    required this.payStep,
  });

  final String id;

  /// 🟡 Временное название, команда ещё обсуждает (T3).
  final String name;
  final WorldStage stage;
  final int minPoints;

  /// Небольшая ступень оплаты смен на стадии (P1), дробная: ×1 / ×1,25 / ×1,5.
  final double payStep;
}

/// `happiness.week_growth` (P7): рост недели к прошлой — бонус, неделя без
/// роста — штраф, растущий с каждой такой неделей подряд.
class WeekGrowthRule {
  const WeekGrowthRule({
    required this.incomeMinShare,
    required this.growthBonus,
    required this.stagnationStep,
    required this.stagnationMax,
  });

  final double incomeMinShare;
  final int growthBonus;
  final int stagnationStep;
  final int stagnationMax;
}

class Clamp {
  const Clamp({required this.perPoint, required this.min, required this.max});

  final double perPoint;
  final double min;
  final double max;
}

class EconomyContent {
  const EconomyContent({
    required this.version,
    required this.pocketMoney,
    required this.indexCurve,
    required this.startGiftAmount,
    required this.startGiftTo,
    required this.maxShiftsPerJobPerWeek,
    required this.maxShiftsPerWeek,
    required this.energyBasePerWeek,
    required this.energyMaxPerWeek,
    required this.livingDrainPerAction,
    required this.sleepMinLeftForBonus,
    required this.sleepCarryNextWeek,
    required this.sleepHappiness,
    required this.exhaustedHappiness,
    required this.snackId,
    required this.snackPrice,
    required this.snackEnergyNow,
    required this.snackMaxPerWeek,
    required this.happinessStart,
    required this.happinessMin,
    required this.happinessMax,
    required this.happinessNeutral,
    required this.payMult,
    required this.energyCostMult,
    required this.decayBase,
    required this.decayK,
    required this.dayDrain,
    required this.weekGrowth,
    required this.leisureWeeklyCap,
    required this.goalReachedBonus,
    required this.food,
    required this.mealsPerWeek,
    this.stageByRent = false,
    required this.homeStart,
    required this.homes,
    required this.petsHappinessTotalCap,
    required this.petsOneActive,
    required this.petDailyTouchHappiness,
    required this.pets,
    required this.transport,
    required this.tech,
    required this.clothing,
    required this.decor,
    required this.leisure,
    required this.jobs,
    required this.experienceMultPerShift,
    required this.goodScoreMin,
    required this.goodShiftEnergyExtra,
    required this.goodShiftHappiness,
    required this.efficiencyBonusMaxShare,
    required this.warnBeforeEarlySleep,
    required this.shortfallOrder,
    required this.shortfallFinniLine,
    required this.pointsRequiredCovered,
    required this.pointsPlanKept,
    required this.pointsSavedRegularly,
    required this.savedRegularlyMinShare,
    required this.stages,
  });

  final String version;

  /// Карманные в неделю (`pocket_money.base`).
  final int pocketMoney;

  /// Индекс цен по неделям; с v0.2 все 1,0 (цены постоянны).
  final List<double> indexCurve;

  /// Стартовый подарок (P2) и куда он кладётся (`goal`).
  final int startGiftAmount;
  final String startGiftTo;

  final int maxShiftsPerJobPerWeek;
  final int maxShiftsPerWeek;

  final double energyBasePerWeek;
  final double energyMaxPerWeek;
  final double livingDrainPerAction;
  final double sleepMinLeftForBonus;
  final double sleepCarryNextWeek;
  final int sleepHappiness;
  final int exhaustedHappiness;
  final String snackId;
  final int snackPrice;
  final double snackEnergyNow;
  final int snackMaxPerWeek;

  final int happinessStart;
  final int happinessMin;
  final int happinessMax;
  final int happinessNeutral;
  final Clamp payMult;
  final Clamp energyCostMult;
  final double decayBase;
  final double decayK;

  /// −😊 за игровой день (`happiness.day_drain`, P7).
  final int dayDrain;

  /// Проверка роста недели (`happiness.week_growth`, P7).
  final WeekGrowthRule weekGrowth;
  final int leisureWeeklyCap;
  final int goalReachedBonus;

  final List<FoodOption> food;

  /// `food.meals_per_week`: сколько раз за неделю Финни ест.
  final int mealsPerWeek;

  /// `growth.stage_by_rent`: стадия — это жильё, которое Финни снимает.
  final bool stageByRent;
  final String homeStart;
  final List<HomeOption> homes;
  final int petsHappinessTotalCap;
  final bool petsOneActive;
  final int petDailyTouchHappiness;
  final List<PetOption> pets;
  final TransportRule transport;

  /// Техника — цели накопления, открывают работы (`tech.options`).
  final List<TechOption> tech;
  final List<ClothingItem> clothing;
  final DecorRule decor;
  final List<LeisureOption> leisure;

  /// Ставки работ по id (`consultant`, `courier`…), в порядке файла.
  final Map<String, JobRate> jobs;

  /// Оплата × это^опыт; опыт — хорошо сделанные смены (P1).
  final double experienceMultPerShift;

  /// Порог «хорошо сделано» для оценки мини-игры 0..1.
  final double goodScoreMin;

  /// ⚡ и 😊 сверх цены карточки за хорошую смену.
  final double goodShiftEnergyExtra;
  final int goodShiftHappiness;

  /// Бонус за эффективность: доля ставки при оценке 1 (P6, 0,2).
  final double efficiencyBonusMaxShare;

  final bool warnBeforeEarlySleep;
  final List<ShortfallStep> shortfallOrder;
  final String shortfallFinniLine;

  final int pointsRequiredCovered;
  final int pointsPlanKept;
  final int pointsSavedRegularly;
  final double savedRegularlyMinShare;

  /// Стадии по возрастанию порога.
  final List<StageRule> stages;

  StageRule stageRule(WorldStage stage) =>
      stages.firstWhere((StageRule s) => s.stage == stage);
}

// --------------------------------------------------------------------- jobs

/// Содержание мини-игры (`jobs.json → jobs.<id>`). Общие поля типизированы;
/// поля конкретной игры — в [data] (без ключей-комментариев), их схему
/// проверяет [WorldContent.parse].
class JobGameContent {
  const JobGameContent({
    required this.id,
    required this.level,
    required this.summary,
    required this.data,
  });

  final String id;
  final int level;

  /// Что делает ребёнок — текст для доски «Требуется…».
  final String summary;
  final Map<String, Object?> data;
}

/// Карточка вуза (`jobs.json → university.cards[]`): совет и настоящий
/// источник. Ссылок нет — адреса только в разделе взрослого.
class UniversityCard {
  const UniversityCard({
    required this.id,
    required this.title,
    required this.text,
    required this.source,
  });

  final String id;
  final String title;
  final String text;

  /// Название источника: «Банк России, «Финансовая культура»».
  final String source;
}

/// Вуз Финни (`jobs.json → university`): почему открыты финансовые работы и
/// советы с настоящими источниками (Денис 29.09, 941 п. 5).
class UniversityContent {
  const UniversityContent({
    required this.title,
    required this.intro,
    required this.cards,
    this.short = '',
    this.adultNote = '',
  });

  static const UniversityContent empty =
      UniversityContent(title: '', intro: '', cards: <UniversityCard>[]);

  final String title;

  /// Одна строка вверху доски: почему открыты финансовые работы.
  final String short;
  final String intro;

  /// Для раздела взрослого S14: откуда советы и адреса источников — только
  /// там (ТЗ §3.1.5).
  final String adultNote;
  final List<UniversityCard> cards;
}

// ------------------------------------------------------------------- events

/// Событие недели. Эффекты читает домен (A7); здесь проверяется только
/// каркас: id, тема, 2–3 варианта с id и репликой Финни.
class WorldEvent {
  const WorldEvent({
    required this.id,
    required this.topic,
    required this.title,
    required this.optionIds,
    required this.data,
  });

  final String id;

  /// `planning` или `savings`.
  final String topic;
  final String title;
  final List<String> optionIds;
  final Map<String, Object?> data;
}

// -------------------------------------------------------------------- whole

class WorldContent {
  const WorldContent({
    required this.economy,
    required this.jobs,
    required this.events,
    this.university = UniversityContent.empty,
    this.lessons = const <WorldLesson>[],
  });

  final EconomyContent economy;
  final Map<String, JobGameContent> jobs;
  final List<WorldEvent> events;

  /// Вуз Финни: карточки советов на доске «Требуется…».
  final UniversityContent university;

  /// Уроки после смен (`jobs.json → lessons`).
  final List<WorldLesson> lessons;

  /// Поля мини-игр по id профессии — для `JobGames.fromData`.
  Map<String, Map<String, Object?>> get jobData =>
      <String, Map<String, Object?>>{
        for (final MapEntry<String, JobGameContent> e in jobs.entries)
          e.key: e.value.data,
      };

  /// Разбирает три файла. Бросает [WorldContentError] с путём до поля.
  static WorldContent parse({
    required String economy,
    required String jobs,
    required String events,
  }) {
    final EconomyContent eco = _parseEconomy(
      _Node.root('economy.json', economy),
    );
    final Map<String, JobGameContent> games = _parseJobs(
      _Node.root('jobs.json', jobs),
      eco,
    );
    final List<WorldEvent> evs = _parseEvents(
      _Node.root('events.json', events),
    );
    return WorldContent(
      economy: eco,
      jobs: games,
      events: evs,
      university: _parseUniversity(_Node.root('jobs.json', jobs)),
      lessons: _parseLessons(_Node.root('jobs.json', jobs), eco),
    );
  }
}

EconomyContent _parseEconomy(_Node r) {
  final _Node pm = r['pocket_money'];
  final _Node gift = r['start_gift'];
  final _Node week = r['week'];
  final _Node en = r['energy'];
  final _Node sleep = en['sleep'];
  final _Node snack = en['snack'];
  final _Node hap = r['happiness'];
  final _Node decay = hap['weekly_decay'];
  final _Node weekGrowth = hap['week_growth'];
  final _Node pets = r['pets'];
  final _Node tr = r['transport'];
  final _Node decor = r['decor'];
  final _Node growth = r['growth'];
  final _Node points = growth['points'];
  final _Node sf = r['shortfall_rule'];
  final _Node payGrowth = r['jobs_pay_growth'];

  Clamp clamp(_Node n) => Clamp(
        perPoint: n['per_point'].number,
        min: n['min'].number,
        max: n['max'].number,
      );

  final List<FoodOption> food = r['food']['options']
      .items
      .map(
        (_Node o) => FoodOption(
          id: o['id'].string,
          name: o['name'].string,
          price: o['price'].integer,
          happiness: o['happiness'].integer,
          energyNow: o['energy_now'].number,
          treat: o.opt('treat')?.boolean ?? false,
          why: o.opt('why')?.string ?? '',
        ),
      )
      .toList();

  final _Node homesNode = r['homes'];
  final List<HomeOption> homes = homesNode['options']
      .items
      .map(
        (_Node o) => HomeOption(
          id: o['id'].string,
          name: o['name'].string,
          price: o['price'].integer,
          weeklyCost: o['weekly_cost'].integer,
          energyPerWeek: o['energy_per_week'].number,
          happinessPerWeek: o['happiness_per_week'].integer,
          isGoal: o['is_goal'].boolean,
          stage: o.opt('stage') == null
              ? null
              : WorldStage.values.byName(o['stage'].oneOf(
                  WorldStage.values.map((WorldStage w) => w.name).toList())),
        ),
      )
      .toList();

  final List<PetOption> roster = pets['roster'].items.map((_Node o) {
    final _Node perk = o['perk'];
    return PetOption(
      id: o['id'].string,
      name: o['name'].string,
      price: o['price'].integer,
      foodPerWeek: o['food_per_week'].integer,
      happinessPerWeek: o['happiness_per_week'].integer,
      tier: o['tier'].oneOf(const <String>['demo', 'reserve']),
      perk: PetPerk(
        type: perk['type'].string,
        value: perk.opt('value')?.number,
        job: perk.opt('job')?.string,
        leisure: perk.opt('leisure')?.string,
      ),
    );
  }).toList();

  final TransportRule transport = TransportRule(
    price: tr['price'].integer,
    isGoal: tr['is_goal'].boolean,
    effects: tr['effects']
        .items
        .map(
          (_Node e) => TransportEffect(
            type: e['type'].string,
            job: e.opt('job')?.string,
            value: e.opt('value')?.number,
            minCost: e.opt('min_cost')?.number,
          ),
        )
        .toList(),
    options: tr['options'].items.map(_named).toList(),
  );

  final List<TechOption> tech = r['tech']['options']
      .items
      .map(
        (_Node o) => TechOption(
          id: o['id'].string,
          name: o['name'].string,
          price: o['price'].integer,
          unlocks: o['unlocks'].strings,
        ),
      )
      .toList();

  final List<ClothingItem> clothing = r['clothing']['items']
      .items
      .map(
        (_Node o) => ClothingItem(
          id: o['id'].string,
          name: o['name'].string,
          price: o['price'].integer,
          fade: o['fade'].integers,
        ),
      )
      .toList();

  final List<NamedOption> decorGroups =
      decor['groups'].items.map(_named).toList();
  final List<DecorItem> decorItems = decor['items'].items.map((_Node o) {
    final _Node group = o['group'];
    group.oneOf(decorGroups.map((NamedOption g) => g.id).toList());
    return DecorItem(
      id: o['id'].string,
      name: o['name'].string,
      price: o['price'].integer,
      group: group.string,
    );
  }).toList();

  final List<LeisureOption> leisure = r['leisure']['options']
      .items
      .map(
        (_Node o) => LeisureOption(
          id: o['id'].string,
          name: o['name'].string,
          price: o['price'].integer,
          energy: o['energy'].number,
          happiness: o['happiness'].integer,
          perExtraPet: o.opt('per_extra_pet')?.integer,
          requires: o.opt('requires')?.string,
        ),
      )
      .toList();

  final Map<String, JobRate> jobs = <String, JobRate>{};
  final _Node jobsNode = r['jobs'];
  for (final String id in jobsNode.keys) {
    final _Node j = jobsNode[id];
    final _Node? tiersNode = j.opt('tiers');
    final List<JobTier> tiers = tiersNode == null
        ? <JobTier>[
            JobTier(id: '', pay: j['pay'].integer, energy: j['energy'].number),
          ]
        : tiersNode.items
            .map(
              (_Node t) => JobTier(
                id: t['id'].string,
                name: t.opt('name')?.string,
                pay: t['pay'].integer,
                energy: t['energy'].number,
                unlockedBy: t.opt('unlocked_by')?.string,
              ),
            )
            .toList();
    if (tiers.isEmpty) tiersNode!.fail('нужен хотя бы один уровень');
    jobs[id] = JobRate(
      id: id,
      name: j['name'].string,
      unlocked: j['unlocked'].boolean,
      unlockedBy: j.opt('unlocked_by')?.string,
      tiers: tiers,
    );
  }

  final _Node stagesNode = growth['stages'];
  final List<StageRule> stages = stagesNode.items.map((_Node s) {
    final String place = s['place'].oneOf(
      WorldStage.values.map((WorldStage w) => w.name).toList(),
    );
    return StageRule(
      id: s['id'].string,
      name: s['name'].string,
      stage: WorldStage.values.byName(place),
      minPoints: s['min_points'].integer,
      payStep: s['pay_step'].number,
    );
  }).toList();
  if (stages.map((StageRule s) => s.stage).toList().join() !=
      WorldStage.values.join()) {
    stagesNode.fail(
      'нужны стадии ${WorldStage.values.map((WorldStage w) => w.name).join(' → ')} '
      'по одной и по порядку',
    );
  }
  for (int i = 1; i < stages.length; i++) {
    if (stages[i].minPoints <= stages[i - 1].minPoints) {
      stagesNode.at(i)['min_points'].fail('пороги стадий должны расти');
    }
  }

  // Ссылки внутри файла: код не должен встречать id, которого нет.
  final _Node homeStartNode = homesNode['start'];
  homeStartNode.oneOf(homes.map((HomeOption h) => h.id).toList());
  final List<ShortfallStep> order = sf['order'].items.map((_Node s) {
    final _Node? to = s.opt('to');
    to?.oneOf(food.map((FoodOption f) => f.id).toList());
    return ShortfallStep(
      step: s['step'].oneOf(const <String>[
        'pet_food_first',
        'downgrade_food',
        'offer_savings_withdrawal',
        'family_help',
      ]),
      to: to?.string,
      requiresConfirmation: s.opt('requires_confirmation')?.boolean,
      happiness: s.opt('happiness')?.integer,
    );
  }).toList();
  final List<_Node> rosterNodes = pets['roster'].items;
  for (int i = 0; i < roster.length; i++) {
    final _Node perk = rosterNodes[i]['perk'];
    perk.opt('job')?.oneOf(jobs.keys.toList());
    perk.opt('leisure')?.oneOf(leisure.map((LeisureOption l) => l.id).toList());
  }
  final List<String> locks = <String>[
    'transport',
    ...roster.map((PetOption p) => p.id),
    for (final TechOption t in tech) ...t.unlocks,
  ];
  for (final String id in jobsNode.keys) {
    final _Node j = jobsNode[id];
    j.opt('unlocked_by')?.oneOf(locks);
    for (final _Node t in j.opt('tiers')?.items ?? const <_Node>[]) {
      t.opt('unlocked_by')?.oneOf(locks);
    }
  }
  final List<_Node> effectNodes = tr['effects'].items;
  for (final _Node e in effectNodes) {
    e.opt('job')?.oneOf(jobs.keys.toList());
  }

  return EconomyContent(
    version: r['version'].string,
    pocketMoney: pm['base'].integer,
    indexCurve: pm['index_curve'].numbers,
    startGiftAmount: gift['amount'].integer,
    startGiftTo: gift['to'].oneOf(const <String>['goal']),
    maxShiftsPerJobPerWeek: week['max_shifts_per_job_per_week'].integer,
    maxShiftsPerWeek: week['max_shifts_per_week'].integer,
    energyBasePerWeek: en['base_per_week'].number,
    energyMaxPerWeek: en['max_per_week'].number,
    livingDrainPerAction: en['living_drain_per_action'].number,
    sleepMinLeftForBonus: sleep['min_left_for_bonus'].number,
    sleepCarryNextWeek: sleep['carry_next_week'].number,
    sleepHappiness: sleep['happiness'].integer,
    exhaustedHappiness: en['exhausted']['happiness'].integer,
    snackId: snack['id'].string,
    snackPrice: snack['price'].integer,
    snackEnergyNow: snack['energy_now'].number,
    snackMaxPerWeek: snack['max_per_week'].integer,
    happinessStart: hap['start'].integer,
    happinessMin: hap['min'].integer,
    happinessMax: hap['max'].integer,
    happinessNeutral: hap['neutral'].integer,
    payMult: clamp(hap['pay_mult']),
    energyCostMult: clamp(hap['energy_cost_mult']),
    decayBase: decay['base'].number,
    decayK: decay['k'].number,
    dayDrain: hap['day_drain'].integer,
    weekGrowth: WeekGrowthRule(
      incomeMinShare: weekGrowth['income_min_share'].number,
      growthBonus: weekGrowth['growth_bonus'].integer,
      stagnationStep: weekGrowth['stagnation_step'].integer,
      stagnationMax: weekGrowth['stagnation_max'].integer,
    ),
    leisureWeeklyCap: hap['leisure_weekly_cap'].integer,
    goalReachedBonus: hap['goal_reached_bonus'].integer,
    food: food,
    mealsPerWeek: _mealsPerWeek(r['food']['meals_per_week']),
    stageByRent: r['growth'].opt('stage_by_rent')?.boolean ?? false,
    homeStart: homeStartNode.string,
    homes: homes,
    petsHappinessTotalCap: pets['happiness_total_cap'].integer,
    petsOneActive: pets['one_active'].boolean,
    petDailyTouchHappiness: pets['daily_touch_happiness'].integer,
    pets: roster,
    transport: transport,
    tech: tech,
    clothing: clothing,
    decor: DecorRule(
      happinessOnce: decor['happiness_once'].integer,
      groups: decorGroups,
      items: decorItems,
    ),
    leisure: leisure,
    jobs: jobs,
    experienceMultPerShift: payGrowth['experience_mult_per_shift'].number,
    goodScoreMin: payGrowth['good_score_min'].number,
    goodShiftEnergyExtra: payGrowth['good_shift_energy_extra'].number,
    goodShiftHappiness: payGrowth['good_shift_happiness'].integer,
    efficiencyBonusMaxShare: payGrowth['efficiency_bonus_max_share'].number,
    warnBeforeEarlySleep: sf['warn_before_early_sleep'].boolean,
    shortfallOrder: order,
    shortfallFinniLine: sf['finni_line'].string,
    pointsRequiredCovered: points['required_covered'].integer,
    pointsPlanKept: points['plan_kept'].integer,
    pointsSavedRegularly: points['saved_regularly'].integer,
    savedRegularlyMinShare: growth['saved_regularly_min_share'].number,
    stages: stages,
  );
}

/// Карта курьера: квадрат [maze] = [столбцы, строки], ровно один `S` и `G`,
/// остальные клетки — `.` или буква из `walls`.
void _checkMap(_Node m, List<int> maze, Set<String> walls) {
  final List<String> rows = m.strings;
  if (maze.length != 2 || maze[0] != maze[1]) {
    m.fail('карта должна быть квадратной, а maze — ${maze.join('×')}');
  }
  if (rows.length != maze[1]) {
    m.fail('строк ${rows.length}, а maze говорит ${maze.join('×')}');
  }
  int starts = 0;
  int goals = 0;
  for (int r = 0; r < rows.length; r++) {
    if (rows[r].length != maze[0]) {
      m.at(r).fail('в строке ${rows[r].length} клеток, а нужно ${maze[0]}');
    }
    for (final String ch in rows[r].split('')) {
      if (ch == 'S') {
        starts++;
      } else if (ch == 'G') {
        goals++;
      } else if (ch != '.' && !walls.contains(ch)) {
        m.at(r).fail('«$ch» — такой стены нет в walls');
      }
    }
  }
  if (starts != 1 || goals != 1) {
    m.fail('нужен ровно один S и один G, а их $starts и $goals');
  }
}

NamedOption _named(_Node o) =>
    NamedOption(id: o['id'].string, name: o['name'].string);

/// `food.meals_per_week`: хотя бы один приём — иначе еда не выбирается, а
/// счёт недели без еды.
int _mealsPerWeek(_Node n) {
  final int v = n.integer;
  if (v < 1) n.fail('нужен хотя бы один приём пищи в неделю');
  return v;
}

/// `jobs.json → lessons.<job>`: урок после смены (критерии ночи §4). 2–3
/// варианта, у каждого — последствие и реплика Финни; доли — от 0 до 1.
List<WorldLesson> _parseLessons(_Node r, EconomyContent eco) {
  final _Node ls = r['lessons'];
  final List<WorldLesson> out = <WorldLesson>[];
  for (final String job in ls.keys) {
    final _Node l = ls[job];
    if (!eco.jobs.containsKey(job)) {
      l.fail('профессии нет в economy.json → jobs');
    }
    final List<_Node> cs = l['choices'].items;
    if (cs.length < 2 || cs.length > 3) {
      l['choices'].fail('нужно 2–3 варианта, а их ${cs.length}');
    }
    double share(_Node e, String k) {
      final _Node? n = e.opt(k);
      if (n == null) return 0;
      final double v = n.number;
      if (v < 0 || v > 1) n.fail('доля от 0 до 1');
      return v;
    }

    out.add(WorldLesson(
      jobId: job,
      topic: l['topic'].oneOf(const <String>['budget', 'savings', 'payments']),
      title: l['title'].string,
      situation: l['situation'].string,
      understood: l['understood'].string,
      word: l['word'].string,
      wordTerm: l['word_term'].string,
      choices: <WorldLessonChoice>[
        for (final _Node c in cs)
          WorldLessonChoice(
            id: c['id'].string,
            label: c['label'].string,
            finni: c['finni'].string,
            goalShare: share(c['effects'], 'goal_share'),
            needShare: share(c['effects'], 'need_share'),
            spend: c['effects'].opt('spend')?.integer ?? 0,
            happiness: c['effects'].opt('happiness')?.integer ?? 0,
          ),
      ],
    ));
  }
  return out;
}

/// `jobs.json → university`. Ссылка в тексте карточки — ошибка: из игры
/// ребёнок никуда не уходит (ТЗ §3.1.5, §3.5).
UniversityContent _parseUniversity(_Node r) {
  final _Node u = r['university'];
  final List<UniversityCard> cards = <UniversityCard>[];
  for (final _Node c in u['cards'].items) {
    final UniversityCard card = UniversityCard(
      id: c['id'].string,
      title: c['title'].string,
      text: c['text'].string,
      source: c['source'].string,
    );
    for (final String f in <String>['text', 'source']) {
      final String v = f == 'text' ? card.text : card.source;
      if (RegExp(r'https?:|www\.|\.ru\b|\.info\b').hasMatch(v)) {
        c[f].fail('ссылок в игре нет — адрес только в разделе взрослого');
      }
    }
    cards.add(card);
  }
  if (cards.isEmpty) u['cards'].fail('нужна хотя бы одна карточка');
  return UniversityContent(
    title: u['title'].string,
    short: u['short'].string,
    intro: u['intro'].string,
    cards: cards,
    adultNote: u['adult_note'].string,
  );
}

Map<String, JobGameContent> _parseJobs(_Node r, EconomyContent eco) {
  final _Node jobs = r['jobs'];
  final Map<String, JobGameContent> out = <String, JobGameContent>{};
  for (final String id in jobs.keys) {
    final _Node j = jobs[id];
    if (!eco.jobs.containsKey(id)) {
      j.fail('профессии нет в economy.json → jobs');
    }
    // Схема каждой игры: то, без чего экран не соберётся.
    switch (id) {
      case 'consultant' || 'accountant':
        for (final String k in <String>[
          'sort_intro',
          'check',
          'check_wait',
          'all_ok',
          'pick',
        ]) {
          j.opt('texts')?.opt(k)?.string;
        }
        if (j['tier_labels'].strings.length != 3) {
          j['tier_labels'].fail('нужно три подписи полок');
        }
        for (final _Node s in j['sets'].items) {
          s['id'].string;
          s['category'].string;
          if (s['items'].items.length != 3) {
            s['items'].fail('нужно три товара — по одному на полку');
          }
          final List<String> ids = <String>[];
          for (final _Node i in s['items'].items) {
            ids.add(i['id'].string);
            i['name'].string;
            i['price'].integer;
            i['why'].string;
            i['traits'].strings;
          }
          final _Node c = s['customer'];
          c['line'].string;
          c['budget'].integer;
          c['best_fit'].oneOf(ids);
          for (final String k in const <String>[
            'feedback_fit',
            'feedback_cheaper',
            'feedback_pricier',
          ]) {
            c[k].string;
          }
        }
      case 'cashier':
        j['coins'].integers;
        j['bills'].integers;
        if (j['customers_per_shift'].integer < 1) {
          j['customers_per_shift'].fail('нужен хотя бы один покупатель');
        }
        final List<_Node> purchases = j['purchases'].items;
        if (purchases.isEmpty) j['purchases'].fail('список пуст');
        for (final _Node p in purchases) {
          p['id'].string;
          p['item'].string;
          if (p['paid_with'].integer <= p['price'].integer) {
            p.fail('покупатель платит не больше цены — сдачи нет');
          }
        }
        for (final String k in const <String>[
          'right',
          'too_little',
          'too_much',
        ]) {
          j['feedback'][k].string;
        }
      case 'gardener':
        j['beds'].integer;
        final List<int> grid = j['grid'].integers;
        if (grid.length != 2 || grid[0] * grid[1] != j['beds'].integer) {
          j['grid'].fail('нужно [столбцы, строки], и их произведение = beds');
        }
        j['taps_to_water'].integer;
        j['max_dry_at_once'].integer;
        j['great_share'].number;
        j['ok_share'].number;
        if (j['calm_turns'].integer < 1) j['calm_turns'].fail('нужен ход');
        if (j['calm_wilt_turns'].integer < 1) {
          j['calm_wilt_turns'].fail('нужен хотя бы один ход');
        }
        for (final String k in const <String>['great', 'ok', 'low']) {
          j['result_lines'][k].string;
        }
      case 'courier':
        final List<String> tiers =
            eco.jobs[id]!.tiers.map((JobTier t) => t.id).toList();
        final _Node walls = j['walls'];
        for (final String k in walls.keys) {
          if (k.length != 1 || 'SG.'.contains(k)) {
            walls.fail('«$k» — стена обозначается одной буквой, не S, G или .');
          }
          walls[k].string;
        }
        j['wrong_turn_rule'].string;
        for (final _Node o in j['orders'].items) {
          o['id'].string;
          o['tier'].oneOf(tiers);
          o['title'].string;
          final List<int> maze = o['maze'].integers;
          _checkMap(o['map'], maze, walls.keys.toSet());
          o['order_card']['to'].string;
          o['order_card']['what'].string;
          o['order_card']['special'].string;
          int correct = 0;
          for (final _Node p in o['parcels'].items) {
            p['id'].string;
            p['label'].string;
            if (p['correct'].boolean) {
              correct++;
            } else {
              p['why'].string;
            }
          }
          if (correct != 1) {
            o['parcels'].fail('нужна ровно одна верная посылка');
          }
        }
      case 'programmer':
        final List<String> tiers =
            eco.jobs[id]!.tiers.map((JobTier t) => t.id).toList();
        for (final _Node t in j['tasks'].items) {
          t['id'].string;
          t['tier'].oneOf(tiers);
          t['device'].string;
          t['goal'].string;
          t['hint_on_error'].string;
          final List<String> blocks = <String>[];
          for (final _Node b in t['blocks'].items) {
            blocks.add(b['id'].string);
            b['label'].string;
          }
          for (final _Node s in t['solution'].items) {
            s.oneOf(blocks);
          }
        }
    }
    out[id] = JobGameContent(
      id: id,
      level: j['level'].integer,
      summary: j['summary'].string,
      data: j.object,
    );
  }
  return out;
}

List<WorldEvent> _parseEvents(_Node r) {
  return r['events'].items.map((_Node e) {
    final List<_Node> options = e['options'].items;
    if (options.length < 2 || options.length > 3) {
      e['options'].fail('нужно 2–3 варианта, а их ${options.length}');
    }
    return WorldEvent(
      id: e['id'].string,
      topic: e['topic'].oneOf(const <String>['planning', 'savings']),
      title: e['title'].string,
      optionIds: options.map((_Node o) {
        o['finni'].string;
        o['label'].string;
        return o['id'].string;
      }).toList(),
      data: e.object,
    );
  }).toList();
}

/// Значение JSON вместе с тем, где оно лежит: ошибка всегда называет поле.
class _Node {
  const _Node(this.file, this.path, this.value);

  factory _Node.root(String file, String text) {
    try {
      return _Node(file, '', jsonDecode(text));
    } on FormatException catch (e) {
      throw WorldContentError(file, '', 'не JSON: ${e.message}');
    }
  }

  final String file;
  final String path;
  final Object? value;

  Never fail(String problem) => throw WorldContentError(file, path, problem);

  Map<String, Object?> get _map {
    final Object? v = value;
    if (v is Map<String, Object?>) return v;
    fail('ожидался объект, а стоит ${_show(v)}');
  }

  /// Ключи объекта без комментариев (`_…`), в порядке файла.
  Iterable<String> get keys =>
      _map.keys.where((String k) => !k.startsWith('_'));

  /// Объект без ключей-комментариев — для полей, которые типизирует домен.
  Map<String, Object?> get object => _strip(_map)! as Map<String, Object?>;

  _Node operator [](String key) {
    final Map<String, Object?> m = _map;
    final String p = path.isEmpty ? key : '$path.$key';
    if (!m.containsKey(key)) {
      throw WorldContentError(file, p, 'поле отсутствует');
    }
    return _Node(file, p, m[key]);
  }

  /// Необязательное поле: null, если его нет.
  _Node? opt(String key) => _map.containsKey(key) ? this[key] : null;

  List<_Node> get items {
    final Object? v = value;
    if (v is! List<Object?>) fail('ожидался список, а стоит ${_show(v)}');
    return <_Node>[
      for (int i = 0; i < v.length; i++) _Node(file, '$path[$i]', v[i]),
    ];
  }

  _Node at(int i) => items[i];

  List<String> get strings => items.map((_Node n) => n.string).toList();

  List<int> get integers => items.map((_Node n) => n.integer).toList();

  List<double> get numbers => items.map((_Node n) => n.number).toList();

  String get string {
    final Object? v = value;
    if (v is String && v.trim().isNotEmpty) return v;
    fail('ожидалась непустая строка, а стоит ${_show(v)}');
  }

  int get integer {
    final Object? v = value;
    if (v is int) return v;
    fail('ожидалось целое число, а стоит ${_show(v)}');
  }

  double get number {
    final Object? v = value;
    if (v is num) return v.toDouble();
    fail('ожидалось число, а стоит ${_show(v)}');
  }

  bool get boolean {
    final Object? v = value;
    if (v is bool) return v;
    fail('ожидалось true или false, а стоит ${_show(v)}');
  }

  String oneOf(List<String> allowed) {
    final String s = string;
    if (!allowed.contains(s)) {
      fail('«$s» — такого id нет; допустимо: ${allowed.join(', ')}');
    }
    return s;
  }

  static String _show(Object? v) => v == null
      ? 'null'
      : v is String
          ? '"$v"'
          : v is Map
              ? 'объект'
              : v is List
                  ? 'список'
                  : '$v';

  static Object? _strip(Object? v) {
    if (v is Map<String, Object?>) {
      return <String, Object?>{
        for (final MapEntry<String, Object?> e in v.entries)
          if (!e.key.startsWith('_')) e.key: _strip(e.value),
      };
    }
    if (v is List<Object?>) return v.map(_strip).toList();
    return v;
  }
}
