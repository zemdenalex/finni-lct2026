import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_harness.dart';
import '../test/support/xp_twins.dart';
import 'test_fonts.dart';

/// Кадры прибавки за опыт словами и монетами (решение Дениса 19.10):
///
///     flutter test --update-goldens tool/render_xp_coins_test.dart
///       →  build/kadry-xp-coins/*.png
///
/// Печатает строки карточек и сверку с начислением (миры-близнецы).
/// На CI не гоняется (папка tool/).
void main() {
  setUpAll(loadAppFonts);

  for (final (String name, double growth, int xp) in <(String, double, int)>[
    ('sborka-opyt5', 1.01, 5),
    ('rost1.2-opyt3', 1.2, 3),
  ]) {
    testWidgets('доска $name 360×640', (WidgetTester tester) async {
      final (WorldGame a, WorldGame b) = twins(growth, xp);
      for (final JobOffer o in a.jobBoard) {
        // ignore: avoid_print
        print('$name ${o.jobId}${o.variant == null ? '' : '/${o.variant}'}: '
            'pay ${o.pay}, ${experiencePayText(pay: o.pay, coins: o.experienceCoins)}');
      }
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const JobBoardScreen(),
            world: a, size: const Size(360, 640), textScale: 1.3);
      });
      await tester.pump(const Duration(milliseconds: 600));
      // Строка опыта первой карточки — в кадре.
      final String first = a.jobBoard.first.jobId;
      await tester
          .ensureVisible(find.byKey(ValueKey<String>('jobs:exp:$first')));
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-xp-coins/doska-$name.png'));
      for (final String id in <String>['cashier', 'consultant', 'gardener']) {
        if (!readyFor(a, b, id)) continue;
        final JobOffer o = a.offer(id)!;
        final int credited = creditedXpCoins(a, b, id);
        // ignore: avoid_print
        print('$name $id: на карточке +${o.experienceCoins}, '
            'начислено сверх близнеца +$credited');
      }
    });
  }

  testWidgets('экран смены консультанта 360×640', (WidgetTester tester) async {
    final (WorldGame a, WorldGame b) = twins(1.2, 3);
    readyFor(a, b, 'consultant');
    await tester.runAsync(() async {
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('consultant')),
          world: a, size: const Size(360, 640), textScale: 1.3);
    });
    await tester.pump(const Duration(milliseconds: 600));
    await tester
        .ensureVisible(find.byKey(const ValueKey<String>('job:offer:terms')));
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../build/kadry-xp-coins/smena-konsultant.png'));
  });
}
