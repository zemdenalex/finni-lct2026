import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../day_end.dart';
import '../home/world_hud.dart';
import '../pic_text.dart';
import '../world_explain.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import 'board/job_offer_card.dart';
import 'job_games.dart';
import 'mini_games.dart';
import 'shift_choice_view.dart';
import '../../../core/world_theme.dart';
import '../world_dock.dart';

/// Смена (S7) и её итог (S7r): карточка → мини-игра → оплата и ползунок
/// «на цель» (`docs/game/job-cashier.md`, `job-consultant.md`).
///
/// 🔴 Числа карточки — только из `world.offer`, экран их не пересчитывает.
/// ⚡ списывается лишь в `completeJob`: вышел из игры — ничего не потрачено.
/// Мини-игры — реестр [miniGames] (`mini_games.dart`).
class JobPlayScreen extends StatefulWidget {
  /// Раунд мини-игры работы [jobId]: её смены за игру, хорошие и нет. После
  /// неудачной смены следующая даёт другой набор (эксперт 16.10: «не хотим
  /// угадайку»), и так же после смен других работ: по общему счёту смен
  /// ступень из двух наборов через одну смену давала тот же (NAS-7, Настя
  /// 18.10). Первая смена профессии — раунд 0 (ценник-якорь, NAS-1).
  static int roundFor(ResourceSnapshot s, String jobId) =>
      s.shiftsByJobTotal[jobId] ?? 0;

  const JobPlayScreen({super.key, this.args});

  /// Для тестов; из таблицы маршрутов — аргумент маршрута.
  final JobPlayArgs? args;

  @override
  State<JobPlayScreen> createState() => _JobPlayScreenState();
}

enum _Stage { offer, play, result }

/// Подсказка, когда урок ждёт ответа, а ребёнок хочет уйти (Настя 20.10:
/// «нужна подсказка, что нужно выбрать что-то из 3 вариантов»). Варианты в
/// альбомной — в правой колонке, в портрете — выше кнопок.
String lessonFirstText({required bool landscape}) =>
    'Выбери один из вариантов ${landscape ? 'справа' : 'выше'} — '
    'потом можно идти.';

class _JobPlayScreenState extends State<JobPlayScreen> {
  _Stage _stage = _Stage.offer;

  /// Карточка, показанная перед игрой: ставка с неё и на итоге.
  JobOffer? _shownOffer;
  WorldResult? _result;

  /// Везение этой смены (`job.payout.luck`), если объяснения включены.
  ShiftLuckLine? _luck;

  /// Оценка мини-игры 0..1 — по ней карточка знает бонус и «хорошо ли».
  double _score = 0;

  /// Мини-решение, показанное на карточке, и выбранный вариант (null —
  /// вопроса не было). Ответ уходит в `completeJob(choice:)`.
  ShiftChoice? _shownChoice;

  /// Нажали вариант старого вопроса — мир его уже сменил: над новым
  /// вопросом одна строка, почему кнопки другие (ревью).
  bool _choiceChanged = false;
  ShiftChoiceOption? _chosen;

  /// Итог урока после смены (критерии ночи §4).
  WorldResult? _lesson;

  /// День и силы до смены: после неё мир мог сам закончить день (силы ниже
  /// самого дешёвого дела — Финни спит, и сразу утро). Тогда под итогом —
  /// строка «уже утро» ([DayEndStrip]).
  int? _dayBefore;
  double _energyBefore = 0;

  /// Начало урока на итоге смены: к нему прокручивают кнопки выхода, пока
  /// урок ждёт ответа.
  final GlobalKey _lessonAnchor = GlobalKey();

  /// Сколько раз ребёнок коснулся экрана итогов мимо урока, пока тот ждёт
  /// ответа: 0 — не касался; каждое касание — вспышка вариантов.
  int _nudge = 0;

  /// Где палец коснулся экрана итогов: касание (не прокрутка) мимо вариантов
  /// урока ведёт к уроку ([_toLesson]).
  Offset? _downAt;

  /// Касание экрана итогов, пока урок ждёт ответа (Настя 20.10: «при любом
  /// нажатии»). Слой прозрачный: кнопки, прокрутка и TalkBack работают как
  /// раньше; касание самих вариантов и сдвиг пальца (прокрутка) — не в счёт.
  void _tapAround(PointerUpEvent e) {
    final Offset? down = _downAt;
    _downAt = null;
    if (down == null || (e.position - down).distance > kTouchSlop) return;
    final RenderObject? box = _lessonAnchor.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached) {
      final Rect r = box.localToGlobal(Offset.zero) & box.size;
      if (r.contains(e.position)) return;
    }
    _toLesson();
  }

  /// Урок ждёт ответа, а ребёнок жмёт «Назад», «К доске работ» или «Домой»:
  /// раньше кнопки были погашены, и это читалось как «не работают, только
  /// перезапуск» (баг-репорт из чата задачи, 15.10). Теперь кнопка ведёт к
  /// уроку; что сделать, написано над кнопками ([lessonFirstText]). Без
  /// всплывающей строки: она ложилась на эти же кнопки.
  void _toLesson() {
    // Подсветка вариантов и подсказки над кнопками — на каждое касание мимо
    // урока (счётчик перезапускает вспышку).
    setState(() => _nudge++);
    final BuildContext? c = _lessonAnchor.currentContext;
    if (c != null) {
      // Низ вариантов — у низа экрана: видны все варианты (и над ними —
      // сколько поместится от вопроса).
      Scrollable.ensureVisible(c,
          duration: context.motion(Motion.state), alignment: 1);
    }
  }

  int _round = 0;

  /// Ступень сложности на начало смены (C2, `day_cycle.xp_stages`); null —
  /// у работы ступеней нет.
  int? _xpStage;

  JobPlayArgs? get _args {
    if (widget.args != null) return widget.args;
    final Object? a = ModalRoute.of(context)?.settings.arguments;
    return a is JobPlayArgs ? a : null;
  }

  /// Назад и «К доске работ»: смена ещё не сдана — ничего не потрачено.
  void _back() {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.jobs);
    }
  }

  void _toRoom() {
    final NavigatorState nav = Navigator.of(context);
    bool atRoom = false;
    nav.popUntil((Route<dynamic> r) {
      if (r.settings.name == WorldRoutes.room) atRoom = true;
      return atRoom || r.isFirst;
    });
    if (!atRoom) nav.pushReplacementNamed(WorldRoutes.room);
  }

  void _help(MiniGame game) {
    showHelp(context, 'Как играть', game.help);
  }

  /// Вопрос смены сейчас — из мира, не из кэша: любая запись журнала
  /// (тап по питомцу, еда) может его сменить.
  ShiftChoice? _liveChoice(WorldState ws, JobPlayArgs args) =>
      ws.world.offer(args.jobId, variant: args.variant)?.choice;

  void _start(JobOffer offer, WorldState ws,
      {ShiftChoice? question, ShiftChoiceOption? option}) {
    final JobPlayArgs? args = _args;
    // Вопрос успел смениться — перерисовать карточку с новым, смену не
    // начинать: ответ на старый вопрос мир бы не принял.
    if (question != null &&
        (args == null || _liveChoice(ws, args)?.id != question.id)) {
      setState(() => _choiceChanged = true);
      return;
    }
    setState(() {
      _shownOffer = offer;
      _shownChoice = question;
      _chosen = option;
      _round =
          args == null ? 0 : JobPlayScreen.roundFor(ws.snapshot, args.jobId);
      _xpStage = args == null ? null : ws.world.xpStage(args.jobId);
      _stage = _Stage.play;
    });
  }

  void _finish(JobPlayArgs args, double score) {
    final WorldState ws = context.read<WorldState>();
    final double s = score.clamp(0.0, 1.0);
    // Ответ — только на тот вопрос, что ещё стоит у смены; иначе смена без
    // ответа (как без вопроса), а не отказ после сыгранной игры.
    final ShiftChoiceOption? chosen =
        _chosen != null && _liveChoice(ws, args)?.id == _shownChoice?.id
            ? _chosen
            : null;
    final int dayBefore = ws.snapshot.dayInWeek;
    final double energyBefore = ws.snapshot.energy;
    final WorldResult r = ws.act((World w) => w.completeJob(args.jobId,
        variant: args.variant, score: s, choice: chosen?.id));
    final ShiftLuckLine? luck =
        r.ok ? WorldExplain.of(context).lastShiftLuck(ws.world) : null;
    setState(() {
      _chosen = chosen;
      _result = r;
      _luck = luck;
      _score = s;
      _lesson = null;
      _dayBefore = dayBefore;
      _energyBefore = energyBefore;
      _stage = _Stage.result;
    });
    if (r.ok) context.cue(Cue.earn);
  }

  void _chooseLesson(String choiceId) {
    final WorldResult r =
        context.read<WorldState>().act((World w) => w.resolveLesson(choiceId));
    setState(() => _lesson = r);
    if (r.ok) context.cue(Cue.done);
  }

  /// Урок после смены: ситуация и 2–3 решения с последствием; после
  /// выбора — «Что мы поняли…» и новое слово (критерии ночи §4).
  List<Widget> _lessonBlock(BuildContext context, World world, String jobId) {
    final WorldResult? done = _lesson;
    if (done != null) {
      return <Widget>[
        KeyedSubtree(
          key: const ValueKey<String>('lesson:result'),
          child: _Note(
              icon: done.ok ? Icons.lightbulb_rounded : Icons.info_rounded,
              text: done.nextStep == null
                  ? done.reason
                  : '${done.reason} ${done.nextStep}.'),
        ),
        const SizedBox(height: Gap.sm),
      ];
    }
    final LessonOffer? l = world.pendingLesson;
    if (l == null || l.jobId != jobId) return const <Widget>[];
    return <Widget>[
      Text(l.title,
          key: const ValueKey<String>('lesson:title'),
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Gap.xs),
      // Ситуация — кеглем вариантов под ней ([gameTextCompact], 16).
      Text(l.situation,
          key: const ValueKey<String>('lesson:situation'),
          style: gameTextCompact),
      const SizedBox(height: Gap.sm),
      // Варианты — одним блоком: к нему прокручивают кнопки выхода, и
      // на экране оказываются все варианты, а не только заголовок.
      KeyedSubtree(
        key: _lessonAnchor,
        // Вспышка рамки вокруг вариантов, когда ребёнок жмёт мимо урока.
        child: TweenAnimationBuilder<double>(
          key: ValueKey<int>(_nudge),
          tween: Tween<double>(begin: _nudge == 0 ? 0 : 1, end: 0),
          duration: context.motion(const Duration(milliseconds: 1400)),
          builder: (BuildContext c, double v, Widget? child) => DecoratedBox(
            key: const ValueKey<String>('lesson:choices'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WorldRadii.button),
              border: Border.all(
                  color: WorldColors.gold.withValues(alpha: v), width: 3),
            ),
            child: Padding(padding: const EdgeInsets.all(3), child: child),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final LessonChoiceView c in l.choices) ...<Widget>[
                OutlinedButton(
                  key: ValueKey<String>('lesson:${c.id}'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(TapSize.min),
                      alignment: Alignment.centerLeft,
                      side:
                          const BorderSide(color: WorldColors.needs, width: 2)),
                  onPressed: c.available ? () => _chooseLesson(c.id) : null,
                  child: PicText(
                      c.preview.isEmpty
                          ? c.label
                          : '${c.label} (${c.preview.text})',
                      style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: Gap.xs),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: Gap.sm),
    ];
  }

  /// Отложить на цель — в копилке (S9): там перенос с подтверждением и
  /// видно, сколько осталось до цели. На итоге смены главное — урок.
  void _toPiggy() => Navigator.of(context).pushNamed(WorldRoutes.piggy);

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    final JobPlayArgs? args = _args;
    final MiniGame game =
        miniGameFor(args?.jobId ?? '', context.read<JobGames>());
    final JobOffer? offer =
        args == null ? null : ws.world.offer(args.jobId, variant: args.variant);
    final String title = offer?.title ?? 'Смена';
    final bool land = WorldLayout.isLandscape(context);
    // Итог смены с уроком без ответа: ни «Назад», ни системная кнопка не
    // уводят — сначала выбор (урок обязателен, Денис 29.09).
    // Только урок этой смены: урок другой работы здесь не показан, и
    // запирать им экран — тупик без выхода.
    final bool lessonLock = _stage == _Stage.result &&
        ws.world.pendingLesson != null &&
        ws.world.pendingLesson!.jobId == args?.jobId;
    final Widget stage = AnimatedSwitcher(
      duration: context.motion(Motion.state),
      child: KeyedSubtree(
        key: ValueKey<_Stage>(_stage),
        child: switch (_stage) {
          _Stage.offer => _offerCard(context, ws, args, offer),
          _Stage.play => game.build(
              context,
              MiniGameArgs(
                jobId: args!.jobId,
                games: context.read<JobGames>().forStage(_xpStage),
                variant: args.variant,
                round: _round,
                heroName: ws.finniName,
                heroGender: ws.profile.gender,
                onDone: (double s) => _finish(args, s),
              ),
            ),
          // Пока урок ждёт ответа — касание в любом месте итогов ведёт к
          // уроку (прозрачный слой, кнопки и прокрутка работают).
          _Stage.result => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: lessonLock
                  ? (PointerDownEvent e) => _downAt = e.position
                  : null,
              onPointerUp: lessonLock ? _tapAround : null,
              child: _resultCard(context, ws),
            ),
        },
      ),
    );
    return PopScope(
      canPop: !lessonLock,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && lessonLock) _toLesson();
      },
      // Нижнее меню (стиль Алины): смена — раздел «Город». Урок итога
      // обязателен — пока нет ответа, меню ведёт к нему, а не уводит.
      child: WithDock(
        current: DockSection.city,
        onBlocked: lessonLock ? _toLesson : null,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            // Альбомная — основная: низкая шапка, высота нужна игре.
            toolbarHeight: land ? 48 : null,
            leading: IconButton(
              key: const ValueKey<String>('job:back'),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Назад',
              iconSize: 28,
              constraints: const BoxConstraints(
                  minWidth: TapSize.min, minHeight: TapSize.min),
              onPressed: lessonLock ? _toLesson : _back,
            ),
            // Название работы целиком: «Продавец-консультант» на 360 dp
            // обрезалось до «Продавец-конс…» (путь ребёнка 16.10, дефект 18).
            // Ужимается в одну строку, не мельче 14 sp (text_size_test).
            title: FittedBox(
              key: const ValueKey<String>('job:title'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(title, maxLines: 1),
            ),
            actions: <Widget>[
              HelpButton(
                key: const ValueKey<String>('job:help'),
                onPressed: () => _help(game),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                // Во время игры в альбомной HUD прячется: числа до конца смены
                // не меняются (они на карточке), а поле получает 56 dp высоты.
                if (!(land && _stage == _Stage.play))
                  WorldHud(snapshot: ws.snapshot),
                Expanded(
                  child: land
                      // Альбомная: высота ограничена, игра и карточки сами
                      // раскладываются на панели (GameSplit), без общей прокрутки.
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Gap.md, Gap.sm, Gap.md, Gap.sm),
                          child: stage,
                        )
                      : SingleChildScrollView(
                          // Свой ключ у каждого этапа: прокрутка игры не
                          // переходит на итог (путь ребёнка 16.10: итог
                          // открывался внизу, урок — под шапкой).
                          key: ValueKey<_Stage>(_stage),
                          padding: const EdgeInsets.fromLTRB(
                              Gap.md, Gap.sm, Gap.md, Gap.lg),
                          child: stage,
                        ),
                ),
                // Портрет: под прокруткой, всегда на экране. Альбомная — в
                // левой панели под заголовком итога: снизу она закрывала бы
                // варианты урока справа.
                if (_stage == _Stage.result && !land)
                  if (_night(ws) case (:final String short, full: _))
                    DayEndStrip(
                        key: const ValueKey<String>('job:result:night'),
                        text: short,
                        style: gameText(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Смена закончила день: [short] — строка «уже утро» под итогом, без
  /// прокрутки; [full] — почему, в абзаце итога вместо «Силы кончились».
  /// null — день идёт. Раньше утро было только последней фразой длинного
  /// абзаца внизу итога, а шапка уже показывала утренние силы (путь ребёнка
  /// rc-7d, D2). Строка короткая: на 360×640 при шрифте 1,3 она не должна
  /// закрывать урок — он обязателен.
  ({String short, String full})? _night(WorldState ws) => dayEndText(
      result: _result,
      dayBefore: _dayBefore,
      energyBefore: _energyBefore,
      now: ws.snapshot,
      gender: ws.onboarding.finniGender);

  /// Портрет — столбиком, альбомная — две панели: [left] числа и пояснения,
  /// [right] действия.
  Widget _split(
      BuildContext context, Key key, List<Widget> left, List<Widget> right) {
    Widget column(List<Widget> c) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: c);
    if (!WorldLayout.isLandscape(context)) {
      return KeyedSubtree(key: key, child: column(<Widget>[...left, ...right]));
    }
    return GameSplit(key: key, panes: <GamePane>[
      GamePane(column(left)),
      GamePane(column(right)),
    ]);
  }

  Widget _offerCard(
      BuildContext context, WorldState ws, JobPlayArgs? args, JobOffer? offer) {
    final TextTheme text = Theme.of(context).textTheme;
    if (args == null || offer == null) {
      return _Note(
        icon: Icons.info_rounded,
        text: args == null
            ? 'Работа не выбрана. Вернись к доске «Требуется…».'
            : 'Такой работы нет.',
      );
    }
    // Те же правила, что у completeJob, — из карточки мира (A13).
    final BlockReason? block = offer.blockReason;
    final String? why = block == null ? null : blockText(block);
    final bool land = WorldLayout.isLandscape(context);
    // Мини-решение (флаг `day_cycle.shift_choices_ui`): вариант и есть
    // «Начать смену». Вопрос — из живой карточки [offer].
    final ShiftChoice? question =
        why == null && context.read<JobGames>().shiftChoicesUi
            ? offer.choice
            : null;
    final Widget terms = PicText(
      'Ставка ${offer.basePay}'
      // Опыт словами и монетами, без процентов (Денис 19.10, Т6 А).
      '${showExperiencePay(pay: offer.pay, coins: offer.experienceCoins) ? ', ${experiencePayText(pay: offer.pay, coins: offer.experienceCoins)}' : ''}'
      '${showStageStep(offer.stageStep) ? ', ${stageStepText(offer.stageStep)} за город' : ''}. '
      'Ошибки оплату не уменьшают. ${goodShiftText(offer)}.',
      key: const ValueKey<String>('job:offer:terms'),
      style: land ? gameText(context) : text.bodyLarge,
    );
    // Альбомная с вопросом: условия — слева под числами, справа только
    // вопрос и варианты, чтобы они были видны без прокрутки (как прежняя
    // «Начать смену»).
    final bool termsLeft = land && question != null;
    // Портрет с вопросом: условия — под вариантами. Над ними на 360×800 второй
    // вариант виднелся на 21 px, и ребёнок жал первый, не видя второго (путь
    // ребёнка rc-7d, D2). Числа смены — тоже под ними (ниже).
    final bool termsBelow = !land && question != null;
    // Числа смены. В портрете с вопросом — под вариантами, как и условия:
    // на 360×640 варианты уходили под край (y ≈ 680, при шрифте 1,3 — 870;
    // баг-прогон 18.10, BG-04). Даже одна строка оплаты над вопросом при
    // шрифте 1,3 сдвигает второй вариант за край, а последствия вариантов
    // («+20 💰 · −2 ⚡») и так на кнопках.
    final List<Widget> numbers = <Widget>[
      _Row(
        icon: Pic.coin,
        label: 'Заплатят',
        value: '${offer.pay}',
        valueKey: 'job:offer:pay',
      ),
      _Row(
        icon: Pic.star,
        label: 'Ещё за эффективность',
        value: 'до ${offer.efficiencyBonusMax}',
      ),
      _Row(
        icon: Pic.bolt,
        label: 'Потратишь сил',
        value: WorldHud.energyText(offer.energyCost),
        valueKey: 'job:offer:energy',
      ),
      if (!offer.shiftsUnlimited)
        _Row(
          icon: Pic.week,
          label: 'Смен на неделе осталось',
          value: '${offer.shiftsLeft}',
        ),
      ..._xpExplain(context),
      ..._xpStageLine(context, ws, args),
    ];
    return _split(
      context,
      const ValueKey<String>('job:offer'),
      <Widget>[
        if (!termsBelow) ...numbers,
        if (termsLeft) ...<Widget>[
          const SizedBox(height: Gap.sm),
          terms,
        ],
      ],
      <Widget>[
        if (!land) const SizedBox(height: Gap.xs),
        if (!termsLeft && !termsBelow) terms,
        if (why != null) ...<Widget>[
          const SizedBox(height: Gap.sm),
          _Note(icon: Icons.lock_rounded, text: why),
        ],
        if (!termsLeft && !termsBelow) const SizedBox(height: Gap.md),
        if (question != null && _choiceChanged) ...<Widget>[
          const Text('Вопрос изменился',
              key: ValueKey<String>('job:choice:changed'),
              style: TextStyle(fontSize: 16, color: WorldColors.gold)),
          const SizedBox(height: Gap.xs),
        ],
        if (question != null)
          ShiftChoiceBlock(
            offer: offer,
            question: question,
            onPick: (ShiftChoiceOption o) =>
                _start(offer, ws, question: question, option: o),
          )
        else
          FilledButton.icon(
            key: const ValueKey<String>('job:start'),
            style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(gameButtonHeight(context))),
            onPressed: why == null ? () => _start(offer, ws) : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Начать смену'),
          ),
        if (termsBelow) ...<Widget>[
          const SizedBox(height: Gap.sm),
          ...numbers,
          const SizedBox(height: Gap.sm),
          terms,
        ],
      ],
    );
  }

  /// «Ступень 2: …» (C2): какая ступень сложности откроется в смене. Текст —
  /// `explain.json → explain.xp_stage_title` (заглушка, пишет front), `{n}` —
  /// номер ступени.
  List<Widget> _xpStageLine(
      BuildContext context, WorldState ws, JobPlayArgs? args) {
    final int? stage = args == null ? null : ws.world.xpStage(args.jobId);
    // Ступень 1 — базовая: «задания сложнее» на ней неправда (BG-10).
    if (stage == null || stage <= 1) return const <Widget>[];
    final String title =
        WorldExplain.of(context).texts['xp_stage_title'] ?? 'Ступень {n}';
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: Gap.xs),
        child: Text(title.replaceAll('{n}', '$stage'),
            key: const ValueKey<String>('job:offer:stage'),
            style: gameText(context)),
      ),
    ];
  }

  /// Опыт одной строкой и «Как это считается» (модель 7 дней, флаг
  /// `explain_ui`): за что дают опыт и почему с ним платят больше.
  List<Widget> _xpExplain(BuildContext context) {
    final WorldExplain ex = WorldExplain.of(context);
    final String? short = ex.xpShort;
    final String? detail = ex.xpDetail;
    if (short == null || detail == null) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: Gap.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Pictogram(Pic.chart, size: 24, color: WorldColors.text),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(short,
                  key: const ValueKey<String>('job:offer:xp'),
                  style: gameText(context)),
            ),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey<String>('job:offer:xpHow'),
          style: TextButton.styleFrom(
              minimumSize: const Size(TapSize.min, TapSize.min)),
          onPressed: () => showHelp(context, 'Как считается опыт', detail),
          icon:
              const Pictogram(Pic.question, size: 22, color: WorldColors.gold),
          label: const Text('Как это считается'),
        ),
      ),
    ];
  }

  Widget _resultCard(BuildContext context, WorldState ws) {
    final TextTheme text = Theme.of(context).textTheme;
    final WorldResult r = _result!;
    final JobOffer? shown = _shownOffer;
    final int pay = shown?.pay ?? r.coins;
    final int bonus = shown?.bonusFor(_score) ?? 0;
    final ShiftChoiceOption? chosen = _chosen;
    final bool good = shown?.isGoodScore(_score) ?? false;
    final bool land = WorldLayout.isLandscape(context);
    final Size wide = Size.fromHeight(land ? 48 : TapSize.min);
    final WorldResult? lessonDone = _lesson;
    final int lessonMood =
        lessonDone != null && lessonDone.ok ? lessonDone.happiness : 0;
    final int mood = r.happiness + lessonMood;
    // Урок после смены обязателен (Денис 29.09): уйти можно, только
    // выбрав ответ.
    final bool mustAnswer = ws.world.pendingLesson != null &&
        ws.world.pendingLesson!.jobId == _args?.jobId;
    final List<Widget> leave = <Widget>[
      if (mustAnswer) ...<Widget>[
        // После касания мимо урока — жирно и золотом; liveRegion — TalkBack
        // зачитывает подсказку, когда она меняется.
        Semantics(
          liveRegion: true,
          child: Text(lessonFirstText(landscape: land),
              key: const ValueKey<String>('job:lessonFirst'),
              style: _nudge > 0
                  ? gameText(context).copyWith(
                      fontWeight: FontWeight.w800, color: WorldColors.gold)
                  : gameText(context)),
        ),
        const SizedBox(height: Gap.sm),
      ],
      FilledButton.icon(
        key: const ValueKey<String>('job:toBoard'),
        style: FilledButton.styleFrom(minimumSize: wide),
        onPressed: mustAnswer ? _toLesson : _back,
        icon: const Icon(Icons.work_rounded),
        label: const Text('К доске работ'),
      ),
      const SizedBox(height: Gap.sm),
      OutlinedButton.icon(
        key: const ValueKey<String>('job:toRoom'),
        style: OutlinedButton.styleFrom(minimumSize: wide),
        onPressed: mustAnswer ? _toLesson : _toRoom,
        icon: const Icon(Icons.home_rounded),
        label: const Text('Домой'),
      ),
    ];
    if (!r.ok) {
      return _split(
        context,
        const ValueKey<String>('job:result'),
        <Widget>[
          _Note(
            icon: Icons.info_rounded,
            text: r.nextStep == null ? r.reason : '${r.reason} ${r.nextStep}.',
          ),
        ],
        <Widget>[
          if (!land) const SizedBox(height: Gap.md),
          ...leave,
        ],
      );
    }
    // Урок — главное на итоге смены (ревью 2b58bdb §4.7): в портрете он
    // сразу под заголовком, выше таблицы оплаты, и виден без прокрутки
    // на 360×640 при шрифте 1,3; в альбомной — вверху правой панели.
    final List<Widget> lesson =
        _lessonBlock(context, ws.world, _args?.jobId ?? '');
    final bool lessonWaits = ws.world.pendingLesson != null;
    // Бывший ползунок «Сколько отложить на цель?» убран: решение о деньгах
    // теперь в уроке. Отложить руками — в копилке, пока урок не ждёт.
    final bool piggy = !lessonWaits && ws.snapshot.free > 0;
    final String? moodWhy = switch (WorldExplain.of(context).moodWhy) {
      final String t => heroText(t, ws.finniName),
      null => null,
    };
    return _split(
      context,
      const ValueKey<String>('job:result'),
      <Widget>[
        Text(good ? 'Смена сделана хорошо!' : 'Смена сделана!',
            key: const ValueKey<String>('job:result:title'),
            style: text.titleLarge),
        const SizedBox(height: Gap.sm),
        if (land)
          if (_night(ws) case (:final String short, full: _)) ...<Widget>[
            DayEndStrip(
                key: const ValueKey<String>('job:result:night'),
                text: short,
                style: gameText(context),
                boxed: true),
            const SizedBox(height: Gap.sm),
          ],
        if (!land) ...lesson,
        _Row(
            icon: Pic.coin,
            label: 'Оплата',
            value: '+$pay',
            valueKey: 'job:result:pay'),
        _Row(
            icon: Pic.star,
            label: 'За эффективность',
            value: '+$bonus',
            valueKey: 'job:result:bonus'),
        if (_luck case final ShiftLuckLine luck) _LuckRow(luck: luck),
        // Ответ на мини-решение: монеты сверх оплаты здесь, силы и
        // настроение — уже в строках ниже (они из итога мира).
        if (chosen != null)
          KeyedSubtree(
            key: const ValueKey<String>('job:result:choice'),
            child: _Row(
                icon: Pic.check,
                label: 'Выбор: ${chosen.label}',
                value: shown == null
                    ? ''
                    : _signedCoins(shiftChoicePayDelta(shown, chosen)),
                valueKey: 'job:result:choice:pay'),
          ),
        _Row(
            icon: Pic.bolt,
            label: good ? 'Сил потрачено (с хорошей сменой)' : 'Сил потрачено',
            value: WorldHud.energyText(-r.energy),
            valueKey: 'job:result:energy'),
        // Смена и урок вместе: иначе строка «−2», а 😊 в шапке уже на 1
        // меньше (смоук 29.09: «Пересчитать» −1).
        if (mood != 0)
          _Row(
              icon: Pic.smile,
              label:
                  lessonMood != 0 ? 'Настроение (после урока)' : 'Настроение',
              value: mood > 0 ? '+$mood' : '−${-mood}',
              valueKey: 'job:result:happiness',
              help: moodWhy == null
                  ? null
                  : HelpButton(
                      key: const ValueKey<String>('job:result:moodWhy'),
                      tooltip: 'Почему меняется настроение',
                      onPressed: () => showHelp(
                          context, 'Почему меняется настроение', moodWhy))),
        if (good)
          const _Row(
              icon: Pic.chart,
              label: 'Опыт',
              value: '+1',
              valueKey: 'job:result:exp'),
        const SizedBox(height: Gap.sm),
        _Note(
            icon: Icons.chat_bubble_rounded,
            text: _night(ws)?.full ?? r.reason),
      ],
      <Widget>[
        if (!land) const SizedBox(height: Gap.md),
        if (land) ...lesson,
        if (piggy) ...<Widget>[
          OutlinedButton.icon(
            key: const ValueKey<String>('job:toPiggy'),
            style: OutlinedButton.styleFrom(minimumSize: wide),
            onPressed: _toPiggy,
            icon: const Icon(Icons.savings_rounded),
            label: const Text('Отложить на цель — в копилке'),
          ),
          const SizedBox(height: Gap.sm),
        ],
        ...leave,
      ],
    );
  }
}

/// «+20», «−10»; ноль — пусто (строка выбора без монет).
String _signedCoins(int n) => n == 0
    ? ''
    : n > 0
        ? '+$n'
        : '−${-n}';

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.valueKey,
    this.help,
  });

  final Pic icon;
  final String label;
  final String value;
  final String? valueKey;

  /// «?» после числа — объяснение строки (модель 7 дней).
  final Widget? help;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          children: <Widget>[
            Pictogram(icon, size: 24, color: WorldColors.text),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _WholeWords(label, style: gameText(context)),
            ),
            const SizedBox(width: Gap.sm),
            Text(
              value,
              key: valueKey == null ? null : ValueKey<String>(valueKey!),
              style: AppType.number(20, color: WorldColors.text),
            ),
            if (help case final Widget h) h,
          ],
        ),
      );
}

/// Везение на смене (модель 7 дней): «Сегодня повезло: …» / «Не повезло:
/// …», под ней — что это дало, справа — монеты сверху или меньше. Так
/// строки итога складываются в то, что пришло в монеты.
class _LuckRow extends StatelessWidget {
  const _LuckRow({required this.luck});

  final ShiftLuckLine luck;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = gameText(context);
    final int pay = luck.pay;
    return MergeSemantics(
      child: Padding(
        key: const ValueKey<String>('job:result:luck'),
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Pictogram(luck.good ? Pic.spark : Pic.info,
                size: 24, color: WorldColors.text),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(luck.line, style: style),
                  if (luck.hint.isNotEmpty)
                    Text(luck.hint,
                        style: style.copyWith(color: WorldColors.textSoft)),
                ],
              ),
            ),
            if (pay != 0) ...<Widget>[
              const SizedBox(width: Gap.sm),
              Text(
                pay > 0 ? '+$pay' : '−${-pay}',
                key: const ValueKey<String>('job:result:luck:pay'),
                style: AppType.number(20, color: WorldColors.text),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WorldColors.panel,
          borderRadius: BorderRadius.circular(WorldRadii.button),
          border: Border.all(color: WorldColors.line, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: WorldColors.text),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: PicText(text, style: gameText(context)),
              ),
            ],
          ),
        ),
      );
}

/// Подпись строки, где слова не рвутся посреди: при крупном шрифте самое
/// длинное слово («эффективность» рядом с «до 30») не влезало в ширину и
/// переносилось по буквам (путь ребёнка, rc-7d, n1). Тогда шрифт подписи
/// уменьшается ровно настолько, чтобы слово встало целиком, но не мельче
/// 14 sp (ТЗ, `text_size_test`); остальное — как у обычного [Text].
class _WholeWords extends StatelessWidget {
  const _WholeWords(this.text, {required this.style});

  final String text;
  final TextStyle style;

  static const double minSp = 14;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final TextScaler scaler = MediaQuery.textScalerOf(context);
          // Мерить тем же шрифтом, что нарисует Text: стиль темы + свой.
          final TextStyle full =
              DefaultTextStyle.of(context).style.merge(style);
          final double size = full.fontSize ?? 14;
          final double shown = scaler.scale(size);
          double widest = 0;
          for (final String w in text.split(RegExp(r'\s+'))) {
            final TextPainter p = TextPainter(
              text: TextSpan(text: w, style: full),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            if (p.width > widest) widest = p.width;
            p.dispose();
          }
          if (!c.hasBoundedWidth || widest <= c.maxWidth || shown <= minSp) {
            return Text(text, style: style);
          }
          // С запасом на округление ширины глифов при другом кегле.
          final double fit = shown * c.maxWidth / widest * 0.98;
          final double target = fit < minSp ? minSp : fit;
          return Text(
            text,
            style: style,
            textScaler: TextScaler.linear(target / size),
          );
        },
      );
}
