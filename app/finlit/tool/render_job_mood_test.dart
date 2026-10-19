import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры доски работ со строкой настроения (C5) — движок сборки в режиме
/// дней, шрифт 1,3, портрет 360×640 и альбомная 640×360:
///
///     flutter test --update-goldens tool/render_job_mood_test.dart
///       →  build/kadry-job-mood/*.png
///
/// На CI не гоняется (папка tool/).
Future<void> _frames(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(loadAppFonts);

  for (final (String name, Size size) in <(String, Size)>[
    ('01-doska-portret', const Size(360, 640)),
    ('02-doska-albom', const Size(640, 360)),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      final WorldGame w = contentDayWorld();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await pumpWorldScreen(tester, const JobBoardScreen(),
          world: w, size: size, textScale: 1.3, explain: explainFor(w));
      await _frames(tester);
      final Finder mood = find.byWidgetPredicate((Widget x) =>
          x.key is ValueKey<String> &&
          (x.key! as ValueKey<String>).value.startsWith('jobs:mood:'));
      await Scrollable.ensureVisible(tester.element(mood.first),
          alignment: 0.3);
      await _frames(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-job-mood/$name.png'));
    });
  }
}
