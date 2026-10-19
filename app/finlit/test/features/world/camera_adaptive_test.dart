import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Камера и адаптив (финал, D17 «полосы по бокам»): комната и город на
/// 360×640, 640×360, 768×1024 и 1440×900 — с настоящим артом.
///
/// Защищает: по бокам комнаты нет полос одного цвета — край сцены
/// продолжает обои и пол (столбец пикселей у края пёстрый, а не 1–2
/// цвета); Финни в кадре. В городе на планшете и компьютере карта крупнее
/// окна и Финни читается (не меньше 48 dp ростом).
/// Уронит: комната снова в полях цвета `edge_wall` / `edge_floor`; город
/// снова в постоянном масштабе 1,1 на любом экране.
World _living() {
  final World w = contentWorld()..startWeek();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  w.chooseGoal('pet_fish');
  w.completeJob('consultant', score: 1);
  return w;
}

const List<Size> _sizes = <Size>[
  Size(360, 640),
  Size(640, 360),
  Size(768, 1024),
  Size(1440, 900),
];

Future<ui.Image> _shoot(WidgetTester tester, Widget screen, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GlobalKey key = GlobalKey();
  late ui.Image img;
  await tester.runAsync(() async {
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: Provider<OnboardingScript>.value(
        value: contentScript,
        child: ChangeNotifierProvider<WorldState>.value(
          value: WorldState(_living()),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            routes: worldRoutes,
            home: WorldTheme(child: screen),
          ),
        ),
      ),
    ));
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final RenderRepaintBoundary b =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    img = await b.toImage(pixelRatio: 1);
  });
  return img;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final Size size in _sizes) {
    final String s = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('$s: у краёв комнаты — обои и пол, а не полосы',
        (WidgetTester tester) async {
      final ui.Image img = await _shoot(tester, const RoomScreen(), size);
      late ByteData px;
      await tester.runAsync(() async {
        px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      final Rect scene = tester.getRect(find.byType(RoomScene));
      // Столбец пикселей у края сцены, ниже плашки HUD: полоса одного
      // цвета даёт 1–2 цвета, обои и доски — десятки.
      int colors(double x) {
        final Set<int> seen = <int>{};
        final int cx = x.round().clamp(0, img.width - 1);
        for (int y = (scene.top + scene.height * 0.3).round();
            y < (scene.bottom - scene.height * 0.05).round();
            y++) {
          seen.add(px.getUint32((y * img.width + cx) * 4));
        }
        return seen.length;
      }

      expect(colors(scene.left + 1), greaterThan(12),
          reason: 'левый край сцены $scene');
      expect(colors(scene.right - 2), greaterThan(12),
          reason: 'правый край сцены $scene');
      final Rect finni =
          tester.getRect(find.byKey(const ValueKey<String>('room:finni')));
      expect(scene.contains(finni.center), isTrue,
          reason: 'Финни $finni в сцене $scene');
    });

    testWidgets('$s: город — Финни в окне, на большом экране не мелкий',
        (WidgetTester tester) async {
      await _shoot(tester, const CityScreen(smoothWalk: true), size);
      final Rect window =
          tester.getRect(find.byKey(const ValueKey<String>('city:cam-x')));
      final Rect finni =
          tester.getRect(find.byKey(const ValueKey<String>('city:finni')));
      expect(window.contains(finni.center), isTrue,
          reason: 'Финни $finni в окне $window');
      // Телефон — масштаб прежний (его держат тесты города); большой
      // экран — Финни не меньше пальца ростом. На 1,1 он был ≈ 30 dp.
      if (size.shortestSide > 412) {
        expect(finni.height, greaterThanOrEqualTo(48), reason: 'Финни $finni');
      }
    });
  }
}
