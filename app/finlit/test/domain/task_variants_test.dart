import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Недельные варианты заданий.
///
/// 🔴 До 23.09 задание повторялось дословно: «Сдача» каждую неделю
/// спрашивала «7 и 10», и со второй недели ребёнок вспоминал ответ, а не
/// считал. Подработка, которая по экономике доверия растёт со стадией,
/// превращалась в нажатие одной и той же кнопки.
void main() {
  late GameContent content;
  setUpAll(() async => content = await loadRealContent());

  test('у каждого задания есть другие недели, и они правда другие', () {
    for (final GameTask t in content.tasks) {
      expect(t.variants, isNotEmpty, reason: t.id);
      final Set<String> prompts = <String>{
        for (final GameTask v in t.allVariants)
          '${v.prompt}|${v.params.toString()}',
      };
      expect(prompts.length, t.allVariants.length,
          reason: '${t.id}: два варианта совпадают');
    }
  });

  test('вариант меняет числа и тексты, но не тип, тему и награду', () {
    for (final GameTask t in content.tasks) {
      for (final GameTask v in t.variants) {
        expect(v.id, t.id);
        expect(v.kind, t.kind);
        expect(v.topic, t.topic);
        expect(v.reward, t.reward,
            reason: '${t.id}: подработка недели не должна зависеть от того, '
                'какой вариант выпал');
      }
    }
  });

  test('первая неделя — основной вариант, дальше по кругу', () {
    final GameTask t = content.task('c1_change');
    final int n = t.allVariants.length;
    expect(identical(t.forWeek(1), t), isTrue);
    for (int week = 1; week <= 3 * n; week++) {
      expect(identical(t.forWeek(week), t.allVariants[(week - 1) % n]), isTrue,
          reason: 'неделя $week');
    }
  });

  test('на второй неделе игра показывает другие числа', () {
    final Game g =
        Game(content: content, profile: GameProfile.fresh(isDemo: false));
    g.startPeriod();
    final String week1 = g.availableTasks
        .firstWhere((GameTask t) => t.id == 'c1_change')
        .prompt;
    g.closePeriod();
    g.startPeriod();
    final String week2 = g.availableTasks
        .firstWhere((GameTask t) => t.id == 'c1_change')
        .prompt;
    expect(week2, isNot(week1));
  });

  test('вариант, который меняет награду, не загрузится', () {
    expect(
      () => GameTask.fromJson(<String, Object?>{
        'id': 'x',
        'topic': 'payments',
        'kind': 'numericInput',
        'title': 'x',
        'prompt': 'x',
        'reward': 2,
        'params': <String, Object?>{'answer': 1},
        'plain': <Object?>['answer'],
        'explainAny': 'x',
        'explainBest': 'x',
        'variants': <Object?>[
          <String, Object?>{'reward': 9},
        ],
      }),
      throwsFormatException,
    );
  });
}
