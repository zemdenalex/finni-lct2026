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

import 'dart:math' as math;

import 'achievements.dart';
import 'contract.dart' show ShiftChoice, WorldStage, roundTens;
import 'room_grid.dart';
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
    this.id,
    required this.jobId,
    required this.topic,
    required this.title,
    required this.situation,
    required this.understood,
    required this.word,
    required this.wordTerm,
    required this.choices,
  });

  /// id урока (`lessons.<job>[].id`); у единственного урока работы — нет,
  /// тогда [lessonId] = id работы, как было.
  final String? id;
  String get lessonId => id ?? jobId;

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
    this.moodKind,
  });

  final String id;
  final String? variant;

  /// Тип работы для настроения (DEN-18): `fin_fun`, `fin_dull`, `fun`,
  /// `dull` — [DayCycle.moodKinds]; `null` — без настроения от типа.
  final String? moodKind;
  final String title;
  final int pay;
  final double energy;

  /// Что открывает работу (или её уровень): `transport`, возможность
  /// техники ([WorldTech.unlocks]: `computer`, `computer_pro`) или id вещи
  /// (питомца). null — открыта с первого дня.
  final String? needs;
}

/// Все числа нового мира.
/// День по энергии (Денис 15.10, D1/D2/D7): неделя делится на дни, у дня своя
/// ⚡ от сна «до уровня», рядом отдельная шкала сытости. [daysPerWeek] = 1 —
/// прежняя неделя без дней (запасной флаг): сон кончает неделю, сытости нет.
/// Сон по таблице Дениса (DEN-20, прочтение pm — карточка DEN-26, ждёт «да»):
/// после сна = max([floor], x + ⌈([cap] − x) × [fraction]⌉), не больше [cap].
/// x — ⚡ до сна. При [floor] 10, [cap] 20, [fraction] 1/5: x ≤ 7 → 10,
/// 8 → 11, 9 → 12, 10–14 → +2, 15–19 → +1, 20 → 20. Сон поощряет тратить
/// силы, но копить можно: много сил — сон добавляет чуть-чуть.
class SleepRule {
  const SleepRule({this.floor = 10, this.cap = 20, this.fraction = 0.2});

  final double floor;
  final double cap;
  final double fraction;

  /// ⚡ после сна при [before] до сна. [capBonus] — постоянный бафф наград
  /// (DEN-32): потолок сна выше на столько же, как и предел ⚡.
  double after(double before, {double capBonus = 0}) {
    final double cap = this.cap + capBonus;
    final double x = before.clamp(0, cap).toDouble();
    // Без ε: при долях 0,1…0,35 и шаге ⚡ 0,5 произведение не выходит
    // «чуть больше целого» (проверено перебором), ⌈⌉ точен.
    final double add = ((cap - x) * fraction).ceilToDouble();
    final double y = x + (add < 0 ? 0 : add);
    if (y < floor) return floor;
    return y > cap ? cap : y;
  }
}

/// Рост оплаты от опыта (DEN-21 A, Денис 17.10: «экспоненциален +
/// округление вверх»): множитель [base] в степени (опыт × 3 / дней в неделе).
/// Недельный рост одинаков при 3, 5 и 7 днях: за неделю с одной хорошей
/// сменой в день оплата растёт в [base]³ раз (≈ +3 % при 1,01). В режиме
/// «неделя» ([daysPerWeek] 1) — [base] в степени опыта, как было.
double experiencePayMult(
    {required double base, required int experience, required int daysPerWeek}) {
  final double perPoint = daysPerWeek > 1 ? 3 / daysPerWeek : 1;
  return math.pow(base, experience * perPoint).toDouble();
}

/// Оплата смены в режиме дней: вверх до целой монеты (DEN-21 A), чтобы
/// каждый пункт опыта был виден сразу.
int ceilPay(double pay) => (pay - 1e-9).ceil();

/// Оплата смены в монетах ровно так, как её начисляет мир (`_offerFor` →
/// `completeJob`): ставка × опыт × ступень × перк × настроение, в том же
/// порядке умножения; режим дней — вверх до монеты ([ceilPay]), «неделя» —
/// до десятка ([roundTens]).
int shiftPayCoins({
  required int basePay,
  required double growth,
  required double step,
  required double perk,
  required double moodMult,
  required bool days,
}) {
  final double raw = basePay * growth * step * perk * moodMult;
  return days ? ceilPay(raw) : roundTens(raw);
}

/// Надбавка за опыт в монетах для этой смены (решение Дениса 19.10: «опыт»
/// на детских экранах словами и монетами): оплата смены минус та же оплата
/// без опыта (множитель 1), всё остальное и округление те же. Поэтому это
/// ровно столько монет, на сколько больше начисляют из-за опыта.
int experienceBonusCoins({
  required int basePay,
  required double growth,
  required double step,
  required double perk,
  required double moodMult,
  required bool days,
}) =>
    shiftPayCoins(
        basePay: basePay,
        growth: growth,
        step: step,
        perk: perk,
        moodMult: moodMult,
        days: days) -
    shiftPayCoins(
        basePay: basePay,
        growth: 1,
        step: step,
        perk: perk,
        moodMult: moodMult,
        days: days);

/// Вверх до десятка: суммы × `day_cycle.pay_scale` (оплата смен, траты
/// уроков) — 67,5 → 70, ровные 90 остаются 90.
int ceilTens(double x) => (x / 10 - 1e-9).ceil() * 10;

/// Везение или невезение на смене (Денис, DEN-23, 17.10): «плохой клиент»,
/// «чистый код», «отпустили пораньше». Сценарий выпадает с вероятностью
/// [DayCycle.luckChance], среди сценариев работы — по [weight]. Оплата ×
/// [payX] (вверх до монеты), [energyBack] ⚡ возвращается. Текст — из контента.
class ShiftLuck {
  const ShiftLuck({
    required this.id,
    required this.job,
    required this.good,
    required this.text,
    this.weight = 1,
    this.payX = 1,
    this.energyBack = 0,
  });

  final String id;
  final String job;
  final bool good;
  final String text;
  final double weight;
  final double payX;
  final double energyBack;
}

/// Настроение от типа работы (DEN-18): сдвиг 😊 за смену и строка итога.
class MoodKind {
  const MoodKind({required this.happiness, required this.text});

  final int happiness;
  final String text;
}

class DayCycle {
  const DayCycle({
    this.daysPerWeek = 1,
    this.sleepLevel = 4,
    this.carryMax = 1,
    this.satietyStart = 70,
    this.satietyPerAction = 10,
    this.satietyNight = 20,
    this.fullAt = 60,
    this.fullBonus = 1,
    this.hungryAt = 25,
    this.hungryMalus = 1,
    this.hungryHappiness = -2,
    this.mealBase = 30,
    this.mealPerEnergy = 15,
    this.dailyActivities = false,
    this.homeMealDaily = false,
    this.maxShiftsPerDay,
    this.maxEventsPerDay,
    this.shopEnergy = 1,
    this.restEnergy = 1,
    this.restHappiness = 2,
    this.sleepRule,
    this.energyMax,
    this.energyScale = 1,
    this.mealsPerWeek,
    this.maxShiftsPerWeek,
    this.maxShiftsPerJobPerWeek,
    this.moodKinds = const <String, MoodKind>{},
    this.moodRevert = 0,
    this.luckChance = 0,
    this.luck = const <ShiftLuck>[],
    this.shiftChoiceChance = 0,
    this.shiftChoices = const <ShiftChoice>[],
    this.eventsPerWeek,
    this.eventEachMorning = false,
    this.explainUi = false,
    this.moodPayDaily = false,
    this.moodPayLive = false,
    this.moodLive = const MoodLive(),
    this.xpStages = false,
    this.xpStageMin = const <int>[0, 2, 5],
    this.xpStageJobs = const <String>[
      'cashier',
      'consultant',
      'accountant',
      'gardener'
    ],
    this.payScale = 1,
    this.homeMealShare = 1,
    this.eventMoneyBase,
  });

  /// Вероятность сценария везения/невезения на смене; 0 — выключено.
  /// Возврат ⚡ в [luck] — уже в единицах цен (× `energy_scale` при разборе).
  final double luckChance;
  final List<ShiftLuck> luck;

  /// Вероятность мини-решения на смене ([ShiftChoice]); 0 — выключено.
  /// ⚡ вариантов — уже в единицах цен (× `energy_scale` при разборе).
  final double shiftChoiceChance;
  final List<ShiftChoice> shiftChoices;

  /// Событий за неделю не больше (режим дней; DEN-23 «побольше»); `null` —
  /// общий предел [WorldConfig.eventsPerWeekMax].
  final int? eventsPerWeek;

  /// Каждое утро — попытка показать событие (до 1 в день с
  /// [maxEventsPerDay]); иначе — только в начале недели и реактивные.
  final bool eventEachMorning;

  /// Объяснения модели «7 дней» на экранах (везение на смене, почему
  /// меняется настроение, как считаются опыт и сон) — `explain_ui`. Нет
  /// ключа — выключено. Домен читает его в одном месте: при включённом
  /// флаге строку везения показывает экран, и в `reason` она не дублируется.
  final bool explainUi;

  /// C6 / DEN-36, вариант A (`mood_pay_daily`): оплата и ⚡ смены — от
  /// настроения утра **этого дня**, а не начала недели. Выключен — как было.
  final bool moodPayDaily;

  /// DEN-36 A (Денис 18.10, `mood_pay_live`): оплата и ⚡ смены — от
  /// настроения **на момент смены** (после события или покупки — тоже), по
  /// шкалам [moodLive]. Сильнее [moodPayDaily]. Досуг — как раньше.
  final bool moodPayLive;
  final MoodLive moodLive;

  /// C2 / DEN-35, вариант A (`xp_stages`): ступени сложности работ от опыта.
  /// Ступень = сколько порогов [xpStageMin] опыт достиг (≥), наибольшая
  /// открытая — сама; только для работ [xpStageJobs]. Выключен — как было.
  final bool xpStages;
  final List<int> xpStageMin;
  final List<String> xpStageJobs;

  /// Масштаб оплаты смен в режиме дней (профиль баланса): база смены ×
  /// [payScale], вверх до десятка — смен в 7 днях вдвое-втрое больше.
  final double payScale;

  /// Какую долю сытости блюда даёт вечерняя еда дома (1 — всю; в строгом
  /// профиле меньше — голод достижим, если не есть самому).
  final double homeMealShare;

  /// База денежных эффектов событий (доли «карманных» в events.json) в
  /// режиме дней; `null` — сами карманные. Профиль баланса меняет карманные,
  /// а суммы событий остаются такими, как их писали (400).
  final int? eventMoneyBase;

  /// Сдвиг 😊 за смену по типу работы ([WorldJob.moodKind]).
  final Map<String, MoodKind> moodKinds;

  /// Утром 😊 возвращается к нейтральному на эту долю расстояния (DEN-18:
  /// настроение «ходит туда-сюда», а не копится). 0 — не возвращается.
  final double moodRevert;

  /// Масштаб ⚡ в режиме дней (DEN-18: смена берёт 6 при пределе 20): все
  /// цены и прибавки ⚡ из `economy.json` и `events.json` (работы, досуг,
  /// «на жизнь», еда, жильё, перенос сна, транспорт, события) умножаются при
  /// загрузке. Свои числа `day_cycle` (сон, перенос, сытость) — как есть.
  final double energyScale;

  /// Приёмов еды за неделю в режиме дней; `null` — `food.meals_per_week`.
  final int? mealsPerWeek;

  /// Смен за неделю и смен одной работы за неделю в режиме дней; `null` —
  /// `week.max_shifts_per_week` и `week.max_shifts_per_job_per_week`.
  final int? maxShiftsPerWeek;
  final int? maxShiftsPerJobPerWeek;

  /// Сон по таблице ([SleepRule]); `null` — прежний сон «до [sleepLevel]
  /// плюс перенос не больше [carryMax]».
  final SleepRule? sleepRule;

  /// Предел ⚡ в режиме дней (DEN-18: 20); `null` — общий `energy.max_per_week`.
  final double? energyMax;

  /// Ежедневные дела (контракт §4): холодильник и «отдохнуть дома». Выключено,
  /// пока Денис не решил; выключено — `stockFridge`/`restAtHome` отказывают.
  final bool dailyActivities;

  /// День без своей еды Финни ест дома меню недели (магазин так и обещает:
  /// «Приёмы, которые ты не выберешь сам, Финни съест дома»): вечером
  /// +сытость блюда. Монеты не списываются — домашняя еда уже в счёте недели.
  final bool homeMealDaily;

  /// Не больше стольких смен за день (DEN-18, «короткий день»); `null` — без
  /// ограничения: смены держат только силы и недельный лимит.
  final int? maxShiftsPerDay;

  /// Не больше стольких событий за день (DEN-23); `null` — как раньше: только
  /// недельный предел. Иначе после выбора в событии в тот же день сразу
  /// приходило следующее (slot_machine_sim → tired_but_good_shift).
  final int? maxEventsPerDay;

  /// ⚡ похода в магазин за едой для холодильника.
  final double shopEnergy;

  /// «Отдохнуть дома»: ⚡ и 😊.
  final double restEnergy;
  final int restHappiness;

  /// Дней в игровой неделе. 1 — дней нет, неделя как сдано.
  final int daysPerWeek;

  /// ⚡ утром от сна: «до уровня», а не «плюс N».
  final double sleepLevel;

  /// Сколько ⚡ вечера переходит в утро, не больше.
  final double carryMax;

  /// Сытость 0–100 на старте игры.
  final int satietyStart;

  /// Сытость: −за каждое дело (игровой день в журнале) и −за ночь.
  final int satietyPerAction;
  final int satietyNight;

  /// Утро: сытость ≥ [fullAt] — +[fullBonus] ⚡ (сытость → энергия, не наоборот).
  final int fullAt;
  final double fullBonus;

  /// Утро: сытость < [hungryAt] — голод: −[hungryMalus] ⚡ и [hungryHappiness] 😊.
  final int hungryAt;
  final double hungryMalus;
  final int hungryHappiness;

  /// Сытость блюда = [mealBase] + [mealPerEnergy] × ⚡ блюда.
  final int mealBase;
  final int mealPerEnergy;

  bool get enabled => daysPerWeek > 1;
}

class WorldConfig {
  const WorldConfig({
    this.dayCycle = const DayCycle(),
    this.shareParent = false,
    this.bankTransfer = false,
    this.achievements = const <AchievementDef>[],
    this.achievementsDays = false,
    this.room = RoomCatalog.empty,
    this.adultSection = false,
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
    this.finniPetHappiness = 1,
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
    this.adultWeeklyBonus = false,
    this.adultWeeklyBonusCoins = 20,
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

  /// День по энергии и сытость; `daysPerWeek == 1` — прежняя неделя.
  final DayCycle dayCycle;

  /// Кнопка «Отправить родителю» на «Прогрессе» (`economy.json →
  /// progress.share_parent`, EXP-9). Денис 18.10: «не делаем» — false.
  final bool shareParent;

  /// Перевод монет между частями в банке (`economy.json → bank.transfer`,
  /// ТЗ Насти «Начальное обучение» экраны 10–11). Решение о включении в
  /// сборку не принято (DEN-41) — false: банк = копилка, как в rc-7d.
  final bool bankTransfer;

  /// Награды и прогресс (`economy.json → achievements`).
  final List<AchievementDef> achievements;

  /// Награды дней включены (`economy.json → achievements_days` при 7 днях):
  /// тогда и экран наград открывается из «Прогресса» (баг-прогон 18.10).
  final bool achievementsDays;

  /// Раздел «Взрослым» как раздел (`economy.json → adult.section`, DEN-27):
  /// false — входа из комнаты нет, «Начать игру заново» и «Режим проверки»
  /// (за тем же примером) — в «Настройках».
  final bool adultSection;

  /// Вещи и сетка комнаты (`room_items.json`) и флаг `room.customize`.
  final RoomCatalog room;
  int get daysPerWeek => dayCycle.daysPerWeek;
  int get satietyStart => dayCycle.satietyStart;

  /// `happiness.finni_pet`: 😊 за первое касание Финни в игровой день.
  final int finniPetHappiness;

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

  /// Бонус взрослого монетами (DEN-27, вариант A, флаг `adult.weekly_bonus`):
  /// взрослый зашёл в раздел и подтвердил — [adultWeeklyBonusCoins] монет в
  /// кошелёк, раз в игровую неделю. Выключен — прежняя «+1 смена».
  final bool adultWeeklyBonus;
  final int adultWeeklyBonusCoins;

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

  /// Уроки работы по порядку файла (C8 / DEN-35 B: 2–3 на работу).
  List<WorldLesson> lessonsFor(String jobId) => <WorldLesson>[
        for (final WorldLesson l in lessons)
          if (l.jobId == jobId) l
      ];

  /// Урок после [n]-й смены работы (с 0): уроки чередуются по кругу, и
  /// каждая смена даёт следующий; нет уроков — null.
  WorldLesson? lessonFor(String jobId, int n) {
    final List<WorldLesson> ls = lessonsFor(jobId);
    return ls.isEmpty ? null : ls[n % ls.length];
  }

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
        price: 5000,
        weeklyCost: 400,
        energyPerWeek: 1,
        happinessPerWeek: 4,
        stage: WorldStage.town),
    WorldHome(
        id: 'home_house',
        title: 'Квартира в Москве',
        price: 12000,
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
        happinessByWeek: <int>[3]),
    WorldItem(
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
    // Скины предметов комнаты (29.09) — зеркало economy.json → decor.
    WorldItem(
        id: 'skin_cabinet__19a',
        title: 'Тумбочка простая',
        price: 100,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__19b',
        title: 'Тумбочка простая',
        price: 100,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__19v',
        title: 'Тумбочка простая',
        price: 100,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__19g',
        title: 'Тумбочка простая',
        price: 100,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__20a',
        title: 'Тумбочка с ящиками',
        price: 300,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__20b',
        title: 'Тумбочка с ящиками',
        price: 300,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__20v',
        title: 'Тумбочка с ящиками',
        price: 300,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__20g',
        title: 'Тумбочка с ящиками',
        price: 300,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__21a',
        title: 'Тумбочка-шкафчик',
        price: 500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__21b',
        title: 'Тумбочка-шкафчик',
        price: 500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__21v',
        title: 'Тумбочка-шкафчик',
        price: 500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_cabinet__21g',
        title: 'Тумбочка-шкафчик',
        price: 500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__2a',
        title: 'Кровать деревенская резная',
        price: 900,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__2b',
        title: 'Кровать деревенская резная',
        price: 900,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__2v',
        title: 'Кровать деревенская резная',
        price: 900,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__2g',
        title: 'Кровать деревенская резная',
        price: 900,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__3a',
        title: 'Кровать деревенская с узором',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__3b',
        title: 'Кровать деревенская с узором',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__3v',
        title: 'Кровать деревенская с узором',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__3g',
        title: 'Кровать деревенская с узором',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__4a',
        title: 'Кровать городская',
        price: 250,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__4b',
        title: 'Кровать городская',
        price: 250,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__4v',
        title: 'Кровать городская',
        price: 250,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__4g',
        title: 'Кровать городская',
        price: 250,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__5a',
        title: 'Кровать городская с ящиками',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__5b',
        title: 'Кровать городская с ящиками',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__5v',
        title: 'Кровать городская с ящиками',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__5g',
        title: 'Кровать городская с ящиками',
        price: 1500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__6a',
        title: 'Кровать городская мягкая',
        price: 4500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__6b',
        title: 'Кровать городская мягкая',
        price: 4500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__6v',
        title: 'Кровать городская мягкая',
        price: 4500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__6g',
        title: 'Кровать городская мягкая',
        price: 4500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__7a',
        title: 'Кровать московская',
        price: 400,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__7b',
        title: 'Кровать московская',
        price: 400,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__7v',
        title: 'Кровать московская',
        price: 400,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__7g',
        title: 'Кровать московская',
        price: 400,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__8a',
        title: 'Кровать московская с полкой',
        price: 4000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__8b',
        title: 'Кровать московская с полкой',
        price: 4000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__8v',
        title: 'Кровать московская с полкой',
        price: 4000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_bed__8g',
        title: 'Кровать московская с полкой',
        price: 4000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__10a',
        title: 'Стол деревенский',
        price: 120,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__10b',
        title: 'Стол деревенский',
        price: 120,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__10v',
        title: 'Стол деревенский',
        price: 120,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__10g',
        title: 'Стол деревенский',
        price: 120,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__11a',
        title: 'Стол деревенский с ящиками',
        price: 720,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__11b',
        title: 'Стол деревенский с ящиками',
        price: 720,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__11v',
        title: 'Стол деревенский с ящиками',
        price: 720,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__11g',
        title: 'Стол деревенский с ящиками',
        price: 720,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__13a',
        title: 'Стол городской',
        price: 200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__13b',
        title: 'Стол городской',
        price: 200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__13v',
        title: 'Стол городской',
        price: 200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__13g',
        title: 'Стол городской',
        price: 200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__14a',
        title: 'Стол городской с компьютером',
        price: 1200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__14b',
        title: 'Стол городской с компьютером',
        price: 1200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__14v',
        title: 'Стол городской с компьютером',
        price: 1200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__14g',
        title: 'Стол городской с компьютером',
        price: 1200,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__15a',
        title: 'Стол городской угловой',
        price: 3500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__15b',
        title: 'Стол городской угловой',
        price: 3500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__15v',
        title: 'Стол городской угловой',
        price: 3500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__15g',
        title: 'Стол городской угловой',
        price: 3500,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__17a',
        title: 'Стол московский с креслом',
        price: 1800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__17b',
        title: 'Стол московский с креслом',
        price: 1800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__17v',
        title: 'Стол московский с креслом',
        price: 1800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__17g',
        title: 'Стол московский с креслом',
        price: 1800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__18a',
        title: 'Стол московский угловой',
        price: 5000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__18b',
        title: 'Стол московский угловой',
        price: 5000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__18v',
        title: 'Стол московский угловой',
        price: 5000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'skin_desk__18g',
        title: 'Стол московский угловой',
        price: 5000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug__31a',
        title: 'Ковёр полосатый',
        price: 100,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug__31b',
        title: 'Ковёр полосатый',
        price: 100,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug__31v',
        title: 'Ковёр полосатый',
        price: 100,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug__33a',
        title: 'Ковёр с узором',
        price: 1000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug__33b',
        title: 'Ковёр с узором',
        price: 1000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug__33v',
        title: 'Ковёр с узором',
        price: 1000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_rug__33g',
        title: 'Ковёр с узором',
        price: 1000,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__34a',
        title: 'Глобус простой',
        price: 130,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__34b',
        title: 'Глобус простой',
        price: 130,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__34v',
        title: 'Глобус простой',
        price: 130,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__34g',
        title: 'Глобус простой',
        price: 130,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__35a',
        title: 'Глобус на ножке',
        price: 480,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__35b',
        title: 'Глобус на ножке',
        price: 480,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__35v',
        title: 'Глобус на ножке',
        price: 480,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__35g',
        title: 'Глобус на ножке',
        price: 480,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__36a',
        title: 'Глобус большой',
        price: 800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__36b',
        title: 'Глобус большой',
        price: 800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__36v',
        title: 'Глобус большой',
        price: 800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_globe__36g',
        title: 'Глобус большой',
        price: 800,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books__37b',
        title: 'Книги с чашкой',
        price: 110,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books__37v',
        title: 'Книги с чашкой',
        price: 110,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books__37g',
        title: 'Книги с чашкой',
        price: 110,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books__38a',
        title: 'Книги на подставке',
        price: 360,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books__38b',
        title: 'Книги на подставке',
        price: 360,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books__38v',
        title: 'Книги на подставке',
        price: 360,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_books__38g',
        title: 'Книги на подставке',
        price: 360,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__40a',
        title: 'Мишка',
        price: 120,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__40b',
        title: 'Мишка',
        price: 120,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__40g',
        title: 'Мишка',
        price: 120,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__41a',
        title: 'Мишка с заплатками',
        price: 420,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__41b',
        title: 'Мишка с заплатками',
        price: 420,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__41v',
        title: 'Мишка с заплатками',
        price: 420,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__41g',
        title: 'Мишка с заплатками',
        price: 420,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__42a',
        title: 'Мишка в шарфе',
        price: 700,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__42b',
        title: 'Мишка в шарфе',
        price: 700,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__42v',
        title: 'Мишка в шарфе',
        price: 700,
        happinessByWeek: <int>[3]),
    WorldItem(
        id: 'decor_bear__42g',
        title: 'Мишка в шарфе',
        price: 700,
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

  /// Порядок — как в `economy.json → jobs` (порядок доски): садовник первым
  /// (NAS-4 А).
  static const List<WorldJob> _jobs = <WorldJob>[
    WorldJob(id: 'gardener', title: 'Садовник', pay: 180, energy: 1),
    WorldJob(
        id: 'consultant', title: 'Продавец-консультант', pay: 300, energy: 2),
    WorldJob(id: 'cashier', title: 'Кассир', pay: 260, energy: 2),
    WorldJob(
        id: 'accountant', title: 'Помощник бухгалтера', pay: 280, energy: 2),
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

/// Шкалы оплаты и ⚡ смены от настроения на момент смены (DEN-36 A,
/// `day_cycle.mood_live`). Оплата — плавно: × (1 + [payPerPoint] × (😊 − 50))
/// в пределах [[payMin], [payMax]]. ⚡ — целыми: грустный (😊 ≤ [sadAt]) —
/// +[energyStep], радостный (😊 ≥ [happyAt]) — −[energyStep], между — без
/// изменений; сотых ⚡ от настроения не бывает. [energyStep] — в показанных
/// ⚡ (energy_scale его не умножает); цена работы не ниже [minJobEnergy].
class MoodLive {
  const MoodLive({
    this.payPerPoint = 0.006,
    this.payMin = 0.8,
    this.payMax = 1.2,
    this.sadAt = 40,
    this.happyAt = 60,
    this.energyStep = 1,
    this.minJobEnergy = 1,
  });

  final double payPerPoint;
  final double payMin;
  final double payMax;
  final int sadAt;
  final int happyAt;
  final double energyStep;
  final double minJobEnergy;

  /// Множитель оплаты при настроении [mood] (нейтраль [neutral]).
  double payMult(int mood, int neutral) =>
      (1 + payPerPoint * (mood - neutral)).clamp(payMin, payMax).toDouble();

  /// Сколько ⚡ настроение [mood] добавляет к цене смены: +шаг, 0 или −шаг.
  double energyDelta(int mood) => mood <= sadAt
      ? energyStep
      : mood >= happyAt
          ? -energyStep
          : 0;
}
