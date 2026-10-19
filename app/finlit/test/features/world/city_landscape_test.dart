import 'package:finlit/features/world/city/city_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Город в альбомной (rc-7d @ f93d06b, кадр d04 города): Финни у края поля
/// наполовину за краем экрана, а в столбце мест видна одна строка — вторую
/// режет полоса с джойстиком.
///
/// Защищает: Финни у края поля виден целиком; в столбце мест видно не меньше
/// двух мест целиком, и джойстик не лежит на списке. Уронит: камера снова
/// упирается в край карты; джойстик снова отнимает высоту у списка.
void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  Future<void> pumpCity(WidgetTester tester, Size size) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const CityScreen(smoothWalk: true),
          world: livingWorld(worldKinds.last), size: size);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  final Finder stick = find.byKey(const ValueKey<String>('city:joystick'));

  Future<void> hold(WidgetTester tester, Offset dir, int ms) async {
    final TestGesture g = await tester.startGesture(tester.getCenter(stick));
    await g.moveBy(dir * 20);
    await g.moveBy(dir * 28);
    for (int t = 0; t < ms; t += 20) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  for (final Size size in <Size>[const Size(640, 360), const Size(800, 360)]) {
    final String s = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('$s: у левого края поля Финни виден целиком',
        (WidgetTester tester) async {
      await pumpCity(tester, size);
      await hold(tester, const Offset(-1, 0), 2500);
      final Rect window =
          tester.getRect(find.byKey(const ValueKey<String>('city:cam-x')));
      final Rect finni =
          tester.getRect(find.byKey(const ValueKey<String>('city:finni')));
      // Мерило — центр Финни, а не его рамка: в тестах вместо арта
      // квадрат-заглушка, по ширине не равный спрайту. Центр не ближе к краю
      // окна, чем половина высоты Финни, — спрайт (уже своей высоты) виден
      // целиком. На f93d06b центр был в 18 px от края.
      expect(
          finni.center.dx - window.left, greaterThanOrEqualTo(finni.height / 2),
          reason: 'Финни $finni, окно $window');
      expect(window.right - finni.center.dx,
          greaterThanOrEqualTo(finni.height / 2));
    });

    testWidgets(
        '$s: в столбце мест видно два места целиком, джойстик не на '
        'списке', (WidgetTester tester) async {
      await pumpCity(tester, size);
      final Finder list = find.byKey(const ValueKey<String>('city:list'));
      final Rect view = tester.getRect(list);
      final List<Rect> rows = <Rect>[
        for (final Element e in find
            .descendant(of: list, matching: find.byType(OutlinedButton))
            .evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      final int whole = rows
          .where((Rect r) =>
              r.top >= view.top - 0.5 && r.bottom <= view.bottom + 0.5)
          .length;
      expect(whole, greaterThanOrEqualTo(2), reason: 'строки $rows в $view');
      final Rect joy = tester.getRect(stick);
      expect(joy.overlaps(view), isFalse,
          reason: 'джойстик $joy, список $view');
    });
  }
}
