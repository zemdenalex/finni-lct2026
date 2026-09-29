import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/world_autopilot.dart';
import '../../../domain/world/world_entry.dart';
import '../../../domain/world/world_game.dart';
import '../shop/shop_kit.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import 'world_checklist.dart';
import '../../../core/world_theme.dart';

/// S16 — панель «Проверка» нового мира (`docs/game/demo-mode.md`, ТЗ 2.5.13.2).
///
/// «Начать игру заново», автопилот на 1 / 5 недель и «до 3-й стадии»
/// (доменный [WorldAutopilot]: только действия мира, журнал пишет сам
/// [WorldGame]), «Закончить неделю», переход на любой экран нового мира и
/// чек-лист Приложения А по журналу.
///
/// Автопилот и отметки «по журналу» есть только у [WorldGame]: на другом
/// [World] (тестовый фейк) кнопки автопилота выключены с объяснением.
///
/// Событие недели — из мира (`World.pendingEvent`, A10): кнопка ведёт в S10,
/// когда событие ждёт выбора.
///
/// «Открыть все профессии» (ТЗ 2.5.8.5) — [World.demoUnlockAllJobs], запись
/// `demo.unlockAllJobs` в журнале: переживает перезапуск, стирается сбросом.
/// Второй раз кнопка выключена — эффект один.
///
/// «Показать событие» (ТЗ 2.5.8.5) — список всех событий мира
/// ([World.demoEvents]); выбранное становится событием недели
/// ([World.demoShowEvent], запись `demo.showEvent`) и открывается S10, где
/// выбор идёт обычным путём. Только пока неделя идёт.
///
/// 🟡 Чего нет в контракте — кнопка видна, но выключена с объяснением:
/// «Полная ⚡».
///
/// 🔴 Отдельного тестового профиля у нового мира нет: сохранение одно, и
/// «Начать игру заново» стирает игру ребёнка. Поэтому кнопка названа
/// честно, а подтверждение говорит, что прогресс пропадёт (ТЗ 3.6.8).
class WorldDemoScreen extends StatefulWidget {
  const WorldDemoScreen({super.key});

  /// Экраны нового мира для перехода: маршрут → подпись.
  static const List<(String, String)> screens = <(String, String)>[
    (WorldRoutes.onboarding, 'S0 · Знакомство'),
    (WorldRoutes.room, 'S1 · Комната'),
    (WorldRoutes.city, 'S2 · Город'),
    (WorldRoutes.shop, 'S4 · Магазин'),
    (WorldRoutes.petShop, 'S5 · Зоомагазин'),
    (WorldRoutes.jobs, 'S6 · Требуется…'),
    (WorldRoutes.job, 'S7 · Смена (кассир)'),
    (WorldRoutes.leisure, 'S8 · Досуг'),
    (WorldRoutes.piggy, 'S9 · Копилка'),
    (WorldRoutes.event, 'S10 · Событие'),
    (WorldRoutes.review, 'S11 · Итоги недели'),
    (WorldRoutes.adult, 'S14 · Взрослым'),
    (WorldRoutes.settings, 'S15 · Настройки'),
    (WorldRoutes.sprites, 'Спрайты (разработка)'),
  ];

  @override
  State<WorldDemoScreen> createState() => _WorldDemoScreenState();
}

class _WorldDemoScreenState extends State<WorldDemoScreen> {
  /// Последний прогон автопилота — журнал по неделям.
  AutopilotReport? _report;
  WorldResult? _last;

  WorldState get _state => context.read<WorldState>();

  void _runWeeks(int n) => _autopilot((WorldAutopilot a) => a.playWeeks(n),
      (AutopilotReport r) => 'Сыграно недель: ${r.weeks.length}.');

  void _toStage3() => _autopilot(
      (WorldAutopilot a) => a.playToStage(WorldStage.moscow),
      (AutopilotReport r) => r.weeks.isEmpty
          ? 'Финни уже на 3-й стадии.'
          : 'До 3-й стадии — недель: ${r.weeks.length}.');

  /// Кнопки автопилота включены только на [WorldGame] — см. [build].
  Future<void> _autopilot(List<AutopilotStep> Function(WorldAutopilot a) play,
      String Function(AutopilotReport r) head) async {
    // Автопилот сам проходит знакомство (сразу начинает неделю) — значит, оно
    // пройдено. Иначе после «Начать игру заново» → «Сыграть 5 недель» →
    // перезапуска (Приложение А, шаг 11) заставка вела на шаг цели онбординга,
    // а не в комнату недели 6.
    if (!_state.onboarding.done) {
      await _state.setOnboardingStep(OnboardingProgress.stepDone);
      if (!mounted) return;
    }
    AutopilotReport? report;
    final WorldResult r = _state.act((World w) {
      final int before = w.snapshot.growthPoints;
      report = AutopilotReport.of(play(WorldAutopilot(w as WorldGame)),
          pointsBefore: before, now: w.snapshot);
      return _summary(report!, head(report!));
    });
    setState(() {
      _report = report;
      _last = r;
    });
  }

  static WorldResult _summary(AutopilotReport r, String head) => WorldResult(
        ok: r.stoppedBecause == null,
        reasonCode: 'demo.autopilot',
        reason: '$head Стадия: ${stageTitle(r.stage)}, очков роста '
            '${r.growthPoints}.',
        nextStep: r.stoppedBecause,
      );

  void _unlockJobs() {
    final WorldResult r = _state.act((World w) => w.demoUnlockAllJobs());
    setState(() => _last = r);
  }

  /// Список всех событий → выбранное становится событием недели → S10.
  Future<void> _pickEvent() async {
    final List<({String id, String title})> all = _state.world.demoEvents;
    final String? id = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Какое событие показать?'),
        contentPadding: const EdgeInsets.fromLTRB(0, Gap.sm, 0, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            key: const ValueKey<String>('demo:events:list'),
            shrinkWrap: true,
            children: <Widget>[
              for (final ({String id, String title}) e in all)
                ListTile(
                  key: ValueKey<String>('demo:event:${e.id}'),
                  minTileHeight: 48,
                  title: Text(e.title, style: kitText),
                  onTap: () => Navigator.of(c).pop(e.id),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('demo:events:cancel'),
            style: TextButton.styleFrom(minimumSize: kitButton),
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final WorldResult r = _state.act((World w) => w.demoShowEvent(id));
    setState(() => _last = r);
    // Уже ждёт выбора (отказ `demo.event.pending`) — тоже в S10.
    if (_state.world.pendingEvent?.id == id) _go(WorldRoutes.event);
  }

  void _endWeek() {
    final WorldResult r = _state.act((World w) => w.sleep());
    setState(() => _last = r);
  }

  Future<void> _reset() async {
    final bool yes = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Начать игру заново?'),
            content: const SingleChildScrollView(
              child: Text(
                'Весь прогресс на этом устройстве будет стёрт: недели, '
                'монеты, копилка, цель, покупки, питомцы и очки роста. '
                'Отдельного тестового профиля нет — это та же игра, в '
                'которую играет ребёнок. Отменить нельзя.',
                style: kitText,
              ),
            ),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>('demo:confirm:no'),
                style: TextButton.styleFrom(minimumSize: kitButton),
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const ValueKey<String>('demo:confirm:yes'),
                style: FilledButton.styleFrom(minimumSize: kitButton),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Стереть и начать'),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes || !mounted) return;
    final WorldState st = _state;
    await st.reset();
    // Тестовый ник, а онбординг — с первого шага.
    await st.setNickname('Тест');
    await st.setOnboardingStep(OnboardingProgress.stepIntro);
    if (!mounted) return;
    WorldDemoSession.resetDone = true;
    setState(() {
      _report = null;
      _last = const WorldResult(
        ok: true,
        reasonCode: 'demo.reset',
        reason: 'Игра начата заново: прогресс стёрт.',
        nextStep: 'Знакомство (S0) или автопилот',
      );
    });
  }

  void _go(String route) {
    Navigator.of(context).pushNamed(route,
        arguments:
            route == WorldRoutes.job ? const JobPlayArgs('cashier') : null);
  }

  @override
  Widget build(BuildContext context) {
    final WorldState st = context.watch<WorldState>();
    final ResourceSnapshot s = st.snapshot;
    final World w = st.world;
    final PendingEvent? event = w.pendingEvent;
    final bool engine = w is WorldGame;
    final Set<String>? kinds = w is WorldGame
        ? w.journal.map((WorldEntry e) => e.kind.name).toSet()
        : null;
    VoidCallback? auto(VoidCallback run) => engine ? run : null;
    final List<WorldCheckStep> steps = WorldChecklist.of(
      snapshot: s,
      phase: st.phase,
      finniName: st.finniName,
      kinds: kinds,
      resetDone: WorldDemoSession.resetDone,
      adultOpened: WorldDemoSession.adultOpened,
    );

    final bool land = WorldLayout.isLandscape(context);
    // Порядок: 0 профиль, 1 автопилот, 2 неделя, 3 экраны, 4 чек-лист.
    final List<Widget> sections = <Widget>[
      _Section(
        title: 'Игра на устройстве',
        children: <Widget>[
          Text(
              'Неделя ${s.weekNo} · ${_phaseTitle(st.phase)} · стадия '
              '${stageTitle(s.stage)} · очков роста ${s.growthPoints}',
              key: const ValueKey<String>('demo:status'),
              style: kitText),
          _Action(
            id: 'reset',
            icon: Icons.restart_alt_rounded,
            title: 'Начать игру заново',
            text: 'Стирает весь прогресс — и игру ребёнка тоже. '
                'С подтверждением.',
            onPressed: _reset,
          ),
        ],
      ),
      _Section(
        title: 'Автопилот',
        children: <Widget>[
          Text(
              engine
                  ? 'Действия ребёнка подряд: план → смены → в копилку → '
                      'досуг → «Спать» → счета.'
                  : 'Недоступно: автопилот играет только на настоящем мире.',
              style: kitSoft),
          _Action(
            id: 'auto1',
            icon: Icons.skip_next_rounded,
            title: 'Сыграть 1 неделю',
            onPressed: auto(() => _runWeeks(1)),
          ),
          _Action(
            id: 'auto5',
            icon: Icons.fast_forward_rounded,
            title: 'Сыграть 5 недель',
            onPressed: auto(() => _runWeeks(5)),
          ),
          _Action(
            id: 'stage3',
            icon: Icons.trending_up_rounded,
            title: 'Дойти до 3-й стадии',
            text: 'Играет недели, пока Финни не переедет в Москву.',
            onPressed: auto(_toStage3),
          ),
          if (!land && _report != null) _ReportView(report: _report!),
        ],
      ),
      _Section(
        title: 'Неделя',
        children: <Widget>[
          _Action(
            id: 'sleep',
            icon: Icons.bedtime_rounded,
            title: 'Закончить неделю',
            text: st.phase == WeekPhase.living
                ? 'Как «Спать»: дальше счета и итоги.'
                : 'Доступно, когда неделя идёт.',
            onPressed: st.phase == WeekPhase.living ? _endWeek : null,
          ),
          const _Action(
            id: 'energy',
            icon: Icons.bolt_rounded,
            title: 'Полная ⚡',
            text: 'Пока нет: демо-записи для ⚡ в журнале нет.',
          ),
          _Action(
            id: 'jobs',
            icon: Icons.work_rounded,
            title: w.allJobsUnlocked
                ? 'Все профессии открыты'
                : 'Открыть все профессии',
            text: w.allJobsUnlocked
                ? 'Курьер и выгульщик уже на доске «Требуется…». Снимет '
                    'только «Начать игру заново».'
                : 'Курьер без транспорта, выгульщик без собаки. Монеты, ⚡ '
                    'и 😊 не меняются, покупок нет.',
            onPressed: w.allJobsUnlocked ? null : _unlockJobs,
          ),
          _Action(
            id: 'events',
            icon: Icons.priority_high_rounded,
            title: event == null
                ? 'Событие недели'
                : 'Событие недели: ${event.title}',
            text: event == null
                ? 'Сейчас нет: событие приходит после плана недели, одно '
                    'на неделю, и уходит после выбора.'
                : 'Ждёт выбора — в городе над зданием «!».',
            onPressed: event == null ? null : () => _go(WorldRoutes.event),
          ),
          _Action(
            id: 'showEvent',
            icon: Icons.list_alt_rounded,
            title: 'Показать событие',
            text: st.phase == WeekPhase.living
                ? 'Любое из ${w.demoEvents.length} событий — сразу, без '
                    'условий и расписания. Монеты, ⚡ и 😊 не меняются, '
                    'выбор — как обычно.'
                : 'Доступно, когда неделя идёт: после плана недели.',
            onPressed: st.phase == WeekPhase.living ? _pickEvent : null,
          ),
        ],
      ),
      _Section(
        title: 'Экраны',
        children: <Widget>[
          for (final (String route, String name) in WorldDemoScreen.screens)
            _Action(
              id: 'go:$route',
              icon: Icons.open_in_new_rounded,
              title: name,
              onPressed: () => _go(route),
            ),
        ],
      ),
      _Checklist(steps: steps, onGo: _go),
    ];

    const String help =
        'Панель для эксперта (ТЗ 2.5.13.2): обязательные этапы подряд '
        'без ожидания.\n\n'
        'Автопилот играет недели теми же действиями, что ребёнок: план, '
        'хорошие смены, остальное в копилку, досуг, «Спать», счета — и '
        'открывает следующую неделю. Под ним — что случилось каждую '
        'неделю.\n\n'
        'Чек-лист отмечает шаги Приложения А сам, по журналу и ресурсам.';

    if (!land) {
      return WorldPage(
        id: 'demo',
        title: 'Проверка',
        snapshot: s,
        helpTitle: 'Режим проверки',
        result: _last,
        help: help,
        body: ListView(
          key: const ValueKey<String>('demo:list'),
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
          children: sections,
        ),
      );
    }
    // Альбомная: слева кнопки (автопилот — первым, он нужен чаще всего;
    // профиль, неделя, экраны), справа итог последнего действия, журнал
    // автопилота и чек-лист. Итог не отдаётся каркасу — иначе он занял бы
    // третью колонку.
    return WorldPage(
      id: 'demo',
      title: 'Проверка',
      snapshot: s,
      helpTitle: 'Режим проверки',
      help: help,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              key: const ValueKey<String>('demo:list'),
              padding:
                  const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.md),
              children: <Widget>[
                sections[1],
                sections[0],
                sections[2],
                sections[3],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey<String>('demo:log'),
              padding:
                  const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.md, Gap.md),
              children: <Widget>[
                if (_last != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: ResultCard(_last!),
                  ),
                if (_report != null)
                  _Section(
                    title: 'Журнал автопилота',
                    children: <Widget>[_ReportView(report: _report!)],
                  ),
                sections[4],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _phaseTitle(WeekPhase p) => switch (p) {
        WeekPhase.onboarding => 'до первой недели',
        WeekPhase.weekStart => 'начало недели',
        WeekPhase.planning => 'план',
        WeekPhase.living => 'неделя идёт',
        WeekPhase.review => 'итоги',
      };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Panel(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(header: true, child: Text(title, style: kitTitle)),
              const SizedBox(height: Gap.sm),
              ...children,
            ],
          ),
        ),
      );
}

/// Кнопка панели: иконка + подпись, под ней строка о том, что она делает.
class _Action extends StatelessWidget {
  const _Action({
    required this.id,
    required this.icon,
    required this.title,
    this.text,
    this.onPressed,
  });

  final String id;
  final IconData icon;
  final String title;
  final String? text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OutlinedButton.icon(
              key: ValueKey<String>('demo:$id'),
              onPressed: onPressed,
              icon: Icon(icon),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: const TextStyle(fontSize: 16)),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                alignment: Alignment.centerLeft,
              ),
            ),
            if (text != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: Gap.xs),
                child: Text(text!, style: kitSoft),
              ),
          ],
        ),
      );
}

/// Журнал автопилота: что случилось каждую неделю.
class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final AutopilotReport report;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey<String>('demo:report'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: Gap.md),
          Text(
            'Итог: стадия ${stageTitle(report.stage)}, очков роста '
            '${report.growthPoints}. '
            '${report.balanceNeverNegative ? 'Баланс ни разу не ушёл в минус.' : 'Баланс уходил в минус!'}',
            key: const ValueKey<String>('demo:report:total'),
            style: kitText,
          ),
          for (final AutopilotWeek wk in report.weeks)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                      'Неделя ${wk.weekNo}: +${wk.pointsGained} очк., всего '
                      '${wk.growthPoints}, ${stageTitle(wk.stage)}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  for (final String line in wk.lines)
                    Text('• $line', style: kitSoft),
                ],
              ),
            ),
        ],
      );
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.steps, required this.onGo});

  final List<WorldCheckStep> steps;
  final void Function(String route) onGo;

  @override
  Widget build(BuildContext context) => _Section(
        title: 'Приложение А: '
            '${WorldChecklist.doneCount(steps)} из ${steps.length}',
        children: <Widget>[
          const Text(
              'Отметки ставит приложение по журналу и ресурсам; шаги '
              '«подтверждает эксперт» — смотрите глазами.',
              style: kitSoft),
          for (final WorldCheckStep st in steps)
            Padding(
              key: ValueKey<String>('demo:step:${st.no}'),
              padding: const EdgeInsets.only(top: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                          st.done
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: st.done
                              ? WorldColors.needs
                              : WorldColors.textSoft),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text('${st.no}. ${st.title}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  Text('${st.statusLabel} · ${st.sourceLabel}', style: kitSoft),
                  for (final WorldCheckPart p in st.parts)
                    Text('${p.done ? '✓' : '–'} ${p.title}', style: kitSoft),
                  Text(st.evidence, style: kitSoft),
                  if (st.route != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(minimumSize: kitButton),
                        onPressed: () => onGo(st.route!),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Открыть экран',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
}

/// Одна неделя прогона автопилота — для журнала на панели.
class AutopilotWeek {
  const AutopilotWeek({
    required this.weekNo,
    required this.lines,
    required this.stage,
    required this.growthPoints,
    required this.pointsGained,
  });

  final int weekNo;

  /// Что произошло, по шагам — `reason` каждого действия.
  final List<String> lines;

  final WorldStage stage;
  final int growthPoints;
  final int pointsGained;
}

/// Прогон автопилота по неделям: шаги доменного [WorldAutopilot],
/// разрезанные по оплаченным счетам.
class AutopilotReport {
  const AutopilotReport({
    required this.weeks,
    required this.stage,
    required this.growthPoints,
    required this.balanceNeverNegative,
    this.stoppedBecause,
  });

  /// Разрезать [steps] на недели: неделя кончается оплаченными счетами.
  /// Шаги после последних счетов (открытие следующей недели) дописываются
  /// к последней неделе. [pointsBefore] — очки роста до прогона, [now] —
  /// мир после него.
  factory AutopilotReport.of(
    List<AutopilotStep> steps, {
    required int pointsBefore,
    required ResourceSnapshot now,
  }) {
    final List<AutopilotWeek> weeks = <AutopilotWeek>[];
    List<String> lines = <String>[];
    int points = pointsBefore;
    bool nonNegative = true;
    String? stopped;
    for (final AutopilotStep st in steps) {
      final ResourceSnapshot a = st.after;
      if (a.need < 0 ||
          a.want < 0 ||
          a.free < 0 ||
          a.goal < 0 ||
          a.unallocated < 0) {
        nonNegative = false;
      }
      if (st.result.ok) {
        lines.add(st.result.reason);
      } else {
        stopped ??= st.result.reason;
        lines.add('Не вышло: ${st.result.reason}');
      }
      if (st.action == AutopilotAction.payBills && st.result.ok) {
        weeks.add(AutopilotWeek(
          weekNo: a.weekNo,
          lines: List<String>.unmodifiable(lines),
          stage: a.stage,
          growthPoints: a.growthPoints,
          pointsGained: a.growthPoints - points,
        ));
        points = a.growthPoints;
        lines = <String>[];
      }
    }
    if (lines.isNotEmpty && weeks.isNotEmpty) {
      final AutopilotWeek last = weeks.removeLast();
      weeks.add(AutopilotWeek(
        weekNo: last.weekNo,
        lines: List<String>.unmodifiable(<String>[...last.lines, ...lines]),
        stage: last.stage,
        growthPoints: last.growthPoints,
        pointsGained: last.pointsGained,
      ));
    }
    return AutopilotReport(
      weeks: List<AutopilotWeek>.unmodifiable(weeks),
      stage: now.stage,
      growthPoints: now.growthPoints,
      balanceNeverNegative: nonNegative,
      stoppedBecause: stopped,
    );
  }

  final List<AutopilotWeek> weeks;
  final WorldStage stage;
  final int growthPoints;

  /// Ни один конверт, кошелёк и копилка ни на одном шаге не ушли в минус.
  final bool balanceNeverNegative;

  /// Первый отказ мира за прогон; null — отказов не было.
  final String? stoppedBecause;
}
