import '../models/pet.dart';

/// Кто сколько даёт на неделе на данной стадии Финни.
class TrustLevel {
  const TrustLevel({required this.fromParents, required this.earnCap});

  /// Бюджет, который доверили родители. Приходит сам в начале недели.
  final int fromParents;

  /// Сколько максимум можно заработать заданиями за неделю.
  final int earnCap;

  /// Больше этого за неделю не получить при любом усердии.
  int get weeklyMax => fromParents + earnCap;
}

/// Числа игровой экономики. Грузятся из assets/content/economy.json.
///
/// 🔴 Ни одно число экономики не живёт в виджетах. §3.2 ТЗ требует отделить
/// учебный контент от интерфейсного кода, а §5 п.6 — описать формулы;
/// и то и другое невозможно, если константы разбросаны по экранам.
class EconomyConfig {
  const EconomyConfig({
    required this.pocketMoney,
    required this.decay,
    required this.moodPerTask,
    required this.moodPerDeposit,
    required this.maxMoodFromTasks,
    required this.planTolerance,
    this.unexpectedEvents = const <UnexpectedEvent>[],
    required this.unexpectedPeriod,
    this.unexpectedEvery = 3,
    required this.startMeters,
    required this.needsThreshold,
    required this.wishThreshold,
    required this.trust,
    required this.parentBonusCap,
    required this.scale,
  });

  /// Карманные в начале недели.
  final int pocketMoney;

  /// Затухание показателей при закрытии недели. Значения отрицательные.
  final PetMeters decay;

  /// Прибавка к настроению за каждое выполненное за неделю задание.
  ///
  /// 🔴 Ключевая правка экономики. Если настроение восстанавливается только
  /// покупками из «Хочу», то чем больше ребёнок откладывает, тем грустнее
  /// питомец — то есть продукт, который учит копить, наказывает за накопление.
  /// Настроение растёт от заданий и от взноса в копилку, поэтому отказ от
  /// необязательной покупки перестаёт быть наказуемым — ровно как требуют
  /// Термины ТЗ: «Отказ от такой покупки … не считается ошибкой пользователя».
  final int moodPerTask;

  /// Прибавка к настроению, если за неделю в копилку ушло больше нуля.
  final int moodPerDeposit;

  final int maxMoodFromTasks;

  /// Допустимое отклонение факта от плана по конверту, в монетках.
  final int planTolerance;

  /// Непредвиденные расходы (§2, специально спланированный кейс) — по кругу.
  ///
  /// 🔴 До 23.09 событие было одно — плед на третьей неделе, — и дальше мир
  /// ничего не приносил: урок «держи немного про запас» звучал один раз
  /// и повторялся тем же пледом в задании. Теперь событие приходит каждые
  /// [unexpectedEvery] недели, каждый раз своё.
  final List<UnexpectedEvent> unexpectedEvents;

  /// На какой неделе наступает первый непредвиденный расход.
  final int unexpectedPeriod;

  /// Через сколько недель приходит следующий.
  final int unexpectedEvery;

  /// Событие недели [periodNo] или `null`, если на этой неделе его нет.
  UnexpectedEvent? unexpectedFor(int periodNo) {
    final int since = periodNo - unexpectedPeriod;
    if (since < 0 || unexpectedEvents.isEmpty) return null;
    if (since % unexpectedEvery != 0) return null;
    return unexpectedEvents[(since ~/ unexpectedEvery) % unexpectedEvents.length];
  }

  /// Показатели питомца в начале игры.
  final PetMeters startMeters;

  /// Порог, с которого «Нужное закрыто»: обе шкалы ухода не ниже этого.
  final int needsThreshold;

  /// С какой цены необязательная вещь предлагает подождать до следующей
  /// недели. 🔴 Порог в монетках, а не во времени: по практике семей
  /// правило «ждать всегда» ломается на мелочах и перестаёт соблюдаться.
  final int wishThreshold;

  /// 🔴 Решение команды 19.09 («вариант 4»): база недели — бюджет, который
  /// доверили родители, а задания — ограниченная подработка. С каждой
  /// стадией Финни доля родителей падает, а доля заработанного растёт.
  /// Взросление видно по росту самостоятельности, а не по возрасту героя.
  ///
  /// Инварианты, которые держит тест: максимум недели не убывает со
  /// стадией (продвинуться никогда не невыгодно), а доля родителей никогда
  /// не опускается ниже того, что нужно на еду и уборку (§3.5: забота
  /// о питомце не должна зависеть от того, выполнил ли ребёнок задания).
  final Map<PetStage, TrustLevel> trust;

  /// На сколько поднимает лимит подработки одно задание, открытое взрослым.
  final int parentBonusCap;

  TrustLevel trustFor(PetStage stage) => trust[stage]!;

  /// Множитель «числа покрупнее» для 9–11 лет. Базовый режим (7–8 лет)
  /// держит все суммы в пределах двадцати: сложение трёх слагаемых в пределах
  /// 20 — это первый класс, а деление 100 на три части — уже третий.
  final int scale;

  static EconomyConfig fromJson(Map<String, Object?> json, {int scale = 1}) {
    final Map<String, Object?> d =
        (json['decay']! as Map<Object?, Object?>).cast<String, Object?>();
    final Map<String, Object?> sm =
        (json['startMeters']! as Map<Object?, Object?>).cast<String, Object?>();
    return EconomyConfig(
      pocketMoney: (json['pocketMoney']! as int) * scale,
      decay: PetMeters(
        fullness: d['fullness']! as int,
        cleanliness: d['cleanliness']! as int,
        mood: d['mood']! as int,
      ),
      moodPerTask: json['moodPerTask']! as int,
      moodPerDeposit: json['moodPerDeposit']! as int,
      maxMoodFromTasks: json['maxMoodFromTasks']! as int,
      planTolerance: (json['planTolerance']! as int) * scale,
      unexpectedEvents: <UnexpectedEvent>[
        for (final Object? e in json['unexpectedEvents']! as List<Object?>)
          UnexpectedEvent.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
              scale: scale),
      ],
      unexpectedPeriod: json['unexpectedPeriod']! as int,
      unexpectedEvery: (json['unexpectedEvery'] ?? 3) as int,
      startMeters: PetMeters(
        fullness: sm['fullness']! as int,
        cleanliness: sm['cleanliness']! as int,
        mood: sm['mood']! as int,
      ),
      needsThreshold: json['needsThreshold']! as int,
      wishThreshold: (json['wishThreshold']! as int) * scale,
      trust: <PetStage, TrustLevel>{
        for (final PetStage st in PetStage.values)
          st: () {
            final Map<String, Object?> t =
                ((json['trust']! as Map<Object?, Object?>)[st.name]!
                        as Map<Object?, Object?>)
                    .cast<String, Object?>();
            return TrustLevel(
              fromParents: (t['fromParents']! as int) * scale,
              earnCap: (t['earnCap']! as int) * scale,
            );
          }(),
      },
      parentBonusCap: (json['parentBonusCap']! as int) * scale,
      scale: scale,
    );
  }
}

/// Одно непредвиденное событие: бытовая поломка или нехватка, без болезней
/// и без спешки — исход всегда поправим (§3.5).
class UnexpectedEvent {
  const UnexpectedEvent({
    required this.id,
    required this.title,
    required this.chip,
    required this.need,
    required this.cost,
    required this.deferLabel,
    required this.paidTitle,
    required this.paid,
    required this.deferred,
  });

  factory UnexpectedEvent.fromJson(Map<String, Object?> j, {int scale = 1}) =>
      UnexpectedEvent(
        id: j['id']! as String,
        title: j['title']! as String,
        chip: j['chip']! as String,
        need: j['need']! as String,
        cost: (j['cost']! as int) * scale,
        deferLabel: j['deferLabel']! as String,
        paidTitle: j['paidTitle']! as String,
        paid: j['paid']! as String,
        deferred: j['deferred']! as String,
      );

  final String id;

  /// Заголовок карточки: «Финни промочил лапы».
  final String title;

  /// Подпись кнопки на главном экране: «У Финни промокли лапы».
  final String chip;

  /// Что нужно купить: «Нужен тёплый плед и чай».
  final String need;
  final int cost;

  /// Четвёртый выход — обойтись и перенести.
  final String deferLabel;
  final String paidTitle;

  /// Что куплено: «Тёплый плед и чай для Финни».
  final String paid;

  /// Как обошлись без покупки.
  final String deferred;
}
