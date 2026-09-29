import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/feel.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/world_art.dart';
import '../../domain/economy/savings_rules.dart';
import '../../domain/economy/economy_config.dart';
import '../../domain/game.dart';
import '../../domain/ledger/ledger_fold.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/goal.dart';
import '../../routes.dart';
import 'coin_stepper.dart';
import '../../domain/custom_goal.dart';

/// Экран накоплений и цели (§2.5.7).
///
/// Ни одного расчёта в этом файле нет: сумма, остаток и срок приходят из
/// [Game] и [SavingsRules], числа — из контента. Экран только показывает
/// и спрашивает.
class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen>
    with SingleTickerProviderStateMixin {
  /// Ребёнок нажал «Выбрать другую цель» — показываем список поверх
  /// уже выбранной цели, не сбрасывая её.
  bool _pickingGoal = false;

  /// Единственный праздник за игру: цель набрана.
  ///
  /// 🔴 Запускается из обработчика взноса, а не из build по сравнению
  /// «стало/было»: build случается и от чужих причин — поворота экрана,
  /// смены настроек, возврата с другого экрана, — и монетки разлетались бы
  /// повторно там, где ребёнок ничего не делал. §6: движение отвечает
  /// на действие.
  /// 🔴 Создаётся в initState: ленивое поле, до которого впервые дошли
  /// из dispose (цель не выбрана — блока с копилкой в дереве не было),
  /// создаёт тикер на отсоединённом элементе и роняет экран.
  late final AnimationController _cheer;

  @override
  void initState() {
    super.initState();
    _cheer = AnimationController(vsync: this, duration: Motion.cheer);
    final AppState app = context.read<AppState>();
    if (app.ready) {
      CustomGoals.restore(app.content, app.game.profile.goalId);
    }
  }

  @override
  void dispose() {
    _cheer.dispose();
    super.dispose();
  }

  void _celebrate() {
    if (!mounted) return;
    _cheer
      ..duration = context.motion(Motion.cheer)
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Копилка')));
    }

    final Game g = app.game;
    final Goal? goal = g.goal;
    final bool picking = goal == null || _pickingGoal;

    return Scaffold(
      appBar: AppBar(title: const Text('Копилка')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
          children: <Widget>[
            // §2, специально спланированный кейс: непредвиденный расход.
            // Стоит первым, но карточка спокойная — не модалка и не красный
            // экран: исход поправим, а Финни не болеет.
            if (g.unexpectedPending) ...<Widget>[
              _UnexpectedCard(app: app),
              const SizedBox(height: Gap.md),
            ],
            if (picking)
              _GoalPicker(
                app: app,
                onChosen: () => setState(() => _pickingGoal = false),
                onCancel: goal == null
                    ? null
                    : () => setState(() => _pickingGoal = false),
              )
            else
              _GoalBlock(
                app: app,
                goal: goal,
                cheer: _cheer,
                onReached: _celebrate,
                onChangeGoal: () => setState(() => _pickingGoal = true),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── выбор цели ─────────────────────────────

/// Список целей (§2.5.7.1) плюс своя цель из набора параметров.
class _GoalPicker extends StatelessWidget {
  const _GoalPicker({
    required this.app,
    required this.onChosen,
    this.onCancel,
  });

  final AppState app;
  final VoidCallback onChosen;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final List<Goal> goals = app.content.goals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text('На что копим?',
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: Gap.xs),
        const Text(
          'Цель можно поменять в любой момент — накопленные монетки останутся.',
          style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
        ),
        const SizedBox(height: Gap.md),
        for (final Goal goal in goals) ...<Widget>[
          _GoalOption(
            goal: goal,
            onTap: () async {
              await app.act((Game g) {
                g.chooseGoal(goal.id);
                return ActionResult(
                  title: 'Цель выбрана',
                  text: '${goal.title} — ${goal.price} '
                      '${Coins.word(goal.price)}.',
                  nextStep: 'Откладывай монетки в копилку — цель станет ближе',
                );
              });
              onChosen();
            },
          ),
          const SizedBox(height: Gap.sm),
        ],
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          icon: const Pictogram(Pic.pencil, color: AppColors.primary),
          label: const Text('Своя цель'),
          onPressed: () => _openCustom(context),
        ),
        if (onCancel != null) ...<Widget>[
          const SizedBox(height: Gap.sm),
          TextButton(onPressed: onCancel, child: const Text('Оставить как было')),
        ],
      ],
    );
  }

  Future<void> _openCustom(BuildContext context) async {
    final String? id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => _CustomGoalSheet(app: app),
    );
    if (id == null || !context.mounted) return;
    CustomGoals.restore(app.content, id);
    final Goal? goal = app.content.goal(id);
    if (goal == null) return;
    await app.act((Game g) {
      g.chooseGoal(id);
      return ActionResult(
        title: 'Цель выбрана',
        text: '${goal.title} — ${goal.price} ${Coins.word(goal.price)}.',
        nextStep: 'Откладывай монетки в копилку — цель станет ближе',
      );
    });
    onChosen();
  }
}

class _GoalOption extends StatelessWidget {
  const _GoalOption({required this.goal, required this.onTap});

  final Goal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${goal.title}, ${goal.price} ${Coins.word(goal.price)}'
          '${goal.isExperience ? ', это впечатление, а не вещь' : ''}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.primary),
            padding: const EdgeInsets.fromLTRB(Gap.sm + 4, Gap.sm + 4, Gap.md, Gap.md + 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Сама вещь — тем же рисунком, что встанет в комнату.
                // Желанное видно до выбора, а не только название.
                SizedBox(
                  width: 96,
                  child: DreamArt(goal: goal, saved: goal.price, height: 96),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(goal.title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: Gap.xs),
                      Coins(goal.price),
                      // 🔴 Подпись у цели-впечатления. Common Sense Media
                      // снизила оценку Star Banks Adventure до 2/5 за посыл
                      // «успех — это накопить на вещь»; одна строка рядом
                      // с целью стоит дешевле, чем та же оценка у нас.
                      if (goal.isExperience) ...<Widget>[
                        const SizedBox(height: Gap.xs),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Pictogram(Pic.heart,
                                size: 18, color: AppColors.needs),
                            SizedBox(width: Gap.xs),
                            Expanded(
                              child: Text(
                                'Копить можно не только на вещи. '
                                'Впечатление — тоже цель.',
                                style: TextStyle(
                                    fontSize: 16, color: AppColors.needs),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Своя цель: название и цена выбираются из набора, а не вводятся.
class _CustomGoalSheet extends StatefulWidget {
  const _CustomGoalSheet({required this.app});

  final AppState app;

  @override
  State<_CustomGoalSheet> createState() => _CustomGoalSheetState();
}

class _CustomGoalSheetState extends State<_CustomGoalSheet> {
  int _title = 0;
  int _price = 0;

  @override
  Widget build(BuildContext context) {
    final List<String> titles = widget.app.content.customGoalTitles;
    final List<int> prices = widget.app.content.customGoalPrices;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Своя цель',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: Gap.md),
            const Text('Что это будет?',
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            const SizedBox(height: Gap.sm),
            for (int i = 0; i < titles.length; i++) ...<Widget>[
              _ChoiceRow(
                selected: i == _title,
                label: titles[i],
                onTap: () => setState(() => _title = i),
              ),
              const SizedBox(height: Gap.sm),
            ],
            const SizedBox(height: Gap.sm),
            const Text('Сколько это стоит?',
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: <Widget>[
                for (int i = 0; i < prices.length; i++)
                  SizedBox(
                    height: TapSize.min,
                    child: _ChoiceRow(
                      selected: i == _price,
                      label: '${prices[i]} ${Coins.word(prices[i])}',
                      onTap: () => setState(() => _price = i),
                      shrink: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: prices.isEmpty || titles.isEmpty
                  ? null
                  : () => Navigator.of(context)
                      // В идентификатор уходят номера выбранных вариантов,
                      // а не само число: цена должна браться из контента,
                      // иначе она застынет в старом масштабе.
                      .pop(CustomGoals.idFor(_title, _price)),
              child: const Text('Выбрать эту цель'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор одного варианта. Галочка и рамка, а не только цвет (§3.6.5).
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.selected,
    required this.label,
    required this.onTap,
    this.shrink = false,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.savingsBg : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.min),
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.md, vertical: Gap.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? AppColors.savings : AppColors.line,
                  width: 2),
            ),
            child: Row(
              mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
              children: <Widget>[
                Pictogram(selected ? Pic.check : Pic.circleEmpty,
                    size: 24,
                    color: selected ? AppColors.savings : AppColors.inkSoft),
                const SizedBox(width: Gap.sm),
                if (shrink)
                  Text(label, style: const TextStyle(fontSize: 16))
                else
                  Expanded(
                      child: Text(label,
                          style: const TextStyle(fontSize: 16))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── цель и копилка ─────────────────────────

class _GoalBlock extends StatelessWidget {
  const _GoalBlock({
    required this.app,
    required this.goal,
    required this.cheer,
    required this.onReached,
    required this.onChangeGoal,
  });

  final AppState app;
  final Goal goal;

  /// Разлёт монеток: 0 — покой, 1 — всё уже осыпалось.
  final Animation<double> cheer;

  /// Взнос, после которого цели хватило.
  final VoidCallback onReached;

  final VoidCallback onChangeGoal;

  @override
  Widget build(BuildContext context) {
    final Game g = app.game;
    final Wallet w = g.snapshot.wallet;
    final GoalForecast f = g.forecast!;
    final int depositable = w.unallocated + w.envelopes.needs + w.envelopes.wants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Stack(
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Pictogram(goalPic(goal.icon),
                            size: 30, color: AppColors.savings),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(goal.title,
                                style: Theme.of(context).textTheme.titleLarge),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    // Мечта — тем же чертежом, что стоит в комнате Финни.
                    DreamArt(goal: goal, saved: w.savings),
                    if (goal.isExperience)
                      const Padding(
                        padding: EdgeInsets.only(top: Gap.xs),
                        child: Text(
                          'Копить можно не только на вещи. Впечатление — тоже цель.',
                          style: TextStyle(fontSize: 16, color: AppColors.needs),
                        ),
                      ),
                    const SizedBox(height: Gap.md),
                    // Карта монеток. Не украшение: Whitebread & Bingham (2013)
                    // рекомендуют «tangible activities such as making a savings
                    // chart… colouring in some coins on the chart».
                    _BigCoinChart(saved: w.savings, total: goal.price),
                    const SizedBox(height: Gap.md),
                    // §2.5.7.2: стоимость, накопленное и оставшийся объём — рядом.
                    // Сумма досчитывает до нового значения: «стало на три
                    // больше» видно тогда, когда число прошло через эти три.
                    Semantics(
                      label: 'Накоплено ${w.savings} из ${goal.price}',
                      excludeSemantics: true,
                      child: CountUp(
                        value: w.savings,
                        builder: (BuildContext c, int shown) => Text(
                            'Накоплено $shown из ${goal.price}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      f.reached
                          ? 'Мечта набрана! Её можно исполнить.'
                          : 'Осталось ${f.remaining} ${Coins.word(f.remaining)}',
                      style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
                    ),
                    const SizedBox(height: Gap.sm),
                    // §2.5.7.4: срок — только из средней суммы пополнения.
                    // Если считать не из чего, показывается причина, а не число.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Pictogram(Pic.clock,
                            size: 20, color: AppColors.inkSoft),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(forecastSentence(f),
                              style: const TextStyle(
                                  fontSize: 16, color: AppColors.inkSoft)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // 🔴 Слой поверх карточки и без перехвата касаний: монетки
            // разлетаются, а ребёнок в это время уже может нажать
            // «Отложить монетки» ещё раз.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _GoalCheer(cheer)),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        if (g.goalReached) ...<Widget>[
          // Мечта набрана — главное действие экрана меняется: теперь
          // золотая кнопка исполняет мечту, а откладывать можно и дальше.
          FilledButton.icon(
            icon: const Pictogram(Pic.star, color: AppColors.onAction),
            label: const Text('Исполнить мечту'),
            onPressed: () => _fulfil(context, app, goal),
          ),
          const SizedBox(height: Gap.sm),
        ],
        (g.goalReached ? OutlinedButton.icon : FilledButton.icon)(
          icon: Pictogram(Pic.jar,
              color: g.goalReached ? AppColors.primary : AppColors.onAction),
          label: const Text('Отложить монетки'),
          onPressed:
              depositable > 0 ? () => _openDeposit(context, app) : null,
        ),
        if (depositable == 0)
          const Padding(
            padding: EdgeInsets.only(top: Gap.xs),
            child: Text(
              'Сейчас откладывать нечего — монетки придут в начале недели '
              'или за задание.',
              style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
            ),
          ),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          icon: const Pictogram(Pic.undo, color: AppColors.primary),
          label: const Text('Взять из копилки'),
          onPressed:
              w.savings > 0 ? () => _openWithdraw(context, app, goal) : null,
        ),
        if (w.savings == 0)
          const Padding(
            padding: EdgeInsets.only(top: Gap.xs),
            child: Text(
              'В копилке пока пусто — брать нечего.',
              style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
            ),
          ),
        const SizedBox(height: Gap.sm),
        TextButton(
          onPressed: onChangeGoal,
          child: const Text('Выбрать другую цель'),
        ),
      ],
    );
  }

  /// Исполнение мечты (§3.6.8: заметно меняет прогресс — с подтверждением).
  ///
  /// 🔴 Диалог называет последствие числами — сколько уйдёт и сколько
  /// останется, — а не спрашивает «вы уверены?»: на такой вопрос семилетка
  /// отвечает «да», не читая.
  Future<void> _fulfil(BuildContext context, AppState app, Goal goal) async {
    final int have = app.game.snapshot.wallet.savings;
    final int left = have - goal.price;
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text('Исполнить «${goal.title}»?'),
            content: Text(
              'Из копилки уйдёт ${goal.price} ${Coins.wordAccusative(goal.price)}, '
              'останется $left. Мечта встанет во дворе у дерева — насовсем, '
              'и можно будет выбрать следующую.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Пока подожду'),
              ),
              FilledButton(
                style: const ButtonStyle(
                  minimumSize:
                      WidgetStatePropertyAll<Size>(Size(0, TapSize.min)),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Исполнить'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    await app.act((Game g) => g.fulfillGoal());
    if (!context.mounted || app.lastFeedback == null) return;
    final Game g = app.game;
    // Единственный большой праздник: мечта во дворе с искрами, Финни
    // радуется и один раз подпрыгивает (без движения — сразу на месте).
    await showFeedback(
      context,
      app.lastFeedback!,
      cue: Cue.earn,
      room: RoomScene(
        stage: g.snapshot.stage,
        keepsakes: g.keepsakes,
        saved: g.snapshot.wallet.savings,
        fulfilled: g.fulfilledGoals,
        freshDream: true,
      ),
    );
    // Дальше экран сам показывает выбор следующей мечты: цель сброшена.
  }

  Future<void> _openDeposit(BuildContext context, AppState app) async {
    final _DepositIntent? intent = await showModalBottomSheet<_DepositIntent>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => _DepositSheet(app: app),
    );
    if (intent == null || !context.mounted) return;
    final bool was = app.game.forecast?.reached ?? false;
    await app.act((Game g) => intent.from == null
        // §2.5.7.3: монетки, которые ещё не разложены, уходят в копилку
        // как распределение; уже разложенные — как перекладывание.
        ? g.allocate(Envelope.savings, intent.amount)
        : g.move(
            from: intent.from!, to: Envelope.savings, amount: intent.amount));
    final bool justReached = !was && (app.game.forecast?.reached ?? false);
    if (context.mounted && app.lastFeedback != null) {
      // Взнос — решение в пользу мечты, и Финни ему радуется.
      await showFeedback(context, app.lastFeedback!, cheer: true);
    }
    // 🔴 После карточки последствия, а не до. Карточка — модальный лист
    // с затемнением: запущенный раньше разлёт монеток ребёнок досмотрел бы
    // сквозь серую пелену, то есть не досмотрел бы.
    if (justReached) onReached();
  }

  Future<void> _openWithdraw(
      BuildContext context, AppState app, Goal goal) async {
    final _WithdrawIntent? intent = await showModalBottomSheet<_WithdrawIntent>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => _WithdrawSheet(app: app, goal: goal),
    );
    if (intent == null || !context.mounted) return;
    await app.act((Game g) => g.move(
        from: Envelope.savings, to: intent.to, amount: intent.amount));
    if (context.mounted && app.lastFeedback != null) {
      await showFeedback(context, app.lastFeedback!);
    }
  }
}

/// Сетка монеток покрупнее, чем на главном экране: здесь она главный объект.
class _BigCoinChart extends StatelessWidget {
  const _BigCoinChart({required this.saved, required this.total});

  final int saved;
  final int total;

  @override
  Widget build(BuildContext context) {
    // При крупных числах («числа покрупнее» умножают всё на 5) одна точка
    // становится несколькими монетками — иначе сетка перестаёт читаться.
    final int step = total <= 40 ? 1 : (total / 40).ceil();
    final int dots = total <= 0 ? 0 : (total / step).ceil();
    final int filled = (saved / step).floor().clamp(0, dots);
    return Semantics(
      label: 'Карта монеток: закрашено $filled из $dots',
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: List<Widget>.generate(dots, (int i) {
          final bool on = i < filled;
          return Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? AppColors.coin : Colors.transparent,
              // Пустая монетка — обводкой 3:1 к белому: именно пустые
              // показывают, сколько ещё осталось.
              border: Border.all(
                  color: on ? AppColors.coinDeep : const Color(0xFF7A8A7D),
                  width: 2),
            ),
            // Закрашенная монетка отличается не только цветом (§3.6.5).
            child: on
                ? const Pictogram(Pic.check, size: 14, color: AppColors.ink)
                : null,
          );
        }),
      ),
    );
  }
}

/// Разлёт монеток над копилкой: цель набрана.
///
/// 🔴 Ровно один проход, 600 мс, и ничего больше. Ни цикла, ни конфетти
/// на весь экран: §6 запрещает движение само по себе, а WCAG 2.3.3 —
/// крупное движение через поле зрения. Здесь движется десяток кружков
/// в пределах карточки.
class _GoalCheer extends CustomPainter {
  _GoalCheer(this.t) : super(repaint: t);

  static const int _count = 10;

  final Animation<double> t;

  final Paint _coin = Paint()..color = AppColors.coin;

  @override
  void paint(Canvas canvas, Size size) {
    final double v = t.value;
    // В покое (0) и после (1) не рисуется ничего: слой всегда в дереве,
    // но существует он только эти 600 мс.
    if (v <= 0 || v >= 1) return;

    final Offset from = Offset(size.width / 2, size.height * 0.34);
    final double reach = math.min(size.width, size.height) * 0.42;
    final double fade = (1 - v) * (1 - v);
    final double spread = Curves.easeOutCubic.transform(v);

    for (int i = 0; i < _count; i++) {
      // Углы считаются, а не берутся случайно: случайность в painter'е
      // означала бы новую картинку на каждом кадре.
      final double a = -math.pi / 2 + (i - (_count - 1) / 2) * 0.42;
      final double r = reach * spread * (0.7 + 0.3 * (i.isEven ? 1 : 0.6));
      final Offset p = from +
          Offset(math.cos(a) * r, math.sin(a) * r) +
          // Монетки не улетают вверх навсегда: к концу их тянет вниз.
          Offset(0, reach * 0.35 * v * v);
      // 🔴 Прозрачность — в самой краске, а не виджетом Opacity:
      // Opacity поднимает saveLayer, самый дорогой вызов во фреймворке.
      _coin.color = AppColors.coin.withValues(alpha: fade);
      canvas.drawCircle(p, 6 - 2 * v, _coin);
    }
  }

  @override
  bool shouldRepaint(_GoalCheer old) => old.t != t;
}

// ───────────────────────── отложить ─────────────────────────

class _DepositIntent {
  const _DepositIntent(this.from, this.amount);

  /// null — монетки ещё не разложены по конвертам.
  final Envelope? from;
  final int amount;
}

class _Source {
  const _Source(this.label, this.envelope, this.available);

  final String label;
  final Envelope? envelope;
  final int available;
}

class _DepositSheet extends StatefulWidget {
  const _DepositSheet({required this.app});

  final AppState app;

  @override
  State<_DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<_DepositSheet> {
  int _source = 0;
  int _amount = 1;

  @override
  Widget build(BuildContext context) {
    final Wallet w = widget.app.game.snapshot.wallet;
    final List<_Source> sources = <_Source>[
      if (w.unallocated > 0)
        _Source('Новые монетки', null, w.unallocated),
      if (w.envelopes.wants > 0)
        _Source('Конверт «Хочу»', Envelope.wants, w.envelopes.wants),
      if (w.envelopes.needs > 0)
        _Source('Конверт «Нужное»', Envelope.needs, w.envelopes.needs),
    ];
    if (sources.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Gap.lg),
          child: Text(
            'Откладывать пока нечего. Монетки придут в начале недели '
            'или за задание.',
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }
    final int index = _source.clamp(0, sources.length - 1);
    final _Source source = sources[index];
    final int amount = _amount.clamp(1, source.available);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Отложить монетки',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: Gap.md),
            const Text('Откуда взять?',
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            const SizedBox(height: Gap.sm),
            for (int i = 0; i < sources.length; i++) ...<Widget>[
              _ChoiceRow(
                selected: i == index,
                label: '${sources[i].label} — ${sources[i].available} '
                    '${Coins.word(sources[i].available)}',
                onTap: () => setState(() {
                  _source = i;
                  _amount = _amount.clamp(1, sources[i].available);
                }),
              ),
              const SizedBox(height: Gap.sm),
            ],
            const SizedBox(height: Gap.sm),
            const Text('Сколько отложить?',
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            const SizedBox(height: Gap.sm),
            CoinStepper(
              label: 'Отложить',
              value: amount,
              min: 1,
              max: source.available,
              onChanged: (int v) => setState(() => _amount = v),
            ),
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop(_DepositIntent(source.envelope, amount)),
              child: Text('Отложить $amount ${Coins.word(amount)}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── взять из копилки ─────────────────────────

class _WithdrawIntent {
  const _WithdrawIntent(this.to, this.amount);

  final Envelope to;
  final int amount;
}

/// 🔴 §2.5.7.5: «снятие … только после отдельного подтверждения. До
/// подтверждения приложение показывает, как уменьшится накопленная сумма и …
/// как изменится срок достижения цели». Поэтому предпросмотр живёт прямо
/// в листе и пересчитывается на каждое нажатие −1/+1, а сам перевод
/// происходит только по кнопке «Да, взять».
class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.app, required this.goal});

  final AppState app;
  final Goal goal;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  Envelope _to = Envelope.needs;
  int _amount = 1;

  @override
  Widget build(BuildContext context) {
    final Game g = widget.app.game;
    final int savings = g.snapshot.wallet.savings;
    final int amount = _amount.clamp(1, SavingsRules.maxWithdraw(savings));
    final WithdrawPreview preview = SavingsRules.previewWithdraw(
      goal: widget.goal,
      savings: savings,
      amount: amount,
      depositHistory: g.depositHistory,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Взять из копилки',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: Gap.sm),
            const Text(
              'Иногда монетки нужны прямо сейчас. Это не ошибка — просто '
              'посмотри, что будет с целью.',
              style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
            ),
            const SizedBox(height: Gap.md),
            const Text('Сколько взять?',
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            const SizedBox(height: Gap.sm),
            CoinStepper(
              label: 'Взять',
              value: amount,
              min: 1,
              max: SavingsRules.maxWithdraw(savings),
              onChanged: (int v) => setState(() => _amount = v),
            ),
            const SizedBox(height: Gap.md),
            const Text('Куда положить?',
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            const SizedBox(height: Gap.sm),
            for (final Envelope e in <Envelope>[
              Envelope.needs,
              Envelope.wants
            ]) ...<Widget>[
              _ChoiceRow(
                selected: _to == e,
                label: 'В конверт «${e.title}»',
                onTap: () => setState(() => _to = e),
              ),
              const SizedBox(height: Gap.sm),
            ],
            const SizedBox(height: Gap.sm),
            Container(
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: AppColors.savingsBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.savings, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Что изменится',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: Gap.xs),
                  Text(
                    'В копилке было ${preview.savingsBefore}, '
                    'станет ${preview.savingsAfter}.',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(termChangeSentence(preview),
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_WithdrawIntent(_to, amount)),
              child: Text('Да, взять $amount ${Coins.word(amount)}'),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Не надо, оставить в копилке'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── непредвиденный расход ─────────────────────────

/// Четыре равноправных выхода.
///
/// 🔴 Четвёртый — «обойтись и перенести» — обязателен и подан той же кнопкой,
/// что и остальные. Без него это не выбор, а налог с тремя способами оплаты.
/// Тон бытовой: Финни не болеет, исход поправим, никакой спешки.
class _UnexpectedCard extends StatelessWidget {
  const _UnexpectedCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final UnexpectedEvent event = app.game.unexpectedThisWeek!;
    final int cost = event.cost;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Pictogram(Pic.umbrella,
                    size: 28, color: AppColors.savings),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(event.title,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(
              '${event.need} — $cost ${Coins.word(cost)}. '
              'Выбери, как поступить: все четыре варианта нормальные.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: Gap.md),
            _ChoiceButton(
              icon: Pic.jar,
              // Сумма прямо в подписи: ребёнок видит цену решения до нажатия,
              // а не после. Заодно кнопка не путается с «Взять из копилки»
              // у цели — это разные действия.
              label: 'Взять $cost из копилки',
              onPressed: () => _pay(context, Envelope.savings),
            ),
            const SizedBox(height: Gap.sm),
            _ChoiceButton(
              icon: Pic.ball,
              label: 'Взять $cost из конверта «Хочу»',
              onPressed: () => _pay(context, Envelope.wants),
            ),
            const SizedBox(height: Gap.sm),
            // Заработать можно, только пока не кончилась подработка недели:
            // иначе кнопка обещала бы монетки, которых задание не даст.
            if (!app.game.earnCapReached) ...<Widget>[
              _ChoiceButton(
                icon: Pic.task,
                label: 'Выполнить задание и заработать',
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.tasks),
              ),
              const SizedBox(height: Gap.sm),
            ],
            _ChoiceButton(
              icon: Pic.house,
              label: event.deferLabel,
              onPressed: () => _defer(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pay(BuildContext context, Envelope from) async {
    await app.act((Game g) => g.payUnexpected(from));
    if (context.mounted && app.lastFeedback != null) {
      await showFeedback(context, app.lastFeedback!);
    }
  }

  Future<void> _defer(BuildContext context) async {
    await app.act((Game g) => g.deferUnexpected());
    if (context.mounted && app.lastFeedback != null) {
      await showFeedback(context, app.lastFeedback!);
    }
  }
}

/// Кнопка с иконкой и переносимой подписью.
///
/// `OutlinedButton.icon` кладёт подпись в Row без Flexible, и длинная строка
/// на 360 dp при системном увеличении шрифта уезжает за край. Здесь текст
/// в Expanded и переносится.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Pic icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
            horizontal: Gap.md, vertical: Gap.sm),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: <Widget>[
          Pictogram(icon, size: 24, color: AppColors.primary),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(label, textAlign: TextAlign.left)),
        ],
      ),
    );
  }
}

// ───────────────────────── общие мелочи ─────────────────────────

/// Пиктограмма цели по ключу из контента. Растровых картинок в проекте нет.
Pic goalPic(String key) => switch (key) {
      'zoo' => Pic.paw,
      'house' => Pic.house,
      'scooter' => Pic.scooter,
      _ => Pic.flag,
    };

String weekWord(int n) {
  final int m10 = n % 10;
  final int m100 = n % 100;
  if (m100 >= 11 && m100 <= 14) return 'недель';
  if (m10 == 1) return 'неделя';
  if (m10 >= 2 && m10 <= 4) return 'недели';
  return 'недель';
}

/// Фраза о сроке. 🔴 Если [GoalForecast.weeks] пуст — показывается причина,
/// а не выдуманное число (§2.5.7.4: расчёт должен быть понятным).
String forecastSentence(GoalForecast f) {
  if (f.reached) return 'Цель набрана.';
  final int? weeks = f.weeks;
  if (weeks == null) return f.reason ?? 'Срок пока не считается.';
  return 'Ты откладываешь в среднем по ${f.averageDeposit} '
      '${Coins.word(f.averageDeposit)} в неделю. Значит, осталось примерно '
      '$weeks ${weekWord(weeks)}.';
}

/// Как снятие изменит срок. Ровно два числа, и оба — из [SavingsRules].
String termChangeSentence(WithdrawPreview p) {
  final int? before = p.before.weeks;
  final int? after = p.after.weeks;
  if (before == null || after == null) {
    final String reason = p.after.reason ?? p.before.reason ?? '';
    return 'Срок до цели пока не считается. $reason'.trim();
  }
  if (before == after) {
    return 'До цели было $before ${weekWord(before)} — столько и останется.';
  }
  return 'До цели было $before ${weekWord(before)}, '
      'станет $after ${weekWord(after)}.';
}
