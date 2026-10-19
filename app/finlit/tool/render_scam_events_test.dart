import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/event/event_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры трёх событий о мошенниках (18.10): выбор и итог «поддаться» —
/// движок сборки в режиме дней, шрифт 1,3, портрет 360×640:
///
///     flutter test --update-goldens tool/render_scam_events_test.dart
///       →  build/kadry-moshenniki/*.png
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

/// Мир, где ждёт событие [id]; «Хочу» не пустое.
WorldGame _at(String id) {
  final WorldGame w = contentDayWorld();
  for (int week = 0; week < 2; week++) {
    ok(w.startWeek());
    final int all = w.snapshot.unallocated;
    ok(w.plan(
        needs: w.snapshot.weeklyBill,
        wants: all - w.snapshot.weeklyBill,
        goal: 0));
    while (true) {
      final PendingEvent? ev = w.pendingEvent;
      if (ev?.id == id) return w;
      if (ev != null) {
        for (final PendingEventChoice c in ev.choices) {
          if (c.available && w.resolveEvent(c.id).ok) break;
        }
      }
      if (w.sleep().reasonCode != 'day.next') break;
    }
    ok(w.payBills());
  }
  throw StateError('$id не показано');
}

void main() {
  setUpAll(loadAppFonts);

  for (final (String n, String id, String fooled) in <(String, String, String)>[
    ('1-kod', 'scam_sms_code', 'tell_code'),
    ('2-zvonok', 'scam_bank_call', 'say_numbers'),
    ('3-priz', 'scam_prize', 'send'),
  ]) {
    testWidgets(n, (WidgetTester tester) async {
      final WorldGame w = _at(id);
      await pumpWorldScreen(tester, const EventScreen(),
          world: w, size: const Size(360, 640), textScale: 1.3);
      await _frames(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-moshenniki/$n-vybor.png'));
      final Finder choice =
          find.byKey(ValueKey<String>('event:choice:$fooled'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await _frames(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-moshenniki/$n-itog.png'));
    });
  }
}
