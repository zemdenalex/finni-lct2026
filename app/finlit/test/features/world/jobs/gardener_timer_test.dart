import 'package:finlit/core/theme.dart';
import 'package:finlit/features/world/jobs/games/gardener_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/world_harness.dart';

/// Садовник по просьбе Насти 20.10: часы на смену и 5 сухих грядок на
/// большом поле.
///
/// Защищает: время вышло — смена кончается сама, итог «Время вышло» и число
/// политых, `onDone` — доля политых (не штраф); на поле больше 6 грядок в
/// начале хода сухих 5, на поле до 6 — одна, как было; TalkBack слышит
/// остаток десятками секунд.
/// Уронит: часы не идут или не заканчивают смену; правило большого поля не
/// читается из `jobs.json`; liveRegion меняется каждую секунду.
/// Почему не ловит job_games_b7_test: он проходит смену по ходам и не ждёт
/// конца времени, поле там одно (смена 0, 6 грядок).
Future<List<double>> _pump(WidgetTester tester, int round) async {
  final List<double> scores = <double>[];
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: GardenerGame(
            content: contentJobGames.gardener,
            round: round,
            onDone: scores.add),
      ),
    ),
  ));
  await tester.pump();
  return scores;
}

int _count(String label, int beds) => <int>[
      for (int i = 0; i < beds; i++)
        if (find
            .byKey(ValueKey<String>('gardener:bed:$i:$label'))
            .evaluate()
            .isNotEmpty)
          i,
    ].length;

void main() {
  final GardenerContent g = contentJobGames.gardener;

  test('в сборке: часы и правило большого поля из jobs.json', () {
    expect(g.timerSec, isNotNull);
    expect(g.bigOverBeds, 6);
    expect(g.bigDry, 5);
  });

  testWidgets('время вышло: смена кончается, итог по числу политых',
      (WidgetTester tester) async {
    final List<double> scores = await _pump(tester, 0);
    final int beds = g.forRound(0).beds;
    // Полили одну сухую грядку и больше ничего не делали.
    final int dry = <int>[
      for (int i = 0; i < beds; i++)
        if (find
            .byKey(ValueKey<String>('gardener:bed:$i:Полей!'))
            .evaluate()
            .isNotEmpty)
          i,
    ].first;
    await tester.tap(find.byKey(ValueKey<String>('gardener:bed:$dry')));
    await tester.pump();
    for (int s = 0; s < g.timerSec!; s++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final Finder summary =
        find.byKey(const ValueKey<String>('gardener:summary'));
    expect(summary, findsOneWidget, reason: 'время вышло — итог');
    final String text = tester
        .widgetList<Text>(find.descendant(of: summary, matching: find.byType(Text)))
        .map((Text t) => t.data ?? '')
        .join(' ');
    expect(text, contains('Время вышло.'));
    expect(text, contains('1 грядку из 1'));
    expect(find.byKey(const ValueKey<String>('gardener:left')), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('gardener:done')));
    await tester.pump();
    expect(scores, <double>[1]);
  });

  testWidgets('большое поле (8 грядок): в начале хода сухих 5',
      (WidgetTester tester) async {
    // Смена 2 — поле «long», 8 грядок 4 × 2.
    final int beds = g.forRound(2).beds;
    expect(beds, greaterThan(6));
    await _pump(tester, 2);
    expect(_count('Полей!', beds), 5);
    // Полили две — на следующем ходу снова 5 (сухие и поникшие вместе).
    int watered = 0;
    for (int i = 0; i < beds && watered < 2; i++) {
      final Finder f = find.byKey(ValueKey<String>('gardener:bed:$i:Полей!'));
      if (f.evaluate().isEmpty) continue;
      await tester.tap(find.byKey(ValueKey<String>('gardener:bed:$i')));
      await tester.pump();
      watered++;
    }
    await tester.tap(find.byKey(const ValueKey<String>('gardener:next')));
    await tester.pump();
    expect(_count('Полей!', beds) + _count('Поникла', beds), 5);
  });

  testWidgets('поле до 6 грядок: сохнет одна, как было',
      (WidgetTester tester) async {
    final int beds = g.forRound(0).beds;
    expect(beds, lessThanOrEqualTo(6));
    await _pump(tester, 0);
    expect(_count('Полей!', beds), 1);
  });

  testWidgets('TalkBack: остаток десятками секунд, не каждую секунду',
      (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await _pump(tester, 0);
    String said() => tester
        .getSemantics(find.byKey(const ValueKey<String>('gardener:clock')))
        .label;
    final int t = g.timerSec!;
    expect(said(), 'Осталось $t секунд');
    await tester.pump(const Duration(seconds: 1));
    expect(said(), 'Осталось $t секунд', reason: 'через секунду — то же');
    await tester.pump(const Duration(seconds: 10));
    expect(said(), 'Осталось ${t - 10} секунд');
    h.dispose();
  });
}
