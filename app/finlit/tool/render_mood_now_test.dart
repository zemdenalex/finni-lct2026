import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_game_loader.dart';
import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры доски работ со строкой «Настроение сейчас» (DEN-36 A) — движок
/// сборки в режиме дней, настроение на старте 10 / 50 / 95, шрифт 1,3:
///
///     flutter test --update-goldens tool/render_mood_now_test.dart
///       →  build/kadry-mood-now/*.png
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

Future<WorldGame> _world(int start) => openWorldGame(
    read: (String p) async {
      final String s = await File(p).readAsString();
      if (!p.endsWith('economy.json')) return s;
      final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
      e['happiness'] = <String, Object?>{
        ...(e['happiness']! as Map<String, Object?>),
        'start': start,
      };
      return jsonEncode(e);
    },
    storage: MemoryStorage());

void main() {
  setUpAll(loadAppFonts);

  for (final (String name, int start, Size size) in <(String, int, Size)>[
    ('01-grustnyy-portret', 10, const Size(360, 640)),
    ('02-obychnyy-portret', 50, const Size(360, 640)),
    ('03-radostnyy-albom', 95, const Size(640, 360)),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      final WorldGame w = (await tester.runAsync(() => _world(start)))!;
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      final PendingEvent? ev = w.pendingEvent;
      if (ev != null) {
        // Событие утра закрываем вариантом без трат — кадр про доску.
        for (final PendingEventChoice c in ev.choices) {
          if (c.available && w.resolveEvent(c.id).ok) break;
        }
      }
      await pumpWorldScreen(tester, const JobBoardScreen(),
          world: w, size: size, textScale: 1.3, explain: explainFor(w));
      await _frames(tester);
      final Finder line = find.byWidgetPredicate((Widget x) =>
          x.key is ValueKey<String> &&
          (x.key! as ValueKey<String>).value.startsWith('jobs:mood_now:'));
      await Scrollable.ensureVisible(tester.element(line.first),
          alignment: 0.3);
      await _frames(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-mood-now/$name.png'));
    });
  }
}
