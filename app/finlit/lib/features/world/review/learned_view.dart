import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';

/// «Чему мы научились» (критерии ночи §8, Денис 938: «результат игры как
/// обучение финансам пока слишком абстрактный»): темы ТЗ — бюджет,
/// сбережения, платежи — и сколько решений по каждой ребёнок уже принял,
/// плюс слова из уроков. Без оценок: не «хорошо/плохо», а «было в игре».
///
/// Одна и та же панель — в истории S12 (ребёнку) и в разделе взрослого S14.
class LearnedPanel extends StatelessWidget {
  const LearnedPanel({
    super.key,
    required this.learning,
    this.forAdult = false,
  });

  final LearningSummary learning;

  /// Подписи для взрослого: «ребёнок», а не «мы».
  final bool forAdult;

  static String _decisions(int n) {
    final int m10 = n % 10;
    final int m100 = n % 100;
    final String w = m100 >= 11 && m100 <= 14
        ? 'решений'
        : m10 == 1
            ? 'решение'
            : m10 >= 2 && m10 <= 4
                ? 'решения'
                : 'решений';
    return '$n $w';
  }

  @override
  Widget build(BuildContext context) {
    const TextStyle line = TextStyle(fontSize: 16, color: WorldColors.text);
    const TextStyle soft = TextStyle(fontSize: 16, color: WorldColors.textSoft);
    return Container(
      key: const ValueKey<String>('learned:panel'),
      padding: const EdgeInsets.all(Gap.sm + Gap.xs),
      decoration: BoxDecoration(
        color: WorldColors.panel,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: WorldColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
                forAdult
                    ? 'Темы, которые уже были в игре'
                    : 'Чему мы научились',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: WorldColors.text)),
          ),
          const SizedBox(height: Gap.xs),
          for (final (String id, String name) in LearningSummary.topicNames)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                      (learning.topics[id] ?? 0) > 0
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: (learning.topics[id] ?? 0) > 0
                          ? WorldColors.needs
                          : WorldColors.textSoft),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      (learning.topics[id] ?? 0) > 0
                          ? '$name — ${_decisions(learning.topics[id]!)}'
                          : '$name — ещё впереди',
                      key: ValueKey<String>('learned:topic:$id'),
                      style: (learning.topics[id] ?? 0) > 0 ? line : soft,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.sm),
          Text(
            learning.words.isEmpty
                ? 'Новые слова появятся после уроков на работе.'
                : 'Слова из уроков (есть в Словарике): '
                    '${learning.words.map((({
                          String id,
                          String term
                        }) w) => w.term).join(', ')}.',
            key: const ValueKey<String>('learned:words'),
            style: learning.words.isEmpty ? soft : line,
          ),
        ],
      ),
    );
  }
}
