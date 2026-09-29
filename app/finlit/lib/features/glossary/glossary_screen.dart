import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/world_theme.dart';
import '../../domain/content.dart';

/// Словарик (§2.5.11.2) — «короткий справочный раздел с объяснением
/// основных терминов».
///
/// 🔴 Термины, ещё не встреченные в игре, показаны приглушённо, но текст
/// открывается по тапу так же, как у остальных. Прятать знание от ребёнка
/// незачем: подпись «откроется, когда встретится в игре» объясняет, почему
/// карточка выглядит иначе, и не превращает справочник в награду.
///
/// В новом мире (S13, маршрут `/w/glossary`) открыт [allOpen]: мир не
/// отмечает встреченные термины, и без флага весь словарик стоял бы под
/// замком. Цвета берутся по яркости темы — на тёмной теме мира тёмный
/// текст старой игры не читался бы.
class GlossaryScreen extends StatelessWidget {
  const GlossaryScreen(
      {super.key, this.allOpen = false, this.learned = const <String>{}});

  /// Все термины показаны как встреченные.
  final bool allOpen;

  /// id слов, которые ребёнок встретил в уроках нового мира: они наверху
  /// и с пометкой «изучено в уроке» (критерии ночи §8 п. 3).
  final Set<String> learned;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Словарик')));
    }
    final Set<String> unlocked = allOpen
        ? <String>{for (final GlossaryTerm t in app.content.glossary) t.id}
        : app.game.profile.unlockedTerms;
    // Встреченные — сверху, в прежнем порядке; невстреченные — группой
    // ниже. Вперемешку «замки» разрывали список знакомых слов.
    final List<GlossaryTerm> terms = <GlossaryTerm>[
      ...app.content.glossary.where((GlossaryTerm t) => learned.contains(t.id)),
      ...app.content.glossary.where((GlossaryTerm t) =>
          unlocked.contains(t.id) && !learned.contains(t.id)),
      ...app.content.glossary
          .where((GlossaryTerm t) => !unlocked.contains(t.id)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Словарик')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.xl),
          itemCount: terms.length,
          separatorBuilder: (_, __) => const SizedBox(height: Gap.sm),
          itemBuilder: (BuildContext context, int i) => _TermCard(
            term: terms[i],
            met: unlocked.contains(terms[i].id),
            learned: learned.contains(terms[i].id),
          ),
        ),
      ),
    );
  }
}

/// Цвета карточки: светлая тема старой игры или тёмная тема мира.
typedef _Ink = ({Color accent, Color ink, Color soft});

_Ink _inkOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? (
            accent: WorldColors.gold,
            ink: WorldColors.text,
            soft: WorldColors.textSoft
          )
        : (
            accent: AppColors.primary,
            ink: AppColors.ink,
            soft: AppColors.inkSoft
          );

class _TermCard extends StatefulWidget {
  const _TermCard(
      {required this.term, required this.met, this.learned = false});

  final GlossaryTerm term;

  /// Слово встретилось в уроке после смены.
  final bool learned;

  /// Термин уже встречался в игре.
  final bool met;

  @override
  State<_TermCard> createState() => _TermCardState();
}

class _TermCardState extends State<_TermCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final GlossaryTerm term = widget.term;
    final bool met = widget.met;
    final _Ink c = _inkOf(context);
    return Card(
      child: Theme(
        // Убираем разделители ExpansionTile: карточка уже в рамке, и две
        // линии подряд читаются как две карточки.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
          childrenPadding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          // 🔴 Своя стрелка вместо системной: у ExpansionTile по умолчанию
          // Material-иконка, а их в продукте нет ни одной (см. icons.dart).
          trailing: Pictogram(_open ? Pic.caretUp : Pic.caretDown,
              size: 26, color: c.accent),
          onExpansionChanged: (bool v) => setState(() => _open = v),
          // Иконка, а не только цвет (§3.6.5).
          leading: Pictogram(
            met ? Pic.dictionary : Pic.lock,
            size: 28,
            color: met ? c.accent : c.soft,
          ),
          title: Text(
            term.term,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: met ? c.ink : c.soft,
            ),
          ),
          subtitle: widget.learned
              ? Text(
                  'изучено в уроке',
                  key: ValueKey<String>('glossary:learned:${term.id}'),
                  style: TextStyle(fontSize: 16, color: c.accent),
                )
              : met
                  ? null
                  : Text(
                      'откроется, когда встретится в игре',
                      style: TextStyle(fontSize: 16, color: c.soft),
                    ),
          children: <Widget>[
            Text(
              term.text,
              style: TextStyle(fontSize: 17, height: 1.35, color: c.ink),
            ),
          ],
        ),
      ),
    );
  }
}
