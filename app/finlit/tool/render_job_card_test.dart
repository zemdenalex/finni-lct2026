import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры доски работ с карточкой «было → станет» (DEN-9 B, Денис 18.10):
///
///     flutter test --update-goldens tool/render_job_card_test.dart
///       →  build/kadry-job-card/*.png
///
/// На CI не гоняется (папка tool/).
void main() {
  setUpAll(loadAppFonts);

  for (final (String name, Size size) in <(String, Size)>[
    ('portret-1.3', const Size(360, 640)),
    ('albom-1.3', const Size(640, 360)),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      final WorldGame w = contentDayWorld(
          onboarding:
              const OnboardingProgress(step: OnboardingProgress.stepDone));
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const JobBoardScreen(),
            world: w, size: size, textScale: 1.3);
      });
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-job-card/$name.png'));
    });
  }
}
