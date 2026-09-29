import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/feel.dart';
import '../../core/finni_art.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../domain/content.dart';
import '../../domain/economy/economy_config.dart';
import '../../domain/economy/period_rules.dart';
import '../../domain/economy/savings_rules.dart';
import '../../domain/game.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../../domain/ledger/ledger_fold.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/task.dart';

/// Прогресс (§2.5.11) и объяснение состояния питомца (§2.5.10.3).
///
/// Порядок блоков — от «что только что произошло» к «что было раньше»:
/// итоги недели, причина настроения, стадии развития, цель, задания,
/// история журнала.
///
/// 🔴 Ни одного вычисления: очки, отклонения и прогноз приходят готовыми
/// из домена, тексты — из assets/content/copy.json. Экран только раскладывает.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  /// Выбранная неделя истории. null — «та, что закрылась последней».
  int? _period;

  /// Стадия, на которую Финни перешёл только что.
  ///
  /// 🔴 Забирается ровно один раз и именно здесь. Экран прогресса —
  /// единственный, который открывается **после** закрытия недели, а очки
  /// заботы начисляются только там: на главном экране питомец успел бы
  /// подрасти за кадром, пока ребёнок читает итоги.
  PetStage? _stageUp;

  /// 🔴 Создаётся в initState, а не лениво при объявлении: поле, до которого
  /// впервые дошли из dispose (стадия не менялась — карточки в дереве не
  /// было), создало бы тикер на уже отсоединённом элементе и уронило тест.
  late final AnimationController _grow;

  /// Перелёт: Финни чуть проскакивает свой новый размер и возвращается.
  /// Так рост читается как событие, а не как смена картинки.
  late final CurvedAnimation _growCurve;

  bool _grown = false;

  @override
  void initState() {
    super.initState();
    _grow = AnimationController(vsync: this, duration: Motion.stageUp);
    _growCurve = CurvedAnimation(parent: _grow, curve: Motion.stageCurve);
    final AppState app = context.read<AppState>();
    if (app.ready) _stageUp = app.takeStageUp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_grown || _stageUp == null) return;
    _grown = true;
    // Нулевая длительность — это не «быстрый рост», а его отсутствие:
    // Финни сразу нужного размера, карточка на месте (§3.6.7).
    _grow
      ..duration = context.motion(Motion.stageUp)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _growCurve.dispose();
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Прогресс')));
    }

    final Game g = app.game;
    final GameSnapshot snap = g.snapshot;
    final PeriodOutcome? outcome = app.lastOutcome;
    final int? closed = _lastClosedPeriod(g.ledger);
    final List<int> periods = _periodsOf(g.ledger);
    final int selected = _period ?? closed ?? snap.periodNo;

    return Scaffold(
      appBar: AppBar(title: const Text('Прогресс')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xl),
          children: <Widget>[
            // Новая стадия — первым, до итогов: это единственное, что
            // случается не каждую неделю, и ради этого стоит поднять глаза.
            if (_stageUp != null) ...<Widget>[
              _StageUpCard(
                petName: g.profile.petName,
                trustNote: app.content.say('trust.grew', <String, Object?>{
                  'fromParents': app.content.economy.trustFor(_stageUp!).fromParents,
                  'cap': app.content.economy.trustFor(_stageUp!).earnCap,
                  'max': app.content.economy.trustFor(_stageUp!).weeklyMax,
                }),
                stage: _stageUp!,
                profile: g.profile,
                meters: snap.meters,
                grow: _growCurve,
              ),
              const SizedBox(height: Gap.md),
            ],
            if (outcome != null) ...<Widget>[
              _OutcomeBlock(outcome: outcome, periodNo: closed),
              const SizedBox(height: Gap.md),
            ],
            _MoodBlock(
              app: app,
              outcome: outcome,
              snap: snap,
              tasksClosedPeriod:
                  closed == null ? 0 : _tasksInPeriod(g.ledger, closed),
            ),
            const SizedBox(height: Gap.md),
            _StagesBlock(
                profile: g.profile, snap: snap, content: app.content),
            const SizedBox(height: Gap.md),
            _GoalBlock(
              goal: g.goal,
              forecast: g.forecast,
              savings: snap.wallet.savings,
            ),
            const SizedBox(height: Gap.md),
            _DoneTasksBlock(profile: g.profile, content: app.content),
            const SizedBox(height: Gap.md),
            _WishTallyBlock(
                key: _WishTallyBlock.blockKey, tally: g.wishTally),
            const SizedBox(height: Gap.md),
            _HistoryBlock(
              content: app.content,
              entries: LedgerFold.ofPeriod(g.ledger, selected),
              periods: periods.isEmpty ? <int>[selected] : periods,
              selected: selected,
              onSelect: (int p) => setState(() => _period = p),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── чтение журнала ─────────────────────────────
// Ниже — только выборка из уже готовых данных: ни одной формулы экономики.

/// Номер последней закрытой недели. Берётся из журнала, а не из счётчика:
/// журнал — единственный источник правды (см. [LedgerEntry]).
int? _lastClosedPeriod(List<LedgerEntry> ledger) {
  int? result;
  for (final LedgerEntry e in ledger) {
    if (e.kind == LedgerKind.periodClosed) result = e.periodNo;
  }
  return result;
}

List<int> _periodsOf(List<LedgerEntry> ledger) {
  final Set<int> all = <int>{for (final LedgerEntry e in ledger) e.periodNo};
  final List<int> list = all.toList()..sort();
  return list;
}

int _tasksInPeriod(List<LedgerEntry> ledger, int periodNo) {
  int n = 0;
  for (final LedgerEntry e in ledger) {
    if (e.periodNo == periodNo && e.kind == LedgerKind.taskReward) n++;
  }
  return n;
}

GameTask? _taskOrNull(GameContent content, String id) {
  for (final GameTask t in content.tasks) {
    if (t.id == id) return t;
  }
  return null;
}

// ───────────────────────────── блоки экрана ─────────────────────────────

/// Карточка раздела с заголовком. Заголовки помечены `header: true` —
/// экранный диктор умеет прыгать по ним, и длинный экран становится
/// проходимым без свайпа по каждой строке.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final Pic? icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Pictogram(icon!, size: 26, color: AppColors.primary),
                  const SizedBox(width: Gap.sm),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            child,
          ],
        ),
      ),
    );
  }
}

/// «Финни научился» (§2.5.10): стадия сменилась на этой неделе.
///
/// Формулировка про умение, а не про рост, — как и в самих стадиях:
/// ребёнок здесь учитель, и научился Финни благодаря ему.
class _StageUpCard extends StatelessWidget {
  const _StageUpCard({
    required this.petName,
    required this.trustNote,
    required this.stage,
    required this.profile,
    required this.meters,
    required this.grow,
  });

  final String petName;

  /// «Родители доверили вам больше самостоятельности…» — из контента.
  final String trustNote;
  final PetStage stage;
  final GameProfile profile;
  final PetMeters meters;
  final Animation<double> grow;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          children: <Widget>[
            FinniView(
              species: profile.species,
              palette: profile.palette,
              stage: stage,
              meters: meters,
              accessories: profile.accessories,
              size: 96,
              grow: grow,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text('$petName научился!',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(stage.title,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.savings)),
                  const SizedBox(height: Gap.xs),
                  Text(stage.description,
                      style: const TextStyle(fontSize: 16, height: 1.3)),
                  const SizedBox(height: Gap.xs),
                  Text(trustNote,
                      style: const TextStyle(fontSize: 16, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §2.5.11.1: итоги последнего игрового периода.
class _OutcomeBlock extends StatelessWidget {
  const _OutcomeBlock({required this.outcome, required this.periodNo});

  final PeriodOutcome outcome;
  final int? periodNo;

  @override
  Widget build(BuildContext context) {
    return _Section(
      icon: Pic.trophy,
      title: periodNo == null
          ? 'Итоги недели'
          : 'Итоги недели $periodNo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Очков заботы за неделю: ${outcome.points} из '
            '${outcome.carePoints.length}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: Gap.sm),
          // 🔴 Объяснение показывается у каждого очка — и у полученного,
          // и у неполученного (§2.2). Формулировки приходят из домена,
          // экран их не переписывает и не добавляет «ты не справился».
          for (final CarePoint p in outcome.carePoints) ...<Widget>[
            _CarePointRow(point: p),
            const SizedBox(height: Gap.sm),
          ],
          const Divider(),
          const SizedBox(height: Gap.xs),
          Semantics(
            header: true,
            child: const Text('План и как вышло',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: Gap.sm),
          for (final EnvelopeDeviation d in outcome.deviations) ...<Widget>[
            _DeviationRow(deviation: d),
            const SizedBox(height: Gap.sm),
          ],
        ],
      ),
    );
  }
}

class _CarePointRow extends StatelessWidget {
  const _CarePointRow({required this.point});

  final CarePoint point;

  @override
  Widget build(BuildContext context) {
    // §3.6.5: не только цвет и не только галочка — рядом подпись словами.
    final String mark = point.earned ? '+1 очко заботы' : 'в этот раз нет';
    return Semantics(
      label: '${point.title}: $mark. ${point.explanation}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Pictogram(
            point.earned ? Pic.check : Pic.circleEmpty,
            size: 28,
            color: point.earned ? AppColors.needs : AppColors.inkSoft,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${point.title}: $mark',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
                Text(
                  point.explanation,
                  style: const TextStyle(
                      fontSize: 16, height: 1.3, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviationRow extends StatelessWidget {
  const _DeviationRow({required this.deviation});

  final EnvelopeDeviation deviation;

  @override
  Widget build(BuildContext context) {
    final Envelope e = deviation.envelope;
    final bool saving = e == Envelope.savings;
    final String verb = saving ? 'Отложить' : 'Потратить';
    final String factVerb = saving ? 'отложено' : 'потрачено';
    // Норма считается асимметрично (см. PeriodRules.withinNorm), поэтому
    // и подпись разная: по копилке смотрим на недовложение, по тратам —
    // на перерасход. Факт, без оценки.
    final String verdict = deviation.withinNorm
        ? (!saving && deviation.actual < deviation.planned
            ? 'потрачено меньше — монетки остались'
            : 'как задумано')
        : saving
            ? 'отложилось меньше, чем задумано'
            : 'ушло больше, чем задумано';

    return Semantics(
      label: 'Конверт «${e.title}». $verb по плану ${deviation.planned}, '
          '$factVerb ${deviation.actual}. $verdict',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Gap.sm),
        decoration: BoxDecoration(
          color: AppColors.bgOf(e),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Pictogram(AppColors.picOf(e), size: 22, color: AppColors.of(e)),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text(
                    e.title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.of(e)),
                  ),
                ),
                Pictogram(
                  deviation.withinNorm ? Pic.check : Pic.info,
                  size: 22,
                  color: deviation.withinNorm
                      ? AppColors.needs
                      : AppColors.inkSoft,
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Text(
              'По плану ${deviation.planned}, вышло ${deviation.actual}',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              verdict,
              style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// §2.5.10.3: краткое объяснение причины изменения состояния питомца.
///
/// 🔴 Объяснение — фразами, а не арифметикой. «−1 +2» ничего не сообщает
/// семилетке, а «прошла неделя, но задания подняли настроение» — сообщает.
class _MoodBlock extends StatelessWidget {
  const _MoodBlock({
    required this.app,
    required this.outcome,
    required this.snap,
    required this.tasksClosedPeriod,
  });

  final AppState app;
  final PeriodOutcome? outcome;
  final GameSnapshot snap;
  final int tasksClosedPeriod;

  @override
  Widget build(BuildContext context) {
    final GameProfile p = app.game.profile;
    final List<String> reasons = <String>[];

    if (outcome != null) {
      // Затухание есть всегда — это и есть «прошла неделя».
      reasons.add(app.content.say('period.decay'));
      if (tasksClosedPeriod > 0) {
        reasons.add('Пройденные задания подняли Финни настроение.');
      }
      final bool saved = outcome!.carePoints
          .any((CarePoint c) => c.id == 'saved' && c.earned);
      if (saved) {
        reasons.add('Отложенные монетки тоже подняли настроение: '
            'цель стала ближе.');
      }
      if (tasksClosedPeriod == 0 && !saved) {
        reasons.add('Настроение поднимают задания и монетки, отложенные '
            'в копилку. Это можно сделать на любой неделе.');
      }
    } else {
      reasons.add('Финни меняется от того, что ты делаешь: еда и уборка '
          'держат сытость и чистоту, задания и копилка поднимают настроение.');
      reasons.add('Подробный разбор появится, когда закончится неделя.');
    }

    return _Section(
      icon: Pic.smile,
      title: 'Почему у ${p.petName} такое настроение',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: FinniView(
              species: p.species,
              palette: p.palette,
              stage: snap.stage,
              meters: snap.meters,
              accessories: p.accessories,
              size: 120,
            ),
          ),
          const SizedBox(height: Gap.sm),
          for (final Meter m in Meter.values) ...<Widget>[
            MeterRow(meter: m, value: snap.meters.byMeter(m)),
            const SizedBox(height: Gap.xs),
          ],
          const SizedBox(height: Gap.sm),
          // Причины идут списком абзацев без значка-маркера: стрелка перед
          // каждой строкой ничего не сообщала, а на 360 dp отъедала колонку
          // под текст, который и так переносится.
          for (final String r in reasons) ...<Widget>[
            Text(r, style: const TextStyle(fontSize: 16, height: 1.3)),
            const SizedBox(height: Gap.sm),
          ],
        ],
      ),
    );
  }
}

/// §2.5.10.1: не менее трёх состояний или стадий развития.
///
/// Будущие стадии показаны сразу и с порогом: ребёнок видит, что будет
/// дальше, а не получает сюрприз. Стадия не откатывается (§2.2) — поэтому
/// про пройденные написано «уже пройдено», а не «потеряно».
class _StagesBlock extends StatelessWidget {
  const _StagesBlock({
    required this.profile,
    required this.snap,
    required this.content,
  });

  final GameProfile profile;
  final GameSnapshot snap;
  final GameContent content;

  @override
  Widget build(BuildContext context) {
    return _Section(
      icon: Pic.spark,
      title: 'Как растёт ${profile.petName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Очков заботы всего: ${snap.carePoints}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: Gap.xs),
          // 🔴 Главный тезис команды: взрослеть — значит становиться
          // самостоятельнее. У каждой стадии полоса недели: серое —
          // доверили родители, золотое — можно заработать самим. Золотого
          // от стадии к стадии больше — это и есть рост.
          const Text(
            'С каждой стадией ты больше зарабатываешь сам: тебе доверяют '
            'всё больше самостоятельности.',
            style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
          const SizedBox(height: Gap.sm),
          for (final PetStage s in PetStage.values) ...<Widget>[
            _StageRow(
              stage: s,
              profile: profile,
              meters: snap.meters,
              current: s == snap.stage,
              open: snap.carePoints >= s.threshold,
              trust: content.economy.trustFor(s),
            ),
            if (s != PetStage.values.last) const SizedBox(height: Gap.sm),
          ],
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.profile,
    required this.meters,
    required this.current,
    required this.open,
    required this.trust,
  });

  final PetStage stage;
  final GameProfile profile;
  final PetMeters meters;
  final bool current;
  final bool open;
  final TrustLevel trust;

  @override
  Widget build(BuildContext context) {
    final String mark = current
        ? 'сейчас'
        : open
            ? 'пройдена'
            : 'откроется при ${stage.threshold} очках заботы';

    return Semantics(
      label: '${stage.title}, $mark. ${stage.description}. '
          'Родители доверяют ${trust.fromParents}, заработать можно до '
          '${trust.earnCap}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Gap.sm + 2),
        decoration: BoxDecoration(
          color: current ? const Color(0xFFFFF4D6) : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.button),
          border: Border.all(
            color: current ? AppColors.ink : AppColors.line,
            width: current ? 3 : 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Будущая стадия показана приглушённо — но показана: видно,
            // что именно изменится в самом Финни.
            Opacity(
              opacity: open ? 1 : 0.4,
              child: FinniView(
                species: profile.species,
                palette: profile.palette,
                stage: stage,
                meters: meters,
                accessories: profile.accessories,
                size: 64,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          stage.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: open ? AppColors.ink : AppColors.inkSoft,
                          ),
                        ),
                      ),
                      if (current) ...<Widget>[
                        const SizedBox(width: Gap.xs),
                        const Pictogram(Pic.star,
                            size: 20, color: AppColors.coinDeep),
                      ],
                    ],
                  ),
                  Text(
                    mark,
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    stage.description,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      color: open ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  TrustBar(
                    fromParents: trust.fromParents,
                    earnCap: trust.earnCap,
                    earned: trust.earnCap,
                    showLegend: false,
                    height: 14,
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    '${trust.fromParents} от родителей, заработать сам — до ${trust.earnCap}',
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §2.5.11.1: прогресс по текущей цели.
/// Сколько раз ребёнок дождался и сколько раз передумал.
///
/// 🔴 Единственное место во всей игре, где число рассказывает ребёнку о нём
/// самом, а не о питомце. Всё остальное на этом экране — про Финни: его
/// настроение, его стадия, его цель. А это — про то, как человек обходится
/// со своими желаниями, и узнать такое про себя больше неоткуда.
///
/// 🔴 Ни один из двух ответов не назван правильным, и числа не сравниваются
/// между собой словами вроде «чаще» или «всего лишь». §8.1 отдельной строкой
/// оценивает «отсутствие давления, стыда и манипулятивных механик», а
/// «передумал всего 2 раза из 9» — это ровно стыд, выданный за статистику.
class _WishTallyBlock extends StatelessWidget {
  const _WishTallyBlock({super.key, required this.tally});

  /// Ключ нужен тесту: он проверяет формулировки **этого** блока, а не всего
  /// экрана, иначе ловит чужие слова из соседних карточек.
  static const Key blockKey = ValueKey<String>('wish-tally');

  final (int kept, int dropped) tally;

  @override
  Widget build(BuildContext context) {
    final int kept = tally.$1;
    final int dropped = tally.$2;
    final int total = kept + dropped;

    return _Section(
      icon: Pic.hand,
      title: 'Решения про «хочу»',
      child: total == 0
          // Пустое состояние объясняет механику, а не извиняется за пустоту.
          ? const Text(
              'Когда захочешь что-то дорогое, можно не покупать сразу, '
              'а подождать неделю. Через неделю я спрошу, хочется ли ещё. '
              'Здесь будет видно, что было решено.',
              style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Подождать с покупкой получилось $total ${Coins.timesWord(total)}.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Gap.sm),
                _TallyRow(
                  pic: Pic.heart,
                  color: AppColors.wants,
                  count: kept,
                  text: 'через неделю всё ещё хотелось',
                ),
                const SizedBox(height: Gap.xs),
                _TallyRow(
                  pic: Pic.leaf,
                  color: AppColors.needs,
                  count: dropped,
                  text: 'через неделю уже не хотелось',
                ),
                const SizedBox(height: Gap.sm),
                const Text(
                  'И то и другое — нормально. Желание, которое пережило '
                  'неделю, скорее всего настоящее.',
                  style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
                ),
              ],
            ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({
    required this.pic,
    required this.color,
    required this.count,
    required this.text,
  });

  final Pic pic;
  final Color color;
  final int count;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Pictogram(pic, size: 22, color: color),
        const SizedBox(width: Gap.sm),
        // 🔴 Expanded обязателен: на 360 dp при увеличенном системном шрифте
        // строка не помещается и Row переполняется.
        Expanded(
          child: Text('$count — $text', style: const TextStyle(fontSize: 17)),
        ),
      ],
    );
  }
}

class _GoalBlock extends StatelessWidget {
  const _GoalBlock({
    required this.goal,
    required this.forecast,
    required this.savings,
  });

  final Goal? goal;
  final GoalForecast? forecast;
  final int savings;

  @override
  Widget build(BuildContext context) {
    if (goal == null || forecast == null) {
      return const _Section(
        icon: Pic.flag,
        title: 'Цель',
        child: Text(
          'Цель пока не выбрана. Её можно выбрать в «Копилке» — так видно, '
          'зачем откладывать.',
          style: TextStyle(fontSize: 16, height: 1.3),
        ),
      );
    }

    final Goal g = goal!;
    final GoalForecast f = forecast!;
    return _Section(
      icon: Pic.flag,
      title: g.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Карта монеток — та же, что на главном: закрашенные кружки
          // ребёнок считает, а проценты не читает.
          _CoinChart(saved: savings, total: g.price),
          const SizedBox(height: Gap.sm),
          Semantics(
            label: 'Накоплено $savings из ${g.price}',
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                Coins(savings),
                const Text('  из  ',
                    style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
                Coins(g.price, color: AppColors.inkSoft),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            f.reached
                ? 'Цель набрана!'
                : 'Осталось накопить ${f.remaining}',
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            f.reached
                ? 'Можно выбрать новую цель.'
                : f.weeks == null
                    ? f.reason!
                    : 'Если откладывать по ${f.averageDeposit}, '
                        'осталось примерно ${f.weeks} нед.',
            style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// Сетка монеток: закрашенные — накопленные.
///
/// Та же картинка, что на главном экране. Повтор осознанный: вынести её
/// в core/widgets.dart можно будет одним движением, но этот файл сейчас
/// пишут параллельно, и правка в нём стоила бы конфликта слияния.
class _CoinChart extends StatelessWidget {
  const _CoinChart({required this.saved, required this.total});

  final int saved;
  final int total;

  @override
  Widget build(BuildContext context) {
    final int step = total <= 40 ? 1 : (total / 40).ceil();
    final int dots = (total / step).ceil();
    final int filled = (saved / step).floor().clamp(0, dots);
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: List<Widget>.generate(dots, (int i) {
        final bool on = i < filled;
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? AppColors.coin : Colors.transparent,
            border: Border.all(
                color: on ? AppColors.coin : AppColors.line, width: 2),
          ),
        );
      }),
    );
  }
}

/// §2.5.11.1: завершённые задания. Сгруппированы по темам (§2.5.8.1),
/// чтобы было видно не только «сколько», но и «чему научился».
class _DoneTasksBlock extends StatelessWidget {
  const _DoneTasksBlock({required this.profile, required this.content});

  final GameProfile profile;
  final GameContent content;

  @override
  Widget build(BuildContext context) {
    final Map<TaskTopic, Map<String, int>> byTopic =
        <TaskTopic, Map<String, int>>{};
    for (final String id in profile.completedTaskIds) {
      final GameTask? t = _taskOrNull(content, id);
      if (t == null) continue;
      final Map<String, int> titles =
          byTopic.putIfAbsent(t.topic, () => <String, int>{});
      titles[t.title] = (titles[t.title] ?? 0) + 1;
    }

    return _Section(
      icon: Pic.task,
      title: 'Выполненные задания',
      child: byTopic.isEmpty
          ? const Text(
              'Пока ни одного. Задания открыты всегда — их можно проходить '
              'сколько захочется.',
              style: TextStyle(fontSize: 16, height: 1.3),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final TaskTopic topic in TaskTopic.values)
                  if (byTopic.containsKey(topic)) ...<Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        topic.title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    for (final MapEntry<String, int> e
                        in byTopic[topic]!.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Pictogram(Pic.check,
                                size: 20, color: AppColors.needs),
                            const SizedBox(width: Gap.sm),
                            Expanded(
                              child: Text(
                                e.value > 1
                                    ? '${e.key}, ${e.value} ${Coins.timesWord(e.value)}'
                                    : e.key,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Gap.sm),
                  ],
              ],
            ),
    );
  }
}

/// История недели (§2.5.11.1) — и доказательство §2.5.4.3.
///
/// 🔴 Любое число в игре разворачивается вот в этот список: у каждой записи
/// журнала есть reasonCode, и текст к нему лежит в copy.json. Баланс не может
/// измениться без строки здесь — другого способа его изменить в коде нет.
class _HistoryBlock extends StatelessWidget {
  const _HistoryBlock({
    required this.content,
    required this.entries,
    required this.periods,
    required this.selected,
    required this.onSelect,
  });

  final GameContent content;
  final List<LedgerEntry> entries;
  final List<int> periods;
  final int selected;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    // Одинаковые подряд идущие строки схлопываются: перекладывание монеток
    // пишет в журнал две записи (откуда и куда), а ребёнку это одно событие.
    final List<LedgerEntry> shown = <LedgerEntry>[];
    String? previous;
    for (final LedgerEntry e in entries) {
      final String text = content.say(e.reasonCode, e.args);
      if (text == previous) continue;
      previous = text;
      shown.add(e);
    }

    return _Section(
      icon: Pic.history,
      title: 'Что происходило',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: <Widget>[
              for (final int p in periods)
                _WeekChip(
                  periodNo: p,
                  selected: p == selected,
                  onTap: () => onSelect(p),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (shown.isEmpty)
            const Text(
              'На этой неделе записей пока нет.',
              style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
            )
          else
            for (final LedgerEntry e in shown) ...<Widget>[
              _EntryRow(entry: e, text: content.say(e.reasonCode, e.args)),
              const SizedBox(height: Gap.sm),
            ],
        ],
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({
    required this.periodNo,
    required this.selected,
    required this.onTap,
  });

  final int periodNo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Неделя $periodNo${selected ? ', выбрана' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.min),
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.md, vertical: Gap.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.line,
                width: 2,
              ),
            ),
            child: Text(
              'Неделя $periodNo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.text});

  final LedgerEntry entry;
  final String text;

  @override
  Widget build(BuildContext context) {
    final int? amount = _amount(entry);
    final Color tint = entry.envelope == null
        ? AppColors.inkSoft
        : AppColors.of(entry.envelope!);

    return Semantics(
      label: amount == null
          ? text
          : '$text ${amount > 0 ? 'плюс' : 'минус'} ${amount.abs()} '
              '${Coins.word(amount.abs())}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Pictogram(_pic(entry.kind), size: 24, color: tint),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 16, height: 1.3)),
          ),
          if (amount != null) ...<Widget>[
            const SizedBox(width: Gap.sm),
            Text(
              // Знак «−» вместо дефиса: минус ребёнок видит, дефис — нет.
              amount > 0 ? '+$amount' : '−${amount.abs()}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: amount > 0 ? AppColors.needs : AppColors.wants,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Число показывается только там, где его нет в самом тексте: у плана
  /// и перекладывания суммы уже названы фразой, и вторая копия рядом
  /// читается как ещё одно движение монеток.
  ///
  /// 🔴 Задание сверх недельного лимита монеток не приносит, и «+0» рядом
  /// с ним читалось бы как «ничего не вышло». Число скрыто: сама запись
  /// словами объясняет, что задание засчитано ради интереса.
  static int? _amount(LedgerEntry e) => switch (e.kind) {
        LedgerKind.taskReward => e.unallocated == 0 ? null : e.unallocated,
        LedgerKind.pocketMoney => e.unallocated,
        LedgerKind.purchase => e.coins,
        LedgerKind.savingsDeposit || LedgerKind.savingsWithdraw => e.savings,
        // Сумма со знаком минус: из копилки ушла цена мечты. Скрывать её
        // нельзя — §2.5.4.3, баланс не меняется без объяснения.
        LedgerKind.goalFulfilled => e.savings,
        LedgerKind.unexpectedCost => e.coins != 0 ? e.coins : e.savings,
        LedgerKind.planConfirmed ||
        LedgerKind.envelopeMove ||
        LedgerKind.purchaseDeclined ||
        LedgerKind.unexpectedDeferred ||
        LedgerKind.weeklyDecay ||
        LedgerKind.periodClosed ||
        LedgerKind.parentUnlockedTask ||
        LedgerKind.wishAdded ||
        LedgerKind.wishKept ||
        LedgerKind.wishDropped =>
          null,
      };

  static Pic _pic(LedgerKind k) => switch (k) {
        LedgerKind.pocketMoney => Pic.wallet,
        LedgerKind.taskReward => Pic.task,
        LedgerKind.planConfirmed => Pic.list,
        LedgerKind.purchase => Pic.basket,
        // Не «запрещено»: попытка купить — это нормальная попытка,
        // а не проступок (§2.5.6.4).
        LedgerKind.purchaseDeclined => Pic.info,
        LedgerKind.envelopeMove => Pic.swap,
        // Рука — «подожди, не спеши»; она же стоит на самом предложении
        // подождать, так что знак в истории совпадает с тем, что ребёнок
        // нажимал.
        LedgerKind.wishAdded => Pic.hand,
        LedgerKind.wishKept => Pic.heart,
        // Не крестик: передумать — не отмена и не ошибка.
        LedgerKind.wishDropped => Pic.leaf,
        // Звезда, а не банка: это не движение копилки, а то, ради чего копили.
        LedgerKind.goalFulfilled => Pic.star,
        // 🔴 Положить и взять — одна банка, но разные стрелки не нужны:
        // сумма рядом уже со знаком. Одинаковая пиктограмма показывает,
        // что это одна и та же копилка, а не два разных места.
        LedgerKind.savingsDeposit || LedgerKind.savingsWithdraw => Pic.jar,
        LedgerKind.unexpectedCost => Pic.umbrella,
        LedgerKind.unexpectedDeferred => Pic.clock,
        LedgerKind.weeklyDecay => Pic.clock,
        LedgerKind.periodClosed => Pic.flag,
        LedgerKind.parentUnlockedTask => Pic.family,
      };
}
