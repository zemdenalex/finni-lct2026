import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
}

// Скриншот Саши 15.10: «План на эту неделю уже есть…» лёг поверх «Сейчас»
// и разделов внизу. Уронит: сообщение комнаты снова идёт снекбаром всего
// экрана — над панелью разделов (портрет) или над боковым столбцом
// (альбомная).
void main() {
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('${o.key}: сообщение комнаты не закрывает кнопки',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      final World w = worldKinds.first.make();
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 100, goal: 50));
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: w, size: o.value);
      });
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('room:nav:week')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey<String>('room:week:plan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final Finder bar = find.byType(SnackBar);
      expect(bar, findsOneWidget, reason: 'сообщение «План уже есть»');
      final Rect msg = tester.getRect(bar);
      final bool land = o.value.width > o.value.height;
      final Rect controls = tester.getRect(
          find.byKey(ValueKey<String>(land ? 'room:side' : 'room:dock')));
      expect(msg.overlaps(controls), isFalse,
          reason: 'сообщение $msg поверх кнопок $controls');
      // Ловит (handoff 16.10): сообщение 4 с ловит касания пола под собой —
      // Финни не идёт туда, куда ткнули. Касание проходит сквозь него в сцену.
      expect(bar.hitTestable(), findsNothing,
          reason: 'касание по сообщению должно доходить до сцены');
      expect(
          find.bySemanticsLabel(RegExp('План на эту неделю')), findsOneWidget,
          reason: 'TalkBack читает сообщение');
      sem.dispose();
    });
  }
}
