import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/feel.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/world_art.dart';
import '../../domain/economy/savings_rules.dart';
import '../../domain/game.dart';
import '../../domain/ledger/ledger_fold.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/task.dart';
import '../../routes.dart';
import '../savings/savings_screen.dart' show goalPic, weekWord;

/// Главный экран (§2.5.3) — дом Финни.
///
/// Требование пункта дословно: питомец, доступный баланс, сумма накоплений,
/// текущая цель, основные показатели состояния и активное задание видны
/// **одновременно, без сложной навигации**. Поэтому здесь один скролл без
/// вкладок, в порядке важности:
///
/// 1. **Комната** — Финни, его вещи и мечта чертежом. Это ответ на вопрос
///    «зачем всё это»: мир, который меняется от решений ребёнка.
/// 2. **Как он** — имя, стадия и три показателя.
/// 3. **Одно главное действие недели** — золотая кнопка.
/// 4. **Кошелёк** — сколько есть, три конверта и откуда пришли монетки.
/// 5. **Задание** и разделы.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Финни')));
    }

    final Game g = app.game;
    final GameSnapshot snap = g.snapshot;
    final List<GameTask> tasks = g.availableTasks;

    return Scaffold(
      appBar: AppBar(
        title: Text('Неделя ${snap.periodNo}'),
        actions: <Widget>[
          if (app.demoMode)
            IconButton(
              tooltip: 'Демонстрационный режим',
              icon: const Pictogram(Pic.flask, color: AppColors.primary),
              onPressed: () => Navigator.pushNamed(context, AppRoutes.demo),
            ),
          IconButton(
            tooltip: 'Подсказка',
            icon: const Pictogram(Pic.question, color: AppColors.primary),
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.onboarding),
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Pictogram(Pic.sliders, color: AppColors.primary),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xl),
          children: <Widget>[
            _SceneCard(app: app, snap: snap),
            const SizedBox(height: Gap.md),
            if (_MainAction.shows(g)) ...<Widget>[
              _MainAction(app: app),
              const SizedBox(height: Gap.md),
            ],
            _WalletBlock(app: app, snap: snap),
            const SizedBox(height: Gap.md),
            _TaskBlock(tasks: tasks, game: g),
            if (g.phase == PeriodPhase.living && !g.unexpectedPending) ...<Widget>[
              const SizedBox(height: Gap.lg),
              _CloseWeek(app: app),
            ],
            const SizedBox(height: Gap.lg),
            const _Sections(),
          ],
        ),
      ),
    );
  }
}

/// Комната и мечта под ней.
class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.app, required this.snap});

  final AppState app;
  final GameSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final Game g = app.game;
    final Goal? goal = g.goal;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.scene),
        boxShadow: Paper.cut(SceneColors.barkDark, depth: 5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.scene),
        child: ColoredBox(
          color: AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RoomView(
                scene: RoomScene(
                  stage: snap.stage,
                  keepsakes: g.keepsakes,
                  goal: goal,
                  saved: snap.wallet.savings,
                  fulfilled: g.fulfilledGoals,
                ),
                species: g.profile.species,
                palette: g.profile.palette,
                meters: snap.meters,
                accessories: g.profile.accessories,
                onShop: () => Navigator.pushNamed(context, AppRoutes.shop),
                onTasks: () => Navigator.pushNamed(context, AppRoutes.tasks),
                onSavings: () =>
                    Navigator.pushNamed(context, AppRoutes.savings),
              ),
              _DreamBand(
                goal: goal,
                savings: snap.wallet.savings,
                forecast: g.forecast,
              ),
              // Как Финни — той же карточкой, что комната: это про него,
              // а не отдельная панель-«дашборд» ниже.
              const Divider(height: 1, thickness: 1.5, color: AppColors.grid),
              _PetStatus(app: app, snap: snap),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полоса под комнатой: ближайшая мечта и сколько до неё.
///
/// 🔴 «На главном всегда одна понятная ближайшая мечта с прогрессом» —
/// из анализа референсов. Число здесь дублирует чертёж в комнате: чертёж
/// показывает, число — сообщает. Одно без другого не работает ни для
/// семилетки, ни для TalkBack.
class _DreamBand extends StatelessWidget {
  const _DreamBand({
    required this.goal,
    required this.savings,
    required this.forecast,
  });

  final Goal? goal;
  final int savings;
  final GoalForecast? forecast;

  @override
  Widget build(BuildContext context) {
    final Goal? g = goal;
    if (g == null) {
      return Semantics(
        button: true,
        label: 'Выбрать мечту: она встанет в комнате',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, AppRoutes.savings),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.primary),
            padding: const EdgeInsets.all(Gap.md),
            child: const Row(
              children: <Widget>[
                _DreamIcon(pic: Pic.flag),
                SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Выбери мечту',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('Она встанет в комнате и будет проявляться, '
                          'пока копишь',
                          style: TextStyle(
                              fontSize: 16, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
                Pictogram(Pic.arrowRight, size: 26, color: AppColors.primary),
              ],
            ),
          ),
        ),
      );
    }

    final int left = (g.price - savings).clamp(0, g.price);
    final double ratio = g.price == 0 ? 0 : (savings / g.price).clamp(0, 1);
    final GoalForecast? f = forecast;
    final String note = left == 0
        ? 'Набрано! Исполнить мечту можно в копилке'
        : f?.weeks != null && f!.weeks! > 0
            ? 'Ещё $left. Если откладывать по ${f.averageDeposit}, '
                'это примерно ${f.weeks} ${weekWord(f.weeks!)}'
            : 'Ещё $left ${Coins.word(left)}';
    return Semantics(
      button: true,
      label: 'Мечта: ${g.title}. Накоплено $savings из ${g.price}. $note',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, AppRoutes.savings),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm + 4, Gap.md, Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _DreamIcon(pic: goalPic(g.icon)),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(g.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: Gap.sm),
                  Text.rich(
                    TextSpan(children: <InlineSpan>[
                      TextSpan(
                          text: '$savings',
                          style: AppType.number(20, color: AppColors.savings)),
                      TextSpan(
                          text: ' / ${g.price}',
                          style: AppType.number(16, color: AppColors.inkSoft)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              _Progress(ratio: ratio),
              const SizedBox(height: Gap.xs),
              Text(note,
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DreamIcon extends StatelessWidget {
  const _DreamIcon({required this.pic});

  final Pic pic;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.savingsBg,
          shape: BoxShape.circle,
        ),
        child: Pictogram(pic, size: 24, color: AppColors.savings),
      );
}

/// Тонкая полоса прогресса к мечте, с чернильным контуром.
class _Progress extends StatelessWidget {
  const _Progress({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    // 🔴 Ширина задана явно. В колонке с выравниванием по началу Container
    // без ширины сжимался до своей заливки, и трека «сколько всего» не было
    // видно: 5 из 30 выглядело короткой таблеткой в пустоте.
    return Container(
      width: double.infinity,
      height: 16,
      decoration: BoxDecoration(
        color: const Color(0xFFD9D4F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: ratio,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.savings,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}

/// Имя, стадия и показатели.
class _PetStatus extends StatelessWidget {
  const _PetStatus({required this.app, required this.snap});

  final AppState app;
  final GameSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final Game g = app.game;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm + 4, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(g.profile.petName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title(18)),
                ),
              ),
              const SizedBox(width: Gap.sm),
              _StagePill(stage: snap.stage),
            ],
          ),
          const SizedBox(height: Gap.sm + 2),
          // При крупном системном шрифте три шкалы в ряд не помещаются, и
          // одну подпись приходилось ужимать. Тогда — столбиком, полностью.
          if (MediaQuery.textScalerOf(context).scale(16) > 18)
            for (final Meter m in Meter.values) ...<Widget>[
              MeterRow(meter: m, value: snap.meters.byMeter(m)),
              if (m != Meter.values.last) const SizedBox(height: Gap.xs + 2),
            ]
          else
            Row(
              children: <Widget>[
                for (final Meter m in Meter.values) ...<Widget>[
                  Expanded(
                    child: MeterRow(
                        meter: m, value: snap.meters.byMeter(m), compact: true),
                  ),
                  if (m != Meter.values.last) const SizedBox(width: Gap.sm),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill({required this.stage});

  final PetStage stage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.grid,
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(stage.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
    );
  }
}

class _WalletBlock extends StatelessWidget {
  const _WalletBlock({required this.app, required this.snap});

  final AppState app;
  final GameSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final Game g = app.game;
    final Wallet w = snap.wallet;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  child: const Text('У тебя есть',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              ),
              // 🔴 Всё, что есть, — вместе с копилкой. Раньше здесь стояло
              // «доступно к трате», и «У тебя есть 3» рядом с конвертами
              // 2 + 1 + 5 не сходилось: главное число игры про деньги
              // противоречило тому, что видно под ним.
              Coins(w.everything, size: 30),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              w.unallocated > 0
                  ? 'Из них ${w.unallocated} ещё не разложены по конвертам'
                  : 'Потратить можно ${w.available}, '
                      'в копилке ${w.savings}',
              style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final Envelope e in Envelope.values) ...<Widget>[
                Expanded(
                  child: EnvelopeCard(
                    envelope: e,
                    compact: true,
                    amount: e == Envelope.savings
                        ? w.savings
                        : w.envelopes.byEnvelope(e),
                    // 🔴 Без «план N»: в конверте лежит остаток за все
                    // недели, а план — только этой. Рядом они читались как
                    // «потратил больше плана» («Хочу 7, план 2»). Сравнение
                    // плана с фактом — на экране плана.
                    onTap: () => Navigator.pushNamed(
                      context,
                      e == Envelope.savings ? AppRoutes.savings : AppRoutes.shop,
                    ),
                  ),
                ),
                if (e != Envelope.values.last) const SizedBox(width: Gap.sm),
              ],
            ],
          ),
          const SizedBox(height: Gap.md),
          const Text('Откуда монетки этой недели',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: Gap.sm),
          TrustBar(
            fromParents: g.trustBudget,
            earnCap: g.earnCap,
            earned: g.earnedThisPeriod,
          ),
        ],
      ),
    );
  }
}

class _TaskBlock extends StatelessWidget {
  const _TaskBlock({required this.tasks, required this.game});

  final List<GameTask> tasks;
  final Game game;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final GameTask t = tasks.first;
    final bool paid = !game.earnCapReached;
    final int pay = paid ? (t.reward < game.earnLeft ? t.reward : game.earnLeft) : 0;
    return Panel(
      onTap: () => Navigator.pushNamed(context, AppRoutes.tasks),
      semanticLabel: 'Задание: ${t.title}. ${t.topic.title}. '
          '${paid ? 'Принесёт $pay ${Coins.word(pay)}' : 'Ради интереса — подработка на неделю закончилась'}',
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.needsBg, shape: BoxShape.circle),
            child:
                const Pictogram(Pic.task, size: 26, color: AppColors.needs),
          ),
          const SizedBox(width: Gap.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Задание',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.needs)),
                Text(t.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                Text(t.topic.title,
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.inkSoft)),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          if (paid)
            _RewardBadge(amount: pay)
          else
            const Text('ради\nинтереса',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

class _RewardBadge extends StatelessWidget {
  const _RewardBadge({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm + 2, Gap.xs),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1CF),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('+', style: AppType.number(18)),
            Coins(amount, size: 18),
          ],
        ),
      );
}

/// Главное действие недели. Ровно одно — чтобы ребёнок не выбирал,
/// с чего начать.
class _MainAction extends StatelessWidget {
  const _MainAction({required this.app});

  final AppState app;

  /// Золотая кнопка есть только там, где неделя ждёт шага: разложить,
  /// начать новую, разобраться с непредвиденным.
  ///
  /// 🔴 Посреди недели её нет. Первый проход ставил туда «Завершить
  /// неделю» — необратимое действие золотым, первым, под рукой. Посреди
  /// недели главное — сама комната: лавка, задания, копилка.
  static bool shows(Game g) =>
      g.unexpectedPending ||
      g.phase != PeriodPhase.living ||
      g.goalReached;

  @override
  Widget build(BuildContext context) {
    final Game g = app.game;
    if (g.unexpectedPending) {
      return FilledButton.icon(
        icon: const Pictogram(Pic.umbrella, color: AppColors.onAction),
        label: Text(g.unexpectedThisWeek!.chip),
        onPressed: () => Navigator.pushNamed(context, AppRoutes.savings),
      );
    }
    // Мечта набрана — это и есть шаг недели: исполнить её в копилке.
    if (g.goalReached && g.phase == PeriodPhase.living) {
      return FilledButton.icon(
        icon: const Pictogram(Pic.star, color: AppColors.onAction),
        label: const Text('Исполнить мечту'),
        onPressed: () => Navigator.pushNamed(context, AppRoutes.savings),
      );
    }
    return switch (g.phase) {
      PeriodPhase.closing => FilledButton.icon(
          icon: const Pictogram(Pic.play, color: AppColors.onAction),
          label: const Text('Начать новую неделю'),
          onPressed: () async {
            await app.act((Game game) => game.startPeriod());
            if (context.mounted && app.lastFeedback != null) {
              // Карманные пришли — это главное «получилось» недели.
              await showFeedback(context, app.lastFeedback!, cue: Cue.earn);
            }
            if (context.mounted) {
              await Navigator.pushNamed(context, AppRoutes.plan);
            }
          },
        ),
      PeriodPhase.planning => FilledButton.icon(
          icon: const Pictogram(Pic.wallet, color: AppColors.onAction),
          label: const Text('Разложить монетки'),
          onPressed: () => Navigator.pushNamed(context, AppRoutes.plan),
        ),
      PeriodPhase.living => const SizedBox.shrink(),
    };
  }
}

/// Конец недели — тихой кнопкой внизу, с пояснением, а не золотом наверху.
class _CloseWeek extends StatelessWidget {
  const _CloseWeek({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Когда всё на эту неделю сделано:',
          style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          icon: const Pictogram(Pic.flag, color: AppColors.primary),
          label: const Text('Завершить неделю'),
          onPressed: () async {
            // §3.6.8: действие, заметно меняющее прогресс, требует
            // подтверждения. Закрытие недели необратимо.
            final bool ok = await _confirmCloseWeek(context, app) ?? false;
            if (!ok || !context.mounted) return;
            await app.closePeriod();
            if (context.mounted) {
              await Navigator.pushNamed(context, AppRoutes.progress);
            }
          },
        ),
      ],
    );
  }
}

/// Подтверждение закрытия недели. Текст называет, что именно изменится,
/// а не спрашивает «вы уверены?»: семилетка на «уверены?» отвечает «да»
/// не читая.
Future<bool?> _confirmCloseWeek(BuildContext context, AppState app) {
  final int left = app.game.snapshot.wallet.unallocated;
  return showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Закончить неделю?'),
      content: Text(
        left > 0
            ? 'У тебя ещё $left ${Coins.word(left)} не разложены по '
                'конвертам. Неделя закончится, Финни подведёт итоги, и '
                'вернуться назад будет нельзя.'
            : 'Финни подведёт итоги недели, покажет, что получилось, и '
                'начнётся новая неделя. Вернуться назад будет нельзя.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Ещё не всё'),
        ),
        FilledButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll<Size>(Size(0, TapSize.min)),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Закончить'),
        ),
      ],
    ),
  );
}

class _Sections extends StatelessWidget {
  const _Sections();

  @override
  Widget build(BuildContext context) {
    // §2.5.3.2: с главного экрана доступны план бюджета, задания, покупки,
    // накопления, прогресс и раздел для взрослого. Покупки, задания и
    // копилка — это места в комнате; здесь — остальное.
    const List<(Pic, String, String)> items = <(Pic, String, String)>[
      (Pic.wallet, 'План', AppRoutes.plan),
      (Pic.chart, 'Прогресс', AppRoutes.progress),
      (Pic.dictionary, 'Словарик', AppRoutes.glossary),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int k = 0; k < items.length; k++) ...<Widget>[
              Expanded(
                child: _Shortcut(
                  icon: items[k].$1,
                  title: items[k].$2,
                  onTap: () => Navigator.pushNamed(context, items[k].$3),
                ),
              ),
              if (k < items.length - 1) const SizedBox(width: Gap.sm),
            ],
          ],
        ),
        const SizedBox(height: Gap.md),
        // Раздел для взрослого — отдельно и тише: он не часть игры.
        Center(
          child: TextButton.icon(
            icon: const Pictogram(Pic.family, color: AppColors.primary),
            label: const Text('Взрослым'),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.adult),
          ),
        ),
      ],
    );
  }
}

/// Ярлык раздела: пиктограмма над словом. Три в ряд на 360 dp.
class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.title, required this.onTap});

  final Pic icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll<Size>(Size(0, TapSize.primary + 8)),
          padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.xs, Gap.sm + 3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Pictogram(icon, size: 26, color: AppColors.primary),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ),
          ],
        ),
      ),
    );
  }
}
