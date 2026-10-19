import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../domain/world/contract.dart'
    show World, WorldLedgerKind, energyShown, heroText;
import '../../domain/world/world_config.dart'
    show DayCycle, ShiftLuck, SleepRule;
import '../../domain/world/world_entry.dart';
import '../../domain/world/world_game.dart';

/// Строка итога смены про везение: «Сегодня повезло: …» / «Не повезло: …»,
/// под ней [hint] — что это дало, справа [pay] — монеты сверху (или меньше).
@immutable
class ShiftLuckLine {
  const ShiftLuckLine(
      {required this.good,
      required this.text,
      required this.hint,
      this.pay = 0});

  final bool good;
  final String text;
  final String hint;

  /// `luckPay` из журнала: на сколько монет везение изменило оплату.
  final int pay;

  /// «Сегодня повезло: …» или «Не повезло: …».
  String get line => '${good ? 'Сегодня повезло' : 'Не повезло'}: $text';
}

/// Объяснения модели «7 дней» (Денис 17.10): везение на смене, почему
/// меняется настроение, как считаются опыт и сон. Тексты подсказок —
/// `content/explain.json` (копия в сборке — [asset]); сценарии везения —
/// домен (`economy.json → day_cycle.shift_luck`). Включает флаг
/// `day_cycle.explain_ui` в режиме дней.
///
/// В приложение — через `Provider<WorldExplain>` (`main.dart`); экран без
/// провайдера получает [off] и выглядит как до 7 дней.
@immutable
class WorldExplain {
  const WorldExplain({
    required this.enabled,
    this.texts = const <String, String>{},
    this.luckHints = const <String, String>{},
    this.sleepRule,
    this.moodPayDaily = false,
    this.moodPayLive = false,
  });

  /// Объяснений нет: флаг выключен, файла нет или он битый.
  static const WorldExplain off = WorldExplain(enabled: false);

  static const String asset = 'assets/content/world/explain.json';

  /// Подсказки, которые обязаны быть в `explain`.
  static const List<String> keys = <String>[
    'mood_why',
    'xp_short',
    'xp_detail',
    'sleep_short',
    'sleep_detail',
  ];

  /// Разбор файла: нет подсказки из [keys] или строка пустая —
  /// [FormatException] с именем ключа. Включено, только если в режиме
  /// дней стоит `explain_ui` ([dayCycle]).
  factory WorldExplain.parse(String json, {required DayCycle dayCycle}) {
    final Object? root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('explain.json: не объект');
    }
    Map<String, String> strings(String section, {List<String>? required}) {
      final Object? m = root[section];
      if (m is! Map<String, Object?>) {
        throw FormatException('explain.json: нет раздела $section');
      }
      final Map<String, String> out = <String, String>{};
      for (final MapEntry<String, Object?> e in m.entries) {
        if (e.key.startsWith('_')) continue;
        final Object? v = e.value;
        if (v is! String || v.trim().isEmpty) {
          throw FormatException('explain.json: пустой текст $section.${e.key}');
        }
        out[e.key] = v;
      }
      for (final String k in required ?? const <String>[]) {
        if (!out.containsKey(k)) {
          throw FormatException('explain.json: нет текста $section.$k');
        }
      }
      return out;
    }

    return WorldExplain(
      enabled: dayCycle.enabled && dayCycle.explainUi,
      texts: strings('explain', required: keys),
      luckHints: strings('shift_luck_hint'),
      sleepRule: dayCycle.enabled ? dayCycle.sleepRule : null,
      moodPayDaily: dayCycle.enabled && dayCycle.moodPayDaily,
      moodPayLive: dayCycle.enabled && dayCycle.moodPayLive,
    );
  }

  /// Файл до первого кадра; битый или без файла — [off]: объяснения не
  /// останавливают запуск.
  static Future<WorldExplain> load(Future<String> Function(String path) read,
      {required DayCycle dayCycle}) async {
    try {
      return WorldExplain.parse(await read(asset), dayCycle: dayCycle);
    } on Object {
      return off;
    }
  }

  /// Из провайдера над экраном; нет провайдера — [off].
  static WorldExplain of(BuildContext context) {
    try {
      return Provider.of<WorldExplain>(context, listen: false);
    } on ProviderNotFoundException {
      return off;
    }
  }

  final bool enabled;
  final Map<String, String> texts;

  /// Что дал сценарий везения, по его id (`shift_luck_hint`).
  final Map<String, String> luckHints;

  /// Таблица сна режима дней; `null` — сон по-старому, объяснения сна нет.
  final SleepRule? sleepRule;

  /// Оплата от настроения утра этого дня (`day_cycle.mood_pay_daily`, C6):
  /// тогда объяснение — `mood_effect_daily`, а не про начало недели.
  final bool moodPayDaily;

  /// Оплата от настроения на момент смены (`mood_pay_live`, DEN-36 A):
  /// объяснение — `mood_effect_live`; сильнее [moodPayDaily].
  final bool moodPayLive;

  String? _text(String id) => enabled ? texts[id] : null;

  /// Почему меняется настроение после смены и (`mood_effect`, если есть)
  /// что оно меняет в работе: оплату и цену в силах по настроению на начало
  /// недели (`economy.json → happiness`).
  String? get moodWhy {
    final String? why = _text('mood_why');
    final String? effect = _text(moodPayLive
        ? 'mood_effect_live'
        : moodPayDaily
            ? 'mood_effect_daily'
            : 'mood_effect');
    if (why == null) return null;
    return effect == null || effect.trim().isEmpty ? why : '$why\n\n$effect';
  }

  /// Тип работы для настроения на доске (C5): `job_mood_<kind>`; нет типа,
  /// текста или объяснения выключены — null.
  String? jobMood(String? kind) =>
      kind == null ? null : _text('job_mood_$kind');

  /// Опыт одной строкой (карточка смены) и подробно (кнопка).
  String? get xpShort => _text('xp_short');
  String? get xpDetail => _text('xp_detail');

  /// Сон: строка диалога «Спать» и подробно. Числа — из [sleepRule], а не
  /// из текста: смена таблицы сна в json не расходится с объяснением.
  String? get sleepShort => _sleep('sleep_short');
  String? get sleepDetail => _sleep('sleep_detail');

  String? _sleep(String id) {
    final SleepRule? r = sleepRule;
    final String? t = _text(id);
    if (r == null || t == null) return null;
    return t
        .replaceAll('{floor}', energyShown(r.floor))
        .replaceAll('{cap}', energyShown(r.cap));
  }

  /// Везение последней смены: id сценария и `luckPay` — из записи
  /// `job.payout` журнала, текст и «повезло / не повезло» — из сценария
  /// домена, подсказка — из [luckHints]. Нет флага, сценария или журнала
  /// (не движок) — `null`.
  ShiftLuckLine? lastShiftLuck(World world) {
    if (!enabled || world is! WorldGame) return null;
    final List<WorldEntry> j = world.journal;
    for (int i = j.length - 1; i >= 0; i--) {
      final WorldEntry e = j[i];
      if (e.kind != WorldLedgerKind.jobPayout) continue;
      final Object? id = e.args['luck'];
      if (id is! String) return null;
      ShiftLuck? s;
      for (final ShiftLuck l in world.config.dayCycle.luck) {
        if (l.id == id) s = l;
      }
      if (s == null) return null;
      final Object? pay = e.args['luckPay'];
      return ShiftLuckLine(
        good: s.good,
        text: heroText(s.text, world.onboarding.finniName),
        hint: luckHints[id] ?? '',
        pay: pay is int ? pay : 0,
      );
    }
    return null;
  }
}
