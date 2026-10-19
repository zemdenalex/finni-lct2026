import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Путь ребёнка 16.10, дефект 3: «Сейчас: на смену» без причины — она была
/// только в тексте для TalkBack.
///
/// Защищает: причина шага видна на самой кнопке. Уронит: вторая строка
/// пропала или показывает не ту сумму.
void main() {
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('«Сейчас: на смену» называет, сколько не хватает · ${o.key}',
        (WidgetTester tester) async {
      final World w = worldKinds.last.make();
      ok(w.startWeek());
      ok(w.plan(needs: 100, wants: 100, goal: 0));
      final ResourceSnapshot s = w.snapshot;
      final int short = s.weeklyBill - (s.need + s.want + s.free);
      expect(short, greaterThan(0), reason: 'настройка: денег меньше счетов');
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: w, size: o.value);
      });
      await tester.pump();
      expect(find.text('На смену'), findsOneWidget);
      final Finder why = find.byKey(const ValueKey<String>('room:now:why'));
      expect(why, findsOneWidget);
      expect(tester.widget<Text>(why).data, 'на счета не хватает $short');
      final Rect button =
          tester.getRect(find.byKey(const ValueKey<String>('room:now')));
      expect(button.contains(tester.getCenter(why)), isTrue,
          reason: 'причина — на кнопке, а не рядом');
      expect(tester.takeException(), isNull);
    });
  }
}
