import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/world_explain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// C5 (план контента 17.10): тип настроения работы виден на доске до выбора
/// смены — «интересная работа с монетами: настроение вверх». Защищает: у
/// каждой из 7 работ в режиме дней есть тип и непустая строка для него;
/// строка стоит на каждой карточке доски, влезает при шрифте 1,3 в обеих
/// ориентациях; в режиме «неделя» (тип не действует) строки нет. Уронит:
/// работе не задан тип, текста для типа нет в explain.json, карточка не
/// показывает строку или показывает её там, где настроение от типа не
/// меняется. Почему не ловят прежние: `mood_kind_test` проверяет сдвиг 😊
/// после смены, а не то, что ребёнок видит до неё.
String? _moodText(Widget w) {
  if (w is! Text) return null;
  return w.data ?? w.textSpan?.toPlainText();
}

Finder _moodFacts() => find.byWidgetPredicate((Widget w) =>
    w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>).value.startsWith('jobs:mood:'));

void main() {
  test('у каждой из 7 работ — тип настроения и текст для него', () {
    final WorldGame w = contentDayWorld();
    final WorldExplain ex = explainFor(w);
    final Set<String> jobs = <String>{};
    for (final JobOffer o in w.jobBoard) {
      expect(o.moodKind, isNotNull, reason: o.jobId);
      final String? text = ex.jobMood(o.moodKind);
      expect(text, isNotNull,
          reason: '${o.jobId}: нет текста для ${o.moodKind}');
      expect(text!.trim(), isNotEmpty);
      expect(text, isNot(contains('😊')), reason: 'без значков посреди фразы');
      jobs.add(o.jobId);
    }
    expect(jobs, hasLength(7));
  });

  test('режим «неделя»: тип настроения не действует — на доске его нет', () {
    for (final JobOffer o in contentWorld().jobBoard) {
      expect(o.moodKind, isNull, reason: o.jobId);
    }
  });

  for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
    testWidgets(
        'доска: строка настроения на каждой карточке, шрифт 1,3 · '
        '${size.width.toInt()}×${size.height.toInt()}',
        (WidgetTester tester) async {
      final WorldGame w = contentDayWorld();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await pumpWorldScreen(tester, const JobBoardScreen(),
          world: w, size: size, textScale: 1.3, explain: explainFor(w));
      expect(tester.takeException(), isNull);
      final Finder cards = find.byWidgetPredicate((Widget x) =>
          x.key is ValueKey<String> &&
          RegExp(r'^jobs:card:[a-z_]+(/[a-z_0-9]+)?$')
              .hasMatch((x.key! as ValueKey<String>).value));
      expect(cards, findsWidgets);
      final int built = cards.evaluate().length;
      expect(_moodFacts().evaluate().length, built,
          reason: 'на каждой построенной карточке');
      for (final Element e in _moodFacts().evaluate()) {
        final String text = find
            .descendant(
                of: find.byWidget(e.widget), matching: find.byType(Text))
            .evaluate()
            .map((Element t) => _moodText(t.widget) ?? '')
            .join(' ');
        expect(text.trim(), isNotEmpty, reason: '${e.widget.key}');
      }
    });
  }

  testWidgets('режим «неделя»: строк настроения на доске нет',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    await pumpWorldScreen(tester, const JobBoardScreen(),
        world: w, explain: explainFor(w));
    expect(_moodFacts(), findsNothing);
  });
}
