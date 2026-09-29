import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../home/world_hud.dart';
import '../review/plan_fact_view.dart';
import '../review/week_review_screen.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import '../pic_text.dart';
import '../review/learned_view.dart';

/// S12 · Прогресс и история (`docs/game/screens-other.md`, ТЗ 2.5.11.1).
///
/// Сверху — где Финни сейчас: очки роста, стадия, цель. Ниже — недели, новая
/// первой: план против факта по конвертам, смены с оплатой, покупки,
/// события, цель на конец недели. Всё — из [World.weekHistory], то есть из
/// журнала; своего хранилища у экрана нет.
///
/// Альбомная: прогресс слева узкой колонкой, недели справа списком.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  void _back(BuildContext context) {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.room);
    }
  }

  void _help(BuildContext context) {
    showHelp(
        context,
        'Что здесь?',
        'Прогресс Финни и все недели.\n\n'
            '⭐ Очки роста копятся каждую неделю — за счета своими '
            'деньгами, неделю без нехватки и отложенные монеты.\n'
            'По каждой неделе видно, сколько мы положили в конверты '
            'по плану и сколько вышло на деле.\n'
            '💼 Смены, 🛍 покупки и ❗ события — тоже здесь.');
  }

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    final ResourceSnapshot now = ws.snapshot;
    final List<WeekPlanFact> weeks = ws.world.weekHistory.reversed.toList();
    final bool land = WorldLayout.isLandscape(context);
    final WorldCatalogItem? goal = now.activeGoalId == null
        ? null
        : ws.world.catalogItem(now.activeGoalId!);

    final Widget summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Summary(
            now: now,
            goal: goal,
            weeks: weeks.length,
            catalog: ws.world.catalog),
        const SizedBox(height: Gap.sm),
        LearnedPanel(learning: ws.world.learning),
      ],
    );
    final List<Widget> cards = <Widget>[
      if (weeks.isEmpty)
        const Text(
          key: ValueKey<String>('history:empty'),
          'Историю начнём с первой недели: разложи карманные по конвертам — '
          'и здесь появится план и что вышло на деле.',
          style: TextStyle(fontSize: 16, color: WorldColors.textSoft),
        ),
      for (int i = 0; i < weeks.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: Gap.sm),
        _WeekCard(
          week: weeks[i],
          pendingBill: weeks[i].weekNo == now.weekNo && !weeks[i].billsPaid
              ? now.weeklyBill
              : null,
        ),
      ],
    ];

    Widget list(List<Widget> children, EdgeInsets padding) =>
        SingleChildScrollView(
          key: const ValueKey<String>('history:list'),
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    final Widget content = OrientationSplit(
      landscape: (BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double side =
              (box.maxWidth * 0.36).clamp(220.0, 300.0).toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: side,
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
                  child: summary,
                ),
              ),
              Expanded(
                child: list(cards,
                    const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.md, Gap.md)),
              ),
            ],
          );
        },
      ),
      portrait: (BuildContext context) => list(
        <Widget>[summary, const SizedBox(height: Gap.md), ...cards],
        const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      ),
    );

    return Scaffold(
      backgroundColor: WorldColors.night,
      appBar: AppBar(
        toolbarHeight: land ? 48 : null,
        leading: IconButton(
          key: const ValueKey<String>('history:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: () => _back(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Прогресс'),
        actions: <Widget>[
          HelpButton(
            key: const ValueKey<String>('history:help'),
            onPressed: () => _help(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorldHud(snapshot: now),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// Где Финни сейчас: очки, стадия, до переезда, цель.
class _Summary extends StatelessWidget {
  const _Summary(
      {required this.now,
      required this.goal,
      required this.weeks,
      required this.catalog});

  final List<WorldCatalogItem> catalog;

  final ResourceSnapshot now;
  final WorldCatalogItem? goal;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final WorldCatalogItem? g = goal;
    final String goalLine = g == null
        ? '🐷 Цель не выбрана · в копилке ${now.saved}'
        : g.price > 0
            ? '🐷 ${g.title}: ${now.saved} из ${g.price}'
            : '🐷 ${g.title}: накоплено ${now.saved}';
    return _Panel(
      key: const ValueKey<String>('history:summary'),
      children: <Widget>[
        PicText('⭐ Очки роста: ${now.growthPoints}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: Gap.xs),
        _line('🏠 Финни живёт: ${WeekReviewScreen.stageName(now.stage)}'),
        _line(WeekReviewScreen.moveLine(now, catalog) ??
            '🏁 Это последняя стадия.'),
        _line(goalLine),
        if (g != null && g.price > 0) ...<Widget>[
          const SizedBox(height: Gap.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (now.saved / g.price).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              color: WorldColors.goal,
              backgroundColor: WorldColors.raised,
            ),
          ),
        ],
        _line('📅 Недель: $weeks'),
      ],
    );
  }
}

/// Одна неделя: план против факта, вывод, смены, покупки, события, цель.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week, this.pendingBill});

  final WeekPlanFact week;
  final int? pendingBill;

  @override
  Widget build(BuildContext context) {
    final WeekPlanFact w = week;
    String items(List<WeekItem> l, String sign) =>
        l.map((WeekItem i) => '${i.title} $sign${i.amount}').join(', ');
    final String goalLine = w.goalTitle == null
        ? '🐷 В копилке: ${w.savedAtEnd}'
        : (w.goalPrice ?? 0) > 0
            ? '🐷 Цель «${w.goalTitle}»: ${w.savedAtEnd} из ${w.goalPrice}'
            : '🐷 Цель «${w.goalTitle}»: накоплено ${w.savedAtEnd}';
    final List<Widget> details = <Widget>[
      _line(w.shifts.isEmpty
          ? '💼 Смен не было'
          : '💼 Смены: ${items(w.shifts, '+')}'),
      _line(w.purchases.isEmpty
          ? '🛍 Покупок не было'
          : '🛍 Покупки: ${items(w.purchases, '')}'),
      _line(w.events.isEmpty
          ? '❗ Событий не было'
          : '❗ События: ${w.events.join(', ')}'),
      if (w.parentBonus) _line('💼 от взрослого: дополнительная смена'),
      if (w.goalsReached.isNotEmpty)
        _line('🎉 Цель достигнута: ${w.goalsReached.join(', ')}'),
      _line(goalLine),
    ];
    final Widget plan = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PlanFactRows(
            week: w,
            keyPrefix: 'history:w${w.weekNo}',
            pendingBill: pendingBill),
        const SizedBox(height: Gap.xs),
        PicText('🙂 ${planFactTakeaway(w)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
    return _Panel(
      key: ValueKey<String>('history:week:${w.weekNo}'),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Неделя ${w.weekNo}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            PicText(w.billsPaid ? '✅ итоги' : '⏳ идёт',
                style:
                    const TextStyle(fontSize: 16, color: WorldColors.textSoft)),
          ],
        ),
        const SizedBox(height: Gap.xs),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) =>
              box.maxWidth >= 560
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: plan),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: details,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[plan, ...details],
                    ),
        ),
      ],
    );
  }
}

Widget _line(String text) => Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: PicText(text,
          style: const TextStyle(fontSize: 16, color: WorldColors.text)),
    );

/// Панель на тёмном фоне: текст никогда не лежит на картинке.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.sm + Gap.xs),
        decoration: BoxDecoration(
          color: WorldColors.panel,
          borderRadius: BorderRadius.circular(WorldRadii.tile),
          border: Border.all(color: WorldColors.line, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}
