import 'dart:math' as math;

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/board/job_offer_card.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// DEN-9 «B» (Денис 18.10, тема 118; страница `docs/final/job-offer/`):
/// карточка смены на доске — «После смены: монеты было → станет, силы было →
/// станет».
///
/// Защищает: на каждой из 7 работ «было» — снимок мира (монеты, силы),
/// «станет» — плюс оплата карточки и минус её цена в ⚡ (не меньше 0), без
/// пересчёта формул; строка настроения работы (C5) осталась; на 360×640 и
/// 640×360 при шрифте 1,3 карточки не вылезают. Уронит: «станет» посчитано
/// не от карточки (своя формула), силы уходят в минус, строку настроения
/// убрали, длинные числа ломают узкую карточку.
WorldGame _world() {
  final WorldGame w = contentDayWorld(
      onboarding: const OnboardingProgress(
          step: OnboardingProgress.stepDone, finniName: 'Финни'));
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  // Настроение и опыт не нулевые: оплата не совпадает с базой.
  ok(w.completeJob('gardener', score: 1));
  return w;
}

String _to(WidgetTester tester, String key) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byKey(const ValueKey<String>('jobs:change:to'))))
    .data!;

void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('${o.key}, шрифт 1,3: 7 работ — «было → станет»',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final WorldGame w = _world();
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const JobBoardScreen(),
            world: w, size: o.value, textScale: 1.3);
      });
      await tester.pump(const Duration(milliseconds: 300));
      final List<JobOffer> board = w.jobBoard;
      expect(board.map((JobOffer x) => x.jobId).toSet(), hasLength(7),
          reason: 'на доске все 7 работ');
      final ResourceSnapshot s = w.snapshot;
      final Finder scroll = find.byType(Scrollable).first;
      for (final JobOffer x in board) {
        final String k = offerKey(x);
        final Finder card = find.byKey(ValueKey<String>('jobs:card:$k'));
        await tester.scrollUntilVisible(card, 200, scrollable: scroll);
        expect(tester.takeException(), isNull, reason: '$k: без переполнения');
        expect(tester.getRect(card).right, lessThanOrEqualTo(o.value.width),
            reason: k);
        expect(find.byKey(ValueKey<String>('jobs:after:$k')), findsOneWidget,
            reason: k);
        final String e0 = energyShown(s.energy);
        final String e1 = energyShown(math.max(0, s.energy - x.energyCost));
        expect(_to(tester, 'jobs:pay:$k'), '${s.available + x.pay}', reason: k);
        expect(_to(tester, 'jobs:energy:$k'), e1, reason: k);
        expect(
            find.bySemanticsLabel(RegExp(
                'Монет было ${s.available}, станет ${s.available + x.pay}\$')),
            findsWidgets,
            reason: k);
        expect(find.bySemanticsLabel(RegExp('Сил было $e0, станет $e1\$')),
            findsWidgets,
            reason: k);
        if (x.moodKind != null) {
          expect(find.byKey(ValueKey<String>('jobs:mood:$k')), findsOneWidget,
              reason: '$k: строка настроения работы (C5)');
        }
      }
      h.dispose();
    });
  }
}
