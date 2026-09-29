import 'dart:convert';

import '../../../domain/world/contract.dart' show FinniGender;

/// Сценки знакомства в комнате — `assets/content/world/onboarding.json`
/// (исходник `content/onboarding.json`).
///
/// После ника и облика Финни сам рассказывает о себе, трёх конвертах,
/// копилке, холодильнике и двери — короткими репликами (Денис, 29.09).
/// Тексты — только в файле (ТЗ 3.2.3): код знает порядок сцен и что
/// показать под репликой, но не слова.
///
/// Приложение читает файл до первого кадра (`main.dart`) и отдаёт через
/// `Provider<OnboardingScript>`; экран без провайдера читает бандл сам.
class OnboardingScript {
  const OnboardingScript({
    required this.scenes,
    required this.envelopes,
    required this.skip,
    required this.ui,
    required this.species,
    required this.envelopesShort,
    required this.planStep,
    this.cityHint,
    this.cityEvent = const <String, String>{},
  });

  /// Подписи знакомства, которые должны быть в `ui` (регистрация, кнопки,
  /// план). Нет ключа — ошибка разбора с его именем.
  static const List<String> uiKeys = <String>[
    'step_of',
    'back',
    'nick_title',
    'nick_text',
    'nick_label',
    'nick_hint',
    'nick_help',
    'look_title',
    'look_help',
    'name_label',
    'boy',
    'girl',
    'look_tile',
    'next',
    'go',
    'plan_done',
    'to_room',
    'scenes_title',
    'pool',
    'unallocated',
    'plan_ready',
    'bills',
    'in_piggy',
    'pool_full',
    'piggy_locked',
  ];

  static const String path = 'assets/content/world/onboarding.json';

  /// Разбор файла. Битое поле — [FormatException] с путём до поля: файл
  /// проверяет тест, до сборки, а не ребёнок на экране.
  factory OnboardingScript.parse(String json) {
    final Object? root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('onboarding.json: ждали объект');
    }
    final Object? env = root['envelopes'];
    final Object? scenes = root['scenes'];
    final Object? skip = root['skip'];
    final Object? ui = root['ui'];
    final Object? species = root['species'];
    final Object? short = root['envelopes_short'];
    final Object? step = root['plan_step'];
    final Object? city = root['city'];
    if (env is! Map<String, Object?>) {
      throw const FormatException('onboarding.json → envelopes: ждали объект');
    }
    if (scenes is! List<Object?> || scenes.isEmpty) {
      throw const FormatException('onboarding.json → scenes: ждали список');
    }
    if (skip is! String) {
      throw const FormatException('onboarding.json → skip: ждали строку');
    }
    String text(Object? v, String at) => v is String && v.isNotEmpty
        ? v
        : throw FormatException('onboarding.json → $at: ждали строку');
    if (ui is! Map<String, Object?>) {
      throw const FormatException('onboarding.json → ui: ждали объект');
    }
    if (species is! Map<String, Object?>) {
      throw const FormatException('onboarding.json → species: ждали объект');
    }
    if (short is! Map<String, Object?>) {
      throw const FormatException(
          'onboarding.json → envelopes_short: ждали объект');
    }
    if (step is! int || step <= 0) {
      throw const FormatException(
          'onboarding.json → plan_step: ждали целое больше нуля');
    }
    final List<OnboardingScene> list = <OnboardingScene>[
      for (int i = 0; i < scenes.length; i++)
        OnboardingScene._parse(scenes[i], 'scenes[$i]'),
    ];
    for (final SceneKind k in <SceneKind>[SceneKind.plan, SceneKind.goal]) {
      if (list.where((OnboardingScene s) => s.kind == k).length != 1) {
        throw FormatException(
            'onboarding.json → scenes: сцена kind=${k.name} нужна ровно одна');
      }
    }
    return OnboardingScript(
      scenes: list,
      envelopes: (
        need: text(env['need'], 'envelopes.need'),
        want: text(env['want'], 'envelopes.want'),
        goal: text(env['goal'], 'envelopes.goal'),
      ),
      skip: skip,
      ui: <String, String>{
        for (final String k in uiKeys) k: text(ui[k], 'ui.$k'),
      },
      species: <String, String>{
        for (final MapEntry<String, Object?> e in species.entries)
          e.key: text(e.value, 'species.${e.key}'),
      },
      envelopesShort: (
        need: text(short['need'], 'envelopes_short.need'),
        want: text(short['want'], 'envelopes_short.want'),
        goal: text(short['goal'], 'envelopes_short.goal'),
      ),
      planStep: step,
      cityHint: city is Map<String, Object?> && city['hint'] is String
          ? city['hint']! as String
          : null,
      cityEvent: <String, String>{
        if (city is Map<String, Object?> &&
            city['event'] is Map<String, Object?>)
          for (final MapEntry<String, Object?> e
              in (city['event']! as Map<String, Object?>).entries)
            if (e.value is String) e.key: e.value! as String,
      },
    );
  }

  final List<OnboardingScene> scenes;

  /// Смысл трёх конвертов одной строкой — под конвертами в сцене `show:
  /// envelopes` и под степперами плана (ТЗ 2.5.1.1: три решения объяснены,
  /// даже если ребёнок пропустил разговор).
  final ({String need, String want, String goal}) envelopes;

  /// Подпись кнопки «Пропустить».
  final String skip;

  /// Подписи знакомства по ключам [uiKeys].
  final Map<String, String> ui;

  /// Названия видов Финни по id реестра (`finni-a1` → «Росток»).
  final Map<String, String> species;

  /// Смысл конвертов коротко — у степперов плана, в одну строку.
  final ({String need, String want, String goal}) envelopesShort;

  /// Шаг кнопок «−» и «+» в плане знакомства.
  final int planStep;

  /// Подсказка над картой города (`city.hint`); нет — запасная в коде.
  final String? cityHint;

  /// Подсказка, когда у здания «!»: по id здания (`city.event`).
  final Map<String, String> cityEvent;

  /// Подпись [key] с подстановками [values] (`{n}`, `{left}`, …).
  String t(String key,
          [Map<String, String> values = const <String, String>{}]) =>
      fillLine(ui[key] ?? key, values);

  /// Запасной сценарий, если `onboarding.json` не прочитался (битая сборка):
  /// без разговора — сразу план и цель, чтобы игра всё равно запустилась.
  /// Это авария, а не контент: в сборке файл есть и проверен тестом.
  static const OnboardingScript fallback = OnboardingScript(
    scenes: <OnboardingScene>[
      OnboardingScene(
          id: 'plan',
          kind: SceneKind.plan,
          lines: <String>['Разложи монеты недели по конвертам.'],
          help: 'НУЖНО — еда и жильё. ХОЧУ — приятное. ЦЕЛЬ — копилка.'),
      OnboardingScene(
          id: 'goal',
          kind: SceneKind.goal,
          lines: <String>['На что копим?'],
          help: 'Цель — то, на что копим.'),
    ],
    envelopes: (
      need: 'Потратить на нужное',
      want: 'Потратить на желаемое',
      goal: 'Отложить на мечту',
    ),
    skip: 'Пропустить',
    ui: <String, String>{
      'step_of': 'Шаг {n} из {total}',
      'back': 'Назад',
      'nick_title': 'Как тебя звать?',
      'nick_text': 'Придумай ник.',
      'nick_label': 'Ник',
      'nick_hint': 'Ник',
      'nick_help': 'Ник — игровое имя.',
      'look_title': 'Финни',
      'look_help': 'Выбери облик и имя.',
      'name_label': 'Имя',
      'boy': 'Мальчик',
      'girl': 'Девочка',
      'look_tile': '{species} {n}',
      'next': 'Дальше',
      'go': 'Дальше',
      'plan_done': 'Готово',
      'to_room': 'Дальше',
      'scenes_title': 'Финни',
      'pool': 'На неделю:',
      'unallocated': 'Не разложено: {left}',
      'plan_ready': 'План готов.',
      'bills': 'счета {bill}',
      'in_piggy': 'В копилке:',
      'pool_full': 'Всё уже разложено',
      'piggy_locked': 'В копилке: {saved} — на цель, тратить нельзя',
    },
    species: <String, String>{},
    envelopesShort: (need: 'нужное', want: 'желаемое', goal: 'отложить'),
    planStep: 10,
  );

  /// Сценарий из [read]; файла нет или он битый — [fallback]. Ошибка не
  /// должна остановить запуск: знакомство без реплик лучше пустого экрана.
  static Future<OnboardingScript> load(
      Future<String> Function(String path) read) async {
    try {
      return OnboardingScript.parse(await read(path));
    } on Object {
      return fallback;
    }
  }

  /// Номер сцены плана: с неё продолжают после «Пропустить» и после
  /// перезапуска в фазе плана.
  int get planIndex => scenes.indexWhere((OnboardingScene s) => s.isPlan);

  /// Номер сцены цели: с неё продолжают, когда план уже подтверждён.
  int get goalIndex => scenes.indexWhere((OnboardingScene s) => s.isGoal);
}

/// Что делает ребёнок в сцене.
enum SceneKind {
  /// Финни говорит; «Дальше» — следующая реплика.
  talk,

  /// План первой недели — конверты.
  plan,

  /// Первая цель.
  goal,
}

/// Одна сцена: реплики Финни, к чему он подходит, что показать под текстом.
class OnboardingScene {
  const OnboardingScene({
    required this.id,
    required this.kind,
    required this.lines,
    required this.help,
    this.focus,
    this.showEnvelopes = false,
    this.linesGirl,
    this.helpGirl,
  });

  factory OnboardingScene._parse(Object? v, String at) {
    if (v is! Map<String, Object?>) {
      throw FormatException('onboarding.json → $at: ждали объект');
    }
    final Object? id = v['id'];
    final Object? kind = v['kind'];
    final Object? lines = v['lines'];
    final Object? help = v['help'];
    final Object? focus = v['focus'];
    final Object? show = v['show'];
    final Object? linesGirl = v['lines_girl'];
    final Object? helpGirl = v['help_girl'];
    if (id is! String || id.isEmpty) {
      throw FormatException('onboarding.json → $at.id: ждали строку');
    }
    final SceneKind? k =
        SceneKind.values.where((SceneKind s) => s.name == kind).firstOrNull;
    if (k == null) {
      throw FormatException(
          'onboarding.json → $at.kind: talk, plan или goal, а не $kind');
    }
    if (lines is! List<Object?> ||
        lines.isEmpty ||
        lines.any((Object? l) => l is! String || l.isEmpty)) {
      throw FormatException(
          'onboarding.json → $at.lines: ждали непустой список строк');
    }
    if (help is! String || help.isEmpty) {
      throw FormatException('onboarding.json → $at.help: ждали строку');
    }
    if (focus != null && (focus is! String || !sceneFocuses.contains(focus))) {
      throw FormatException('onboarding.json → $at.focus: '
          'одно из ${sceneFocuses.join(', ')} или null, а не $focus');
    }
    if (linesGirl != null &&
        (linesGirl is! List<Object?> ||
            linesGirl.length != lines.length ||
            linesGirl.any((Object? l) => l is! String || l.isEmpty))) {
      throw FormatException('onboarding.json → $at.lines_girl: '
          'столько же непустых строк, сколько в lines');
    }
    if (helpGirl != null && (helpGirl is! String || helpGirl.isEmpty)) {
      throw FormatException('onboarding.json → $at.help_girl: ждали строку');
    }
    if (show != null && show != 'envelopes') {
      throw FormatException(
          'onboarding.json → $at.show: envelopes или нет поля, а не $show');
    }
    return OnboardingScene(
      id: id,
      kind: k,
      lines: lines.cast<String>(),
      help: help,
      focus: focus as String?,
      showEnvelopes: show == 'envelopes',
      linesGirl: (linesGirl as List<Object?>?)?.cast<String>(),
      helpGirl: helpGirl as String?,
    );
  }

  /// К чему Финни может подойти в комнате.
  static const Set<String> sceneFocuses = <String>{
    'finni',
    'piggy',
    'fridge',
    'door',
    'bed',
  };

  final String id;
  final SceneKind kind;
  final List<String> lines;
  final String help;

  /// Предмет комнаты, к которому Финни подходит сам и который подсвечен.
  final String? focus;

  /// Под репликой — три конверта со смыслом.
  final bool showEnvelopes;

  /// Реплики и подсказка, когда Финни — девочка (`lines_girl`,
  /// `help_girl`); нет — те же, что у мальчика (фразы без рода).
  final List<String>? linesGirl;
  final String? helpGirl;

  /// Реплики для выбранного пола Финни.
  List<String> linesFor(FinniGender? g) =>
      g == FinniGender.girl ? linesGirl ?? lines : lines;

  /// Подсказка «?» для выбранного пола Финни.
  String helpFor(FinniGender? g) =>
      g == FinniGender.girl ? helpGirl ?? help : help;

  bool get isPlan => kind == SceneKind.plan;
  bool get isGoal => kind == SceneKind.goal;
}

/// Подстановки в репликах: `{nick}`, `{name}`, `{pool}`, `{bill}`,
/// `{saved}`. Числа считает мир — в файле их нет.
String fillLine(String line, Map<String, String> values) => line
    .replaceAllMapped(RegExp(r'\{(\w+)\}'), (Match m) => values[m[1]] ?? m[0]!);
