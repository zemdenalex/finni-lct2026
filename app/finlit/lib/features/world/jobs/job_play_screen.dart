import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../home/world_hud.dart';
import '../pic_text.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import 'board/job_offer_card.dart';
import 'job_games.dart';
import 'mini_games.dart';
import '../../../core/world_theme.dart';

/// Смена (S7) и её итог (S7r): карточка → мини-игра → оплата и ползунок
/// «на цель» (`docs/game/job-cashier.md`, `job-consultant.md`).
///
/// 🔴 Числа карточки — только из `world.offer`, экран их не пересчитывает.
/// ⚡ списывается лишь в `completeJob`: вышел из игры — ничего не потрачено.
/// Мини-игры — реестр [miniGames] (`mini_games.dart`).
class JobPlayScreen extends StatefulWidget {
  const JobPlayScreen({super.key, this.args});

  /// Для тестов; из таблицы маршрутов — аргумент маршрута.
  final JobPlayArgs? args;

  @override
  State<JobPlayScreen> createState() => _JobPlayScreenState();
}

enum _Stage { offer, play, result }

class _JobPlayScreenState extends State<JobPlayScreen> {
  _Stage _stage = _Stage.offer;

  /// Карточка, показанная перед игрой: ставка с неё и на итоге.
  JobOffer? _shownOffer;
  WorldResult? _result;

  /// Оценка мини-игры 0..1 — по ней карточка знает бонус и «хорошо ли».
  double _score = 0;

  /// Итог урока после смены (критерии ночи §4).
  WorldResult? _lesson;
  int _round = 0;

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

  void _start(JobOffer offer, WorldState ws) => setState(() {
        _shownOffer = offer;
        _round = ws.snapshot.experience;
        _stage = _Stage.play;
      });

  void _finish(JobPlayArgs args, double score) {
    final WorldState ws = context.read<WorldState>();
    final double s = score.clamp(0.0, 1.0);
    final WorldResult r = ws.act((World w) =>
        w.completeJob(args.jobId, variant: args.variant, score: s));
    setState(() {
      _result = r;
      _score = s;
      _lesson = null;
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
      Text(l.situation,
          key: const ValueKey<String>('lesson:situation'),
          style: gameText(context)),
      const SizedBox(height: Gap.sm),
      for (final LessonChoiceView c in l.choices) ...<Widget>[
        OutlinedButton(
          key: ValueKey<String>('lesson:${c.id}'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(TapSize.min),
              alignment: Alignment.centerLeft,
              side: const BorderSide(color: WorldColors.needs, width: 2)),
          onPressed: c.available ? () => _chooseLesson(c.id) : null,
          child: PicText(
              c.preview.isEmpty ? c.label : '${c.label} (${c.preview.text})',
              style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: Gap.xs),
      ],
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
    final MiniGame game = miniGameFor(args?.jobId ?? '');
    final JobOffer? offer =
        args == null ? null : ws.world.offer(args.jobId, variant: args.variant);
    final String title = offer?.title ?? 'Смена';
    final bool land = WorldLayout.isLandscape(context);
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
                games: context.read<JobGames>(),
                variant: args.variant,
                round: _round,
                onDone: (double s) => _finish(args, s),
              ),
            ),
          _Stage.result => _resultCard(context, ws),
        },
      ),
    );
    return Scaffold(
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
          onPressed: _back,
        ),
        title: Text(title),
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
                      padding: const EdgeInsets.fromLTRB(
                          Gap.md, Gap.sm, Gap.md, Gap.lg),
                      child: stage,
                    ),
            ),
          ],
        ),
      ),
    );
  }

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
    return _split(
      context,
      const ValueKey<String>('job:offer'),
      <Widget>[
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
          icon: Pic.spark,
          label: 'Потратишь энергии',
          value: WorldHud.energyText(offer.energyCost),
          valueKey: 'job:offer:energy',
        ),
        _Row(
          icon: Pic.week,
          label: 'Смен на неделе осталось',
          value: '${offer.shiftsLeft}',
        ),
      ],
      <Widget>[
        if (!land) const SizedBox(height: Gap.xs),
        PicText(
          'Ставка ${offer.basePay}'
          '${offer.experiencePercent > 0 ? ', опыт +${offer.experiencePercent} %' : ''}'
          '${showStageStep(offer.stageStep) ? ', ${stageStepText(offer.stageStep)} за город' : ''}. '
          'Ошибки оплату не уменьшают. ${goodShiftText(offer)}.',
          key: const ValueKey<String>('job:offer:terms'),
          style: land ? gameText(context) : text.bodyLarge,
        ),
        if (why != null) ...<Widget>[
          const SizedBox(height: Gap.sm),
          _Note(icon: Icons.lock_rounded, text: why),
        ],
        const SizedBox(height: Gap.md),
        FilledButton.icon(
          key: const ValueKey<String>('job:start'),
          style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(gameButtonHeight(context))),
          onPressed: why == null ? () => _start(offer, ws) : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Начать смену'),
        ),
      ],
    );
  }

  Widget _resultCard(BuildContext context, WorldState ws) {
    final TextTheme text = Theme.of(context).textTheme;
    final WorldResult r = _result!;
    final JobOffer? shown = _shownOffer;
    final int pay = shown?.pay ?? r.coins;
    final int bonus = shown?.bonusFor(_score) ?? 0;
    final bool good = shown?.isGoodScore(_score) ?? false;
    final bool land = WorldLayout.isLandscape(context);
    final Size wide = Size.fromHeight(land ? 48 : TapSize.min);
    final WorldResult? lessonDone = _lesson;
    final int lessonMood =
        lessonDone != null && lessonDone.ok ? lessonDone.happiness : 0;
    final int mood = r.happiness + lessonMood;
    final List<Widget> leave = <Widget>[
      FilledButton.icon(
        key: const ValueKey<String>('job:toBoard'),
        style: FilledButton.styleFrom(minimumSize: wide),
        onPressed: _back,
        icon: const Icon(Icons.work_rounded),
        label: const Text('К доске работ'),
      ),
      const SizedBox(height: Gap.sm),
      OutlinedButton.icon(
        key: const ValueKey<String>('job:toRoom'),
        style: OutlinedButton.styleFrom(minimumSize: wide),
        onPressed: _toRoom,
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
    return _split(
      context,
      const ValueKey<String>('job:result'),
      <Widget>[
        Text(good ? 'Смена сделана хорошо!' : 'Смена сделана!',
            key: const ValueKey<String>('job:result:title'),
            style: text.titleLarge),
        const SizedBox(height: Gap.sm),
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
        _Row(
            icon: Pic.spark,
            label: good
                ? 'Энергии потрачено (с хорошей сменой)'
                : 'Энергии потрачено',
            value: WorldHud.energyText(-r.energy),
            valueKey: 'job:result:energy'),
        // Смена и урок вместе: иначе строка «−2», а 😊 в шапке уже на 1
        // меньше (смоук 29.09: «Пересчитать» −1).
        if (mood != 0)
          _Row(
              icon: Pic.smile,
              label: lessonMood != 0 ? 'Настроение (с уроком)' : 'Настроение',
              value: mood > 0 ? '+$mood' : '−${-mood}',
              valueKey: 'job:result:happiness'),
        if (good)
          const _Row(
              icon: Pic.chart,
              label: 'Опыт',
              value: '+1',
              valueKey: 'job:result:exp'),
        const SizedBox(height: Gap.sm),
        _Note(icon: Icons.chat_bubble_rounded, text: r.reason),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.valueKey,
  });

  final Pic icon;
  final String label;
  final String value;
  final String? valueKey;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          children: <Widget>[
            Pictogram(icon, size: 24, color: WorldColors.text),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(label, style: gameText(context)),
            ),
            const SizedBox(width: Gap.sm),
            Text(
              value,
              key: valueKey == null ? null : ValueKey<String>(valueKey!),
              style: AppType.number(20, color: WorldColors.text),
            ),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WorldColors.panel,
          borderRadius: BorderRadius.circular(Radii.chip),
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
                child: Text(text, style: gameText(context)),
              ),
            ],
          ),
        ),
      );
}
