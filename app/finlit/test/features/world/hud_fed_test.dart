import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Сытость в HUD дня (Денис, чат 1900: «где шкала голода/сытости?»): в
/// RC она была только полоской над Финни.
///
/// Защищает: в режиме дней в HUD есть сытость — миска, слово «сытость» и
/// число (видно без TalkBack), TalkBack читает «Сытость: N из 100»; на
/// 360 dp при шрифте 1,0 и 1,3 без переполнения. В прежней неделе (`days_per_week: 1`) сытости нет.
/// Уронит: вид HUD по умолчанию снова без сытости; вторая полоса снова не
/// влезает в ряд 48 dp.
void main() {
  setUpAll(loadAppFonts);

  WorldGame dayWorld() {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 100, wants: 100, goal: 0));
    return w;
  }

  final RegExp fedLabel = RegExp(r'Сытость: \d+ из 100');

  for (final double scale in <double>[1.0, 1.3]) {
    for (final MapEntry<String, Size> s in bothOrientations.entries) {
      testWidgets('дни, ${s.key}, шрифт $scale: сытость в HUD словом и числом',
          (WidgetTester tester) async {
        final SemanticsHandle h = tester.ensureSemantics();
        final WorldGame w = dayWorld();
        await pumpWorldScreen(tester, const RoomScreen(),
            world: w, size: s.value, textScale: scale);
        expect(tester.takeException(), isNull, reason: 'без переполнения');
        final Finder fed = find.byKey(const ValueKey<String>('hud:fed'));
        expect(fed, findsOneWidget);
        expect(tester.getSemantics(fed).label,
            'Сытость: ${w.snapshot.satiety} из 100');
        // Видно без TalkBack: слово и число на экране, рядом с «День N».
        expect(
            tester
                .widget<Text>(
                    find.byKey(const ValueKey<String>('hud:fed:text')))
                .data,
            'сытость ${w.snapshot.satiety}');
        h.dispose();
      });
    }
  }

  testWidgets('прежняя неделя: сытости в HUD нет', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final World w = contentWorld()..startWeek();
    await pumpWorldScreen(tester, const RoomScreen(), world: w);
    expect(w.snapshot.satiety, isNull, reason: 'настройка: дней нет');
    expect(find.bySemanticsLabel(fedLabel), findsNothing);
    h.dispose();
  });
}
