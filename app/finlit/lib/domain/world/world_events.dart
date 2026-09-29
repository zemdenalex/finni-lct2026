/// События недели из `content/events.json` (карточка A10,
/// `docs/game/events.md`) — модель и разбор.
///
/// 🔴 Домен файлов не читает (`layering_test`): сюда приходит уже
/// раскодированный JSON — `WorldEvent.data` загрузчика
/// (`lib/data/world_content.dart`) или `jsonDecode` в тесте. Ключи на `_`
/// — комментарии, их пропускаем.
///
/// Называется WorldEventSpec, а не WorldEvent: `WorldEvent` уже есть в
/// `lib/data/world_content.dart`, и файл, который видит оба, получил бы
/// неоднозначный импорт.
///
/// Неизвестный эффект или условие — [FormatException] с путём до поля:
/// опечатка в файле видна при загрузке, а не молчаливым «событие не
/// появилось» на демонстрации.
library;

import 'dart:math' as math;

/// Откуда берётся положительный `savings_pocket_x` (`effects.savings_from`).
enum SavingsSource {
  /// Новые деньги — подарок (бабушка). По умолчанию.
  gift,

  /// Перевод своих монет: из ХОЧУ, затем из заработка.
  wallet,

  /// Часть карманных новой недели, до плана (`recurring`).
  pocketMoney,
}

/// Условия появления события или видимости варианта (`conditions`).
class EventConditions {
  const EventConditions({
    this.minWeek,
    this.hasPet,
    this.noTransport,
    this.savingsGoal,
    this.savingsShare,
    this.energyMin,
    this.energyMax,
    this.flagAny = const <String>[],
    this.flag,
  });

  final int? minWeek;
  final bool? hasPet;
  final bool? noTransport;

  /// `savings_min_share_of_goal.goal`: `transport` или id цели.
  final String? savingsGoal;

  /// `savings_min_share_of_goal.share`: копилка ≥ доля × цена цели.
  final double? savingsShare;
  final double? energyMin;
  final double? energyMax;

  /// Продолжение: метка из прошлого выбора, свежая (поставлена после
  /// прошлого показа этого события и раньше этой недели).
  final List<String> flagAny;

  /// У варианта: вариант виден только при этой свежей метке.
  final String? flag;

  /// Условие зависит от того, что меняется внутри недели (⚡ или метка),
  /// — такое событие может появиться не только в начале недели.
  bool get reactive =>
      energyMin != null || energyMax != null || flagAny.isNotEmpty;

  static const Set<String> _known = <String>{
    'min_week',
    'has_pet',
    'no_transport',
    'savings_min_share_of_goal',
    'energy_min',
    'energy_max',
    'flag_any',
    'flag',
  };

  factory EventConditions.fromJson(Object? json, String path) {
    if (json == null) return const EventConditions();
    final Map<String, Object?> m = _map(json, path);
    _onlyKnown(m, _known, path);
    final Object? share = m['savings_min_share_of_goal'];
    Map<String, Object?>? s;
    if (share != null) {
      s = _map(share, '$path.savings_min_share_of_goal');
    }
    return EventConditions(
      minWeek: _optInt(m, 'min_week', path),
      hasPet: _optBool(m, 'has_pet', path),
      noTransport: _optBool(m, 'no_transport', path),
      savingsGoal:
          s == null ? null : _str(s, 'goal', '$path.savings_min_share_of_goal'),
      savingsShare: s == null
          ? null
          : _num(s, 'share', '$path.savings_min_share_of_goal'),
      energyMin: _optNum(m, 'energy_min', path),
      energyMax: _optNum(m, 'energy_max', path),
      flagAny: m['flag_any'] == null
          ? const <String>[]
          : _strings(m['flag_any'], '$path.flag_any'),
      flag: m['flag'] == null ? null : _str(m, 'flag', path),
    );
  }
}

/// Эффекты варианта (`effects`, схема — `events.json → _effects_schema`).
///
/// Суммы — доли карманных этой недели (`*_pocket_x`); цены досуга, товара и
/// смены берутся из `economy.json`, у события своих цен нет.
class EventEffects {
  const EventEffects({
    this.moneyX = 0,
    this.savingsX = 0,
    this.savingsFrom = SavingsSource.gift,
    this.requiredExtraX = 0,
    this.happiness = 0,
    this.energy = 0,
    this.energyNextWeek = 0,
    this.goalDiscountGoal,
    this.goalDiscountShare = 0,
    this.flag,
    this.leisure,
    this.payFromSavings = false,
    this.buy,
    this.discount = 0,
    this.shift,
    this.recurring,
    this.recurringWeeks = 0,
    this.simulation,
  });

  final double moneyX;
  final double savingsX;
  final SavingsSource savingsFrom;
  final double requiredExtraX;
  final int happiness;
  final double energy;
  final double energyNextWeek;
  final String? goalDiscountGoal;
  final double goalDiscountShare;
  final String? flag;
  final String? leisure;

  /// `pay_from: savings` — досуг оплачивается из копилки.
  final bool payFromSavings;
  final String? buy;

  /// Скидка на [buy], доля.
  final double discount;
  final String? shift;

  /// Что повторяется в начале каждой из следующих [recurringWeeks] недель.
  /// Исполняются деньги, копилка и 😊.
  final EventEffects? recurring;
  final int recurringWeeks;
  final String? simulation;

  static const Set<String> _known = <String>{
    'money_pocket_x',
    'savings_pocket_x',
    'savings_from',
    'required_extra_pocket_x',
    'happiness',
    'energy',
    'energy_next_week',
    'goal_discount',
    'flag',
    'leisure',
    'pay_from',
    'buy',
    'discount',
    'shift',
    'recurring',
    'simulation',
  };

  static const Set<String> _knownRecurring = <String>{
    'money_pocket_x',
    'savings_pocket_x',
    'savings_from',
    'happiness',
    'weeks',
  };

  factory EventEffects.fromJson(Object? json, String path,
      {bool recurring = false}) {
    if (json == null) return const EventEffects();
    final Map<String, Object?> m = _map(json, path);
    _onlyKnown(m, recurring ? _knownRecurring : _known, path);
    final Object? gd = m['goal_discount'];
    Map<String, Object?>? g;
    if (gd != null) g = _map(gd, '$path.goal_discount');
    final Object? payFrom = m['pay_from'];
    if (payFrom != null && payFrom != 'savings') {
      throw FormatException('$path.pay_from: ожидалось "savings", '
          'а стоит ${_show(payFrom)}');
    }
    final Object? rec = m['recurring'];
    EventEffects? r;
    int weeks = 0;
    if (rec != null) {
      r = EventEffects.fromJson(rec, '$path.recurring', recurring: true);
      weeks = _int(_map(rec, '$path.recurring'), 'weeks', '$path.recurring');
    }
    return EventEffects(
      moneyX: _optNum(m, 'money_pocket_x', path) ?? 0,
      savingsX: _optNum(m, 'savings_pocket_x', path) ?? 0,
      savingsFrom: _source(m['savings_from'], '$path.savings_from'),
      requiredExtraX: _optNum(m, 'required_extra_pocket_x', path) ?? 0,
      happiness: _optInt(m, 'happiness', path) ?? 0,
      energy: _optNum(m, 'energy', path) ?? 0,
      energyNextWeek: _optNum(m, 'energy_next_week', path) ?? 0,
      goalDiscountGoal:
          g == null ? null : _str(g, 'goal', '$path.goal_discount'),
      goalDiscountShare:
          g == null ? 0 : _num(g, 'share', '$path.goal_discount'),
      flag: m['flag'] == null ? null : _str(m, 'flag', path),
      leisure: m['leisure'] == null ? null : _str(m, 'leisure', path),
      payFromSavings: payFrom == 'savings',
      buy: m['buy'] == null ? null : _str(m, 'buy', path),
      discount: _optNum(m, 'discount', path) ?? 0,
      shift: m['shift'] == null ? null : _str(m, 'shift', path),
      recurring: r,
      recurringWeeks: weeks,
      simulation: m['simulation'] == null ? null : _str(m, 'simulation', path),
    );
  }

  static SavingsSource _source(Object? v, String path) => switch (v) {
        null || 'gift' => SavingsSource.gift,
        'wallet' => SavingsSource.wallet,
        'pocket_money' => SavingsSource.pocketMoney,
        _ => throw FormatException('$path: ожидалось gift, wallet или '
            'pocket_money, а стоит ${_show(v)}'),
      };
}

/// Вариант выбора в событии (`options[]`).
class WorldEventOptionSpec {
  const WorldEventOptionSpec({
    required this.id,
    required this.label,
    required this.finni,
    required this.effects,
    this.nextStep,
    this.conditions = const EventConditions(),
  });

  final String id;
  final String label;

  /// Реплика Финни после выбора, с `{nick}` (и `{spent}`/`{won}` у
  /// симуляции).
  final String finni;
  final String? nextStep;
  final EventConditions conditions;
  final EventEffects effects;

  factory WorldEventOptionSpec.fromJson(Object? json, String path) {
    final Map<String, Object?> m = _map(json, path);
    return WorldEventOptionSpec(
      id: _str(m, 'id', path),
      label: _str(m, 'label', path),
      finni: _str(m, 'finni', path),
      nextStep: m['next_step'] == null ? null : _str(m, 'next_step', path),
      conditions: EventConditions.fromJson(m['conditions'], '$path.conditions'),
      effects: EventEffects.fromJson(m['effects'], '$path.effects'),
    );
  }
}

/// Строка таблицы выигрышей автомата.
class SlotPayout {
  const SlotPayout(this.coins, this.chance);
  final int coins;
  final double chance;
}

/// Симуляция автомата «понарошку» (`events[].simulation`, решение 26.09):
/// никаких списаний и выдач, только счёт «потрачено бы / выиграно бы».
class SlotSimSpec {
  const SlotSimSpec({
    required this.id,
    required this.spins,
    required this.pricePerSpin,
    required this.payouts,
    required this.maxWinShare,
    this.accessoryName,
    this.accessoryChance = 0,
    this.accessoryMinSpin = 0,
    this.accessoryGuaranteedBy = 0,
  });

  final String id;
  final int spins;
  final int pricePerSpin;
  final List<SlotPayout> payouts;

  /// Выигрыш урезается до этой доли потраченного после каждого вращения:
  /// «проигрыш всегда ≥ выигрыша».
  final double maxWinShare;
  final String? accessoryName;
  final double accessoryChance;
  final int accessoryMinSpin;
  final int accessoryGuaranteedBy;

  factory SlotSimSpec.fromJson(Object? json, String path) {
    final Map<String, Object?> m = _map(json, path);
    final Object? acc = m['rare_accessory'];
    final Map<String, Object?>? a =
        acc == null ? null : _map(acc, '$path.rare_accessory');
    final Object? table = m['payout_table'];
    if (table is! List<Object?>) {
      throw FormatException(
          '$path.payout_table: ожидался список, а стоит ${_show(table)}');
    }
    return SlotSimSpec(
      id: _str(m, 'id', path),
      spins: _int(m, 'spins', path),
      pricePerSpin: _int(m, 'virtual_price_per_spin', path),
      payouts: <SlotPayout>[
        for (int i = 0; i < table.length; i++)
          SlotPayout(
            _int(_map(table[i], '$path.payout_table[$i]'), 'coins',
                '$path.payout_table[$i]'),
            _num(_map(table[i], '$path.payout_table[$i]'), 'chance',
                '$path.payout_table[$i]'),
          ),
      ],
      maxWinShare: _num(m, 'max_win_share', path),
      accessoryName: a == null ? null : _str(a, 'name', '$path.rare_accessory'),
      accessoryChance:
          a == null ? 0 : _num(a, 'chance', '$path.rare_accessory'),
      accessoryMinSpin:
          a == null ? 0 : _int(a, 'min_spin', '$path.rare_accessory'),
      accessoryGuaranteedBy:
          a == null ? 0 : _int(a, 'guaranteed_by_spin', '$path.rare_accessory'),
    );
  }

  /// Один прогон — как `run_slot_sim` в `content/sim/economy_sim.py`.
  /// Детерминирован по [seed]: мир передаёт номер записи журнала, и один и
  /// тот же путь действий даёт тот же счёт. Итог пишется в журнал, при
  /// свёртке не перебрасывается.
  ({int spent, int won, int? accessorySpin}) run(int seed) {
    final math.Random rng = math.Random(seed);
    int spent = 0;
    int won = 0;
    int? accSpin;
    for (int spin = 1; spin <= spins; spin++) {
      spent += pricePerSpin;
      final double roll = rng.nextDouble();
      double acc = 0;
      int win = 0;
      for (final SlotPayout p in payouts) {
        acc += p.chance;
        if (roll < acc) {
          win = p.coins;
          break;
        }
      }
      won = math.min(won + win, (spent * maxWinShare).floor());
      if (accessoryName != null &&
          accSpin == null &&
          spin >= accessoryMinSpin) {
        if (rng.nextDouble() < accessoryChance ||
            spin >= accessoryGuaranteedBy) {
          accSpin = spin;
        }
      }
    }
    return (spent: spent, won: won, accessorySpin: accSpin);
  }
}

/// Событие недели (`events[]`).
class WorldEventSpec {
  const WorldEventSpec({
    required this.id,
    required this.topic,
    required this.buildingId,
    required this.title,
    required this.situation,
    required this.options,
    this.conditions = const EventConditions(),
    this.simulation,
  });

  final String id;

  /// `planning` или `savings`.
  final String topic;

  /// `events[].building` — здание города с «!».
  final String buildingId;
  final String title;
  final String situation;
  final EventConditions conditions;
  final List<WorldEventOptionSpec> options;
  final SlotSimSpec? simulation;

  WorldEventOptionSpec? option(String id) {
    for (final WorldEventOptionSpec o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  factory WorldEventSpec.fromJson(Object? json, String path) {
    final Map<String, Object?> m = _map(json, path);
    final String topic = _str(m, 'topic', path);
    if (topic != 'planning' && topic != 'savings') {
      throw FormatException('$path.topic: ожидалось planning или savings, '
          'а стоит «$topic»');
    }
    final Object? opts = m['options'];
    if (opts is! List<Object?> || opts.length < 2 || opts.length > 3) {
      throw FormatException('$path.options: нужно 2–3 варианта');
    }
    return WorldEventSpec(
      id: _str(m, 'id', path),
      topic: topic,
      buildingId: _str(m, 'building', path),
      title: _str(m, 'title', path),
      situation: _str(m, 'situation', path),
      conditions: EventConditions.fromJson(m['conditions'], '$path.conditions'),
      options: <WorldEventOptionSpec>[
        for (int i = 0; i < opts.length; i++)
          WorldEventOptionSpec.fromJson(opts[i], '$path.options[$i]'),
      ],
      simulation: m['simulation'] == null
          ? null
          : SlotSimSpec.fromJson(m['simulation'], '$path.simulation'),
    );
  }
}

/// Разобрать `events.json → events[]`. [events] — список объектов событий
/// (для загрузчика — `WorldEvent.data` каждого события).
List<WorldEventSpec> parseWorldEvents(Iterable<Object?> events) {
  final List<Object?> list = events.toList();
  return <WorldEventSpec>[
    for (int i = 0; i < list.length; i++)
      WorldEventSpec.fromJson(list[i], 'events.json → events[$i]'),
  ];
}

/// Реплика Финни: `{nick}` → ник, прочие `{ключ}` → [vars]. Ника ещё нет —
/// обращение опускается вместе с запятой, первая буква становится заглавной.
String finniLine(String text, String nick,
    [Map<String, String> vars = const <String, String>{}]) {
  String s = text;
  vars.forEach((String k, String v) => s = s.replaceAll('{$k}', v));
  if (nick.isNotEmpty) return s.replaceAll('{nick}', nick);
  s = s
      .replaceAll(', {nick}', '')
      .replaceAll('{nick}, ', '')
      .replaceAll('{nick}', '')
      .trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ───────────────────────────── разбор полей ─────────────────────────────

String _show(Object? v) => v == null ? 'null' : '«$v» (${v.runtimeType})';

Map<String, Object?> _map(Object? v, String path) {
  if (v is Map) return v.cast<String, Object?>();
  throw FormatException('$path: ожидался объект, а стоит ${_show(v)}');
}

void _onlyKnown(Map<String, Object?> m, Set<String> known, String path) {
  for (final String k in m.keys) {
    if (k.startsWith('_') || known.contains(k)) continue;
    throw FormatException('$path.$k: такого ключа домен не знает — '
        'добавь его в код или исправь опечатку');
  }
}

String _str(Map<String, Object?> m, String key, String path) {
  final Object? v = m[key];
  if (v is String && v.trim().isNotEmpty) return v;
  throw FormatException(
      '$path.$key: ожидалась непустая строка, а стоит ${_show(v)}');
}

List<String> _strings(Object? v, String path) {
  if (v is List<Object?> && v.every((Object? e) => e is String)) {
    return v.cast<String>();
  }
  throw FormatException('$path: ожидался список строк, а стоит ${_show(v)}');
}

double _num(Map<String, Object?> m, String key, String path) {
  final Object? v = m[key];
  if (v is num) return v.toDouble();
  throw FormatException('$path.$key: ожидалось число, а стоит ${_show(v)}');
}

double? _optNum(Map<String, Object?> m, String key, String path) =>
    m[key] == null ? null : _num(m, key, path);

int _int(Map<String, Object?> m, String key, String path) {
  final Object? v = m[key];
  if (v is int) return v;
  throw FormatException(
      '$path.$key: ожидалось целое число, а стоит ${_show(v)}');
}

int? _optInt(Map<String, Object?> m, String key, String path) =>
    m[key] == null ? null : _int(m, key, path);

bool? _optBool(Map<String, Object?> m, String key, String path) {
  final Object? v = m[key];
  if (v == null || v is bool) return v as bool?;
  throw FormatException(
      '$path.$key: ожидалось true/false, а стоит ${_show(v)}');
}
