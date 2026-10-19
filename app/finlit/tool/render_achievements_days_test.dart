import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/achievements/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_game_loader.dart';
import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры экрана наград с дневными наградами (C7, `achievements_days`) —
/// движок сборки в режиме дней после трёх дней игры, шрифт 1,3:
///
///     flutter test --update-goldens tool/render_achievements_days_test.dart
///       →  build/kadry-achievements-days/*.png
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

Future<WorldGame> _world() async {
  final WorldGame w = await openWorldGame(
      read: (String p) async {
        final String s = await File(p).readAsString();
        if (!p.endsWith('economy.json')) return s;
        final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
        e['achievements_days'] = true;
        return jsonEncode(e);
      },
      storage: MemoryStorage());
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  for (final String job in <String>['cashier', 'consultant', 'gardener']) {
    ok(w.completeJob(job, score: 1));
    ok(w.sleep());
  }
  return w;
}

void main() {
  setUpAll(loadAppFonts);

  for (final (String name, Size size) in <(String, Size)>[
    ('01-nagrady-portret', const Size(360, 640)),
    ('02-nagrady-albom', const Size(640, 360)),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      final WorldGame w = (await tester.runAsync(_world))!;
      await pumpWorldScreen(tester, const AchievementsScreen(),
          world: w, size: size, textScale: 1.3);
      await _frames(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-achievements-days/$name.png'));
      final Finder list = find.byType(Scrollable);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -1200));
        await _frames(tester);
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                '../build/kadry-achievements-days/$name-niz.png'));
      }
      // DEN-32: строки баффов («Даёт +3 😊 на 3 дня», «+1 ⚡ навсегда»).
      final Finder fx =
          find.byKey(const ValueKey<String>('achievements:effect:jobs_3'));
      await tester.scrollUntilVisible(fx, 200, scrollable: list.first);
      await Scrollable.ensureVisible(tester.element(fx), alignment: 0.1);
      await _frames(tester);
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              '../build/kadry-achievements-days/$name-baffy.png'));
    });
  }
}
