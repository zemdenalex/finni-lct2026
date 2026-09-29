import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/world_art.dart';
import '../../domain/game.dart';
import '../../domain/models/task.dart';
import 'allocate_task_screen.dart';
import 'numeric_task_screen.dart';
import 'order_task_screen.dart';

/// Список заданий (§2.5.8).
///
/// Задания сгруппированы по темам — §2.5.8.1 требует минимум три темы:
/// планирование бюджета, формирование сбережений, платежи и покупки.
/// Группировка идёт по [TaskTopic], а не по вручную собранным спискам:
/// новое задание появляется в своей теме само, одним JSON-файлом (§2.5.14).
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Задания')));
    }
    final List<GameTask> tasks = app.game.availableTasks;

    return Scaffold(
      appBar: AppBar(title: const Text('Задания')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
          children: <Widget>[
            SceneHeader(
              // 🔴 Честно про лимит: если монеток осталось меньше, чем
              // стоит одно задание, их принесёт только следующее
              // выполненное — остальные будут ради интереса. Иначе чипы
              // «+1» на всех карточках обещали монетку, которой не будет.
              say: app.game.earnCapReached
                  ? 'Монетки за задания на этой неделе кончились. '
                      'Но разобраться всё равно интересно!'
                  : _onlyOneMorePaid(app.game)
                      ? 'Осталась последняя подработка: '
                          '${app.game.earnLeft} ${Coins.word(app.game.earnLeft)} '
                          'принесёт следующее задание. Остальные — ради интереса.'
                      : 'За задания — монетки. На этой неделе можно '
                          'заработать ещё ${app.game.earnLeft}.',
            ),
            const SizedBox(height: Gap.md),
            _EarningsPanel(game: app.game),
            const SizedBox(height: Gap.lg),
            if (tasks.isEmpty)
              const Text(
                'На этой неделе задания закончились. Новые появятся, '
                'когда начнётся следующая неделя.',
                style: TextStyle(fontSize: 18),
              ),
            for (final TaskTopic topic in TaskTopic.values) ...<Widget>[
              if (tasks.any((GameTask t) => t.topic == topic)) ...<Widget>[
                Semantics(
                  header: true,
                  child: Text(topic.title,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: Gap.sm),
                for (final GameTask t
                    in tasks.where((GameTask t) => t.topic == topic)) ...<Widget>[
                  _TaskCard(task: t, pay: _payFor(app.game, t)),
                  const SizedBox(height: Gap.sm),
                ],
                const SizedBox(height: Gap.md),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Лимит подработки кончится на первом же задании.
bool _onlyOneMorePaid(Game g) {
  int least = 1 << 30;
  for (final GameTask t in g.availableTasks) {
    if (t.reward < least) least = t.reward;
  }
  return g.earnLeft > 0 && g.earnLeft <= least;
}

/// Сколько монеток принесёт задание прямо сейчас — с учётом лимита недели.
int _payFor(Game g, GameTask t) => t.reward < g.earnLeft ? t.reward : g.earnLeft;

/// Подработка недели — **до** выбора задания.
///
/// 🔴 Ребёнок не должен узнавать о лимите постфактум, из карточки «монеток
/// не будет». Поэтому предел виден здесь заранее: сколько уже заработано,
/// сколько ещё можно, и что будет, когда подработка кончится.
class _EarningsPanel extends StatelessWidget {
  const _EarningsPanel({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final bool over = game.earnCapReached;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: const Text('Подработка на этой неделе',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            over
                ? 'Задания можно проходить ради интереса — то, в чём '
                    'разберёшься, останется с тобой. Монетки за них — '
                    'со следующей недели.'
                : 'Когда подработка кончится, задания останутся — '
                    'ради интереса.',
            style: const TextStyle(fontSize: 17, height: 1.4),
          ),
          const SizedBox(height: Gap.md),
          TrustBar(
            fromParents: game.trustBudget,
            earnCap: game.earnCap,
            earned: game.earnedThisPeriod,
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.pay});

  final GameTask task;

  /// Сколько принесёт сейчас: 0 — лимит недели исчерпан.
  final int pay;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${task.title}. ${kindTitle(task.kind)}. '
          '${pay > 0 ? 'Награда $pay' : 'Ради интереса, без монеток'}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openTask(context, task),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.primary),
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.md + 4),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: AppColors.needsBg, shape: BoxShape.circle),
                  child: Pictogram(kindPic(task.kind),
                      size: 26, color: AppColors.needs),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(task.title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(kindTitle(task.kind),
                          style: const TextStyle(
                              fontSize: 16, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                if (pay > 0)
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                        Gap.sm, Gap.xs, Gap.sm + 2, Gap.xs),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1CF),
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('+', style: AppType.number(18)),
                        Coins(pay, size: 18),
                      ],
                    ),
                  )
                else
                  const Text('ради\nинтереса',
                      textAlign: TextAlign.right,
                      style:
                          TextStyle(fontSize: 16, color: AppColors.inkSoft)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Открытие задания: у каждого вида свой проигрыватель.
Future<void> openTask(BuildContext context, GameTask task) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (BuildContext _) => taskPlayer(task)),
  );
}

Widget taskPlayer(GameTask task) => switch (task.kind) {
      TaskKind.allocate => AllocateTaskScreen(task: task),
      TaskKind.orderAndBuy => OrderTaskScreen(task: task),
      TaskKind.numericInput => NumericTaskScreen(task: task),
    };

/// Что предстоит делать — словами, до открытия задания.
String kindTitle(TaskKind kind) => switch (kind) {
      TaskKind.allocate => 'Разложить монетки',
      TaskKind.orderAndBuy => 'Расставить по очереди',
      TaskKind.numericInput => 'Посчитать',
    };

Pic kindPic(TaskKind kind) => switch (kind) {
      TaskKind.allocate => Pic.wallet,
      TaskKind.orderAndBuy => Pic.list,
      TaskKind.numericInput => Pic.calc,
    };
