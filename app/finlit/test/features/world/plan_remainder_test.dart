import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Лист «План недели»: верхняя строка — сколько ещё можно разложить (Настя,
/// тема 11, msg 1972): ввели «Нужное» 700 из 820 — «Осталось разложить:
/// 120»; вся сумма недели остаётся мелкой строкой.
///
/// Защищает: остаток считается на лету при вводе и «+»/«−»; ввод больше
/// остатка обрезается до остатка; «+» при нулевом остатке ничего не
/// прибавляет; «−» возвращает монеты в остаток; на 360×640 и 640×360 при
/// шрифте 1,3 — без переполнения. Уронит: строка снова показывает всю
/// сумму недели, а не остаток.
void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  World planning() => contentDayWorld()..startWeek();

  String shown(WidgetTester tester, String key) => find
      .descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
          matchRoot: true)
      .evaluate()
      .map((Element e) => (e.widget as Text).data ?? '')
      .join(' ');

  int pool(WidgetTester tester) => int.parse(
      RegExp(r'\d+').firstMatch(shown(tester, 'plan:pool:value'))!.group(0)!);

  Future<void> tapKey(WidgetTester tester, String key) async {
    final Finder f = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> type(WidgetTester tester, String row, int value) async {
    await tapKey(tester, 'amount:$row');
    await tester.enterText(
        find.byKey(const ValueKey<String>('amount:field')), '$value');
    await tester.pump();
    await tapKey(tester, 'amount:ok');
  }

  for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()}, шрифт $scale: '
          'остаток на лету, ввод и «+» упираются в него',
          (WidgetTester tester) async {
        final World w = planning();
        final int total = w.snapshot.unallocated;
        expect(total, greaterThan(700), reason: 'настройка: сумма недели');
        await tester.runAsync(() async {
          await pumpWorldScreen(tester, const RoomScreen(),
              world: w, size: size, textScale: scale);
        });
        await tester.pump();
        await tapKey(tester, 'room:nav:week');
        await tapKey(tester, 'room:week:plan');
        expect(
            find.byKey(const ValueKey<String>('plan:confirm')), findsOneWidget,
            reason: 'лист плана открыт');
        expect(shown(tester, 'plan:pool:total'), contains('$total'),
            reason: 'вся сумма недели видна мелкой строкой');
        final int start = pool(tester);

        await type(tester, 'need', 700);
        expect(pool(tester), lessThan(start),
            reason: 'после «Нужно» 700 — остаток уменьшился');

        // Больше остатка — обрезается до остатка.
        await type(tester, 'want', 100000);
        expect(pool(tester), 0, reason: 'ввод больше остатка → остаток 0');

        // «+» на нуле остатка — ничего.
        await tapKey(tester, 'sheet:plus:goal');
        expect(pool(tester), 0, reason: '«+» без остатка не прибавляет');
        expect(shown(tester, 'amount:goal'), '0',
            reason: '«+» без остатка: в «Копилке» осталось 0');
        expect(find.byKey(const ValueKey<String>('plan:full')), findsWidgets,
            reason: '«+» без остатка — «Всё уже разложено»');

        // «−» возвращает монеты в остаток.
        await tapKey(tester, 'sheet:minus:want');
        expect(pool(tester), greaterThan(0), reason: '«−» вернул в остаток');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
