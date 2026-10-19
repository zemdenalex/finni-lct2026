import 'package:finlit/features/world/city/city_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Джойстик города — такой же, как в комнате (Настя, тема 11, msg 1971):
/// не закреплён в правом нижнем углу, а плавающий — под пальцем; в покое
/// бледный круг слева внизу.
///
/// Защищает: на 360×640, 640×360, 768×1024 и 1440×900 круг в покое — в
/// левой половине карты внизу; ход пальцем с середины карты рисует круг с
/// центром под пальцем и ведёт Финни. Уронит: джойстик снова прибит справа
/// внизу; перетаскивание по карте снова листает её, а не ведёт Финни.
void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final Size size in const <Size>[
    Size(360, 640),
    Size(640, 360),
    Size(768, 1024),
    Size(1440, 900),
  ]) {
    final String s = '${size.width.toInt()}×${size.height.toInt()}';
    testWidgets('$s: джойстик как в комнате — плавающий, в покое слева',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const CityScreen(smoothWalk: true),
            world: livingWorld(worldKinds.last), size: size);
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pump();
      final Rect window =
          tester.getRect(find.byKey(const ValueKey<String>('city:cam-x')));
      final Rect rest =
          tester.getRect(find.byKey(const ValueKey<String>('city:joystick')));
      expect(rest.center.dx, lessThan(window.center.dx),
          reason: 'в покое слева: $rest в окне $window');
      expect(rest.bottom, greaterThan(window.center.dy),
          reason: 'в покое внизу: $rest в окне $window');

      // Где Финни на карте (не на экране: камера едет за ним).
      double finniX() =>
          tester
              .getRect(find.byKey(const ValueKey<String>('city:finni')))
              .left -
          tester.getRect(find.byKey(const ValueKey<String>('city:map'))).left;
      final double before = finniX();
      // Палец — посреди карты, не на круге в покое.
      final Offset at = window.center + const Offset(0, 20);
      final TestGesture g = await tester.startGesture(at);
      await g.moveBy(const Offset(-20, 0));
      await g.moveBy(const Offset(-28, 0));
      await tester.pump();
      final Finder pad = find.byKey(const ValueKey<String>('joystick:pad'));
      expect(pad, findsOneWidget, reason: 'круг под пальцем');
      expect((tester.getCenter(pad) - at).distance, lessThan(1),
          reason: 'центр круга — где коснулись');
      for (int t = 0; t < 600; t += 20) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await g.up();
      await tester.pump();
      expect(pad, findsNothing, reason: 'отпустил — круга под пальцем нет');
      // Финни пошёл влево по карте.
      expect(finniX(), lessThan(before - 5),
          reason: 'Финни на карте: $before → ${finniX()}');
      expect(tester.takeException(), isNull);
    });
  }
}
