/// Контракт нового мира Финни (карточка A0.5, `docs/zadachi-agentam-29-09.md`).
///
/// 🔴 Один файл, против которого пишут все: домен (A1–A9) реализует [World]
/// на журнале, экраны (поток B) строятся против [World] с `FakeWorld`, потом
/// подмена одной строкой. Меняется этот файл — договариваются оба потока.
///
/// Миграция добавлением: старый мир (`Game`, `PetMeters`, `PetSpecies`,
/// `LedgerKind`) не трогается, пока поток B не переключит экраны.
///
/// Чистый Dart — проверяется `test/domain/layering_test.dart`.
library;

/// Стадия роста = где живёт Финни (open-questions T3: деревня → пригород →
/// Москва). 🟡 Названия на экране ещё обсуждаются командой — в коде только id.
///
/// Пороги очков (0 / 4 / 9, T2) и небольшая ступень оплаты после переезда
/// (P1, `growth.stages[].pay_step`) — данные `economy.json`, а не поля
/// перечисления.
enum WorldStage { village, town, moscow }

/// Этап игровой недели (`docs/game/week-loop.md`).
///
/// Называется WeekPhase, а не PeriodPhase: старый `PeriodPhase` из `game.dart`
/// живёт до переключения экранов, и одинаковые имена дали бы неоднозначный
/// импорт в любом файле, который видит оба.
enum WeekPhase {
  /// Первый запуск или сброс: ещё не было ни одной недели.
  onboarding,

  /// Начало недели 2+: карманные, запас ⚡, события. Сразу переходит в
  /// [planning] — отдельным состоянием держится ради защиты от двойного
  /// начисления при перезапуске.
  weekStart,

  /// Раскладка карманных по НУЖНО / ХОЧУ / ЦЕЛЬ. Без подтверждённого плана
  /// работа, покупки и досуг недоступны (ТЗ 2.5.5.1).
  planning,

  /// Неделя идёт: любые действия в любом порядке.
  living,

  /// Неделя кончилась (⚡ не хватает ни на одно действие или «Спать»):
  /// счета, правило нехватки, итоги, очки роста.
  review,
}

/// Чем кончилась неделя.
enum WeekEnd {
  /// ⚡ не хватает ни на одно действие. Не наказание, просто без бонуса сна.
  energyOut,

  /// Ребёнок нажал «Спать».
  sleep,
}

/// Новые виды записей журнала для нового мира (`docs/game/state-model.md`).
///
/// 🔴 Отдельное перечисление, а не новые значения `LedgerKind`: в
/// `LedgerFold.factOfPeriod` исчерпывающий `switch` по `LedgerKind`, и любое
/// новое значение там ломает анализатор и старые экраны.
///
/// Старые виды (`pocketMoney`, `planConfirmed`, `purchase`,
/// `purchaseDeclined`, `envelopeMove`, `savingsDeposit`, `savingsWithdraw`,
/// `periodClosed`, `wish*`, `goalFulfilled`) остаются в `LedgerKind` и
/// используются новым миром как есть. Как запись несёт вид нового мира —
/// решает реализация журнала (A2).
enum WorldLedgerKind {
  /// Начало недели: запас ⚡ и счета недели.
  weekStarted,

  /// Стартовый подарок в ЦЕЛЬ при первом запуске (P2, 200 монет).
  startGift,

  /// Обязательный счёт оплачен (еда, корм, жильё).
  billPaid,

  /// Счёт не закрыт своими деньгами — для учёта.
  billMissed,

  /// Карточка смены показана, оплата зафиксирована в `args.pay`.
  jobStarted,

  /// Оплата смены в кошелёк заработка `free`.
  jobPayout,

  /// Ползунок «на цель» после смены: `free` → ЦЕЛЬ.
  goalSliderDeposit,

  /// Досуг: парк, кафе, кино, игра с питомцем.
  leisure,

  /// «Спать»: неделя закрыта ребёнком.
  sleep,

  /// ⚡ кончилась: неделя закрыта сама.
  energyOut,

  /// Событие недели показано.
  eventShown,

  /// Выбор в событии и его последствия.
  eventChoice,

  /// Куплен питомец (цель).
  petBought,

  /// Куплен транспорт (цель).
  transportBought,

  /// Куплено жильё (цель).
  homeBought,

  /// Куплена техника (цель): ноутбук открывает работы (Денис 29.09, 941).
  techBought,

  /// Вещь осталась у Финни: одежда, декор.
  itemOwned,

  /// Сменён активный питомец.
  activePetChanged,

  /// 😊 за первый тап по питомцу в игровой день.
  petTapHappiness,

  /// Нехватку на обязательное покрыла семья: −😊, без очка роста.
  familyHelp,

  /// Симуляция «понарошку» без денег (вместо автомата, К1).
  simulationRun,

  /// Дополнительное задание от взрослого (К4, ТЗ 2.5.12.3): +1 смена к
  /// лимиту **этой** недели — и к общему, и к лимиту каждой работы. Не
  /// монеты: монеты, ⚡ и 😊 запись не меняет. Раз в неделю.
  parentBonus,

  /// Финни перешёл на новую стадию.
  stageChanged,

  /// Прошёл игровой день (смена, досуг, событие с тратой ⚡): −😊, как −1 ⚡
  /// «на жизнь» (P7). Пишется перед записью самого действия.
  dayPassed,

  /// Урок после смены (критерии ночи §4): выбор ребёнка и его последствие
  /// — монеты в конверт, трата, 😊. `args.jobId`, `args.choiceId`.
  lessonChoice,

  /// Финни поел (Денис 29.09, 938): блюдо `args.foodId` за `args.price` из
  /// НУЖНО → заработок → ХОЧУ, ⚡ и 😊 сразу. Не игровой день.
  mealEaten,
}

/// Снимок ресурсов. Не хранится — выводится из журнала (у фейка — из полей).
///
/// Все суммы монет целые; ⚡ дробная (на экране — полоса с шагом 0,5).
class ResourceSnapshot {
  const ResourceSnapshot({
    required this.weekNo,
    required this.need,
    required this.want,
    required this.goal,
    required this.free,
    required this.unallocated,
    required this.energy,
    required this.happiness,
    required this.growthPoints,
    required this.stage,
    required this.experience,
    required this.shiftsThisWeek,
    required this.weeklyBill,
    required this.owned,
    this.activeGoalId,
    this.activePetId,
    this.endedBy,
    this.moodReason = MoodReason.neutral,
    this.foodId,
    this.daysThisWeek = 0,
    this.snacksThisWeek = 0,
    this.mealsThisWeek = 0,
    this.mealsPerWeek = 0,
    this.toolPayback = const <String, int>{},
  });

  /// Номер игровой недели, с 1. До первой недели — 0.
  final int weekNo;

  /// Конверт НУЖНО: зарезервировано на счета недели.
  final int need;

  /// Конверт ХОЧУ.
  final int want;

  /// Конверт ЦЕЛЬ = накоплено (ТЗ 2.5.3.1). В доступное не входит.
  final int goal;

  /// Кошелёк заработка: оплата смен и неразложенный остаток плана (К10).
  final int free;

  /// Карманные, которые ждут плана.
  final int unallocated;

  /// ⚡ 0..14, в начале недели 10 + бонусы.
  final double energy;

  /// 😊 0..100, старт 50.
  final int happiness;

  /// Очки роста за все недели. Никогда не уменьшаются.
  final int growthPoints;

  final WorldStage stage;

  /// Опыт = число **хорошо** сделанных смен за всю игру (P1, пересмотр
  /// 27.09): оценка мини-игры не ниже [JobOffer.goodScoreMin].
  final int experience;

  final int shiftsThisWeek;

  /// Сумма обязательных счетов, которые спишутся в конце этой недели:
  /// еда + корм питомцам + жильё + добавка события (рюкзак,
  /// `required_extra_pocket_x`). Питомец, купленный на этой неделе, ест
  /// со следующей.
  final int weeklyBill;

  /// id всего, чем Финни владеет: питомцы, транспорт, жильё, вещи.
  final Set<String> owned;

  final String? activeGoalId;
  final String? activePetId;

  /// Чем кончилась неделя — только в [WeekPhase.review].
  final WeekEnd? endedBy;

  /// Почему у Финни такое настроение — одной фразой (ТЗ 2.5.10.3, карточка
  /// A12): тап по Финни в комнате, итоги недели S11.
  final MoodReason moodReason;

  // ── этап 4 (фидбек дизайнера 28.09, п. 7): холодильник в комнате ──
  // Добавлено с умолчаниями, как C2: выводится из журнала, не хранится.

  /// Домашнее меню (`food.options[].id`): это блюдо Финни ест в итогах
  /// недели за приёмы, которые ребёнок не выбрал сам. null — мир не знает.
  final String? foodId;

  /// Игровых дней на этой неделе: действий, тративших ⚡ (смена, досуг,
  /// событие с тратой ⚡). Та же мера, что «день» у тапа питомца (T7).
  final int daysThisWeek;

  /// Перекусов куплено на этой неделе.
  final int snacksThisWeek;

  /// Сколько раз Финни поел на этой неделе ([World.eat]).
  final int mealsThisWeek;

  /// Сколько раз за неделю Финни ест (`food.meals_per_week`); 0 — мир не
  /// знает.
  final int mealsPerWeek;

  /// Окупаемость инструментов (ноутбук, транспорт): id вещи → сколько уже
  /// принесли смены сверх лучшей работы, открытой с первого дня. Дошло до
  /// цены — вещь окупилась (перепроверка экономики 29.09, Денис 1001).
  final Map<String, int> toolPayback;

  /// Приёмов пищи до конца недели: их Финни съест дома, если не выбрать.
  int get mealsLeft =>
      mealsPerWeek > mealsThisWeek ? mealsPerWeek - mealsThisWeek : 0;

  /// Доступно сейчас (💰 в HUD) = НУЖНО + ХОЧУ + заработок + неразложенное.
  int get available => need + want + free + unallocated;

  /// Накоплено на цель.
  int get saved => goal;
}

/// Итог любого действия: получилось ли, и **почему** — человеческой фразой.
///
/// 🔴 Называется WorldResult, а не ActionResult: `game.dart` уже экспортирует
/// `ActionResult`, и файл, который видит оба (экраны, `app_state`), получил
/// бы неоднозначный импорт — тот же класс ошибок, что с `Feedback` и `Split`.
///
/// Отказ — не исключение: действие не выполнено, ничего не изменилось, а
/// [reason] объясняет, чего не хватило, и [nextStep] — что можно сделать
/// (ТЗ 2.5.9.3–4).
class WorldResult {
  const WorldResult({
    required this.ok,
    required this.reasonCode,
    required this.reason,
    this.nextStep,
    this.coins = 0,
    this.goal = 0,
    this.energy = 0,
    this.happiness = 0,
  });

  const WorldResult.refused(this.reasonCode, this.reason, {this.nextStep})
      : ok = false,
        coins = 0,
        goal = 0,
        energy = 0,
        happiness = 0;

  /// Действие выполнено.
  final bool ok;

  /// Ключ текста в `copy.json` — для истории и озвучки.
  final String reasonCode;

  /// Что изменилось и почему, одной-двумя фразами голосом Финни.
  final String reason;

  /// Что делать дальше, если есть что предложить.
  final String? nextStep;

  /// Изменение доступных монет (💰 в HUD).
  final int coins;

  /// Изменение накоплений.
  final int goal;

  /// Изменение ⚡.
  final double energy;

  /// Изменение 😊.
  final int happiness;

  @override
  String toString() => 'WorldResult(${ok ? 'ok' : 'refused'} $reasonCode: '
      '$reason; coins $coins goal $goal energy $energy happiness $happiness)';
}

/// Карточка смены на доске «Требуется…» (S6).
///
/// 🔴 Оплата считается при показе и не меняется от времени и ошибок (P4):
/// [pay] = база × 1,02^опыт × ступень стадии × настроение × перки (P8).
/// Настроение и цена в ⚡ — по 😊 на начало недели (P7): всю неделю карточка
/// стоит одинаково, хотя каждый игровой день тратит немного 😊.
///
/// P1 (пересмотр 27.09): после игры оценка 0..1. **Хорошая смена** (оценка
/// ≥ [goodScoreMin]) даёт +1 опыт и бонус за эффективность ([bonusFor], до
/// [efficiencyBonusMax] = 20 % ставки, P6), но стоит сверх карточки
/// [goodEnergyExtra] ⚡ и [goodHappiness] 😊. **Обычная** — ровно [pay], без
/// опыта и бонуса, ⚡ ровно [energyCost].
class JobOffer {
  const JobOffer({
    required this.jobId,
    required this.title,
    required this.basePay,
    required this.experiencePercent,
    required this.stageStep,
    required this.pay,
    required this.efficiencyBonusMax,
    required this.energyCost,
    required this.shiftsLeft,
    required this.goodScoreMin,
    required this.goodEnergyExtra,
    required this.goodHappiness,
    this.variant,
    this.lockedReason,
    this.blockReason,
  });

  /// id работы из `economy.json → jobs`.
  final String jobId;

  /// Уровень у курьера и программиста (`tiers[].id`), иначе null.
  final String? variant;

  final String title;

  /// Базовая ставка из файла.
  final int basePay;

  /// «Опыт +X %» на доске: (1,02^опыт − 1) × 100, округлено.
  final int experiencePercent;

  /// Ступень стадии после переезда (`growth.stages[].pay_step`), сейчас
  /// ×1 / ×1,25 / ×1,5. 🔴 Дробная с 27.09 (была `int` при ×1 / ×3 / ×10):
  /// на экране — через форматтер, иначе интерполяция покажет «×2.0».
  final double stageStep;

  /// Сколько заплатят — известно до начала игры.
  final int pay;

  /// «+ за эффективность»: максимум сверху при оценке 1 (хорошая смена).
  final int efficiencyBonusMax;

  /// Цена в ⚡ целиком: база × настроение − транспорт + 1 «на жизнь».
  /// Столько нужно, чтобы начать; хорошая смена стоит ещё [goodEnergyExtra].
  final double energyCost;

  /// Сколько смен этой работы ещё можно взять на этой неделе.
  final int shiftsLeft;

  /// Порог «хорошо сделано» для оценки 0..1 (`good_score_min`).
  final double goodScoreMin;

  /// ⚡ сверх [energyCost] за хорошую смену (`good_shift_energy_extra`).
  /// Списывается после игры и не больше, чем осталось: смена не отменяется.
  final double goodEnergyExtra;

  /// 😊 за хорошую смену (`good_shift_happiness`, отрицательное).
  final int goodHappiness;

  /// Почему закрыта («нужен транспорт»), или null, если открыта.
  final String? lockedReason;

  bool get locked => lockedReason != null;

  /// Почему смену нельзя взять **прямо сейчас** (карточка A13), или null.
  ///
  /// Те же правила и в том же порядке, что у [World.completeJob] и
  /// [World.canDo] с [WorldAction.job]: фаза недели → закрыта ([lockedReason],
  /// «нужен транспорт») → смены кончились → мало ⚡. [BlockReason.code] равен
  /// `reasonCode` отказа `completeJob` — доска S6 не держит свою копию правил.
  ///
  /// 🔴 Не путать с [locked]: [locked] — только постоянный замок (транспорт,
  /// собака), а здесь ещё фаза, лимит смен и ⚡.
  final BlockReason? blockReason;

  /// Смену нельзя взять сейчас — по любой причине из [blockReason].
  bool get blocked => blockReason != null;

  /// Хорошо ли сделана смена с такой оценкой.
  bool isGoodScore(double score) => score >= goodScoreMin - 1e-9;

  /// Бонус за эффективность при оценке [score]: 0 за обычную смену, иначе
  /// [efficiencyBonusMax] × оценка, до монеты.
  int bonusFor(double score) {
    final double s = score.clamp(0.0, 1.0);
    return isGoodScore(s) ? roundTens(efficiencyBonusMax * s) : 0;
  }
}

/// Монеты, которые ребёнок видит за смену (ставка, бонус), — круглые, до
/// десятков (ревью df2164a §1.9: «Заплатят 303», «+61» читались как ошибка).
/// Половина — от нуля, как `num.round()` и `dround` симулятора.
int roundTens(num x) => (x / 10).round() * 10;

// ═══════════════ C2 (27.09): дыры, найденные потоком B — A10–A14 ═══════════════
//
// Всё ниже — **добавление**: старые поля и методы не переименованы, у новых
// полей снимка и карточки значения по умолчанию, поэтому существующие вызовы
// конструкторов собираются как раньше.

/// Причина настроения Финни (карточка A12, ТЗ 2.5.10.3): код + фраза.
class MoodReason {
  const MoodReason(this.code, this.text);

  /// Ключ текста в `copy.json`: `mood.leisure`, `mood.family_help`, …
  final String code;

  /// Одна фраза для ребёнка: тап по Финни, итоги недели.
  final String text;

  /// Причины нет — обычное настроение.
  static const MoodReason neutral =
      MoodReason('mood.neutral', 'У Финни обычное настроение.');

  @override
  String toString() => 'MoodReason($code: $text)';
}

/// ⚡ на экране — шагом 0,5 и с запятой, как полоса HUD: «3», «2,5».
/// Внутри ⚡ дробная (цена смены зависит от 😊), но ребёнку «3,02» ничего
/// не говорит (`economy.json → energy._note`).
/// «+» в плане, когда разложены все монеты (телефон Алины 28.09: «+» были
/// погашены, и казалось, что кнопки не работают). Кнопка не гаснет — говорит,
/// что сделать.
const String planAllSpentHint =
    'Все монеты уже разложены. Сначала нажми «−» там, где много, потом «+» здесь.';

/// Строка под конвертами, когда всё разложено: сразу подсказывает, как переложить.
const String planAllSpentLine =
    'Всё разложено. Переложить: «−» в одном конверте, «+» в другом.';

String energyShown(double e) {
  final double r = (e * 2).round() / 2;
  return r == r.roundToDouble()
      ? r.toInt().toString()
      : r.toStringAsFixed(1).replaceAll('.', ',');
}

/// Отказ по ⚡: «Нужно ⚡ 3, есть 2,5.» Если после округления числа совпали
/// (нужно 3,02, есть 2,99) — без двух одинаковых чисел.
String energyShortText(double need, double have) {
  final String n = energyShown(need);
  final String h = energyShown(have);
  return n == h ? 'Сил чуть-чуть не хватает: ⚡ $h.' : 'Нужно ⚡ $n, есть $h.';
}

/// Почему действие сейчас нельзя сделать (карточка A13).
///
/// [code] и [text] — ровно те, что вернёт само действие отказом
/// ([WorldResult.reasonCode], [WorldResult.reason]): экран может заранее
/// погасить кнопку и подписать её, не держа своей копии правил.
class BlockReason {
  const BlockReason(this.code, this.text, {this.nextStep});

  /// `phase.job`, `job.limit`, `job.energy`, `job.locked`, `buy.short`, …
  final String code;

  /// Чего не хватает, голосом Финни.
  final String text;

  /// Что можно сделать вместо этого, если есть что предложить.
  final String? nextStep;

  /// Тот же отказ в виде итога действия.
  WorldResult get refusal =>
      WorldResult.refused(code, text, nextStep: nextStep);

  @override
  String toString() => 'BlockReason($code: $text)';
}

/// Что проверяет [World.canDo]. Аргумент `id` — у каждого свой.
enum WorldAction {
  /// [World.startWeek].
  startWeek,

  /// [World.plan]. Проверяется только фаза: суммы плана — в самом `plan`.
  plan,

  /// [World.chooseGoal], `id` — цель.
  chooseGoal,

  /// [World.chooseFood], `id` — домашнее меню.
  chooseFood,

  /// [World.eat], `id` — блюдо.
  eat,

  /// [World.completeJob], `id` — работа, `variant` — уровень.
  job,

  /// [World.buy], `id` — товар.
  buy,

  /// [World.leisure], `id` — вид досуга.
  leisure,

  /// [World.sleep].
  sleep,

  /// [World.payBills].
  payBills,

  /// [World.resolveEvent], `id` — вариант выбора (без него — есть ли что
  /// решать вообще).
  resolveEvent,

  /// [World.parentExtraShift] — бонус взрослого на S14.
  parentBonus,
}

/// Раздел каталога (карточка A11).
enum WorldCatalogCategory {
  /// Питомец — цель, покупается из ЦЕЛИ целиком.
  pet,

  /// Транспорт — цель.
  transport,

  /// Жильё — цель. Стартовой комнаты в каталоге нет: она не продаётся.
  home,

  /// Техника — цель: ноутбук открывает программиста (`tech.options`).
  tech,

  /// Одежда — из ХОЧУ, радость угасает за три недели.
  clothes,

  /// Декор комнаты — из ХОЧУ, радость один раз.
  decor,

  /// Перекус — из ХОЧУ, ⚡ сразу, не больше [WorldCatalogItem.weeklyLimit]
  /// в неделю.
  snack,

  /// Блюдо: приём пищи ([World.eat]), обязательная трата из НУЖНО.
  food,

  /// Досуг ([World.leisure]).
  leisure,
}

/// Позиция каталога: всё, что экран показывает **до** действия (карточка
/// A11). Цены и эффекты — только отсюда, в коде экранов чисел нет.
///
/// Каталог живой: ⚡ досуга зависит от 😊, поэтому [World.catalog] читается
/// заново после каждого действия, а не кешируется экраном.
class WorldCatalogItem {
  const WorldCatalogItem({
    required this.id,
    required this.title,
    required this.category,
    required this.price,
    this.weeklyCost = 0,
    this.happiness = 0,
    this.happinessByWeek = const <int>[],
    this.energy = 0,
    this.requires,
    this.requiresText,
    this.perk,
    this.weeklyLimit,
  });

  /// id для [World.buy], [World.chooseGoal], [World.chooseFood],
  /// [World.eat], [World.leisure].
  final String id;

  /// Название по-русски.
  final String title;

  final WorldCatalogCategory category;

  /// Цена в монетах. У еды — за один приём.
  final int price;

  /// Сколько прибавится к недельному счёту, пока вещь есть: корм питомца
  /// (со следующей недели после покупки), плата за жильё. У еды — счёт
  /// недели, если всю неделю есть только это блюдо (цена × приёмы).
  final int weeklyCost;

  /// 😊: питомец, еда, жильё — в неделю; одежда — при покупке (дальше по
  /// [happinessByWeek]); декор — один раз; досуг — за раз (до недельного
  /// колпака).
  final int happiness;

  /// Одежда: 😊 по неделям владения, [0] — при покупке. У остальных пусто.
  final List<int> happinessByWeek;

  /// ⚡ со знаком: перекус и еда — сразу, за раз (+);
  /// жильё — к запасу каждой недели (+); досуг — **цена сейчас** (−), уже с
  /// поправкой на 😊 и +1 «на жизнь».
  final double energy;

  /// Что нужно, чтобы открылось: `any_pet`, `transport` или id вещи. null —
  /// открыто всегда.
  final String? requires;

  /// То же по-русски: «Нужен питомец».
  final String? requiresText;

  /// Что ещё даёт (перк питомца, транспорт), одной фразой.
  final String? perk;

  /// Сколько раз в неделю можно (перекус, еда), или null — без лимита.
  final int? weeklyLimit;

  /// Покупается из ЦЕЛИ целиком (питомцы, транспорт, жильё, техника).
  bool get isGoal =>
      category == WorldCatalogCategory.pet ||
      category == WorldCatalogCategory.transport ||
      category == WorldCatalogCategory.home ||
      category == WorldCatalogCategory.tech;
}

/// Чему Финни научился (критерии ночи §8): сколько решений принято по темам
/// ТЗ и какие слова Словарика встретились в уроках. Только из журнала,
/// без оценок: число — это сколько раз тема была в игре, а не балл.
class LearningSummary {
  const LearningSummary({
    this.topics = const <String, int>{},
    this.words = const <({String id, String term})>[],
  });

  /// Тема ТЗ (`budget`, `savings`, `payments`) → решений по ней: уроки после
  /// смен и выборы в событиях (событие «планирование» — это бюджет).
  final Map<String, int> topics;

  /// Слова из уроков — в порядке первой встречи, без повторов.
  final List<({String id, String term})> words;

  /// Темы ТЗ по порядку и их названия для ребёнка.
  static const List<(String, String)> topicNames = <(String, String)>[
    ('budget', 'Бюджет'),
    ('savings', 'Сбережения'),
    ('payments', 'Платежи и покупки'),
  ];

  /// Тема события → тема ТЗ.
  static String topicOfEvent(String eventTopic) =>
      eventTopic == 'planning' ? 'budget' : eventTopic;
}

/// Урок после смены, который ждёт выбора ([World.pendingLesson]).
class LessonOffer {
  const LessonOffer({
    required this.jobId,
    required this.topic,
    required this.title,
    required this.situation,
    required this.wordTerm,
    required this.choices,
  });

  final String jobId;
  final String topic;
  final String title;
  final String situation;

  /// Новое слово Словарика, которое даёт урок.
  final String wordTerm;
  final List<LessonChoiceView> choices;
}

/// Вариант урока: подпись, что изменится (до выбора) и почему нельзя.
class LessonChoiceView {
  const LessonChoiceView({
    required this.id,
    required this.label,
    required this.preview,
    this.blockReason,
  });

  final String id;
  final String label;
  final EffectPreview preview;
  final BlockReason? blockReason;

  bool get available => blockReason == null;
}

/// Что изменится, если выбрать вариант события — показывается **до** выбора
/// (карточка A10). Все поля — изменения, как у [WorldResult].
class EffectPreview {
  const EffectPreview({
    this.coins = 0,
    this.goal = 0,
    this.energy = 0,
    this.happiness = 0,
    this.weeklyBill = 0,
  });

  /// Изменение доступных монет (💰).
  final int coins;

  /// Изменение накоплений (ЦЕЛЬ).
  final int goal;

  /// Изменение ⚡ сейчас.
  final double energy;

  /// Изменение 😊 — примерно: до границ 0–100 и недельного колпака досуга.
  final int happiness;

  /// Добавка к обязательному счёту этой недели (сломался рюкзак).
  final int weeklyBill;

  /// Ничего не меняется в числах.
  bool get isEmpty =>
      coins == 0 &&
      goal == 0 &&
      energy.abs() < 1e-9 &&
      happiness == 0 &&
      weeklyBill == 0;

  /// Коротко для кнопки: «−200 из копилки · −2 ⚡ · +9 😊».
  String get text {
    if (isEmpty) return 'Без трат';
    String signed(int v) => v > 0 ? '+$v' : '−${-v}';
    String en(double v) {
      final double a = v.abs();
      final String n = a == a.roundToDouble()
          ? a.round().toString()
          : a.toStringAsFixed(1).replaceAll('.', ',');
      return '${v > 0 ? '+' : '−'}$n';
    }

    return <String>[
      if (coins != 0) '${signed(coins)} 💰',
      if (goal > 0) '+$goal в копилку',
      if (goal < 0) '−${-goal} из копилки',
      if (weeklyBill != 0) '${signed(weeklyBill)} к счёту недели',
      if (energy.abs() >= 1e-9) '${en(energy)} ⚡',
      if (happiness != 0) '${signed(happiness)} 😊',
    ].join(' · ');
  }

  @override
  String toString() => 'EffectPreview($text)';
}

/// Вариант выбора в событии.
class PendingEventChoice {
  const PendingEventChoice({
    required this.id,
    required this.label,
    required this.preview,
    this.blockReason,
  });

  /// `options[].id` из `events.json` — аргумент [World.resolveEvent].
  final String id;

  final String label;

  /// Что изменится — до выбора.
  final EffectPreview preview;

  /// Почему вариант сейчас недоступен (не хватает денег или ⚡), или null.
  /// Недоступный вариант показывается, но гаснет (`_rules.affordability`,
  /// ТЗ 2.5.6.4). Бесплатный вариант в событии есть всегда.
  final BlockReason? blockReason;

  bool get available => blockReason == null;
}

/// Событие недели, которое ждёт ребёнка (карточка A10, S10).
class PendingEvent {
  const PendingEvent({
    required this.id,
    required this.topic,
    required this.title,
    required this.text,
    required this.buildingId,
    required this.choices,
  });

  /// `events[].id` из `events.json`.
  final String id;

  /// `planning` или `savings` — для раздела взрослого, ребёнку не
  /// показывается.
  final String topic;

  final String title;

  /// Ситуация (`situation`).
  final String text;

  /// Здание города с «!» (`city_screen.dart → cityBuildings`: `home`,
  /// `grocery`, `job-centre`, `pet-shop`, `park`, `cinema`, `piggy-bank`).
  /// Из `events.json → events[].building` (добавлено 27.09, закрывает Р4).
  final String buildingId;

  final List<PendingEventChoice> choices;
}

/// Облик Финни: мальчик или девочка (open-questions К11).
enum FinniGender { boy, girl }

/// Как мир сохраняет прогресс онбординга. Домен не знает про файлы: адаптер
/// над `Storage` — `lib/data/onboarding_store.dart`.
typedef OnboardingSave = Future<void> Function(Map<String, Object?> json);

/// Прогресс онбординга S0 (карточка A14): что ребёнок уже выбрал и с какого
/// шага продолжить после перезапуска.
///
/// Шаги — как на экране потока B, с нуля: 0 комната · 1 три решения · 2 ник ·
/// 3 облик и имя · 4 карманные и конверты · 5 первая цель · 6 готово.
///
/// 🔴 Шаги 4–5 решает **фаза мира**, а не сохранённый [step]: карманные
/// недели 1 начисляются один раз `startWeek`, и продолжать надо оттуда, где
/// мир, — см. [resumeStep].
class OnboardingProgress {
  const OnboardingProgress({
    this.step = stepIntro,
    this.nickname = '',
    this.finniSpecies,
    this.finniGender,
    this.finniLook,
    this.finniName = defaultFinniName,
  });

  static const int stepIntro = 0;
  static const int stepDecisions = 1;
  static const int stepNickname = 2;
  static const int stepFinni = 3;
  static const int stepMoney = 4;
  static const int stepGoal = 5;
  static const int stepDone = 6;

  /// Ник и имя Финни — от 1 до 16 символов (ТЗ 2.5.1.2).
  static const int maxNameLength = 16;
  static const String defaultFinniName = 'Финни';

  /// С какого шага продолжить (сохранённый).
  final int step;

  /// Ник ребёнка; пусто — ещё не выбран.
  final String nickname;

  /// Вид Финни — id из `assets/registry.json → finni` (`finni-a1`…).
  final String? finniSpecies;

  final FinniGender? finniGender;

  /// Вариант облика 1..N — тег `idle-N` в листе вида.
  final int? finniLook;

  final String finniName;

  bool get done => step >= stepDone;

  /// Шаг, с которого продолжить, с учётом фазы мира:
  /// - неделя ещё не начата — не дальше шага облика (переход с него и
  ///   начинает неделю 1);
  /// - неделя 1 ждёт плана — шаг карманных;
  /// - план есть, цели нет — шаг цели; цель есть — готово;
  /// - неделя 2 и дальше — готово всегда: онбординг бывает только в неделе 1.
  ///
  /// [goalChosen] — цель выбрана **или уже куплена** (`buy` снимает
  /// `activeGoalId`); проще звать [resumeFrom].
  int resumeStep(
      {required WeekPhase phase, required bool goalChosen, int weekNo = 1}) {
    if (done || weekNo > 1) return stepDone;
    return switch (phase) {
      WeekPhase.onboarding => step < stepFinni ? step : stepFinni,
      WeekPhase.weekStart || WeekPhase.planning => stepMoney,
      WeekPhase.living || WeekPhase.review => goalChosen ? stepDone : stepGoal,
    };
  }

  /// [resumeStep] по снимку мира: цель выбрана, если есть активная цель или
  /// Финни уже чем-то владеет (на шаге 6 ребёнок в магазин не попадает, так
  /// что вещь в неделе 1 — это купленная цель).
  int resumeFrom(
          {required WeekPhase phase, required ResourceSnapshot snapshot}) =>
      resumeStep(
        phase: phase,
        weekNo: snapshot.weekNo,
        goalChosen: snapshot.activeGoalId != null || snapshot.owned.isNotEmpty,
      );

  OnboardingProgress copyWith({
    int? step,
    String? nickname,
    String? finniSpecies,
    FinniGender? finniGender,
    int? finniLook,
    String? finniName,
  }) =>
      OnboardingProgress(
        step: step ?? this.step,
        nickname: nickname ?? this.nickname,
        finniSpecies: finniSpecies ?? this.finniSpecies,
        finniGender: finniGender ?? this.finniGender,
        finniLook: finniLook ?? this.finniLook,
        finniName: finniName ?? this.finniName,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'step': step,
        'nickname': nickname,
        if (finniSpecies != null) 'finniSpecies': finniSpecies,
        if (finniGender != null) 'finniGender': finniGender!.name,
        if (finniLook != null) 'finniLook': finniLook,
        'finniName': finniName,
      };

  /// Из сохранённого. null или битые поля — значения по умолчанию, а не
  /// падение: лучше пройти шаг заново, чем не запуститься.
  factory OnboardingProgress.fromJson(Map<String, Object?>? json) {
    if (json == null) return const OnboardingProgress();
    final Object? step = json['step'];
    final Object? nick = json['nickname'];
    final Object? species = json['finniSpecies'];
    final Object? gender = json['finniGender'];
    final Object? look = json['finniLook'];
    final Object? name = json['finniName'];
    FinniGender? g;
    for (final FinniGender v in FinniGender.values) {
      if (v.name == gender) g = v;
    }
    return OnboardingProgress(
      step: step is int ? step.clamp(stepIntro, stepDone) : stepIntro,
      nickname: nick is String ? nick : '',
      finniSpecies: species is String ? species : null,
      finniGender: g,
      finniLook: look is int ? look : null,
      finniName: name is String && name.isNotEmpty ? name : defaultFinniName,
    );
  }

  @override
  String toString() => 'OnboardingProgress(${toJson()})';
}

// ═══════════ C3 (28.09): план против факта и история недель ═══════════
//
// Добавление: ТЗ 2.5.5.3 (план против факта в итогах S11) и 2.5.11.1
// (история S12). Модель чтения — выводится из журнала, нигде не хранится.

/// Один конверт недели: сколько ребёнок **запланировал** и сколько вышло
/// **на деле**.
class EnvelopePlanFact {
  const EnvelopePlanFact({required this.planned, required this.actual});

  /// Положено в конверт при подтверждении плана.
  final int planned;

  /// На деле: НУЖНО — счета недели (вся сумма, кто бы ни доплатил);
  /// ХОЧУ — потрачено на покупки, досуг и траты событий (из ХОЧУ или из
  /// заработка); ЦЕЛЬ — чистое отложенное: взносы минус снятое из копилки,
  /// то же число, что проверяет очко «откладывал» (`depositsThisWeek`).
  final int actual;

  /// Больше плана (+) или меньше (−).
  int get diff => actual - planned;
}

/// Строка истории недели: смена (оплата), покупка или досуг (цена).
class WeekItem {
  const WeekItem({required this.id, required this.title, required this.amount});

  /// id работы, товара или досуга.
  final String id;
  final String title;

  /// Монеты: оплата смены с бонусом или цена покупки.
  final int amount;
}

/// Неделя глазами итогов и истории: план против факта по конвертам, смены,
/// покупки, события, цель. Выводится из журнала (у фейка — из его учёта).
class WeekPlanFact {
  const WeekPlanFact({
    required this.weekNo,
    required this.planMade,
    required this.billsPaid,
    required this.need,
    required this.want,
    required this.goal,
    this.shifts = const <WeekItem>[],
    this.purchases = const <WeekItem>[],
    this.events = const <String>[],
    this.goalsReached = const <String>[],
    this.goalTitle,
    this.goalPrice,
    this.savedAtEnd = 0,
    this.parentBonus = false,
    this.food = 0,
    this.treats = 0,
  });

  final int weekNo;

  /// План недели подтверждён. Нет — плановые числа нули, а не «положил 0».
  final bool planMade;

  /// Счета недели оплачены (итоги подведены). Нет — [need].actual ещё 0,
  /// а не «счета ничего не стоили»; неделя идёт.
  final bool billsPaid;

  final EnvelopePlanFact need;
  final EnvelopePlanFact want;
  final EnvelopePlanFact goal;

  /// Смены по порядку: название и сколько заплатили.
  final List<WeekItem> shifts;

  /// Покупки и платный досуг по порядку, включая купленные цели.
  final List<WeekItem> purchases;

  /// Названия событий, в которых ребёнок сделал выбор.
  final List<String> events;

  /// Цели, купленные на этой неделе.
  final List<String> goalsReached;

  /// Активная цель на конец недели (или сейчас), null — не выбрана.
  final String? goalTitle;
  final int? goalPrice;

  /// В копилке на конец недели (или сейчас).
  final int savedAtEnd;

  /// Взрослый открыл на этой неделе дополнительную смену (ТЗ 2.5.12.3).
  final bool parentBonus;

  /// Еда недели: и выбранная посреди недели, и домашняя в счёте (входит в
  /// [need].actual).
  final int food;

  /// Из [food] — «вкусное без пользы» (пицца, бургер: `treat` в JSON).
  final int treats;
}

/// Бонус взрослого (ТЗ 2.5.12.3, К4 решён 28.09): ключ записи
/// `parentBonus` и итога [World.parentExtraShift].
const String parentBonusCode = 'parent.extra_shift';

/// Причина в записи журнала `parentBonus` — одна у обоих миров.
const String parentBonusReason =
    'Взрослый открыл дополнительную смену на эту неделю';

/// Отказ: дополнительная смена на этой неделе уже открыта.
const BlockReason parentBonusDone = BlockReason('parent.bonus.done',
    'Дополнительная смена на этой неделе уже открыта. Следующая — через неделю.');

/// Мир Финни — всё, что экраны читают и делают.
///
/// Действия не бросают исключений на игровые ситуации: нехватка денег,
/// ⚡, не та фаза недели — это [WorldResult.refused] с причиной.
abstract class World {
  /// Текущие ресурсы.
  ResourceSnapshot get snapshot;

  /// Этап недели.
  WeekPhase get phase;

  /// Доска «Требуется…»: все работы и уровни, включая закрытые.
  List<JobOffer> get jobBoard;

  /// ⚡ самого дешёвого действия, доступного сейчас (смена или досуг).
  /// Когда ⚡ меньше, делать в неделе больше нечего — остаётся «Спать»;
  /// комната по нему выбирает главную (золотую) кнопку.
  double get cheapestActionEnergy;

  /// Из чего сложен [ResourceSnapshot.weeklyBill] этой недели: еда Финни,
  /// корм питомцев (купленных раньше этой недели), жильё и добавка события.
  /// Сумма частей равна `weeklyBill`. Экраны называют корм отдельной
  /// строкой до счетов (фидбек дизайнера 28.09, п. 9).
  WeekBillParts get weeklyBillParts;

  /// Карточка одной работы или null, если такой нет.
  JobOffer? offer(String jobId, {String? variant});

  /// Новая неделя: карманные в неразложенное, запас ⚡. Из [WeekPhase.onboarding]
  /// — первая неделя и стартовый подарок в ЦЕЛЬ; из [WeekPhase.review] —
  /// только после [payBills].
  WorldResult startWeek();

  /// План недели: раскладка неразложенных карманных. Сумма не больше
  /// доступного; остаток уходит в кошелёк заработка. Переводит в [WeekPhase.living].
  WorldResult plan({required int needs, required int wants, required int goal});

  /// Выбрать активную цель накопления (шаг 6 онбординга, копилка S9).
  WorldResult chooseGoal(String goalId);

  /// Выбрать домашнее меню (`food.options[].id`): что Финни ест в итогах
  /// недели за невыбранные приёмы. Меняет счёт недели.
  WorldResult chooseFood(String foodId);

  /// Урок после последней смены (критерии ночи §4), или null — урока нет
  /// или он уже решён. Держится до следующей смены или новой недели.
  LessonOffer? get pendingLesson;

  /// Чему Финни научился: темы ТЗ и слова (критерии ночи §8).
  LearningSummary get learning;

  /// Выбрать вариант урока: запись журнала `lessonChoice` с причиной. Итог
  /// начинается с «Что мы поняли». Не игровой день.
  WorldResult resolveLesson(String choiceId);

  /// Поесть сейчас (Денис 29.09, 938): блюдо из НУЖНО → заработок → ХОЧУ,
  /// ⚡ и 😊 сразу, не больше [ResourceSnapshot.mealsPerWeek] раз в неделю.
  /// Не игровой день. Не хватает — отказ с тем, что можно подешевле.
  WorldResult eat(String foodId);

  /// Смена сделана. Оплата — как на карточке [offer]; ошибки ставку не
  /// снижают. Хорошая смена ([JobOffer.isGoodScore]) — плюс бонус
  /// [JobOffer.bonusFor], +1 опыт, сверх цены [JobOffer.goodEnergyExtra] ⚡ и
  /// [JobOffer.goodHappiness] 😊. ⚡ списывается только здесь: вышел из
  /// игры — ничего не потрачено.
  WorldResult completeJob(String jobId,
      {String? variant, required double score});

  /// Ползунок «на цель» после смены: из кошелька заработка в ЦЕЛЬ.
  WorldResult depositToGoal(int amount);

  /// Купить: цель — из ЦЕЛИ целиком; вещь, декор, перекус — из ХОЧУ, затем
  /// из заработка. Не хватает — отказ «Не хватает N», ничего не списано.
  WorldResult buy(String itemId);

  /// Досуг: `park`, `cafe`, `cinema`, `pet_play`.
  WorldResult leisure(String kind);

  /// Тап по питомцу: реакция всегда, 😊 — за первый тап в игровой день (T7).
  WorldResult petTap(String petId);

  /// «Спать»: неделя кончается сейчас. Бонус сна — если ⚡ осталось.
  WorldResult sleep();

  /// Счета конца недели и правило нехватки: корм первым → простая еда →
  /// (если [takeFromGoal]) из накоплений → «семья помогает». Баланс никогда
  /// не уходит в минус. Затем итоги недели и очки роста.
  WorldResult payBills({bool takeFromGoal = false});

  /// Снять из копилки в кошелёк заработка. Экран сначала показывает превью
  /// «было / станет» и спрашивает подтверждение (ТЗ 2.5.7.5).
  WorldResult withdrawFromGoal(int amount);

  // ───────────── C2 (27.09): A10–A14, добавлено для потока B ─────────────

  /// A10. Событие недели, которое ждёт выбора, или null. Появляется, когда
  /// неделя идёт ([WeekPhase.living]), и уходит после [resolveEvent].
  PendingEvent? get pendingEvent;

  /// A10. Здание города, над которым «!» — [PendingEvent.buildingId] или null.
  String? get eventBuildingId;

  /// A10. Выбрать вариант события. Отказ — если события нет или вариант
  /// недоступен ([PendingEventChoice.blockReason]); ничего не изменилось.
  /// После любого выбора [WorldResult.reason] — объяснение Финни
  /// (ТЗ 2.5.8.3), [WorldResult.nextStep] — что дальше.
  WorldResult resolveEvent(String choiceId);

  /// A11. Каталог: цели, товары, декор, еда, досуг — с названием, ценой,
  /// недельным счётом, эффектом и условием открытия.
  List<WorldCatalogItem> get catalog;

  /// A11. Позиция каталога по id или null.
  WorldCatalogItem? catalogItem(String id);

  /// A13. Почему действие сейчас не выйдет, или null — выйдет. Те же
  /// правила, в том же порядке и с теми же кодами, что у самого действия.
  /// Проверки, которым нужна сумма (`plan`, `depositToGoal`,
  /// `withdrawFromGoal`), остаются в действии.
  BlockReason? canDo(WorldAction action, {String? id, String? variant});

  /// A14. Что уже выбрано в онбординге и с какого шага продолжить.
  OnboardingProgress get onboarding;

  /// A14. Шаг «ник»: 1–16 символов после обрезки пробелов. Сохраняется
  /// сразу; продолжение — с шага облика.
  Future<WorldResult> setNickname(String nickname);

  /// A14. Шаг «облик»: вид, мальчик/девочка, вариант. null — не менять.
  /// Сохраняется сразу; шаг не сдвигается (имя — на том же экране).
  Future<WorldResult> setFinniLook(
      {String? species, FinniGender? gender, int? look});

  /// A14. Имя Финни: пусто — «Финни», не длиннее 16. Сохраняется сразу;
  /// продолжение — с шага карманных.
  Future<WorldResult> setFinniName(String name);

  /// A14. Записать шаг как есть (0..6): шаги без выбора, «назад», «готово».
  Future<WorldResult> setOnboardingStep(int step);

  // ───────────── C3 (28.09): план против факта, история ─────────────

  /// Все начатые недели по порядку, с первой; последняя — текущая (может
  /// ещё идти). Выводится из журнала: итоги S11 (ТЗ 2.5.5.3) и история S12
  /// (ТЗ 2.5.11.1). До первой недели — пусто.
  List<WeekPlanFact> get weekHistory;

  // ───────────── C4 (28.09): демо для эксперта (ТЗ 2.5.8.5) ─────────────

  /// Все закрытые работы уже открыты демо-действием [demoUnlockAllJobs].
  bool get allJobsUnlocked;

  /// Демо «Открыть все профессии»: снимает замки работ (курьер без
  /// транспорта, выгульщик без собаки) одной записью `demo.unlockAllJobs`.
  /// Монеты, ⚡, 😊, цель и владение не меняются: скидки транспорта и перков
  /// питомцев нет. Работает в любой фазе; повтор — отказ `demo.jobs.done`,
  /// журнал не пополняется. Сброс игры снимает эффект вместе с журналом.
  WorldResult demoUnlockAllJobs();

  /// Все события мира по порядку конфига (`events.json → events[]`) — список
  /// демо «Показать событие»: id и заголовок.
  List<({String id, String title})> get demoEvents;

  /// Демо «Показать событие» (ТЗ 2.5.8.5): событие [eventId] становится
  /// событием этой недели одной записью `demo.showEvent` — ждёт выбора в S10
  /// так же, как событие по расписанию, и выбор идёт обычным путём
  /// ([resolveEvent]: деньги, ⚡, 😊, записи с причинами). Условия показа
  /// (неделя, питомец, повтор) не проверяются: уже отвеченное событие можно
  /// показать снова. Ждавшее выбора событие заменяется. Сама запись не
  /// меняет ни монет, ни ⚡, ни 😊 и не сдвигает расписание.
  ///
  /// Только пока неделя идёт — иначе тот же отказ `phase.event`, что у
  /// выбора в событии. Неизвестный id — `demo.event.unknown`; событие уже
  /// ждёт выбора — `demo.event.pending`. Отказ журнал не пополняет. Сброс
  /// игры стирает запись вместе с журналом.
  WorldResult demoShowEvent(String eventId);

  // ──────── C5 (28.09): бонус взрослого (ТЗ 2.5.12.3, К4 решён) ────────

  /// Сколько смен можно на этой неделе всего: `maxShiftsPerWeek` + 1, если
  /// взрослый открыл дополнительную смену ([parentExtraShift]).
  int get shiftsLimitThisWeek;

  /// Взрослый уже открыл дополнительную смену на этой неделе.
  bool get parentBonusThisWeek;

  /// Бонус взрослого (S14): «взрослый открывает дополнительное задание» —
  /// одна смена сверх лимита на **эту** неделю. Запись `parentBonus` с
  /// причиной; +1 к общему лимиту смен недели и +1 к лимиту каждой работы,
  /// поэтому дополнительная смена годится на любую работу. Монеты, ⚡ и 😊
  /// не меняются (ТЗ §2.1: ресурсы ограничены). Со следующей недели лимит
  /// прежний.
  ///
  /// Только пока неделя идёт — иначе отказ `phase.parentBonus`; второй раз за
  /// неделю — `parent.bonus.done`. Отказ журнал не пополняет.
  WorldResult parentExtraShift();
}

/// Части счёта недели ([World.weeklyBillParts]).
typedef WeekBillParts = ({int food, int petFood, int rent, int extra});
