import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../data/world_content.dart'
    show UniversityCard, UniversityContent;
import '../../../domain/world/contract.dart';
import '../home/world_hud.dart';
import '../world_help.dart';
import '../shop/shop_kit.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import 'board/job_offer_card.dart';
import 'job_games.dart';
import '../../../core/world_theme.dart';

/// S6 · «Требуется…»: доска смен (`docs/game/jobs-board.md`).
///
/// 🔴 Оплата, ⚡, опыт, ступень, бонус и остаток смен — поля [JobOffer] из
/// `world.jobBoard` как есть; экран ничего не пересчитывает (P4).
///
/// Смену нельзя взять — карточка не гаснет молча, а говорит почему
/// ([JobOffer.blockReason] мира: своей копии правил у доски нет).
class JobBoardScreen extends StatelessWidget {
  const JobBoardScreen({super.key});

  /// Карточка смены не уже этого: в альбомной 640 dp — две колонки.
  static const double _minCard = 260;

  /// Первая строка доски: что здесь делают и что каждая смена — мини-игра.
  static const String introText =
      'Выбери работу — каждая смена это мини-игра. Сколько заплатят — '
      'видно сразу.';

  /// Подпись над доской, если сейчас не работается совсем.
  static String? _phaseBanner(WeekPhase phase) => switch (phase) {
        WeekPhase.onboarding => 'Работа откроется, когда начнётся неделя.',
        WeekPhase.weekStart ||
        WeekPhase.planning =>
          'Работа — после плана недели. Вернись домой и нажми «План».',
        WeekPhase.review =>
          'Неделя кончилась. Посмотри итоги дома — и начнём новую.',
        WeekPhase.living => null,
      };

  /// Группы по работе в порядке доски: у курьера и программиста — уровни.
  static List<List<JobOffer>> _groups(List<JobOffer> board) {
    final Map<String, List<JobOffer>> by = <String, List<JobOffer>>{};
    for (final JobOffer o in board) {
      (by[o.jobId] ??= <JobOffer>[]).add(o);
    }
    return by.values.toList();
  }

  /// Название работы без уровня: «Курьер · близко» → «Курьер».
  static String _groupTitle(List<JobOffer> g) =>
      g.first.title.split(' · ').first;

  void _back(BuildContext context) {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.city);
    }
  }

  void _help(BuildContext context) {
    showHelp(
        context,
        'Что здесь?',
        'Это доска «Требуется…» — здесь берут смены.\n\n'
            'Работа — это финансовые задания: каждая смена — мини-игра.\n\n'
            '«Заплатят» — сколько монет дадут за смену. Число известно '
            'заранее и не уменьшится от ошибок или времени.\n'
            '⭐ — можно получить ещё немного сверху, если сделать хорошо.\n'
            '⚡ — сколько сил уйдёт. Силы тратятся только в конце смены: '
            'вышел раньше — ничего не потрачено.\n'
            '📈 — чем больше смен сделано, тем выше оплата.\n'
            '📅 — сколько раз эту работу ещё можно взять на неделе.\n\n'
            'Если смену сейчас не взять, на карточке написано почему.');
  }

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    final World world = ws.world;
    final WeekPhase phase = world.phase;
    final ResourceSnapshot snap = world.snapshot;
    final List<List<JobOffer>> groups = _groups(world.jobBoard);
    final String? banner = _phaseBanner(phase);

    final bool land = WorldLayout.isLandscape(context);
    UniversityContent uni = UniversityContent.empty;
    try {
      uni = context.read<JobGames>().university;
    } on ProviderNotFoundException {
      // Экран без содержания мини-игр (отдельный тест) — без блока вуза.
    }
    Widget card(JobOffer o) => Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: JobOfferCard(
            offer: o,
            onTake: () => Navigator.of(context).pushNamed(WorldRoutes.job,
                arguments: JobPlayArgs(o.jobId, variant: o.variant)),
          ),
        );
    // Одиночные работы подряд — одной сеткой, уровни одной работы — своей
    // сеткой под заголовком: в альбомной уровни не разъезжаются.
    final List<Widget> sections = <Widget>[];
    final List<Widget> singles = <Widget>[];
    void flushSingles() {
      if (singles.isEmpty) return;
      sections.add(CardGrid(
          minCard: _minCard,
          maxColumns: 2,
          children: List<Widget>.of(singles)));
      singles.clear();
    }

    for (final List<JobOffer> g in groups) {
      if (g.length == 1) {
        singles.add(card(g.single));
        continue;
      }
      flushSingles();
      sections
        ..add(Padding(
          padding: const EdgeInsets.only(top: Gap.xs, bottom: Gap.sm),
          child: Semantics(
            header: true,
            child: Text('${_groupTitle(g)}: выбери уровень',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: WorldColors.text)),
          ),
        ))
        ..add(CardGrid(
            minCard: _minCard,
            maxColumns: 2,
            children: <Widget>[for (final JobOffer o in g) card(o)]));
    }
    flushSingles();

    return Scaffold(
      backgroundColor: WorldColors.night,
      appBar: AppBar(
        toolbarHeight: land ? 48 : null,
        leading: IconButton(
          key: const ValueKey<String>('jobs:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: () => _back(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Требуется…'),
        actions: <Widget>[
          HelpButton(
            key: const ValueKey<String>('jobs:help'),
            onPressed: () => _help(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorldHud(snapshot: snap),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Всегда, и при баннере фазы тоже: из комнаты сюда
                    // ведёт «Работа», и ребёнок должен сразу понять, что
                    // каждая смена — мини-игра (фидбек дизайнера 28.09).
                    const Text(introText,
                        key: ValueKey<String>('jobs:intro'),
                        style:
                            TextStyle(fontSize: 16, color: WorldColors.text)),
                    const SizedBox(height: Gap.sm),
                    if (uni.short.isNotEmpty) ...<Widget>[
                      _FinniNote(text: uni.short),
                      const SizedBox(height: Gap.sm),
                    ],
                    if (banner != null) ...<Widget>[
                      _Banner(text: banner),
                      const SizedBox(height: Gap.md),
                    ],
                    // Сначала все работы, и открытые, и с замками: замок
                    // говорит, что купить, чтобы работа открылась (ревью
                    // 2b58bdb §3.3). Вуз — под работами.
                    ...sections,
                    if (uni.cards.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Gap.sm),
                      Semantics(
                        header: true,
                        child: Text(uni.title,
                            key: const ValueKey<String>('jobs:university'),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: WorldColors.text)),
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(uni.intro,
                          style: const TextStyle(
                              fontSize: 16, color: WorldColors.textSoft)),
                      const SizedBox(height: Gap.sm),
                      CardGrid(
                          minCard: _minCard,
                          maxColumns: 2,
                          children: <Widget>[
                            for (final UniversityCard c in uni.cards)
                              _UniversityTile(card: c),
                          ]),
                      const SizedBox(height: Gap.sm),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Финни о себе: почему ему сразу открыты финансовые работы (вуз).
class _FinniNote extends StatelessWidget {
  const _FinniNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('jobs:finni'),
        // Одна строка без лишних полей: первая работа видна без прокрутки
        // на 360 × 640 при шрифте 1,3 (ревью 28d9a1f).
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
        decoration: BoxDecoration(
          color: WorldColors.needsBg,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.school_rounded, color: WorldColors.needs),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 16, color: WorldColors.text)),
            ),
          ],
        ),
      );
}

/// Карточка вуза: совет и настоящий источник, без ссылки (адреса — только
/// в разделе взрослого).
class _UniversityTile extends StatelessWidget {
  const _UniversityTile({required this.card});

  final UniversityCard card;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Container(
          key: ValueKey<String>('jobs:uni:${card.id}'),
          padding: const EdgeInsets.all(Gap.sm + Gap.xs),
          decoration: BoxDecoration(
            color: WorldColors.panel,
            borderRadius: BorderRadius.circular(Radii.chip),
            border: Border.all(color: WorldColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(card.title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: WorldColors.text)),
              const SizedBox(height: Gap.xs),
              Text(card.text,
                  style:
                      const TextStyle(fontSize: 16, color: WorldColors.text)),
              const SizedBox(height: Gap.xs),
              Text('Источник: ${card.source}',
                  style: const TextStyle(
                      fontSize: 16, color: WorldColors.textSoft)),
            ],
          ),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('jobs:banner'),
        padding: const EdgeInsets.all(Gap.sm + Gap.xs),
        decoration: BoxDecoration(
          color: WorldColors.goalBg,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: WorldColors.goal),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.event_note_rounded, color: WorldColors.goal),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 16, color: WorldColors.text)),
            ),
          ],
        ),
      );
}
