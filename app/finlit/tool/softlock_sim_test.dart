// Поиск тупиков режима дней на настоящем движке (`WorldGame`), не на модели.
//
// Запуск (из app/finlit):
//   flutter test tool/softlock_sim_test.dart
// Без переменных — числа сборки как есть (economy.json). Каждая переменная
// меняет только своё число:
//   SIM_DAYS=3            дней в неделе (day_cycle.days_per_week)
//   SIM_POCKET=460        карманные (pocket_money.base)
//   SIM_SLEEP=4           сон «до уровня» (day_cycle.sleep_level)
//   SIM_CARRY=1           перенос ⚡ (day_cycle.carry_max)
//   SIM_SHIFTS_DAY=1      смен в день (day_cycle.max_shifts_per_day; 0 — без лимита)
//   SIM_NIGHT=60          сытость за ночь (day_cycle.satiety_night): проверка, что детектор голода не слеп
//   SIM_SEEDS=20          зёрен на стратегию (20 — быстрый прогон в CI; полный — SIM_SEEDS=1000)
//   SIM_WEEKS=10          недель на прогон
//   SIM_STRATEGIES=random,greedy,...   (по умолчанию все)
//   SIM_SEED=17 SIM_STRATEGIES=random SIM_TRACE=1   — воспроизвести одно зерно с журналом ходов
//   SIM_OUT=путь.json     куда записать сводку (по умолчанию — только печать)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

const double _eps = 1e-9;

/// Сколько действий допускается на одну неделю, прежде чем считать, что
/// итоги недели недостижимы для этой стратегии.
const int stepsPerWeek = 250;

String _env(String k, String d) => Platform.environment[k] ?? d;
int _envInt(String k, int d) => int.parse(_env(k, '$d'));

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Числа сборки как есть (17.10: 7 дней, сон по таблице, ⚡ 20); каждая
/// переменная SIM_* меняет только своё число.
WorldConfig buildConfig() {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  final Map<String, String> env = Platform.environment;
  final Map<String, Object?> dc = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
    if (env['SIM_DAYS'] != null) 'days_per_week': _envInt('SIM_DAYS', 7),
    if (env['SIM_SLEEP'] != null) 'sleep_level': _envInt('SIM_SLEEP', 4),
    if (env['SIM_CARRY'] != null) 'carry_max': _envInt('SIM_CARRY', 1),
    if (env['SIM_NIGHT'] != null) 'satiety_night': _envInt('SIM_NIGHT', 20),
  };
  if (env['SIM_SHIFTS_DAY'] != null) {
    final int perDay = _envInt('SIM_SHIFTS_DAY', 0);
    if (perDay > 0) {
      dc['max_shifts_per_day'] = perDay;
    } else {
      dc.remove('max_shifts_per_day');
    }
  }
  eco['day_cycle'] = dc;
  if (env['SIM_POCKET'] != null) {
    eco['pocket_money'] = <String, Object?>{
      ...(eco['pocket_money']! as Map<String, Object?>),
      'base': _envInt('SIM_POCKET', 400),
    };
  }
  return worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  ));
}

/// Один ход: название (для журнала) и само действие.
class Move {
  Move(this.name, this.run, {this.kind = ''});
  final String name;
  final String kind;
  final WorldResult Function() run;
  @override
  String toString() => name;
}

/// Все ходы, которые мир сейчас разрешает (`canDo` == null), — те же кнопки,
/// что у ребёнка на экранах. Демо и бонус взрослого не входят.
List<Move> legalMoves(WorldGame w, math.Random rng) {
  final List<Move> m = <Move>[];
  final ResourceSnapshot s = w.snapshot;
  bool can(WorldAction a, {String? id, String? variant}) =>
      w.canDo(a, id: id, variant: variant) == null;

  if (can(WorldAction.startWeek)) {
    m.add(Move('startWeek', w.startWeek, kind: 'startWeek'));
  }
  if (w.phase == WeekPhase.planning || w.phase == WeekPhase.weekStart) {
    if (can(WorldAction.plan)) {
      final int have = s.unallocated;
      final int a = rng.nextInt(have + 1);
      final int b = rng.nextInt(have - a + 1);
      m.add(Move('plan($a,$b,${have - a - b})',
          () => w.plan(needs: a, wants: b, goal: have - a - b),
          kind: 'plan'));
    }
  }
  if (can(WorldAction.payBills)) {
    m.add(Move('payBills', w.payBills, kind: 'payBills'));
    if (s.goal > 0) {
      m.add(Move('payBills(goal)', () => w.payBills(takeFromGoal: true),
          kind: 'payBills'));
    }
  }
  final LessonOffer? lesson = w.pendingLesson;
  if (lesson != null) {
    for (final LessonChoiceView c in lesson.choices) {
      if (!c.available) continue;
      m.add(
          Move('lesson ${c.id}', () => w.resolveLesson(c.id), kind: 'lesson'));
    }
  }
  final PendingEvent? ev = w.pendingEvent;
  if (ev != null) {
    for (final PendingEventChoice c in ev.choices) {
      if (can(WorldAction.resolveEvent, id: c.id)) {
        m.add(Move('event ${ev.id}/${c.id}', () => w.resolveEvent(c.id),
            kind: 'event'));
      }
    }
  }
  for (final WorldCatalogItem i in w.catalog) {
    if (i.isGoal &&
        s.activeGoalId != i.id &&
        can(WorldAction.chooseGoal, id: i.id)) {
      m.add(Move('goal ${i.id}', () => w.chooseGoal(i.id), kind: 'goal'));
    }
    if (i.category == WorldCatalogCategory.leisure &&
        can(WorldAction.leisure, id: i.id)) {
      m.add(Move('leisure ${i.id}', () => w.leisure(i.id), kind: 'leisure'));
    } else if (i.category != WorldCatalogCategory.leisure &&
        i.category != WorldCatalogCategory.food &&
        can(WorldAction.buy, id: i.id)) {
      m.add(Move('buy ${i.id}', () => w.buy(i.id), kind: 'buy'));
    }
  }
  for (final WorldFood f in w.config.foods) {
    if (can(WorldAction.eat, id: f.id)) {
      m.add(Move('eat ${f.id}', () => w.eat(f.id), kind: 'eat'));
    }
    if (s.foodId != f.id && can(WorldAction.chooseFood, id: f.id)) {
      m.add(Move('menu ${f.id}', () => w.chooseFood(f.id), kind: 'menu'));
    }
    if (can(WorldAction.stockFridge, id: f.id)) {
      m.add(
          Move('fridge ${f.id}', () => w.stockFridge(f.id, 1), kind: 'fridge'));
    }
  }
  for (final JobOffer o in w.jobBoard) {
    if (o.blocked) continue;
    if (!can(WorldAction.job, id: o.jobId, variant: o.variant)) continue;
    final double score = rng.nextDouble();
    m.add(Move('job ${o.jobId}${o.variant == null ? '' : '/${o.variant}'}',
        () => w.completeJob(o.jobId, variant: o.variant, score: score),
        kind: 'job'));
  }
  if (w.phase == WeekPhase.living || w.phase == WeekPhase.review) {
    if (s.free > 0) {
      final int amt = 1 + rng.nextInt(s.free);
      m.add(Move('deposit $amt', () => w.depositToGoal(amt), kind: 'deposit'));
    }
  }
  if (w.phase == WeekPhase.living && s.goal > 0) {
    final int amt = 1 + rng.nextInt(s.goal);
    m.add(
        Move('withdraw $amt', () => w.withdrawFromGoal(amt), kind: 'withdraw'));
  }
  if (can(WorldAction.restAtHome)) {
    m.add(Move('rest', w.restAtHome, kind: 'rest'));
  }
  if (w.phase == WeekPhase.living) {
    m.add(Move('petFinni', w.petFinni, kind: 'pet'));
  }
  if (can(WorldAction.sleep)) {
    m.add(Move('sleep', w.sleep, kind: 'sleep'));
  }
  return m;
}

typedef Strategy = Move? Function(
    WorldGame w, List<Move> legal, math.Random rng, WorldAutopilot ap);

/// Ходы, после которых неделя ближе к концу: тратят ⚡ или ведут фазу.
const Set<String> _advancing = <String>{
  'startWeek',
  'plan',
  'payBills',
  'lesson',
  'event',
  'job',
  'eat',
  'leisure',
  'rest',
  'fridge',
  'sleep',
};

Move? _first(List<Move> l, String kind) {
  for (final Move m in l) {
    if (m.kind == kind) return m;
  }
  return null;
}

/// Ходы, без которых неделя не идёт: план, урок, событие, счета, новая неделя.
Move? _mandatory(WorldGame w, List<Move> l, math.Random rng) {
  for (final String k in const <String>[
    'startWeek',
    'lesson',
    'event',
    'payBills'
  ]) {
    final List<Move> c = l.where((Move m) => m.kind == k).toList();
    if (c.isNotEmpty) return c[rng.nextInt(c.length)];
  }
  return null;
}

WorldResult _planAll(WorldGame w, {required bool saveAll}) {
  final ResourceSnapshot s = w.snapshot;
  final int have = s.unallocated;
  if (saveAll) return w.plan(needs: 0, wants: 0, goal: have);
  final int need = math.min(have, s.weeklyBill);
  return w.plan(needs: need, wants: 0, goal: 0);
}

final Map<String, Strategy> strategies = <String, Strategy>{
  // Любая доступная кнопка; в половине ходов — та, что двигает время
  // (иначе выбор цели и меню по кругу забивает неделю бесплатными ходами).
  'random': (WorldGame w, List<Move> l, math.Random rng, _) {
    if (l.isEmpty) return null;
    final List<Move> busy =
        l.where((Move m) => _advancing.contains(m.kind)).toList();
    if (busy.isNotEmpty && rng.nextBool()) {
      return busy[rng.nextInt(busy.length)];
    }
    return l[rng.nextInt(l.length)];
  },
  // Деньги прежде всего: смены, пока дают; ест, только когда голоден; без досуга.
  'greedy': (WorldGame w, List<Move> l, math.Random rng, _) {
    final Move? must = _mandatory(w, l, rng);
    if (must != null) return must;
    if (_first(l, 'plan') != null) {
      return Move('plan(need=bill)', () => _planAll(w, saveAll: false));
    }
    final Move? job = _first(l, 'job');
    if (job != null) return job;
    final ResourceSnapshot s = w.snapshot;
    if ((s.satiety ?? 100) < s.satietyHungryAt) {
      final Move? eat = _first(l, 'eat');
      if (eat != null) return eat;
    }
    return _first(l, 'sleep') ?? (l.isEmpty ? null : l.first);
  },
  // Ленивый: только обязательное и «Спать».
  'lazy': (WorldGame w, List<Move> l, math.Random rng, _) {
    final Move? must = _mandatory(w, l, rng);
    if (must != null) return must;
    if (_first(l, 'plan') != null) {
      return Move('plan(0,0,0)', () => w.plan(needs: 0, wants: 0, goal: 0));
    }
    return _first(l, 'sleep') ?? (l.isEmpty ? null : l.first);
  },
  // «Правильный»: автопилот демо — так, как учит игра.
  'correct': (WorldGame w, List<Move> l, math.Random rng, WorldAutopilot ap) {
    final LessonOffer? lesson = w.pendingLesson;
    if (lesson != null) return _first(l, 'lesson');
    final AutopilotMove mv = ap.nextMove();
    return Move(
        'autopilot ${mv.action.name}${mv.id == null ? '' : ' ${mv.id}'}',
        () => ap.step().result);
  },
  // Никогда не ест сам (только домашняя еда по правилам мира).
  'noeat': (WorldGame w, List<Move> l, math.Random rng, _) {
    final List<Move> c =
        l.where((Move m) => m.kind != 'eat' && m.kind != 'fridge').toList();
    return c.isEmpty ? null : c[rng.nextInt(c.length)];
  },
  // Только копит: всё в ЦЕЛЬ, без покупок и досуга, смены — да.
  'saver': (WorldGame w, List<Move> l, math.Random rng, _) {
    final Move? must = _mandatory(w, l, rng);
    if (must != null) return must;
    if (_first(l, 'plan') != null) {
      return Move('plan(goal=all)', () => _planAll(w, saveAll: true));
    }
    final ResourceSnapshot s = w.snapshot;
    if (s.free > 0 && _first(l, 'deposit') != null) {
      return Move('deposit all', () => w.depositToGoal(w.snapshot.free));
    }
    final Move? job = _first(l, 'job');
    if (job != null) return job;
    return _first(l, 'sleep') ?? (l.isEmpty ? null : l.first);
  },
};

/// Ходы, которые выводят неделю к итогам и дальше.
const Set<String> _exits = <String>{'plan', 'sleep', 'payBills', 'startWeek'};

/// Что проверяется в каждом прогоне.
const List<String> flagNames = <String>[
  'stuck', // нет ни одного доступного хода, а неделя не кончилась
  'hunger_no_exit', // утро голодным, еда недели кончилась, а дни остались
  'hunger_broke', // утро голодным, монет на еду нет (выход — копилка, вечер дома)
  'hunger_3_mornings', // три утра подряд голодным
  'negative', // минус в кармане, ⚡, сытости или 😊
  'event_loop', // то же событие дважды за неделю / не ушло после выбора
  'no_review', // итоги недели не достигнуты, выхода (план, «Спать», счета, новая неделя) не было
  'dawdle', // стратегия кружит бесплатными ходами, хотя выход был (не тупик)
  'no_free_choice', // урок или событие, где все варианты погашены
  'cando_lies', // canDo разрешил, действие отказало (кроме сумм)
  'exception', // движок бросил исключение
];

class RunResult {
  RunResult(this.strategy, this.seed);
  final String strategy;
  final int seed;
  final Map<String, String> flags = <String, String>{};
  int steps = 0;
  int weeksClosed = 0;
  int finalStage = 0;
  void flag(String f, String detail) => flags.putIfAbsent(f, () => detail);
}

RunResult runOne(WorldConfig cfg, String strategy, int seed, int weeks,
    {bool trace = false}) {
  final RunResult r = RunResult(strategy, seed);
  final math.Random rng = math.Random(seed);
  final WorldGame w = WorldGame(config: cfg);
  final WorldAutopilot ap = WorldAutopilot(w);
  final Strategy pick = strategies[strategy]!;
  int stepsThisWeek = 0;
  // Выход считается в текущей фазе: план в начале недели не выводит из
  // «живём», если «Спать» заперт.
  bool exitSeen = false;
  WeekPhase? exitPhase;
  int lastDayKey = -1;
  int hungryRun = 0;
  final Set<String> eventsThisWeek = <String>{};
  int eventWeek = -1;
  String? lastEventId;
  void log(String s) {
    if (trace) stdout.writeln(s);
  }

  try {
    while (r.weeksClosed < weeks) {
      final ResourceSnapshot s = w.snapshot;
      // Утро: новый день или первый день недели после плана.
      if (w.phase == WeekPhase.living) {
        final int key = s.weekNo * 100 + s.dayInWeek;
        if (key != lastDayKey) {
          lastDayKey = key;
          final int? sat = s.satiety;
          if (sat != null && sat < s.satietyHungryAt) {
            hungryRun++;
            final bool canEat = w.config.foods.any(
                (WorldFood f) => w.canDo(WorldAction.eat, id: f.id) == null);
            if (!canEat && s.mealsLeft > 0) {
              r.flag(
                  'hunger_broke',
                  'неделя ${s.weekNo} день ${s.dayInWeek}: сытость $sat, приёмов '
                      '${s.mealsLeft}, монет ${s.need + s.want + s.free}, копилка ${s.goal}');
            }
            if (!canEat && s.mealsLeft == 0) {
              r.flag(
                  'hunger_no_exit',
                  'неделя ${s.weekNo} день ${s.dayInWeek}: сытость $sat, '
                      'поесть нельзя (${w.canDo(WorldAction.eat, id: w.config.foods.first.id)?.code})');
            }
            if (hungryRun >= 3) {
              r.flag('hunger_3_mornings',
                  'неделя ${s.weekNo} день ${s.dayInWeek}: 3 утра подряд голодным');
            }
          } else {
            hungryRun = 0;
          }
        }
        final PendingEvent? ev = w.pendingEvent;
        if (s.weekNo != eventWeek) {
          eventWeek = s.weekNo;
          eventsThisWeek.clear();
        }
        if (ev != null && ev.id != lastEventId) {
          if (!eventsThisWeek.add(ev.id)) {
            r.flag('event_loop', 'неделя ${s.weekNo}: «${ev.id}» второй раз');
          }
        }
        lastEventId = ev?.id;
      }
      if (s.need < 0 ||
          s.want < 0 ||
          s.goal < 0 ||
          s.free < 0 ||
          s.unallocated < 0 ||
          s.energy < -_eps ||
          (s.satiety ?? 0) < 0 ||
          s.happiness < 0) {
        r.flag('negative',
            'неделя ${s.weekNo} день ${s.dayInWeek}: need ${s.need} want ${s.want} goal ${s.goal} free ${s.free} ⚡ ${s.energy} сыт ${s.satiety} 😊 ${s.happiness}');
      }
      final LessonOffer? les = w.pendingLesson;
      if (les != null &&
          !les.choices.any((LessonChoiceView c) => c.available)) {
        r.flag('no_free_choice', 'урок ${les.jobId}: все варианты погашены');
      }
      final PendingEvent? pev = w.pendingEvent;
      if (pev != null &&
          !pev.choices.any((PendingEventChoice c) => c.available)) {
        r.flag('no_free_choice', 'событие ${pev.id}: все варианты погашены');
      }
      final List<Move> legal = legalMoves(w, rng);
      if (legal.isEmpty) {
        r.flag(
            'stuck',
            'фаза ${w.phase.name}, неделя ${s.weekNo} день ${s.dayInWeek}, ⚡ ${s.energy}, '
                'урок ${w.pendingLesson != null}, событие ${w.pendingEvent?.id}, '
                'sleep: ${w.canDo(WorldAction.sleep)?.code}');
        break;
      }
      if (w.phase != exitPhase) {
        exitPhase = w.phase;
        exitSeen = false;
      }
      if (legal.any((Move m) => _exits.contains(m.kind))) exitSeen = true;
      final Move? mv = pick(w, legal, rng, ap);
      if (mv == null) {
        r.flag('stuck', 'стратегии нечего выбрать: ${legal.join(', ')}');
        break;
      }
      final String? evBefore = w.pendingEvent?.id;
      final WorldResult res = mv.run();
      r.steps++;
      stepsThisWeek++;
      log('${s.weekNo}.${s.dayInWeek} ${w.phase.name} ⚡${s.energy.toStringAsFixed(1)} '
          'сыт ${s.satiety} | $mv → ${res.ok ? 'ok' : 'ОТКАЗ'} ${res.reasonCode}');
      if (!res.ok &&
          legal.any((Move l) => identical(l, mv)) &&
          !const <String>{'plan', 'deposit', 'withdraw'}.contains(mv.kind)) {
        r.flag('cando_lies', '$mv: ${res.reasonCode} ${res.reason}');
      }
      if (res.ok &&
          mv.kind == 'event' &&
          evBefore != null &&
          w.pendingEvent?.id == evBefore) {
        r.flag('event_loop', 'событие «$evBefore» не ушло после выбора');
      }
      if (w.weekHistory.length > r.weeksClosed) {
        r.weeksClosed = w.weekHistory.length;
        stepsThisWeek = 0;
        exitSeen = false;
      }
      if (stepsThisWeek > stepsPerWeek) {
        r.flag(
            exitSeen ? 'dawdle' : 'no_review',
            'неделя ${w.snapshot.weekNo}: $stepsPerWeek ходов без итогов, фаза ${w.phase.name}, '
            '«Спать» ${w.canDo(WorldAction.sleep)?.code ?? 'доступен'}');
        break;
      }
    }
  } catch (e, st) {
    r.flag('exception', '$e ${st.toString().split('\n').take(3).join(' / ')}');
  }
  r.finalStage = w.snapshot.stage.index;
  return r;
}

/// Защищает: в режиме дней у ребёнка всегда есть ход к итогам недели, баланс
/// не уходит в минус, `canDo` не обещает того, что действие отклонит.
/// Уронит: новая проверка фазы или лимита, которая запирает неделю (нет
/// «Спать»/счетов), событие без доступного варианта, списание в минус.
void main() {
  test('softlock sim', () {
    final WorldConfig cfg = buildConfig();
    final int seeds = _envInt('SIM_SEEDS', 20);
    final int weeks = _envInt('SIM_WEEKS', 10);
    final String? one = Platform.environment['SIM_SEED'];
    final bool trace = _env('SIM_TRACE', '') == '1';
    final List<String> names =
        _env('SIM_STRATEGIES', strategies.keys.join(',')).split(',');
    final Map<String, Object?> summary = <String, Object?>{
      'params': <String, Object?>{
        'days': cfg.daysPerWeek,
        'pocket': cfg.pocketMoney,
        'sleep_rule': cfg.dayCycle.sleepRule != null,
        'energy_max': cfg.energyMax,
        'shifts_per_day': cfg.dayCycle.maxShiftsPerDay,
        'seeds': one == null ? seeds : 1,
        'weeks': weeks,
      },
    };
    final Map<String, Object?> per = <String, Object?>{};
    for (final String name in names) {
      final List<int> seedList = one == null
          ? List<int>.generate(
              seeds, (int i) => _envInt('SIM_SEED_FROM', 0) + i)
          : <int>[int.parse(one)];
      final Map<String, int> counts = <String, int>{
        for (final String f in flagNames) f: 0
      };
      final Map<String, List<Map<String, Object?>>> examples =
          <String, List<Map<String, Object?>>>{};
      final List<RunResult> all = <RunResult>[];
      int steps = 0;
      int stage = 0;
      for (final int seed in seedList) {
        final RunResult r = runOne(cfg, name, seed, weeks, trace: trace);
        all.add(r);
        steps += r.steps;
        stage += r.finalStage;
        r.flags.forEach((String f, String d) {
          counts[f] = counts[f]! + 1;
          final List<Map<String, Object?>> ex =
              examples.putIfAbsent(f, () => <Map<String, Object?>>[]);
          if (ex.length < 3) {
            ex.add(<String, Object?>{'seed': r.seed, 'detail': d});
          }
        });
      }
      all.sort((RunResult a, RunResult b) {
        final int c = b.flags.length.compareTo(a.flags.length);
        return c != 0 ? c : a.weeksClosed.compareTo(b.weeksClosed);
      });
      per[name] = <String, Object?>{
        'runs': seedList.length,
        'flags': counts,
        'examples': examples,
        'avg_steps': steps / seedList.length,
        'avg_final_stage': stage / seedList.length,
        'worst': all
            .take(3)
            .map((RunResult r) => <String, Object?>{
                  'seed': r.seed,
                  'weeks_closed': r.weeksClosed,
                  'flags': r.flags,
                })
            .toList(),
      };
      stdout.writeln('$name: ${jsonEncode(counts)}');
    }
    summary['strategies'] = per;
    final String out = const JsonEncoder.withIndent('  ').convert(summary);
    final String? path = Platform.environment['SIM_OUT'];
    if (path != null) File(path).writeAsStringSync(out);
    if (one != null || path == null) stdout.writeln(out);
    // Тупики из правил (не следствия выбора игрока) — ноль в любой стратегии.
    // Без переменных окружения это быстрый прогон CI: 20 зёрен на числах DEN-18.
    for (final MapEntry<String, Object?> e in per.entries) {
      final Map<String, int> f =
          (e.value! as Map<String, Object?>)['flags']! as Map<String, int>;
      for (final String hard in const <String>[
        'stuck',
        'no_review',
        'negative',
        'event_loop',
        'no_free_choice',
        'cando_lies',
        'exception',
      ]) {
        expect(f[hard], 0, reason: '${e.key}: $hard');
      }
    }
  }, timeout: Timeout.none);
}
