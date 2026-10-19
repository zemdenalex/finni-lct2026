// Линт детских текстов по правилам Насти (docs/final/formulirovki-reshenija-nasti.md).
//
//   dart run tool/lint_child_texts.dart [out.tsv]
//
// Берёт строки, которые видит ребёнок: литералы с кириллицей в экранах нового
// мира и в фразах домена (тот же список файлов, что у инвентаря формулировок
// formulirovki-inventar-vygruzka.py), и значения JSON контента (кроме ключей
// «_…» — это заметки). Печатает итог по правилам и пишет TSV:
// правило · место · строка. Только отчёт: в CI не подключается, строки не правит.
import 'dart:convert';
import 'dart:io';

/// Нарушение одного правила в одной строке.
class Finding {
  const Finding(this.rule, this.where, this.text);
  final String rule;
  final String where;
  final String text;
}

/// Правило: имя для отчёта и проверка строки.
class Rule {
  const Rule(this.id, this.title, this.test);
  final String id;
  final String title;
  final bool Function(String s) test;
}

final RegExp _caps = RegExp(r'(?<![А-ЯЁа-яё])[А-ЯЁ]{4,}(?![А-ЯЁа-яё])');
const Set<String> _acceptedCaps = <String>{'НУЖНО', 'ХОЧУ', 'ЦЕЛЬ'};
final RegExp _icon = RegExp(r'(⚡|😊|💰)');
final RegExp _word = RegExp(r'[А-Яа-яЁё]{2,}');

bool _iconMidPhrase(String s) {
  for (final RegExpMatch m in _icon.allMatches(s)) {
    final String before = s.substring(0, m.start);
    final String after = s.substring(m.end);
    if (_word.hasMatch(before) && _word.hasMatch(after)) return true;
  }
  return false;
}

/// Правила. Порядок — как в отчёте.
final List<Rule> rules = <Rule>[
  Rule('1-konvert', 'правило 1: слово «конверт»',
      (String s) => RegExp(r'[Кк]онверт').hasMatch(s)),
  Rule(
      '1-caps',
      'правило 1: КАПС длиннее 3 букв (кроме НУЖНО/ХОЧУ/ЦЕЛЬ)',
      (String s) => _caps
          .allMatches(s)
          .any((RegExpMatch m) => !_acceptedCaps.contains(m.group(0)))),
  Rule(
      '2-ochki-stadiya-zalog',
      'правило 2: «очки роста», «стадия», «залог»',
      (String s) =>
          RegExp(r'[Оо]чк[А-Яа-яЁё]* роста|[Сс]тади[яиюейям]|[Зз]алог')
              .hasMatch(s)),
  Rule('3-znachok', 'правило 3: значок ⚡ 😊 💰 посреди фразы', _iconMidPhrase),
  Rule(
      '4-slova',
      'правило 4: не те слова для денег и сил (энергия, деньги, монетки, мечта, кошелёк, карманные)',
      (String s) => RegExp(
              r'[Ээ]нерги|[Дд]еньг|[Дд]енег|[Мм]онетк|[Мм]ечт|[Кк]ошел[её]к|[Кк]ошельк|[Кк]арманн')
          .hasMatch(s)),
  // \b в RegExp Dart — только латиница, поэтому границы слова — через
  // соседние буквы кириллицы.
  Rule(
      '5-rod',
      'правило 5: обращение к ребёнку с родом',
      (String s) => RegExp(
              r'(?<![А-Яа-яЁё])[Тт]ы\s+(сам[а]?|готов[а]?|был[а]?|рад[а]?|[А-Яа-яЁё]+л[аио]?)(?![А-Яа-яЁё])'
              r'|[А-Яа-яЁё]+л[аио]?\s+ты(?![А-Яа-яЁё])'
              r'|[А-Яа-яЁё]\(а\)|[А-Яа-яЁё]/а(?![А-Яа-яЁё])')
          .hasMatch(s)),
  Rule('7-dlinno', 'правило 7: строка длиннее 140 знаков (подсказки)',
      (String s) => s.length > 140),
  Rule('8-sborka', 'правило 8: «Сборка» на детском экране',
      (String s) => RegExp(r'Сборка ').hasMatch(s)),
  Rule(
      '9-nedelya-den',
      'режим дней: «недел…» рядом с силами, сном или едой',
      (String s) =>
          RegExp(r'[Нн]едел').hasMatch(s) &&
          RegExp(r'⚡|[Сс]ил[аыу ]|[Сс]пат|[Сс]пит|(?<![А-Яа-яЁё])[Сс]он(?![А-Яа-яЁё])|[Лл]ёг|[Ее]да|[Ее]ды|[Пп]оел|[Гг]олод|[Сс]ыт')
              .hasMatch(s)),
];

/// Для сведения, не нарушение: по 1А капса быть не должно, по 8А «Источник»
/// на совете остаётся.
final List<Rule> notes = <Rule>[
  Rule(
      'i-caps-prinyatye',
      'сведения: НУЖНО/ХОЧУ/ЦЕЛЬ капсом (по 1А их не должно быть)',
      (String s) => RegExp(r'НУЖНО|ХОЧУ|ЦЕЛЬ').hasMatch(s)),
  Rule('i-istochnik', 'сведения: «Источник:» (по 8А допустимо на советах)',
      (String s) => s.contains('Источник:')),
];

/// Где «конверт» разрешён: правило 1Б Насти (18.10) — «конверты» остаются
/// образом методики, но один раз, в обучении, рядом с картинкой конверта
/// (сценка знакомства `envelopes`). Везде больше — «три части».
const String konvertAllowedAt =
    'assets/content/world/onboarding.json:scenes[envelopes].lines';

/// Все нарушения в строке [s] из [where].
List<Finding> lintText(String where, String s, {List<Rule>? using}) =>
    <Finding>[
      for (final Rule r in using ?? rules)
        if (r.test(s) &&
            !(r.id == '1-konvert' && where.startsWith(konvertAllowedAt)))
          Finding(r.id, where, s),
    ];

// ─────────────────────────────── сбор строк ───────────────────────────────

final RegExp _cyr = RegExp(r'[А-Яа-яЁё]');

/// Литерал в одинарных или двойных кавычках.
const String _sq = r"'(?:[^'\\\n]|\\.)*'";
const String _dq = r'"(?:[^"\\\n]|\\.)*"';

/// Литерал и соседние, склеенные пробелом (неявная конкатенация Dart).
final RegExp _literalRun = RegExp('(?:$_sq|$_dq)(?:\\s*(?:$_sq|$_dq))*');
final RegExp _literal = RegExp('$_sq|$_dq');

/// Текст литерала без кавычек.
String _unquote(String lit) => lit.substring(1, lit.length - 1);

/// Строки с кириллицей из Dart-файла: (номер строки, текст).
List<(int, String)> dartStrings(String source) {
  final List<String> lines = source.split('\n');
  final StringBuffer clean = StringBuffer();
  for (final String l in lines) {
    final String t = l.trimLeft();
    final bool skip = t.startsWith('//') ||
        t.startsWith('///') ||
        l.contains('debugPrint') ||
        l.contains('assert(') ||
        l.contains('StateError') ||
        l.contains('FormatException');
    clean.writeln(skip ? '' : l);
  }
  final String text = clean.toString();
  final List<(int, String)> out = <(int, String)>[];
  for (final RegExpMatch run in _literalRun.allMatches(text)) {
    final String joined = _literal
        .allMatches(run.group(0)!)
        .map((RegExpMatch m) => _unquote(m.group(0)!))
        .join();
    if (!_cyr.hasMatch(joined)) continue;
    final int line = '\n'.allMatches(text.substring(0, run.start)).length + 1;
    out.add((line, joined.replaceAll(r'\n', ' ')));
  }
  return out;
}

const Set<String> _notShown = <String>{
  'not_indexed',
  'indexed',
  'source',
  'rounding',
  'status',
};

/// Строки с кириллицей из JSON: (путь ключей, текст); ключи «_…» — заметки.
List<(String, String)> jsonStrings(Object? node, [String path = '']) {
  final List<(String, String)> out = <(String, String)>[];
  if (node is Map) {
    for (final MapEntry<dynamic, dynamic> e in node.entries) {
      final String k = '${e.key}';
      // «_…» и служебные поля экономики — заметки для команды, не экран.
      if (k.startsWith('_') || _notShown.contains(k)) continue;
      out.addAll(jsonStrings(e.value, path.isEmpty ? k : '$path.$k'));
    }
  } else if (node is List) {
    for (int i = 0; i < node.length; i++) {
      final Object? v = node[i];
      final String id = v is Map && v['id'] != null ? '${v['id']}' : '$i';
      out.addAll(jsonStrings(v, '$path[$id]'));
    }
  } else if (node is String && _cyr.hasMatch(node)) {
    out.add((path, node));
  }
  return out;
}

/// Файлы, которые видит ребёнок (как у инвентаря формулировок).
List<File> childDartFiles() {
  bool shown(String p) {
    final String n = p.replaceAll(r'\', '/');
    return !n.contains('/demo/') &&
        !n.contains('/adult/') &&
        !n.contains('/dev/');
  }

  final List<File> files = <File>[
    ...Directory('lib/features/world')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart') && shown(f.path)),
    ...Directory('lib/features/glossary')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart')),
    for (final String f in <String>[
      'lib/domain/world/world_game.dart',
      'lib/domain/world/world_mood.dart',
      'lib/domain/world/world_catalog.dart',
      'lib/domain/world/world_fold.dart',
      'lib/domain/world/contract.dart',
      'lib/domain/phrases.dart',
    ])
      File(f),
  ];
  return files.where((File f) => f.existsSync()).toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

const List<String> childJsonFiles = <String>[
  'assets/content/world/economy.json',
  'assets/content/world/events.json',
  'assets/content/world/jobs.json',
  'assets/content/world/onboarding.json',
  'assets/content/world/hud.json',
  'assets/content/glossary.json',
  'assets/content/copy.json',
];

void main(List<String> args) {
  final List<(String, String)> texts = <(String, String)>[];
  for (final File f in childDartFiles()) {
    final String rel = f.path.replaceAll(r'\', '/');
    for (final (int line, String s) in dartStrings(f.readAsStringSync())) {
      texts.add(('$rel:$line', s));
    }
  }
  for (final String p in childJsonFiles) {
    final File f = File(p);
    if (!f.existsSync()) continue;
    for (final (String key, String s)
        in jsonStrings(jsonDecode(f.readAsStringSync()))) {
      texts.add(('$p:$key', s));
    }
  }
  final List<Finding> found = <Finding>[
    for (final (String where, String s) in texts) ...lintText(where, s),
    for (final (String where, String s) in texts)
      ...lintText(where, s, using: notes),
  ];
  stdout.writeln('строк проверено: ${texts.length}');
  for (final Rule r in <Rule>[...rules, ...notes]) {
    final int n = found.where((Finding f) => f.rule == r.id).length;
    stdout.writeln('${r.id}\t$n\t${r.title}');
  }
  final String out =
      args.isEmpty ? 'build/lint-detskih-tekstov.tsv' : args.first;
  File(out)
    ..createSync(recursive: true)
    ..writeAsStringSync(<String>[
      'правило\tгде\tстрока',
      for (final Finding f in found)
        '${f.rule}\t${f.where}\t${f.text.replaceAll('\t', ' ')}',
    ].join('\n'));
  stdout.writeln('TSV: $out');
}
