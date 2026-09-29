/// Числа нового мира — один объект, который домен получает снаружи.
///
/// 🔴 Домен не читает файлы (`layering_test`). Конфиг из файла строит
/// `lib/data/world_config_from_content.dart` и передаёт в `WorldGame`.
/// Значения по умолчанию = `content/economy.json` v0.3 (Настя v13 + решения
/// 27–28.09, `docs/game/open-questions.md` P1–P8): их читают `WorldGame()` без
/// конфига и `FakeWorld`, а тест загрузчика сверяет их с файлом.
///
/// Имена полей повторяют ключи `economy.json`, чтобы загрузчик был прямым
/// переносом: `energy.base_per_week` → [energyBasePerWeek] и т. д.
library;

import 'contract.dart' show WorldStage;
import 'world_events.dart';

/// Блюдо (`food.options[]`): приём пищи с тремя шкалами — цена, вкус (😊)
/// и польза (⚡ сразу). Финни ест [WorldConfig.mealsPerWeek] раз в неделю;
/// что ребёнок не выбрал сам, Финни ест дома в конце недели — это
/// домашнее меню (`WorldState.foodId`, по умолчанию самое простое блюдо).
class WorldFood {
  const WorldFood({
    required this.id,
    required this.title,
    required this.price,
    required this.happiness,
    required this.energyNow,
    this.treat = false,
    this.why = '',
  });

  final String id;
  final String title;

  /// Почему так вышло — фраза после «Съесть» (`food.options[].why`).
  final String why;

  /// «Вкусное без пользы» (`food.options[].treat`): итоги недели называют,
  /// какую долю еды оно съело (критерии ночи 29.09, §2 п. 8).
  final bool treat;

  /// Монет за один приём.
  final int price;

  /// Вкус: 😊 за один приём.
  final int happiness;

  /// Польза: ⚡ за один приём — сразу, если съедено посреди недели, и на
  /// следующую неделю, если съедено дома в итогах.
  final double energyNow;
}

/// Жильё (`homes.options[]`). Цена 0 — стартовое, не цель.
class WorldHome {
  const WorldHome({
    required this.id,
    required this.title,
    required this.price,
    required this.weeklyCost,
    required this.energyPerWeek,
    required this.happinessPerWeek,
    this.stage,
  });

  final String id;
  final String title;

  /// Залог и первая неделя (аренда; платится из ЦЕЛИ). У стартового — 0.
  final int price;
  final int weeklyCost;
  final double energyPerWeek;
  final int happinessPerWeek;

  /// Где это жильё: переезд сюда меняет стадию ([WorldConfig.stageByRent]).
  final WorldStage? stage;

  bool get isGoal => price > 0;
}

/// Питомец (`pets.roster[]`).
class WorldPet {
  const WorldPet({
    required this.id,
    required this.title,
    required this.price,
    required this.foodPerWeek,
    required this.happinessPerWeek,
  });

  final String id;
  final String title;
  final int price;
  final int foodPerWeek;
  final int happinessPerWeek;
}

/// Техника (`tech.options[]`): цель накопления, открывает работы. [unlocks]
/// — возможности (`computer`, `computer_pro`), на которые ссылается
/// [WorldJob.needs]. Денис 29.09, 941 п. 5.
class WorldTech {
  const WorldTech({
    required this.id,
    required this.title,
    required this.price,
    required this.unlocks,
  });

  final String id;
  final String title;
  final int price;
  final List<String> unlocks;
}

/// Вариант урока после смены (`jobs.json → lessons.<job>.choices[]`).
/// Доли — от оплаты этой смены, округляются до десятков.
class WorldLessonChoice {
  const WorldLessonChoice({
    required this.id,
    required this.label,
    required this.finni,
    this.goalShare = 0,
    this.needShare = 0,
    this.spend = 0,
    this.happiness = 0,
  });

  final String id;
  final String label;

  /// Реплика Финни после выбора.
  final String finni;

  /// Доля оплаты смены: из кошелька в ЦЕЛЬ (`goal_share`).
  final double goalShare;

  /// Доля оплаты смены: из кошелька в НУЖНО (`need_share`).
  final double needShare;

  /// Потратить столько монет: из кошелька, потом из ХОЧУ (`spend`).
  final int spend;
  final int happiness;
}

/// Урок после смены (Денис 29.09, 938; критерии ночи §4): ситуация, связанная
/// с работой, и 2–3 варианта с последствием. Тексты — `jobs.json → lessons`.
class WorldLesson {
  const WorldLesson({
    required this.jobId,
    required this.topic,
    required this.title,
    required this.situation,
    required this.understood,
    required this.word,
    required this.wordTerm,
    required this.choices,
  });

  final String jobId;

  /// Тема ТЗ: `budget`, `savings`, `payments`.
  final String topic;
  final String title;
  final String situation;

  /// «Что мы поняли» — первая фраза итога.
  final String understood;

  /// Новое слово Словарика: id (`glossary.json`) и само слово.
  final String word;
  final String wordTerm;
  final List<WorldLessonChoice> choices;

  WorldLessonChoice? choice(String id) {
    for (final WorldLessonChoice c in choices) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Самая дешёвая техника с возможностью [ability] (`computer` → ноутбук),
/// или null — такую возможность техника не даёт.
WorldTech? cheapestTechFor(WorldConfig c, String ability) {
  WorldTech? best;
  for (final WorldTech t in c.techs) {
    if (!t.unlocks.contains(ability)) continue;
    if (best == null || t.price < best.price) best = t;
  }
  return best;
}

/// Вещь из магазина: одежда (угасающая 😊), декор (+😊 один раз).
class WorldItem {
  const WorldItem({
    required this.id,
    required this.title,
    required this.price,
    required this.happinessByWeek,
  });

  final String id;
  final String title;
  final int price;

  /// 😊 по неделям владения: [0] — при покупке, [1] — через неделю…
  /// У декора один элемент.
  final List<int> happinessByWeek;
}

/// Досуг (`leisure`).
class WorldLeisure {
  const WorldLeisure({
    required this.id,
    required this.title,
    required this.price,
    required this.energy,
    required this.happiness,
    this.perExtraPet = 0,
    this.requires,
  });

  /// `leisure.options[].requires: any_pet` — нужен хотя бы один питомец.
  static const String anyPet = 'any_pet';

  final String id;
  final String title;
  final int price;

  /// Базовая ⚡ без «на жизнь».
  final double energy;
  final int happiness;

  /// `per_extra_pet`: +😊 за каждого питомца сверх первого.
  final int perExtraPet;

  /// `requires`: условие доступа ([anyPet]) или null.
  final String? requires;

  bool get needsPet => requires == anyPet;
}

/// Работа или её уровень (`jobs.json`). 🔴 [energy] — базовая цена, «на жизнь»
/// добавляет домен.
class WorldJob {
  const WorldJob({
    required this.id,
    required this.title,
    required this.pay,
    required this.energy,
    this.variant,
    this.needs,
  });

  final String id;
  final String? variant;
  final String title;
  final int pay;
  final double energy;

  /// Что открывает работу (или её уровень): `transport`, возможность
  /// техники ([WorldTech.unlocks]: `computer`, `computer_pro`) или id вещи
  /// (питомца). null — открыта с первого дня.
  final String? needs;
}

/// Все числа нового мира.
class WorldConfig {
  const WorldConfig({
    this.pocketMoney = 400,
    this.startGift = 200,
    this.energyBasePerWeek = 10,
    this.energyMax = 14,
    this.livingDrainPerAction = 1,
    this.sleepMinLeftForBonus = 1,
    this.sleepCarryNextWeek = 1,
    this.sleepHappiness = 3,
    this.exhaustedHappiness = 0,
    this.happinessStart = 50,
    this.happinessMin = 0,
    this.happinessMax = 100,
    this.happinessNeutral = 50,
    this.payMultPerPoint = 0.004,
    this.payMultMin = 0.9,
    this.payMultMax = 1.15,
    this.energyCostMultPerPoint = 0.005,
    this.energyCostMultMin = 0.85,
    this.energyCostMultMax = 1.15,
    this.weeklyDecayBase = 6,
    this.weeklyDecayK = 0.7,
    this.happinessDayDrain = 1,
    this.weekGrowthIncomeMinShare = 0.1,
    this.weekGrowthBonus = 2,
    this.stagnationStep = 3,
    this.stagnationMax = 9,
    this.leisureWeeklyCap = 16,
    this.goalReachedBonus = 10,
    this.petsHappinessCap = 14,
    this.petTapHappiness = 1,
    this.familyHelpHappiness = -6,
    this.simpleFoodId = 'food_simple',
    this.startFoodId = 'food_simple',
    this.startHomeId = 'home_room',
    this.mealsPerWeek = 3,
    this.stageByRent = true,
    this.maxShiftsPerWeek = 3,
    this.maxShiftsPerJobPerWeek = 2,
    this.experienceGrowth = 1.01,
    this.goodScoreMin = 0.75,
    this.goodShiftEnergyExtra = 0.5,
    this.goodShiftHappiness = -1,
    this.efficiencyShare = 0.2,
    this.savedRegularlyMinShare = 0.1,
    this.growthPointsPerReason = const <String, int>{
      'required_covered': 1,
      'plan_kept': 1,
      'saved_regularly': 1,
    },
    this.stageMinPoints = const <int>[0, 4, 9],
    this.stageSteps = const <double>[1, 1.2, 1.35],
    this.snackId = 'snack',
    this.snackPrice = 60,
    this.snackEnergyNow = 1,
    this.snackMaxPerWeek = 2,
    this.transportPrice = 1800,
    this.transportDiscount = 0.5,
    this.transportMinJobEnergy = 1,
    this.foods = _foods,
    this.homes = _homes,
    this.pets = _pets,
    this.transports = _transports,
    this.techs = _techs,
    this.lessons = const <WorldLesson>[],
    this.clothes = _clothes,
    this.decor = _decor,
    this.leisure = _leisure,
    this.jobs = _jobs,
    this.sleepHappinessPerks = const <String, int>{'pet_hamster': 2},
    this.sleepCarryPerks = const <String, double>{'pet_turtle': 1},
    this.decayPerks = const <String, double>{'pet_fish': -1},
    this.payPerks = const <String, ({String jobId, double mult})>{
      'pet_kitten': (jobId: 'consultant', mult: 1.1),
    },
    this.events = const <WorldEventSpec>[],
    this.eventsPerWeekMax = 2,
    this.eventRepeatWeeks = 4,
  });

  // ── деньги ──
  final int pocketMoney;
  final int startGift;

  // ── ⚡ ──
  final double energyBasePerWeek;
  final double energyMax;
  final double livingDrainPerAction;
  final double sleepMinLeftForBonus;
  final double sleepCarryNextWeek;
  final int sleepHappiness;

  /// v13 слайд 16: «когда энергия закончилась — нет штрафа». В старом файле −2.
  final int exhaustedHappiness;

  // ── 😊 ──
  final int happinessStart;
  final int happinessMin;
  final int happinessMax;
  final int happinessNeutral;
  final double payMultPerPoint;
  final double payMultMin;
  final double payMultMax;
  final double energyCostMultPerPoint;
  final double energyCostMultMin;
  final double energyCostMultMax;

  /// Остывание в конце недели: base + k × (😊 на начало недели − нейтраль).
  /// v13: 6 при 😊 50 (в старом файле 12); k 0,7 — A15 (P7), выше 50
  /// остывает сильнее, чем при 0,5, и 😊 не сидит на 100.
  final double weeklyDecayBase;
  final double weeklyDecayK;

  /// P7 (Денис 28.09): каждый игровой день — действие, которое тратит ⚡
  /// (смена, досуг, событие с тратой ⚡), — ещё и −это 😊, как −1 ⚡ «на
  /// жизнь» (`happiness.day_drain`).
  final int happinessDayDrain;

  /// P7, проверка роста в итогах недели (`happiness.week_growth`): заработок
  /// недели (смены и деньги событий, без стипендии) вырос хотя бы на эту долю
  /// к прошлой неделе — это рост.
  final double weekGrowthIncomeMinShare;

  /// 😊 за неделю роста (`growth_bonus`).
  final int weekGrowthBonus;

  /// Неделя без роста: −[stagnationStep] × недель без роста подряд, но не
  /// больше [stagnationMax] (`stagnation_step`, `stagnation_max`).
  final int stagnationStep;
  final int stagnationMax;
  final int leisureWeeklyCap;
  final int goalReachedBonus;
  final int petsHappinessCap;
  final int petTapHappiness;

  /// `shortfall_rule.order[family_help].happiness`.
  final int familyHelpHappiness;

  // ── счета ──
  /// Куда понижается еда при нехватке (`shortfall_rule.order[downgrade_food].to`).
  final String simpleFoodId;
  final String startFoodId;
  final String startHomeId;

  /// Стадия = снятое жильё (`growth.stage_by_rent`, Денис 941 п. 3): очки
  /// роста открывают переезд, переезжает ребёнок сам, когда накопил на залог.
  /// false — стадия по очкам, как до 29.09.
  final bool stageByRent;

  /// `food.meals_per_week`: сколько раз за неделю Финни ест. Приёмы, которые
  /// ребёнок не выбрал сам, входят в счёт недели по цене домашнего меню.
  final int mealsPerWeek;

  // ── работа ──
  /// Не больше стольких смен за неделю всего (P8: 4).
  final int maxShiftsPerWeek;
  final int maxShiftsPerJobPerWeek;

  /// Оплата × это^опыт; опыт — хорошо сделанные смены (P1; P8: 1,02).
  final double experienceGrowth;

  /// Порог «хорошо сделано» для оценки мини-игры 0..1
  /// (`jobs_pay_growth.good_score_min`).
  final double goodScoreMin;

  /// ⚡ сверх цены карточки за хорошую смену (`good_shift_energy_extra`).
  final double goodShiftEnergyExtra;

  /// 😊 за хорошую смену (`good_shift_happiness`).
  final int goodShiftHappiness;

  /// Бонус за эффективность: доля ставки при оценке 1, только за хорошую
  /// смену (P6: до 20 %, `efficiency_bonus_max_share`).
  final double efficiencyShare;

  // ── рост ──
  final double savedRegularlyMinShare;

  /// Очки роста за причину недели (`growth.points`): `required_covered`,
  /// `plan_kept`, `saved_regularly`.
  final Map<String, int> growthPointsPerReason;

  /// Пороги очков по стадиям в порядке `WorldStage.values`.
  final List<int> stageMinPoints;

  /// Ступень оплаты по стадиям (`growth.stages[].pay_step`), дробная.
  final List<double> stageSteps;

  // ── перекус ──
  final String snackId;
  final int snackPrice;
  final double snackEnergyNow;
  final int snackMaxPerWeek;

  // ── транспорт ──
  final int transportPrice;
  final double transportDiscount;
  final double transportMinJobEnergy;

  // ── каталоги ──
  final List<WorldFood> foods;
  final List<WorldHome> homes;
  final List<WorldPet> pets;

  /// id транспорта → название. Цена у всех [transportPrice].
  final Map<String, String> transports;

  /// Техника — цели, которые открывают работы.
  final List<WorldTech> techs;

  /// Уроки после смен (`jobs.json → lessons`). По умолчанию пусто: тексты
  /// живут только в файле, как у событий.
  final List<WorldLesson> lessons;

  WorldLesson? lesson(String jobId) =>
      _find(lessons, (WorldLesson l) => l.jobId == jobId);
  final List<WorldItem> clothes;
  final List<WorldItem> decor;
  final List<WorldLeisure> leisure;
  final List<WorldJob> jobs;

  // ── перки питомцев (`pets.roster[].perk`) ──
  // payPerks.mult — множитель (1,1); в файле доля `value: 0.1`, загрузчик
  // переводит в 1 + value.
  final Map<String, int> sleepHappinessPerks;
  final Map<String, double> sleepCarryPerks;
  final Map<String, double> decayPerks;
  final Map<String, ({String jobId, double mult})> payPerks;

  // ── события недели (A10, `events.json`) ──

  /// События из `events.json → events[]` ([parseWorldEvents]). По умолчанию
  /// пусто: тексты событий живут только в файле, и мир без загрузчика
  /// событий не показывает (старые тесты чисел идут без них).
  final List<WorldEventSpec> events;

  /// `_rules.frequency`: не больше стольких событий за неделю (1–2).
  final int eventsPerWeekMax;

  /// `_rules.frequency`: одно и то же событие — не чаще раза в столько недель.
  final int eventRepeatWeeks;

  WorldFood? food(String id) => _find(foods, (WorldFood f) => f.id == id);
  WorldHome? home(String id) => _find(homes, (WorldHome h) => h.id == id);
  WorldPet? pet(String id) => _find(pets, (WorldPet p) => p.id == id);
  WorldTech? tech(String id) => _find(techs, (WorldTech t) => t.id == id);
  WorldItem? cloth(String id) => _find(clothes, (WorldItem c) => c.id == id);
  WorldItem? decorItem(String id) => _find(decor, (WorldItem d) => d.id == id);
  WorldLeisure? leisureKind(String id) =>
      _find(leisure, (WorldLeisure l) => l.id == id);
  WorldJob? job(String id, String? variant) =>
      _find(jobs, (WorldJob j) => j.id == id && j.variant == variant);
  WorldEventSpec? event(String id) =>
      _find(events, (WorldEventSpec e) => e.id == id);

  static T? _find<T>(List<T> list, bool Function(T) test) {
    for (final T x in list) {
      if (test(x)) return x;
    }
    return null;
  }

  // ─────────────────────── значения по умолчанию: v13 ───────────────────────

  /// Блюда v0.5 (Денис 29.09, сообщение 938): цена · 😊 · ⚡ за один приём.
  static const List<WorldFood> _foods = <WorldFood>[
    WorldFood(
        id: 'food_simple',
        title: 'Каша с хлебом',
        price: 70,
        happiness: 0,
        energyNow: 0.5,
        why: 'дёшево, но сил немного'),
    WorldFood(
        id: 'food_soup',
        title: 'Суп с хлебом',
        price: 90,
        happiness: 0,
        energyNow: 1,
        why: 'суп полезный, хоть и не праздник'),
    WorldFood(
        id: 'food_regular',
        title: 'Котлета с картошкой',
        price: 120,
        happiness: 1,
        energyNow: 1,
        why: 'обычный обед: сытно'),
    WorldFood(
        id: 'food_syrniki',
        title: 'Сырники с ягодами',
        price: 150,
        happiness: 2,
        energyNow: 1,
        why: 'вкусно и полезно'),
    WorldFood(
        id: 'food_burger',
        title: 'Бургер с картошкой',
        price: 160,
        happiness: 3,
        energyNow: 0,
        treat: true,
        why: 'вкусно, но сил от фастфуда нет'),
    WorldFood(
        id: 'food_tasty',
        title: 'Пицца',
        price: 200,
        happiness: 4,
        energyNow: 0.5,
        treat: true,
        why: 'пицца вкусная, но сил от неё мало'),
    WorldFood(
        id: 'food_fish',
        title: 'Рыба с овощами',
        price: 230,
        happiness: 3,
        energyNow: 1.5,
        why: 'рыба полезная и вкусная'),
    WorldFood(
        id: 'food_bread_tea',
        title: 'Бутерброд с чаем',
        price: 60,
        happiness: 0,
        energyNow: 0,
        why: 'самое дешёвое, но сил не даёт'),
    WorldFood(
        id: 'food_oatmeal',
        title: 'Овсянка с бананом',
        price: 80,
        happiness: 1,
        energyNow: 0.5,
        why: 'недорого и чуть приятнее каши'),
    WorldFood(
        id: 'food_pasta',
        title: 'Макароны с сосиской',
        price: 100,
        happiness: 2,
        energyNow: 0.5,
        why: 'вкусно и недорого, но сил немного'),
    WorldFood(
        id: 'food_omelet',
        title: 'Омлет с овощами',
        price: 130,
        happiness: 1,
        energyNow: 1.5,
        why: 'сил много, а на вкус — обычный завтрак'),
    WorldFood(
        id: 'food_icecream',
        title: 'Мороженое',
        price: 70,
        happiness: 2,
        energyNow: 0,
        treat: true,
        why: 'дёшево и радует, но сил ноль'),
    WorldFood(
        id: 'food_sushi',
        title: 'Роллы',
        price: 260,
        happiness: 4,
        energyNow: 1,
        why: 'самое вкусное и самое дорогое'),
  ];

  static const List<WorldHome> _homes = <WorldHome>[
    WorldHome(
        id: 'home_room',
        title: 'Комната в деревне',
        price: 0,
        weeklyCost: 250,
        energyPerWeek: 0,
        happinessPerWeek: 0,
        stage: WorldStage.village),
    WorldHome(
        id: 'home_flat',
        title: 'Квартира в городе',
        price: 1200,
        weeklyCost: 400,
        energyPerWeek: 1,
        happinessPerWeek: 4,
        stage: WorldStage.town),
    WorldHome(
        id: 'home_house',
        title: 'Квартира в Москве',
        price: 2000,
        weeklyCost: 1000,
        energyPerWeek: 2,
        happinessPerWeek: 8,
        stage: WorldStage.moscow),
  ];

  /// Рыбка 400 — решение 27.09 (docx Насти, P3); в слайдах v13 ещё 500.
  static const List<WorldPet> _pets = <WorldPet>[
    WorldPet(
        id: 'pet_fish',
        title: 'Рыбка',
        price: 400,
        foodPerWeek: 40,
        happinessPerWeek: 3),
    WorldPet(
        id: 'pet_hamster',
        title: 'Хомяк',
        price: 750,
        foodPerWeek: 60,
        happinessPerWeek: 4),
    WorldPet(
        id: 'pet_turtle',
        title: 'Черепаха',
        price: 900,
        foodPerWeek: 50,
        happinessPerWeek: 4),
    WorldPet(
        id: 'pet_kitten',
        title: 'Котёнок',
        price: 1800,
        foodPerWeek: 120,
        happinessPerWeek: 6),
    WorldPet(
        id: 'pet_dog',
        title: 'Собака',
        price: 3200,
        foodPerWeek: 180,
        happinessPerWeek: 7),
  ];

  static const Map<String, String> _transports = <String, String>{
    'transport_bike': 'Велосипед',
    'transport_scooter': 'Самокат',
    'transport_skateboard': 'Скейт',
  };

  /// Цены — разведка `ekonomika-realizm.md` §2.5 (1 монета ≈ 10 ₽).
  static const List<WorldTech> _techs = <WorldTech>[
    WorldTech(
        id: 'tech_laptop',
        title: 'Ноутбук',
        price: 3000,
        unlocks: <String>['computer']),
    WorldTech(
        id: 'tech_laptop_pro',
        title: 'Мощный ноутбук',
        price: 6000,
        unlocks: <String>['computer', 'computer_pro']),
  ];

  static const List<WorldItem> _clothes = <WorldItem>[
    WorldItem(
        id: 'cloth_cap',
        title: 'Кепка',
        price: 300,
        happinessByWeek: <int>[6, 3, 1]),
    WorldItem(
        id: 'cloth_scarf',
        title: 'Шарф',
        price: 350,
        happinessByWeek: <int>[6, 3, 1]),
    WorldItem(
        id: 'cloth_hoodie',
        title: 'Толстовка',
        price: 600,
        happinessByWeek: <int>[9, 5, 2]),
    WorldItem(
        id: 'cloth_sneakers',
        title: 'Кроссовки',
        price: 800,
        happinessByWeek: <int>[11, 6, 3]),
  ];

  static const List<WorldItem> _decor = <WorldItem>[
    WorldItem(
        id: 'poster_city',
        title: 'Плакат «Город»',
        price: 200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'poster_pets',
        title: 'Плакат «Питомцы»',
        price: 300,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'poster_music',
        title: 'Плакат «Музыка»',
        price: 450,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'plant_cactus',
        title: 'Кактус',
        price: 250,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'plant_flower',
        title: 'Цветок',
        price: 400,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'plant_floor',
        title: 'Напольное растение',
        price: 650,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'light_bulb',
        title: 'Лампочка',
        price: 300,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'light_garland_short',
        title: 'Короткая гирлянда',
        price: 500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'light_garland_long',
        title: 'Длинная гирлянда',
        price: 750,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'poster_space',
        title: 'Плакат «Космос»',
        price: 350,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'poster_sea',
        title: 'Плакат «Море»',
        price: 250,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'poster_dino',
        title: 'Плакат «Динозавр»',
        price: 400,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'plant_lemon',
        title: 'Лимонное деревце',
        price: 550,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'plant_fern',
        title: 'Папоротник',
        price: 350,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'light_lava',
        title: 'Лава-лампа',
        price: 600,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'light_star',
        title: 'Ночник-звезда',
        price: 400,
        happinessByWeek: <int>[3]),    WorldItem(
        id: 'decor_globe',
        title: 'Глобус',
        price: 450,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books',
        title: 'Стопка книг',
        price: 300,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear',
        title: 'Мягкий мишка',
        price: 350,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug',
        title: 'Круглый ковёр',
        price: 500,
        happinessByWeek: <int>[3]),
  ];

  static const List<WorldLeisure> _leisure = <WorldLeisure>[
    WorldLeisure(id: 'park', title: 'Парк', price: 0, energy: 1, happiness: 6),
    WorldLeisure(
        id: 'cafe',
        title: 'Кафе с друзьями',
        price: 200,
        energy: 1,
        happiness: 9),
    WorldLeisure(
        id: 'cinema',
        title: 'Кино с друзьями',
        price: 150,
        energy: 2,
        happiness: 10),
    WorldLeisure(
        id: 'pet_play',
        title: 'Игра с питомцем',
        price: 0,
        energy: 1,
        happiness: 4,
        perExtraPet: 1,
        requires: WorldLeisure.anyPet),
  ];

  static const List<WorldJob> _jobs = <WorldJob>[
    WorldJob(
        id: 'consultant', title: 'Продавец-консультант', pay: 300, energy: 2),
    WorldJob(id: 'cashier', title: 'Кассир', pay: 260, energy: 2),
    WorldJob(
        id: 'accountant', title: 'Помощник бухгалтера', pay: 280, energy: 2),
    WorldJob(id: 'gardener', title: 'Садовник', pay: 180, energy: 1),
    WorldJob(
        id: 'programmer',
        variant: 'easy',
        title: 'Программист · лёгкая',
        pay: 280,
        energy: 2,
        needs: 'computer'),
    WorldJob(
        id: 'programmer',
        variant: 'medium',
        title: 'Программист · средняя',
        pay: 400,
        energy: 3,
        needs: 'computer'),
    WorldJob(
        id: 'programmer',
        variant: 'hard',
        title: 'Программист · сложная',
        pay: 480,
        energy: 4,
        needs: 'computer_pro'),
    WorldJob(
        id: 'courier',
        variant: 'near',
        title: 'Курьер · близко',
        pay: 300,
        energy: 2,
        needs: 'transport'),
    WorldJob(
        id: 'courier',
        variant: 'district',
        title: 'Курьер · район',
        pay: 400,
        energy: 3,
        needs: 'transport'),
    WorldJob(
        id: 'courier',
        variant: 'far',
        title: 'Курьер · далеко',
        pay: 520,
        energy: 4,
        needs: 'transport'),
    WorldJob(
        id: 'dog_walker',
        title: 'Выгульщик собак',
        pay: 220,
        energy: 1,
        needs: 'pet_dog'),
  ];
}
