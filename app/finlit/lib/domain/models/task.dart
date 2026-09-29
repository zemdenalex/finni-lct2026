import '../phrases.dart';

/// Тема задания (§2.5.8.1 — минимум три темы).
enum TaskTopic {
  budget('Планирую бюджет'),
  savings('Коплю'),
  payments('Покупаю');

  const TaskTopic(this.title);
  final String title;

  static TaskTopic byId(String id) =>
      TaskTopic.values.firstWhere((TaskTopic t) => t.name == id);
}

/// Тип сценария задания — определяет, какой виджет его играет.
///
/// 🔴 Типов намеренно три, а не шесть. ТЗ §2.6 требует шесть **заданий**
/// по трём темам, а не шесть механик. Каждый тип переиспользуется дважды —
/// это и экономит неделю работы, и доказывает утверждение «новое задание =
/// один JSON-файл» лучше, чем six разных виджетов.
enum TaskKind {
  /// Разложить сумму по конвертам или по вариантам.
  allocate,

  /// Расставить покупки по очерёдности и купить в своём порядке.
  orderAndBuy,

  /// Ввести число: сдача, срок, выгода.
  numericInput,
}

/// Задание или мини-сценарий (§2.5.8).
///
/// ТЗ §2.5.8.2 требует «игровую ситуацию с выбором и последствиями», которая
/// «не ограничивается выбором ответа из предложенных вариантов». Поэтому
/// ни один тип не является тестом с вариантами: ребёнок раскладывает,
/// упорядочивает или считает.
class GameTask {
  const GameTask({
    required this.id,
    required this.topic,
    required this.kind,
    required this.title,
    required this.prompt,
    required this.reward,
    required this.params,
    required this.explainAny,
    required this.explainBest,
    this.moneyParams = const <String>[],
    this.plainParams = const <String>[],
    this.repeatable = true,
    this.variants = const <GameTask>[],
  });

  final String id;
  final TaskTopic topic;
  final TaskKind kind;
  final String title;

  /// Условие задания, короткой фразой.
  final String prompt;

  final int reward;

  /// Параметры сценария: суммы уже в той размерности, в которой играет
  /// ребёнок, а строки — уже с подставленными числами.
  final Map<String, Object?> params;

  /// Какие параметры — это монетки (§2.5.8.4, «числа покрупнее»).
  ///
  /// 🔴 Классификация живёт в JSON, а не в коде, потому что автомат её не
  /// выведет: `answer` в «Сдаче» — монетки и умножается на пять, а `answer`
  /// в «Сколько недель копить?» — недели, и умножать его нельзя. Раньше
  /// умножалась только награда, и при масштабе 5 задание «Что сначала?»
  /// давало бюджет 6 при цене каши 10 — непроходимое.
  /// Проверка целостности требует, чтобы каждое число задания попало либо
  /// сюда, либо в [plainParams]: забыть классификацию нельзя.
  final List<String> moneyParams;

  /// Числа, которые монетками не являются: недели, штуки, разы.
  final List<String> plainParams;

  /// Объяснение, которое выдаётся **при любом исходе** (§2.5.8.3).
  final String explainAny;

  /// Дополнение, если ребёнок нашёл лучший вариант. Не «правильно» —
  /// у большинства заданий нет одного правильного ответа.
  final String explainBest;

  /// Задание можно проходить повторно — каждую неделю в своём варианте.
  ///
  /// Иначе к 4–5 неделе активных заданий не остаётся, а §2.5.3.1 требует,
  /// чтобы активное задание было видно на главном экране всегда.
  final bool repeatable;

  /// Другие недели того же задания: тот же навык, другие числа и сюжет.
  ///
  /// 🔴 Без них повтор был дословным: «Сдача» на второй неделе снова
  /// спрашивала «7 и 10», и ребёнок вспоминал ответ, а не считал —
  /// подработка превращалась в нажатие одной и той же кнопки.
  /// Вариант задаётся в JSON и меняет только `params` и тексты; тип,
  /// тему и награду он не трогает, иначе экономика недели зависела бы
  /// от того, какой вариант выпал.
  final List<GameTask> variants;

  /// Все варианты, включая основной, — для проверок целостности.
  List<GameTask> get allVariants => <GameTask>[this, ...variants];

  /// Вариант на неделю [periodNo]: первая — основной, дальше по кругу.
  GameTask forWeek(int periodNo) {
    if (variants.isEmpty) return this;
    final int i = (periodNo - 1) % (variants.length + 1);
    return i <= 0 ? this : variants[i - 1];
  }

  /// Что вариант имеет право переопределить.
  static const Set<String> _variantKeys = <String>{
    'params',
    'prompt',
    'explainAny',
    'explainBest',
  };

  static Map<String, Object?> _mergeVariant(
      Map<String, Object?> base, Map<String, Object?> v) {
    final Set<String> extra = v.keys.toSet().difference(_variantKeys);
    if (extra.isNotEmpty) {
      throw FormatException(
          'Задание ${base['id']}: вариант меняет ${extra.join(', ')} — '
          'можно только ${_variantKeys.join(', ')}');
    }
    return <String, Object?>{
      ...base,
      ...v,
      'params': <String, Object?>{
        ...(base['params']! as Map<Object?, Object?>).cast<String, Object?>(),
        ...((v['params'] as Map<Object?, Object?>?) ??
                const <Object?, Object?>{})
            .cast<String, Object?>(),
      },
    }..remove('variants');
  }

  /// Разбор задания с учётом масштаба «чисел покрупнее».
  ///
  /// Порядок важен: сначала умножаются денежные параметры, и только потом
  /// их значения подставляются в тексты. Иначе условие задания называет
  /// одно число, а экран считает по другому — ровно то, из-за чего задание
  /// «Сколько недель копить?» утверждало «Зоопарк стоит 20», когда цель
  /// стоила 100.
  static GameTask fromJson(Map<String, Object?> json, {int scale = 1}) {
    final List<String> money =
        ((json['money'] as List<Object?>?) ?? const <Object?>[]).cast<String>();
    final List<String> plain =
        ((json['plain'] as List<Object?>?) ?? const <Object?>[]).cast<String>();
    final int reward = (json['reward']! as int) * scale;

    final Map<String, Object?> params =
        (json['params']! as Map<Object?, Object?>).cast<String, Object?>().map(
              (String k, Object? v) => MapEntry<String, Object?>(
                  k, money.contains(k) ? _scaled(v, scale) : v),
            );

    // Подставлять можно только числа: списки идентификаторов и уже готовые
    // строки в тексте условия не нужны.
    final Map<String, Object?> numbers = <String, Object?>{
      'reward': reward,
      for (final MapEntry<String, Object?> e in params.entries)
        if (e.value is int) e.key: e.value,
    };
    String fill(String s) => Phrases.fill(s, numbers);

    return GameTask(
      id: json['id']! as String,
      topic: TaskTopic.byId(json['topic']! as String),
      kind: TaskKind.values.byName(json['kind']! as String),
      title: json['title']! as String,
      prompt: fill(json['prompt']! as String),
      reward: reward,
      params: params.map((String k, Object? v) =>
          MapEntry<String, Object?>(k, v is String ? fill(v) : v)),
      explainAny: fill(json['explainAny']! as String),
      explainBest: fill(json['explainBest']! as String),
      moneyParams: money,
      plainParams: plain,
      repeatable: (json['repeatable'] ?? true) as bool,
      variants: <GameTask>[
        for (final Object? v
            in (json['variants'] as List<Object?>?) ?? const <Object?>[])
          fromJson(
              _mergeVariant(
                  json, (v! as Map<Object?, Object?>).cast<String, Object?>()),
              scale: scale),
      ],
    );
  }

  /// Умножение денежного параметра: число или карта «конверт → монетки».
  static Object? _scaled(Object? value, int scale) {
    if (value is int) return value * scale;
    if (value is Map<Object?, Object?>) {
      return value.map((Object? k, Object? v) =>
          MapEntry<Object?, Object?>(k, (v! as int) * scale));
    }
    return value;
  }
}
