import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Меню стоит на одном месте в комнате и в любом пункте меню (Денис 20.10:
/// «на компьютере когда открываешь любой пункт меню меню уходит влево, надо
/// чтобы в одном месте держалось»).
///
/// Защищает: на широком окне (телефон ~800 боком, планшет, компьютер) пять
/// пунктов меню комнаты лежат там же, где пункты меню города, «Моего пути»
/// и настроек, — с полями системы и крупным шрифтом.
/// Уронит: комната снова кладёт меню полосой снизу, а экраны — столбцом
/// слева (или наоборот), столбец другой ширины или без системного поля.
/// Почему не ловят другие: `dock_every_screen_test` проверяет, что меню
/// есть и раздел подсвечен, но не где оно лежит.

const List<String> _ids = <String>['home', 'city', 'week', 'progress', 'more'];

Future<Map<String, Rect>> _navRects(
    WidgetTester tester, Widget screen, String prefix,
    {required Size size, required double scale}) async {
  tester.view.padding = const FakeViewPadding(top: 24, left: 24);
  addTearDown(tester.view.resetPadding);
  await tester.runAsync(() async {
    await pumpWorldScreen(tester, screen,
        world: livingWorld(worldKinds.last), size: size, textScale: scale);
  });
  await tester.pump(const Duration(milliseconds: 300));
  return <String, Rect>{
    for (final String id in _ids)
      id: tester.getRect(find.byKey(ValueKey<String>('$prefix:nav:$id'))),
  };
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final Size size in <Size>[
    const Size(800, 360),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets(
          'меню на месте: комната = город = мой путь = настройки · '
          '$size · ×$scale', (WidgetTester tester) async {
        final Map<String, Rect> room = await _navRects(
            tester, const RoomScreen(), 'room',
            size: size, scale: scale);
        expect(tester.takeException(), isNull);
        for (final (String, Widget) page in <(String, Widget)>[
          ('город', const CityScreen()),
          ('мой путь', const HistoryScreen()),
          ('настройки', const WorldSettingsScreen()),
        ]) {
          final Map<String, Rect> other = await _navRects(
              tester, page.$2, 'dock',
              size: size, scale: scale);
          for (final String id in _ids) {
            final Rect a = room[id]!;
            final Rect b = other[id]!;
            expect(
                (a.left - b.left).abs() <= 0.5 &&
                    (a.top - b.top).abs() <= 0.5 &&
                    (a.right - b.right).abs() <= 0.5 &&
                    (a.bottom - b.bottom).abs() <= 0.5,
                isTrue,
                reason: '${page.$1}: пункт «$id» в комнате $a, '
                    'на экране $b');
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
