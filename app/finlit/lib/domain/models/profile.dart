import 'envelope.dart';

/// Вид питомца. Три вида × три расцветки = девять визуально различимых
/// комбинаций (§2.6), и ещё больше — с купленными аксессуарами.
enum PetSpecies {
  // 🔴 Не кот. У заказчика — Департамента финансов Москвы — уже есть свой
  // кот-проводник по финансам, Бублик из цикла «Деньги 24» на «Москва 24».
  // Питомец-кот читался бы либо как заимствование, либо как путаница с их
  // персонажем. Белка же — готовая метафора самой игры: она откладывает
  // запасы на зиму, и это знает любой ребёнок из сказок.
  squirrel('Бельчонок'),
  fox('Лисёнок'),
  owl('Совёнок');

  const PetSpecies(this.title);
  final String title;
}

enum PetPalette {
  mint('Мятный'),
  apricot('Абрикосовый'),
  lilac('Сиреневый');

  const PetPalette(this.title);
  final String title;
}

/// Локальный игровой профиль (Термины ТЗ) — набор данных одного игрока,
/// хранящийся **только на устройстве**.
///
/// 🔴 Здесь намеренно нет ни настоящего имени, ни возраста, ни телефона,
/// ни e-mail, ни идентификатора устройства. §3.5.1 требует, чтобы
/// обязательный сценарий работал без сбора персональных данных, а шаг 2
/// Приложения А проверяется именно на этом. Игровое имя питомца
/// персональными данными не является.
class GameProfile {
  const GameProfile({
    required this.petName,
    required this.species,
    required this.palette,
    required this.accessories,
    required this.goalId,
    required this.plans,
    required this.carePoints,
    required this.completedTaskIds,
    required this.unlockedTerms,
    required this.isDemo,
    required this.settings,
    required this.unexpectedResolvedPeriods,
    required this.parentUnlockedTasks,
    required this.wishList,
    required this.wishKept,
    required this.wishDropped,
  });

  factory GameProfile.fresh({required bool isDemo}) => GameProfile(
        petName: 'Финни',
        species: PetSpecies.squirrel,
        // Рыжая, а не мятная: мятная белка на превью читалась белкой
        // через раз, рыжую узнают сразу.
        palette: PetPalette.apricot,
        accessories: const <String>{},
        goalId: null,
        plans: const <int, Allocation>{},
        carePoints: 0,
        completedTaskIds: const <String>[],
        unlockedTerms: const <String>{'envelope', 'needs', 'wants', 'savings'},
        isDemo: isDemo,
        settings: const GameSettings(),
        unexpectedResolvedPeriods: const <int>{},
        parentUnlockedTasks: 0,
        wishList: const <String, int>{},
        wishKept: 0,
        wishDropped: 0,
      );

  final String petName;
  final PetSpecies species;
  final PetPalette palette;
  final Set<String> accessories;
  final String? goalId;

  /// План по номеру игровой недели. Нужен для сравнения плана с фактом
  /// (§2.5.5.3) и для подсчёта очка «План сошёлся».
  final Map<int, Allocation> plans;

  final int carePoints;

  /// Идентификаторы выполненных заданий. Задание можно пройти повторно —
  /// список нужен для экрана прогресса (§2.5.11.1), а не для блокировки.
  final List<String> completedTaskIds;

  final Set<String> unlockedTerms;
  final bool isDemo;
  final GameSettings settings;

  /// Недели, в которых непредвиденный расход уже решён (оплачен или перенесён).
  final Set<int> unexpectedResolvedPeriods;

  /// Сколько дополнительных заданий открыл взрослый (§2.5.12).
  /// 🔴 Именно заданий, а не монеток: иначе дыра в бюджете закрывается
  /// просьбой к родителю, а §2.1 требует ограниченности ресурсов.
  final int parentUnlockedTasks;

  /// Список ожидания: что ребёнок захотел и отложил до следующей недели,
  /// и на какой неделе отложил.
  ///
  /// 🔴 Ожидание здесь — выбор, а не запрет. Купить сейчас можно всегда:
  /// принуждённая пауза превращает педагогический приём в наказание, а
  /// данные (Warneken & Tomasello; Weinstein & Ryan) говорят, что
  /// принуждение к «правильному» поведению даёт обратный эффект.
  final Map<String, int> wishList;

  /// Сколько раз ребёнок, дождавшись, подтвердил желание, и сколько раз
  /// передумал. Это единственный факт, который игра сообщает ребёнку
  /// о нём самом, а не о его питомце.
  final int wishKept;
  final int wishDropped;

  GameProfile copyWith({
    String? petName,
    PetSpecies? species,
    PetPalette? palette,
    Set<String>? accessories,
    Object? goalId = _unset,
    Map<int, Allocation>? plans,
    int? carePoints,
    List<String>? completedTaskIds,
    Set<String>? unlockedTerms,
    bool? isDemo,
    GameSettings? settings,
    Set<int>? unexpectedResolvedPeriods,
    int? parentUnlockedTasks,
    Map<String, int>? wishList,
    int? wishKept,
    int? wishDropped,
  }) =>
      GameProfile(
        petName: petName ?? this.petName,
        species: species ?? this.species,
        palette: palette ?? this.palette,
        accessories: accessories ?? this.accessories,
        goalId: goalId == _unset ? this.goalId : goalId as String?,
        plans: plans ?? this.plans,
        carePoints: carePoints ?? this.carePoints,
        completedTaskIds: completedTaskIds ?? this.completedTaskIds,
        unlockedTerms: unlockedTerms ?? this.unlockedTerms,
        isDemo: isDemo ?? this.isDemo,
        settings: settings ?? this.settings,
        unexpectedResolvedPeriods:
            unexpectedResolvedPeriods ?? this.unexpectedResolvedPeriods,
        parentUnlockedTasks: parentUnlockedTasks ?? this.parentUnlockedTasks,
        wishList: wishList ?? this.wishList,
        wishKept: wishKept ?? this.wishKept,
        wishDropped: wishDropped ?? this.wishDropped,
      );

  static const Object _unset = Object();

  Map<String, Object?> toJson() => <String, Object?>{
        'petName': petName,
        'species': species.name,
        'palette': palette.name,
        'accessories': accessories.toList(),
        'goalId': goalId,
        'plans': plans.map((int k, Allocation v) =>
            MapEntry<String, Object?>(k.toString(), v.toJson())),
        'carePoints': carePoints,
        'completedTaskIds': completedTaskIds,
        'unlockedTerms': unlockedTerms.toList(),
        'isDemo': isDemo,
        'settings': settings.toJson(),
        'unexpectedResolvedPeriods': unexpectedResolvedPeriods.toList(),
        'parentUnlockedTasks': parentUnlockedTasks,
        'wishList': wishList.map((String k, int v) =>
            MapEntry<String, Object?>(k, v)),
        'wishKept': wishKept,
        'wishDropped': wishDropped,
      };

  /// 🔴 Вид питомца читается мягко. До 23.09 первым видом был кот (`cat`),
  /// и сохранённые профили хранят это имя. `byName` на нём бросил бы
  /// исключение, и ребёнок после обновления потерял бы игру целиком.
  /// Неизвестный вид становится белкой — тем, кем стал бывший кот.
  static PetSpecies _speciesFrom(String? name) {
    for (final PetSpecies s in PetSpecies.values) {
      if (s.name == name) return s;
    }
    return PetSpecies.squirrel;
  }

  static GameProfile fromJson(Map<String, Object?> json) => GameProfile(
        petName: json['petName']! as String,
        species: _speciesFrom(json['species'] as String?),
        palette: PetPalette.values.byName(json['palette']! as String),
        accessories: (json['accessories']! as List<Object?>).cast<String>().toSet(),
        goalId: json['goalId'] as String?,
        plans: (json['plans']! as Map<Object?, Object?>).map(
          (Object? k, Object? v) => MapEntry<int, Allocation>(
            int.parse(k! as String),
            Allocation.fromJson((v! as Map<Object?, Object?>).cast<String, Object?>()),
          ),
        ),
        carePoints: json['carePoints']! as int,
        completedTaskIds:
            (json['completedTaskIds']! as List<Object?>).cast<String>(),
        unlockedTerms:
            (json['unlockedTerms']! as List<Object?>).cast<String>().toSet(),
        isDemo: json['isDemo']! as bool,
        settings: GameSettings.fromJson(
            (json['settings']! as Map<Object?, Object?>).cast<String, Object?>()),
        unexpectedResolvedPeriods:
            (json['unexpectedResolvedPeriods']! as List<Object?>)
                .cast<int>()
                .toSet(),
        parentUnlockedTasks: json['parentUnlockedTasks']! as int,
        // Поля списка ожидания появились позже остальных, поэтому читаются
        // мягко: сохранённый профиль предыдущей сборки должен открыться,
        // а не уронить приложение при первом запуске после обновления.
        wishList: (json['wishList'] as Map<Object?, Object?>? ??
                const <Object?, Object?>{})
            .map((Object? k, Object? v) =>
                MapEntry<String, int>(k! as String, v! as int)),
        wishKept: json['wishKept'] as int? ?? 0,
        wishDropped: json['wishDropped'] as int? ?? 0,
      );
}

/// Настройки доступности и подачи (§3.6).
class GameSettings {
  const GameSettings({
    this.soundOn = true,
    this.animationsOn = true,
    this.readAloud = false,
    this.bigNumbers = false,
  });

  /// §3.6.7: «Звуки и анимации можно отключить».
  final bool soundOn;
  final bool animationsOn;

  /// Озвучивать объяснения. ICO для 6–9 лет: «ability or willingness to engage
  /// with written materials cannot be assumed» — семилетка не прочитает
  /// абзац, поэтому ключевые тексты можно прослушать.
  final bool readAloud;

  /// «Числа покрупнее» — режим для 9–11 лет, множитель экономики.
  /// Базовый режим держит суммы в пределах двадцати.
  final bool bigNumbers;

  int get scale => bigNumbers ? 5 : 1;

  GameSettings copyWith({
    bool? soundOn,
    bool? animationsOn,
    bool? readAloud,
    bool? bigNumbers,
  }) =>
      GameSettings(
        soundOn: soundOn ?? this.soundOn,
        animationsOn: animationsOn ?? this.animationsOn,
        readAloud: readAloud ?? this.readAloud,
        bigNumbers: bigNumbers ?? this.bigNumbers,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'soundOn': soundOn,
        'animationsOn': animationsOn,
        'readAloud': readAloud,
        'bigNumbers': bigNumbers,
      };

  static GameSettings fromJson(Map<String, Object?> json) => GameSettings(
        soundOn: json['soundOn']! as bool,
        animationsOn: json['animationsOn']! as bool,
        readAloud: json['readAloud']! as bool,
        bigNumbers: json['bigNumbers']! as bool,
      );
}
