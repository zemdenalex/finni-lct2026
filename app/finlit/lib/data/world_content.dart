import 'dart:convert';

import '../domain/world/contract.dart';
import 'content_loader.dart' show ReadAsset;
import '../domain/world/world_config.dart'
    show
        DayCycle,
        MoodKind,
        MoodLive,
        ShiftLuck,
        SleepRule,
        WorldLesson,
        WorldLessonChoice;

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

  /// Четыре файла читаются разом: в браузере это четыре сетевых запроса,
  /// и подряд они складывали задержки до первого кадра (Настя 20.10).
  Future<WorldContent> load() async {
    final List<String> f = await Future.wait(<Future<String>>[
      read('$base/economy.json'),
      read('$base/jobs.json'),
      read('$base/events.json'),
      read('$base/room_items.json'),
    ]);
    return WorldContent.parse(
        economy: f[0], jobs: f[1], events: f[2], roomItems: f[3]);
  }
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
    this.payAdd = 0,
  });

  final String id;

  /// `pay_add` — прибавка к оплате смены в режиме 7 дней, монет, уже после
  /// `pay_scale` (Настя 20.10: «к прошлым зарплатам добавь те суммы»).
  final int payAdd;

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
    this.moodKind,
  });

  final String id;
  final String name;
  final bool unlocked;

  /// `mood_kind`: тип работы для настроения в режиме дней.
  final String? moodKind;

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
    this.adultWeeklyBonus = false,
    this.adultWeeklyBonusCoins = 20,
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
    this.shareParent = false,
    this.bankTransfer = false,
    required this.homeStart,
    required this.homes,
    this.adultSection = false,
    required this.petsHappinessTotalCap,
    required this.petsOneActive,
    required this.petDailyTouchHappiness,
    this.dayCycle = const DayCycle(),
    this.shiftChoicesUi = false,
    this.dogWalkGame = dogWalkGameDefault,
    this.tutorialUi = tutorialUiDefault,
    this.backgroundMusic = true,
    this.achievements = const <AchievementDef>[],
    this.achievementsDays = achievementsDaysDefault,
    this.cityLabelScale = cityLabelScaleDefault,
    this.achievementsDaysItems = const <AchievementDef>[],
    required this.finniPetHappiness,
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

  /// Бонус взрослого монетами (DEN-27, вариант A): `adult.weekly_bonus` —
  /// флаг, `adult.weekly_bonus_coins` — сколько монет раз в неделю.
  final bool adultWeeklyBonus;
  final int adultWeeklyBonusCoins;

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

  /// `progress.share_parent` (EXP-9, Денис 18.10: вариант 0 «не делаем»):
  /// кнопка «Отправить родителю» на «Прогрессе». Флаг экрана; нет ключа —
  /// false, как в файле.
  final bool shareParent;

  /// `bank.transfer` (ТЗ Насти 18.10, экраны 10–11; DEN-41 не решено):
  /// карточка «Что такое банк?» и экран «Перевод монет». Флаг экрана и
  /// действия; нет ключа — false, как в файле.
  final bool bankTransfer;
  final String homeStart;
  final List<HomeOption> homes;

  /// `adult.section` (DEN-27, Денис 18.10: «Взрослых мы вообще убираем пока
  /// как раздел»): входа «Взрослым» в комнате нет, сброс и режим проверки —
  /// в «Настройках». Нет ключа — false, как в файле.
  final bool adultSection;
  final int petsHappinessTotalCap;
  final bool petsOneActive;
  final int petDailyTouchHappiness;

  /// `day_cycle` (необязательный раздел): день по энергии и сытость.
  final DayCycle dayCycle;

  /// `day_cycle.shift_choices_ui`: экран смены показывает мини-решение
  /// (`JobOffer.choice`). Флаг экрана, не правило мира: движок вопрос
  /// задаёт и без него. Нет ключа — false (экран как раньше).
  final bool shiftChoicesUi;

  /// `day_cycle.dog_walk_game`: у выгульщика собак мини-игра «прогулка»
  /// (`jobs.json → jobs.dog_walker`); false — прежняя заглушка «Сделать».
  /// Флаг экрана, не правило мира. Нет ключа — [dogWalkGameDefault].
  final bool dogWalkGame;

  /// Значение [dogWalkGame] без ключа в файле — то же, что в сборке.
  static const bool dogWalkGameDefault = true;

  /// Обучалка первого захода (C4, `day_cycle.tutorial_ui`); вид при
  /// включённом — T1 ([tutorialLookFor]). Нет ключа — [tutorialUiDefault].
  final bool tutorialUi;

  /// Значение [tutorialUi] без ключа в файле — то же, что в сборке. Было
  /// включено (DEN-4 T1, Денис 18.10); 20.10 Денис: второе знакомство в
  /// комнате после сценок — дубль, «надо старый убрать».
  static const bool tutorialUiDefault = false;

  /// `day_cycle.xp_stages` без ключа в файле — то же, что в сборке (DEN-35
  /// B, Денис 18.10). Прямой `DayCycle()` в домене — по-прежнему без ступеней.
  static const bool xpStagesDefault = true;

  /// `city.label_scale` (DEN-30 A, Денис 18.10): подписи зданий на карте —
  /// радиус шкалы проекта, не «пилюля». Флаг экрана: `main.dart` передаёт его
  /// городу (`applyContentScreenFlags`). Нет ключа — [cityLabelScaleDefault].
  final bool cityLabelScale;

  /// Значение [cityLabelScale] без ключа в файле — то же, что в сборке.
  static const bool cityLabelScaleDefault = true;

  /// `audio.background_music`: фоновая мелодия есть в игре (DEN-34). false —
  /// плеер не создаётся, «Музыки» нет ни в настройках, ни в меню комнаты;
  /// звуки и вибрация не меняются. Нет ключа — true (как до флага).
  final bool backgroundMusic;

  /// `achievements` (необязательный): награды и прогресс.
  final List<AchievementDef> achievements;

  /// C7 (`achievements_days`): в режиме дней к [achievements] добавляются
  /// [achievementsDaysItems] — награды под 7 дней и работы.
  final bool achievementsDays;
  final List<AchievementDef> achievementsDaysItems;

  /// Значение [achievementsDays] без ключа в файле — то же, что в сборке
  /// (DEN-6 A, Денис 18.10).
  static const bool achievementsDaysDefault = true;

  /// `happiness.finni_pet`.
  final int finniPetHappiness;
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
    this.room = RoomCatalog.empty,
  });

  final EconomyContent economy;

  /// Кастомизация комнаты: `room_items.json` и флаг `economy.json →
  /// room.customize`. Нет файла — вещей нет.
  final RoomCatalog room;
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

  /// Разбирает файлы мира. Бросает [WorldContentError] с путём до поля.
  /// [roomItems] — `room_items.json`; null — вещей комнаты нет.
  static WorldContent parse({
    required String economy,
    required String jobs,
    required String events,
    String? roomItems,
  }) {
    final EconomyContent eco = _parseEconomy(
      _Node.root('economy.json', applyBalanceProfile(economy)),
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
      room: _parseRoom(
        roomItems == null ? null : _Node.root('room_items.json', roomItems),
        enabled: _Node.root('economy.json', economy)
                .opt('room')
                ?.opt('customize')
                ?.boolean ??
            false,
        eventBadge: _Node.root('economy.json', economy)
                .opt('room')
                ?.opt('event_badge')
                ?.boolean ??
            false,
        petName: _Node.root('economy.json', economy)
                .opt('room')
                ?.opt('pet_name')
                ?.boolean ??
            RoomCatalog.petNameDefault,
        view: _roomView(_Node.root('economy.json', economy)),
      ),
    );
  }
}

/// `economy.json → room.view`: `front` (как сдано) или `iso` (V2). Нет
/// ключа — [RoomCatalog.viewDefault]; другое значение — ошибка с путём.
String _roomView(_Node economy) {
  final _Node? v = economy.opt('room')?.opt('view');
  if (v == null) return RoomCatalog.viewDefault;
  final String s = v.string;
  if (!RoomCatalog.views.contains(s)) {
    throw WorldContentError(
        'economy.json', 'room.view', 'нужно «front» или «iso», а не «$s»');
  }
  return s;
}

/// `room_items.json`: сетка комнаты и вещи для неё. Ошибка — с путём.
RoomCatalog _parseRoom(_Node? r,
    {required bool enabled,
    bool eventBadge = false,
    bool petName = RoomCatalog.petNameDefault,
    String view = RoomCatalog.viewDefault}) {
  if (r == null) {
    return RoomCatalog(
        enabled: enabled, eventBadge: eventBadge, petName: petName, view: view);
  }
  final _Node g = r['grid'];
  final int cols = g['cols'].integer, rows = g['rows'].integer;
  final _Node cells = g['cells'];
  final List<String> map = cells.strings;
  if (map.length != rows) {
    throw WorldContentError(
        'room_items.json', 'grid.cells', 'рядов ${map.length}, а rows $rows');
  }
  for (int y = 0; y < map.length; y++) {
    if (map[y].length != cols || !RegExp(r'^[fwt.]*$').hasMatch(map[y])) {
      throw WorldContentError('room_items.json', 'grid.cells[$y]',
          'нужно $cols букв из f, w, t, «.»: «${map[y]}»');
    }
  }
  final List<RoomItemSpec> items = <RoomItemSpec>[];
  final List<_Node> list = r['items'].items;
  for (int i = 0; i < list.length; i++) {
    final _Node o = list[i];
    final String slotName = o['slot_type'].string;
    final RoomSlotType slot = RoomSlotType.byName(slotName) ??
        (throw WorldContentError('room_items.json', 'items[$i].slot_type',
            'неизвестное место «$slotName» (floor, wall, table)'));
    final int w = o['size_cells']['w'].integer,
        h = o['size_cells']['h'].integer;
    if (w < 1 || h < 1 || w > cols || h > rows) {
      throw WorldContentError('room_items.json', 'items[$i].size_cells',
          '$w × $h не встаёт в сетку $cols × $rows');
    }
    items.add(RoomItemSpec(
      id: o['id'].string,
      name: o['name'].string,
      w: w,
      h: h,
      price: o['price'].integer,
      sprite: o['sprite'].string,
      slot: slot,
    ));
  }
  return RoomCatalog(
    enabled: enabled,
    eventBadge: eventBadge,
    petName: petName,
    view: view,
    happinessOnce: r.opt('happiness_once')?.integer ?? 0,
    grid: RoomGrid(
      cols: cols,
      rows: rows,
      originX: g['origin']['x'].number,
      originY: g['origin']['y'].number,
      cell: g['cell'].number,
      map: map,
    ),
    items: items,
  );
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
            JobTier(
                id: '',
                pay: j['pay'].integer,
                energy: j['energy'].number,
                payAdd: j.opt('pay_add')?.integer ?? 0),
          ]
        : tiersNode.items
            .map(
              (_Node t) => JobTier(
                id: t['id'].string,
                name: t.opt('name')?.string,
                pay: t['pay'].integer,
                energy: t['energy'].number,
                unlockedBy: t.opt('unlocked_by')?.string,
                payAdd: t.opt('pay_add')?.integer ?? 0,
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
      moodKind: j.opt('mood_kind')?.string,
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
    adultWeeklyBonus: r.opt('adult')?.opt('weekly_bonus')?.boolean ?? false,
    adultWeeklyBonusCoins:
        r.opt('adult')?.opt('weekly_bonus_coins')?.integer ?? 20,
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
    shareParent: r.opt('progress')?.opt('share_parent')?.boolean ?? false,
    bankTransfer: r.opt('bank')?.opt('transfer')?.boolean ?? false,
    homeStart: homeStartNode.string,
    homes: homes,
    adultSection: r.opt('adult')?.opt('section')?.boolean ?? false,
    petsHappinessTotalCap: pets['happiness_total_cap'].integer,
    petsOneActive: pets['one_active'].boolean,
    petDailyTouchHappiness: pets['daily_touch_happiness'].integer,
    dayCycle: _dayCycle(r.opt('day_cycle')),
    shiftChoicesUi:
        r.opt('day_cycle')?.opt('shift_choices_ui')?.boolean ?? false,
    dogWalkGame: r.opt('day_cycle')?.opt('dog_walk_game')?.boolean ??
        EconomyContent.dogWalkGameDefault,
    tutorialUi: r.opt('day_cycle')?.opt('tutorial_ui')?.boolean ??
        EconomyContent.tutorialUiDefault,
    backgroundMusic: r.opt('audio')?.opt('background_music')?.boolean ?? true,
    achievements: _achievements(r.opt('achievements')),
    achievementsDays: r.opt('achievements_days')?.boolean ??
        EconomyContent.achievementsDaysDefault,
    cityLabelScale: r.opt('city')?.opt('label_scale')?.boolean ??
        EconomyContent.cityLabelScaleDefault,
    achievementsDaysItems: _achievements(r.opt('achievements_days_items')),
    finniPetHappiness: hap['finni_pet'].integer,
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

/// `jobs.json → lessons.<job>`: урок после смены (критерии ночи §4) —
/// объект или список уроков (C8 / DEN-35 B: 2–3 на работу, чередуются; у
/// каждого в списке свой `id`). 2–3 варианта, у каждого — последствие и
/// реплика Финни; доли — от 0 до 1.
List<WorldLesson> _parseLessons(_Node r, EconomyContent eco) {
  final _Node ls = r['lessons'];
  final List<WorldLesson> out = <WorldLesson>[];
  final Set<String> ids = <String>{};
  for (final String job in ls.keys) {
    final _Node node = ls[job];
    if (!eco.jobs.containsKey(job)) {
      node.fail('профессии нет в economy.json → jobs');
    }
    final bool many = node.value is List<Object?>;
    for (final _Node l in many ? node.items : <_Node>[node]) {
      final String? id = many ? l['id'].string : l.opt('id')?.string;
      if (id != null && !ids.add(id)) l['id'].fail('id урока повторяется');
      out.add(_parseLesson(job, id, l));
    }
  }
  return out;
}

WorldLesson _parseLesson(String job, String? id, _Node l) {
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

  return WorldLesson(
    id: id,
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
  );
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
    _checkGame(id, j, eco);
    // Ступени сложности (C2): база + переопределения ступени, та же схема.
    final List<_Node> stages = j.opt('stages')?.items ?? const <_Node>[];
    for (final _Node s in stages) {
      _checkGame(
          id, _Node(s.file, s.path, mergeJobStage(j.object, s.object)), eco);
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

/// Схема каждой игры: то, без чего экран не соберётся. [j] — поля игры
/// (база или ступень, слитая с базой).
void _checkGame(String id, _Node j, EconomyContent eco) {
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
      if (j['anchor_shifts'].integer < 0) {
        j['anchor_shifts'].fail('смен с ценником-якорем не меньше 0');
      }
      for (final String k in const <String>['shelf_penalty', 'pick_penalty']) {
        final double v = j[k].number;
        if (v < 0 || v > 1) j[k].fail('штраф — доля оценки от 0 до 1');
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
          final _Node? review = i.opt('review');
          if (review != null && review.string.length > 140) {
            review.fail('отзыв — одно короткое предложение (до 140 знаков)');
          }
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
        'retry',
        'too_little',
        'too_much',
      ]) {
        j['feedback'][k].string;
      }
      j['count_up'].string;
      if (j['diff_hint_from'].integer < 1) {
        j['diff_hint_from']
            .fail('с какой ошибки подряд видно «на сколько»: от 1');
      }
    case 'gardener':
      j['beds'].integer;
      final List<int> grid = j['grid'].integers;
      if (grid.length != 2 || grid[0] * grid[1] != j['beds'].integer) {
        j['grid'].fail('нужно [столбцы, строки], и их произведение = beds');
      }
      // Поля по сменам (C3): у каждого свои грядки и сетка.
      for (final _Node f in j.opt('fields')?.items ?? const <_Node>[]) {
        f['id'].string;
        final List<int> fg = f['grid'].integers;
        if (fg.length != 2 || fg[0] * fg[1] != f['beds'].integer) {
          f['grid'].fail('нужно [столбцы, строки], и их произведение = beds');
        }
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
    case 'dog_walker':
      final Set<String> items = j['items'].keys.toSet();
      final Set<String> blocks = j['blocks'].keys.toSet();
      for (final String k in <String>{...items, ...blocks}) {
        if (k.length != 1 || 'SG.'.contains(k)) {
          j.fail('«$k» — клетка обозначается одной буквой, не S, G или .');
        }
      }
      if (items.intersection(blocks).isNotEmpty) {
        j['blocks'].fail('буква и предмет, и препятствие');
      }
      for (final String k in items) {
        j['items'][k]['name'].string;
        j['items'][k]['found'].string;
      }
      for (final String k in blocks) {
        j['blocks'][k]['name'].string;
        j['blocks'][k]['note'].string;
      }
      final List<_Node> levels = j['levels'].items;
      if (levels.isEmpty) j['levels'].fail('нужна хотя бы одна прогулка');
      final Set<String> levelIds = <String>{};
      for (final _Node l in levels) {
        if (!levelIds.add(l['id'].string)) {
          l['id'].fail('повтор id прогулки');
        }
        l['title'].string;
        _checkMap(l['map'], l['maze'].integers, <String>{...items, ...blocks});
        if (!l['map'].strings.join().split('').any(items.contains)) {
          l['map'].fail('на тропинке нечего собрать');
        }
        if (l['best_steps'].integer < 1) {
          l['best_steps'].fail('нужен хотя бы один шаг');
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
}

/// Ступень сложности (C2): поля ступени поверх базовых — словари
/// сливаются, списки и числа заменяются; `stages` в результат не идёт.
Map<String, Object?> mergeJobStage(
    Map<String, Object?> base, Map<String, Object?> patch) {
  Map<String, Object?> merge(Map<String, Object?> a, Map<String, Object?> b) {
    final Map<String, Object?> out = <String, Object?>{...a};
    b.forEach((String k, Object? v) {
      final Object? old = out[k];
      out[k] = old is Map<String, Object?> && v is Map<String, Object?>
          ? merge(old, v)
          : v;
    });
    return out;
  }

  return merge(base, patch)..remove('stages');
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

/// Лимит смен режима дней: нет ключа — недельный лимит (`null`), ключ со
/// значением `null` — лимита нет ([kNoShiftLimit]), число — оно.
int? _limit(_Node n, String key) {
  final _Node? v = n.opt(key);
  if (v == null) return null;
  return v.value == null ? kNoShiftLimit : v.integer;
}

/// Профиль баланса (finni по решению Дениса «продумать экономику заново»,
/// 17.10): `balance_profile` выбирает один из `balance_profiles`, и его
/// значения поверх файла — словари сливаются, числа и строки заменяются.
/// Нет `balance_profile` или режим «неделя» (`days_per_week` ≤ 1) — файл
/// как есть. Неизвестный профиль — ошибка.
String applyBalanceProfile(String economyJson) {
  final Object? root = jsonDecode(economyJson);
  if (root is! Map<String, Object?>) return economyJson;
  final Object? name = root['balance_profile'];
  if (name == null) return economyJson;
  // Профили — для экономики дней; запасной режим «неделя» — как сдано.
  final Object? dc = root['day_cycle'];
  final Object? days = dc is Map<String, Object?> ? dc['days_per_week'] : null;
  if (days is! num || days <= 1) return economyJson;
  final Object? all = root['balance_profiles'];
  final Object? patch = all is Map<String, Object?> ? all[name] : null;
  if (patch is! Map<String, Object?>) {
    throw WorldContentError(
        'economy.json', 'balance_profile', 'нет профиля «$name»');
  }
  Map<String, Object?> merge(Map<String, Object?> a, Map<String, Object?> b) {
    final Map<String, Object?> out = <String, Object?>{...a};
    b.forEach((String k, Object? v) {
      final Object? old = out[k];
      out[k] = old is Map<String, Object?> && v is Map<String, Object?>
          ? merge(old, v)
          : v;
    });
    return out;
  }

  return jsonEncode(merge(root, patch));
}

/// `day_cycle`: нет раздела — прежняя неделя (`days_per_week` 1).
DayCycle _dayCycle(_Node? n) {
  if (n == null) return const DayCycle();
  const DayCycle d = DayCycle();
  int i(String k, int def) => n.opt(k)?.integer ?? def;
  double x(String k, double def) => n.opt(k)?.number ?? def;
  return DayCycle(
    daysPerWeek: i('days_per_week', d.daysPerWeek),
    sleepLevel: x('sleep_level', d.sleepLevel),
    carryMax: x('carry_max', d.carryMax),
    satietyStart: i('satiety_start', d.satietyStart),
    satietyPerAction: i('satiety_per_action', d.satietyPerAction),
    satietyNight: i('satiety_night', d.satietyNight),
    fullAt: i('satiety_full_at', d.fullAt),
    fullBonus: x('satiety_full_bonus', d.fullBonus),
    hungryAt: i('satiety_hungry_at', d.hungryAt),
    hungryMalus: x('satiety_hungry_malus', d.hungryMalus),
    hungryHappiness: i('satiety_hungry_happiness', d.hungryHappiness),
    mealBase: i('satiety_meal_base', d.mealBase),
    mealPerEnergy: i('satiety_meal_per_energy', d.mealPerEnergy),
    dailyActivities: n.opt('daily_activities')?.boolean ?? d.dailyActivities,
    explainUi: n.opt('explain_ui')?.boolean ?? d.explainUi,
    moodPayDaily: n.opt('mood_pay_daily')?.boolean ?? d.moodPayDaily,
    moodPayLive: n.opt('mood_pay_live')?.boolean ?? d.moodPayLive,
    moodLive: switch (n.opt('mood_live')) {
      null => d.moodLive,
      final _Node m => () {
          final MoodLive v = MoodLive(
            payPerPoint: m['pay_per_point'].number,
            payMin: m['pay_min'].number,
            payMax: m['pay_max'].number,
            sadAt: m['sad_at'].integer,
            happyAt: m['happy_at'].integer,
            energyStep: m['energy_step'].number,
            minJobEnergy: m.opt('min_job_energy')?.number ?? 1,
          );
          if (v.payMin > 1 || v.payMax < 1 || v.sadAt >= v.happyAt) {
            m.fail('mood_live: pay_min ≤ 1 ≤ pay_max и sad_at < happy_at');
          }
          return v;
        }(),
    },
    xpStages: n.opt('xp_stages')?.boolean ?? EconomyContent.xpStagesDefault,
    xpStageMin: switch (n.opt('xp_stage_min')) {
      null => d.xpStageMin,
      final _Node m => () {
          final List<int> v = m.integers;
          for (int k = 0; k < v.length; k++) {
            if (k == 0 ? v[k] != 0 : v[k] <= v[k - 1]) {
              m.fail('пороги ступеней: с 0 и строго по возрастанию');
            }
          }
          return v;
        }(),
    },
    xpStageJobs: n.opt('xp_stage_jobs')?.strings ?? d.xpStageJobs,
    payScale: x('pay_scale', d.payScale),
    homeMealShare: x('home_meal_satiety_share', d.homeMealShare),
    eventMoneyBase: n.opt('event_money_base')?.integer,
    homeMealDaily: n.opt('home_meal_daily')?.boolean ?? d.homeMealDaily,
    maxShiftsPerDay: n.opt('max_shifts_per_day')?.integer,
    maxEventsPerDay: n.opt('max_events_per_day')?.integer,
    shopEnergy: x('shop_energy', d.shopEnergy),
    restEnergy: x('rest_energy', d.restEnergy),
    restHappiness: i('rest_happiness', d.restHappiness),
    sleepRule: switch (n.opt('sleep_rule')) {
      null => null,
      final _Node s => SleepRule(
          floor: s.opt('floor')?.number ?? 10,
          cap: s.opt('cap')?.number ?? 20,
          fraction: s.opt('fraction')?.number ?? 0.2,
        ),
    },
    energyMax: n.opt('energy_max')?.number,
    energyScale: x('energy_scale', d.energyScale),
    mealsPerWeek: n.opt('meals_per_week')?.integer,
    maxShiftsPerWeek: _limit(n, 'max_shifts_per_week'),
    maxShiftsPerJobPerWeek: _limit(n, 'max_shifts_per_job_per_week'),
    moodKinds: <String, MoodKind>{
      if (n.opt('mood_kinds') case final _Node m)
        for (final MapEntry<String, Object?> e in m._map.entries)
          if (!e.key.startsWith('_'))
            e.key: MoodKind(
              happiness: m[e.key]['happiness'].integer,
              text: m[e.key]['text'].string,
            ),
    },
    moodRevert: x('mood_revert', d.moodRevert),
    luckChance: n.opt('shift_luck')?.opt('chance')?.number ?? 0,
    luck: <ShiftLuck>[
      if (n.opt('shift_luck')?.opt('scenarios') case final _Node list)
        for (final _Node s in list.items)
          ShiftLuck(
            id: s['id'].string,
            job: s['work'].string,
            good: s['kind'].string == 'good',
            text: s['text'].string,
            weight: s.opt('weight')?.number ?? 1,
            payX: s.opt('pay_x')?.number ?? 1,
            // ⚡ — до масштаба: × energy_scale.
            energyBack:
                (s.opt('energy_back')?.number ?? 0) * x('energy_scale', 1),
          ),
    ],
    shiftChoiceChance: n.opt('shift_choices')?.opt('chance')?.number ?? 0,
    shiftChoices: <ShiftChoice>[
      if (n.opt('shift_choices')?.opt('items') case final _Node list)
        for (final _Node q in list.items) _shiftChoice(q, x('energy_scale', 1)),
    ],
    eventsPerWeek: n.opt('events_per_week')?.integer,
    eventEachMorning: n.opt('event_each_morning')?.boolean ?? false,
  );
}

/// `day_cycle.shift_choices.items[]`: вопрос и 2–3 варианта с разными id.
/// ⚡ варианта — до масштаба: × [energyScale].
ShiftChoice _shiftChoice(_Node q, double energyScale) {
  final List<_Node> os = q['options'].items;
  if (os.length < 2 || os.length > 3) {
    q['options'].fail('нужно 2–3 варианта, а их ${os.length}');
  }
  final List<ShiftChoiceOption> options = <ShiftChoiceOption>[
    for (final _Node o in os)
      ShiftChoiceOption(
        id: o['id'].string,
        label: o['label'].string,
        payX: o.opt('pay_x')?.number ?? 1,
        energy: (o.opt('energy')?.number ?? 0) * energyScale,
        happiness: o.opt('happiness')?.integer ?? 0,
        effectHint: o.opt('effect_hint')?.string,
      ),
  ];
  if (options.map((ShiftChoiceOption o) => o.id).toSet().length !=
      options.length) {
    q['options'].fail('id вариантов повторяются');
  }
  return ShiftChoice(
    id: q['id'].string,
    work: q['work'].string,
    question: q['question'].string,
    options: options,
  );
}

/// `achievements`: нет раздела — наград нет. Неизвестная метрика — ошибка
/// контента, а не молчаливо пропущенная награда.
List<AchievementDef> _achievements(_Node? n) {
  if (n == null) return const <AchievementDef>[];
  return <AchievementDef>[
    for (final _Node a in n.items)
      AchievementDef(
        id: a['id'].string,
        title: a['title'].string,
        topic: a['topic'].string,
        hint: a['hint'].string,
        metric: AchievementMetric.byKey(a['metric'].string) ??
            (throw FormatException(
                'achievements: метрика ${a['metric'].string} не известна')),
        target: a['target'].integer,
        effect: _achievementEffect(a.opt('effect')),
      ),
  ];
}

/// `effect` награды (DEN-32): `{"type": "mood", "happiness": 3, "days": 3}`
/// или `{"type": "energy_max", "value": 1}`. Границы — чтобы опечатка в
/// файле не сломала баланс: 😊 1–10, дней 1–7, ⚡ 1–3.
AchievementEffect? _achievementEffect(_Node? n) {
  if (n == null) return null;
  switch (n['type'].string) {
    case 'mood':
      final int h = n['happiness'].integer;
      final int d = n['days'].integer;
      if (h < 1 || h > 10 || d < 1 || d > 7) {
        n.fail('effect mood: happiness 1–10, days 1–7');
      }
      return MoodBuff(happiness: h, days: d);
    case 'energy_max':
      final double v = n['value'].number;
      if (v < 1 || v > 3) n.fail('effect energy_max: value 1–3');
      return EnergyMaxBuff(value: v);
    default:
      n.fail('effect: type mood | energy_max');
  }
}
