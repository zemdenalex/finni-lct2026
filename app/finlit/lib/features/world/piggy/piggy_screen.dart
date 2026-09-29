import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/phrases.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/goal_eta.dart';
import '../shop/shop_kit.dart';
import '../world_layout.dart';
import '../world_state.dart';
import '../../../core/world_theme.dart';

/// S9 — копилка: активная цель, накоплено / цена / осталось, выбор цели,
/// «отложить из кошелька», «снять» с превью «было / станет» и отдельным
/// подтверждением, покупка цели (`docs/game/goals-savings.md`), примерный
/// срок до цели по среднему пополнению закрытых недель ([goalEta]).
class PiggyScreen extends StatefulWidget {
  const PiggyScreen({super.key});

  /// Шаг выбора суммы.
  static const int step = 10;

  @override
  State<PiggyScreen> createState() => _PiggyScreenState();
}

class _PiggyScreenState extends State<PiggyScreen> {
  WorldResult? _last;

  /// Реестр арта — картинки целей (ноутбук, транспорт, питомцы). Читается
  /// один раз при открытии экрана, как в магазине.
  AssetRegistry? _reg;

  @override
  void initState() {
    super.initState();
    AssetRegistry.load().then((AssetRegistry r) {
      if (mounted) setState(() => _reg = r);
    }, onError: (Object _) {});
  }

  int _deposit = 0;
  int _withdraw = 0;

  WorldState get _state => context.read<WorldState>();

  void _show(WorldResult r) => setState(() {
        _last = r;
        _deposit = 0;
        _withdraw = 0;
      });

  void _choose(WorldCatalogItem e) =>
      _show(_state.act((World w) => w.chooseGoal(e.id)));

  void _depositNow(int amount) =>
      _show(_state.act((World w) => w.depositToGoal(amount)));

  Future<void> _withdrawNow(int amount) async {
    final WorldState st = _state;
    final ResourceSnapshot s = st.snapshot;
    final WorldCatalogItem? goal =
        s.activeGoalId == null ? null : st.world.catalogItem(s.activeGoalId!);
    final bool yes = await confirmAction(
      context,
      title: 'Снять $amount из копилки?',
      lines: <String>[
        'В копилке: было ${s.goal} → станет ${s.goal - amount}.',
        'В кошельке: было ${s.free} → станет ${s.free + amount}.',
        if (goal != null)
          'До цели «${goal.title}»: было ${math.max(0, goal.price - s.goal)} '
              '→ станет ${math.max(0, goal.price - s.goal + amount)}.',
      ],
      yes: 'Снять',
      no: 'Оставить',
    );
    if (!yes || !mounted) return;
    _show(st.act((World w) => w.withdrawFromGoal(amount)));
  }

  Future<void> _buy(WorldCatalogItem e) async {
    final WorldState st = _state;
    if (!await confirmBuy(context, st.world, e) || !mounted) return;
    _show(st.act((World w) => w.buy(e.id)));
  }

  @override
  Widget build(BuildContext context) {
    final WorldState st = context.watch<WorldState>();
    // Каталог и запреты читаются заново при каждой перерисовке: мир живой.
    final World w = st.world;
    final ResourceSnapshot s = st.snapshot;
    final int deposit = math.min(_deposit, s.free);
    final int withdraw = math.min(_withdraw, s.goal);
    final WorldCatalogItem? goal =
        s.activeGoalId == null ? null : w.catalogItem(s.activeGoalId!);

    final bool land = WorldLayout.isLandscape(context);
    final Widget goalPanel = _GoalPanel(
      goal: goal,
      snapshot: s,
      eta: goal == null
          ? null
          : goalEta(w.weekHistory, math.max(0, goal.price - s.goal)),
      buyBlock: goal == null ? null : w.canDo(WorldAction.buy, id: goal.id),
      onBuy: _buy,
    );
    final Widget depositPanel = _MovePanel(
      key: const ValueKey<String>('piggy:deposit'),
      icon: Icons.south_rounded,
      title: 'Отложить из кошелька',
      text: 'В кошельке заработка ${s.free}.',
      empty: 'В кошельке пусто — отложить нечего. Заработать можно '
          'сменой на работе.',
      id: 'deposit',
      value: deposit,
      max: s.free,
      onChanged: (int v) => setState(() => _deposit = v),
      action: 'Отложить',
      onGo: () => _depositNow(deposit),
    );
    final Widget withdrawPanel = _MovePanel(
      key: const ValueKey<String>('piggy:withdraw'),
      icon: Icons.north_rounded,
      title: 'Снять из копилки',
      text: 'В копилке ${s.goal}. Снятое уйдёт в кошелёк.',
      empty: 'В копилке пусто — снимать нечего.',
      id: 'withdraw',
      value: withdraw,
      max: s.goal,
      onChanged: (int v) => setState(() => _withdraw = v),
      action: 'Снять',
      onGo: () => _withdrawNow(withdraw),
    );
    final List<Widget> goals = <Widget>[
      const Text('На что копить', style: kitTitle),
      const SizedBox(height: Gap.xs),
      const Text('Накопленное остаётся в копилке, если сменить цель.',
          style: kitSoft),
      for (final (WorldCatalogCategory sec, String name)
          in const <(WorldCatalogCategory, String)>[
        (WorldCatalogCategory.pet, 'Питомцы'),
        (WorldCatalogCategory.transport, 'Транспорт'),
        (WorldCatalogCategory.tech, 'Техника'),
        (WorldCatalogCategory.home, 'Жильё'),
      ]) ...<Widget>[
        const SizedBox(height: Gap.sm),
        Text(name,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: WorldColors.textSoft)),
        for (final WorldCatalogItem e in catalogOf(w, sec))
          _GoalRow(
            key: ValueKey<String>('row:${e.id}'),
            entry: e,
            snapshot: s,
            block: w.canDo(WorldAction.chooseGoal, id: e.id),
            onChoose: () => _choose(e),
            picture: _reg?.item(e.id),
          ),
      ],
    ];

    return WorldPage(
      id: 'piggy',
      title: 'Копилка',
      snapshot: s,
      helpTitle: 'Копилка',
      // В альбомной итог — над переносом монет справа, а не третьей колонкой.
      result: land ? null : _last,
      help: 'Копилка — конверт ЦЕЛЬ. Монеты здесь не тратятся на покупки, '
          'только на цель.\n\n'
          '«Отложить» переносит монеты из кошелька заработка в копилку. '
          '«Снять» возвращает их в кошелёк — сначала покажем, что было и '
          'что станет.\n\n'
          'Цель можно сменить: накопленное останется в копилке. Когда '
          'накоплено хватает — цель можно купить.',
      body: land
          // Альбомная: цель и выбор цели слева, перенос монет справа.
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: ListView(
                    key: const ValueKey<String>('piggy:goals'),
                    padding: const EdgeInsets.fromLTRB(
                        Gap.md, Gap.sm, Gap.xs, Gap.lg),
                    children: <Widget>[
                      goalPanel,
                      const SizedBox(height: Gap.md),
                      ...goals,
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Итог закреплён над прокруткой: после «Снять» внизу
                      // списка он всё равно на виду.
                      if (_last != null)
                        Flexible(
                          // Длинный итог при крупном шрифте — не выше
                          // половины панели, дальше прокручивается.
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                                Gap.xs, Gap.sm, Gap.md, 0),
                            child: ResultCard(_last!),
                          ),
                        ),
                      Expanded(
                        child: ListView(
                          key: const ValueKey<String>('piggy:moves'),
                          padding: const EdgeInsets.fromLTRB(
                              Gap.xs, Gap.sm, Gap.md, Gap.lg),
                          children: <Widget>[
                            depositPanel,
                            const SizedBox(height: Gap.sm),
                            withdrawPanel,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
              children: <Widget>[
                goalPanel,
                const SizedBox(height: Gap.md),
                depositPanel,
                const SizedBox(height: Gap.md),
                withdrawPanel,
                const SizedBox(height: Gap.md),
                ...goals,
              ],
            ),
    );
  }
}

class _GoalPanel extends StatelessWidget {
  const _GoalPanel({
    required this.goal,
    required this.snapshot,
    required this.eta,
    required this.buyBlock,
    required this.onBuy,
  });

  final WorldCatalogItem? goal;
  final ResourceSnapshot snapshot;

  /// Срок до цели; null — цель не выбрана или уже хватает.
  final GoalEta? eta;

  /// Почему цель сейчас не купить — ответ мира ([World.canDo]).
  final BlockReason? buyBlock;
  final ValueChanged<WorldCatalogItem> onBuy;

  @override
  Widget build(BuildContext context) {
    final ResourceSnapshot s = snapshot;
    final WorldCatalogItem? g = goal;
    if (g == null) {
      return Panel(
        key: const ValueKey<String>('piggy:goal'),
        color: WorldColors.goalBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const MarkLine(Icons.star_outline_rounded, 'Цель не выбрана',
                color: WorldColors.goal),
            const SizedBox(height: Gap.xs),
            Text(
                'В копилке ${s.goal}. Выбери цель ниже — накопленное '
                'пойдёт на неё.',
                style: kitText),
          ],
        ),
      );
    }
    final int left = math.max(0, g.price - s.goal);
    final double fill = (s.goal / g.price).clamp(0.0, 1.0);
    return Panel(
      key: const ValueKey<String>('piggy:goal'),
      color: WorldColors.goalBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const MarkLine(Icons.star_rounded, 'Цель', color: WorldColors.goal),
          Text(g.title, style: kitTitle),
          const SizedBox(height: Gap.xs),
          Text('Цена ${g.price} · накоплено ${s.goal} · осталось $left',
              key: const ValueKey<String>('piggy:numbers'), style: kitText),
          const SizedBox(height: Gap.xs),
          Semantics(
            label: 'Накоплено ${(fill * 100).round()} процентов',
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: fill,
                      minHeight: 12,
                      color: WorldColors.goal,
                      backgroundColor: WorldColors.panel,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text('${(fill * 100).round()} %', style: kitText),
              ],
            ),
          ),
          if (eta case final GoalEta e) ...<Widget>[
            const SizedBox(height: Gap.xs),
            Text(_etaLine(e),
                key: const ValueKey<String>('piggy:eta'), style: kitSoft),
          ],
          const SizedBox(height: Gap.xs),
          if (buyBlock case final BlockReason b)
            BlockNote(b, key: const ValueKey<String>('piggy:block'))
          else
            FilledButton.icon(
              key: const ValueKey<String>('piggy:buy'),
              style: FilledButton.styleFrom(minimumSize: kitButton),
              onPressed: () => onBuy(g),
              icon: const Icon(Icons.shopping_bag_rounded),
              label: Text('Купить: ${g.title}'),
            ),
        ],
      ),
    );
  }
}

/// Строка срока до цели на S9 — без давления: «как сейчас», «примерно».
String _etaLine(GoalEta e) {
  final int? weeks = e.weeks;
  if (weeks != null) {
    return 'Если откладывать как сейчас (~${e.perWeek} в неделю) — '
        'примерно $weeks ${Phrases.weekWord(weeks)}.';
  }
  return switch (e.reason!) {
    GoalEtaGap.noDeposit =>
      'Срок посчитаем после первого взноса в копилку — по тому, сколько '
          'получается откладывать.',
  };
}

/// Перенос монет: сумма ползунком и кнопками −/+, затем действие.
class _MovePanel extends StatelessWidget {
  const _MovePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.empty,
    required this.id,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.action,
    required this.onGo,
  });

  final IconData icon;
  final String title;
  final String text;
  final String empty;

  /// Префикс ключей: `deposit`, `withdraw`.
  final String id;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  final String action;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    const int step = PiggyScreen.step;
    final bool land = WorldLayout.isLandscape(context);
    final Widget go = FilledButton(
      key: ValueKey<String>('$id:go'),
      style: FilledButton.styleFrom(minimumSize: kitButton),
      onPressed: value > 0 ? onGo : null,
      child: Text('$action $value'),
    );
    return Panel(
      padding: EdgeInsets.all(land ? Gap.sm : Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(children: <Widget>[
            Icon(icon, color: WorldColors.goal),
            const SizedBox(width: Gap.xs),
            Expanded(child: Text(title, style: kitTitle)),
          ]),
          const SizedBox(height: Gap.xs),
          Text(max == 0 ? empty : text, style: kitBody(context)),
          if (max > 0) ...<Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  key: ValueKey<String>('$id:minus'),
                  tooltip: '$title: меньше на $step',
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: value > 0
                      ? () => onChanged(math.max(0, value - step))
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Expanded(
                  child: Slider(
                    key: ValueKey<String>('$id:slider'),
                    value: value.toDouble(),
                    max: max.toDouble(),
                    divisions: math.max(1, max ~/ step),
                    label: '$value',
                    onChanged: (double v) =>
                        onChanged(v >= max ? max : ((v / step).round() * step)),
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('$id:plus'),
                  tooltip: '$title: больше на $step',
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: value < max
                      ? () => onChanged(math.min(max, value + step))
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            Align(alignment: Alignment.centerRight, child: go),
          ],
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    super.key,
    required this.entry,
    required this.snapshot,
    required this.block,
    required this.onChoose,
    this.picture,
  });

  /// Картинка цели из реестра; нет — строка без картинки.
  final String? picture;

  final WorldCatalogItem entry;
  final ResourceSnapshot snapshot;

  /// Почему эту цель сейчас не выбрать — ответ мира ([World.canDo]).
  final BlockReason? block;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final WorldCatalogItem e = entry;
    final bool owned = snapshot.owned.contains(e.id);
    final bool active = snapshot.activeGoalId == e.id;
    final String weekly = e.weeklyCost == 0
        ? 'без платы в неделю'
        : switch (e.category) {
            WorldCatalogCategory.pet => 'корм ${e.weeklyCost} в неделю',
            _ => 'плата ${e.weeklyCost} в неделю',
          };
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Panel(
        padding: const EdgeInsets.all(Gap.sm),
        child: Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.xs,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            // Картинка цели (ноутбук, велосипед, питомец…), если есть арт.
            if (picture case final String p)
              ItemPicture(p, width: 48, height: 48),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(e.title,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: WorldColors.text)),
                PriceLine(e.price),
                Text(weekly, style: kitSoft),
                // Инструмент — вложение: что открывает и за сколько смен
                // окупится (ноутбук, транспорт; критерии ночи §3 п. 4).
                if (e.category == WorldCatalogCategory.tech ||
                    e.category == WorldCatalogCategory.transport ||
                    e.category == WorldCatalogCategory.home)
                  if (owned && snapshot.toolPayback.containsKey(e.id))
                    Text(
                        snapshot.toolPayback[e.id]! >= e.price
                            ? 'Окупился: принёс ${snapshot.toolPayback[e.id]} '
                                'сверх работы без него'
                            : 'Окупилось ${snapshot.toolPayback[e.id]} из '
                                '${e.price}',
                        key: ValueKey<String>('payback:${e.id}'),
                        style: kitSoft)
                  else if (e.perk case final String perk)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(perk,
                          key: ValueKey<String>('perk:${e.id}'),
                          style: kitSoft),
                    ),
              ],
            ),
            if (owned)
              const MarkLine(Icons.home_rounded, 'Уже есть')
            else if (active)
              const MarkLine(Icons.star_rounded, 'Копим',
                  color: WorldColors.goal)
            else ...<Widget>[
              OutlinedButton.icon(
                key: ValueKey<String>('goal:${e.id}'),
                style: OutlinedButton.styleFrom(minimumSize: kitButton),
                onPressed: block == null ? onChoose : null,
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('Копить'),
              ),
              if (block case final BlockReason b)
                BlockNote(b, key: ValueKey<String>('block:${e.id}')),
            ],
          ],
        ),
      ),
    );
  }
}
