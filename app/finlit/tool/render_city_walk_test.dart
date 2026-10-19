import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart' show contentScript, contentWorld;
import 'test_fonts.dart';

/// Кадры ходьбы по городу (`docs/final/gorod-dvizhenie.md`):
///
///     flutter test tool/render_city_walk_test.dart  →  build/city-walk/*.png
///
/// На CI не гоняется.
World _living() {
  final World w = contentWorld()..startWeek();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  w.chooseGoal('pet_fish');
  w.completeJob('consultant', score: 1);
  return w;
}

typedef _Act = Future<void> Function(WidgetTester tester);

Future<void> _frames(WidgetTester tester, int n, int ms) async {
  for (int i = 0; i < n; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// Магазин из списка мест и обратно: Финни стоит у двери Магазина.
Future<void> _backFromShop(WidgetTester tester) async {
  final Finder places = find.byKey(const ValueKey<String>('city:places'));
  if (places.evaluate().isNotEmpty) {
    await tester.tap(places);
    await _frames(tester, 6, 100);
  }
  final Finder shop = find.byKey(const ValueKey<String>('city:button:grocery'));
  await tester.ensureVisible(shop);
  await tester.pump();
  await tester.tap(shop);
  await _frames(tester, 6, 100);
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await _frames(tester, 8, 100);
}

/// Касание Парка: кадр посреди пути от Дома.
Future<void> _midWalk(WidgetTester tester) async {
  final Finder park = find.byKey(const ValueKey<String>('city:icon-tap:park'));
  await tester.ensureVisible(park);
  await tester.pump();
  await tester.tap(park);
  await tester.pump();
  // Кадры ходьбы читаются из бандла — дать им прийти по пути.
  await _frames(tester, 9, 40);
}

/// Джойстик влево 2,5 с: вдоль косого края к левому углу.
Future<void> _slideLeft(WidgetTester tester) async {
  final Finder stick = find.byKey(const ValueKey<String>('city:joystick'));
  final TestGesture g = await tester.startGesture(tester.getCenter(stick));
  await g.moveBy(const Offset(-20, 0));
  await g.moveBy(const Offset(-28, 0));
  for (int t = 0; t < 2500; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await g.up();
  await _frames(tester, 4, 100);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  for (final (String name, Size size, bool smooth, _Act act)
      in <(String, Size, bool, _Act)>[
    ('d01-port-magazin-dver', const Size(360, 640), true, _backFromShop),
    ('d02-port-magazin-flag-vykl', const Size(360, 640), false, _backFromShop),
    ('d03-port-v-obhod-doma', const Size(360, 640), true, _midWalk),
    ('d04-land-vdol-kraya', const Size(640, 360), true, _slideLeft),
    ('d05-land-vdol-kraya-flag-vykl', const Size(640, 360), false, _slideLeft),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final GlobalKey key = GlobalKey();
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
                home: WorldTheme(child: CityScreen(smoothWalk: smooth)),
              ),
            ),
          ),
        ));
        await _frames(tester, 10, 40);
        await act(tester);
        final RenderRepaintBoundary b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ui.Image img = await b.toImage(pixelRatio: 2);
        final ByteData? png =
            await img.toByteData(format: ui.ImageByteFormat.png);
        final File out = File('build/city-walk/$name.png');
        await out.create(recursive: true);
        await out.writeAsBytes(png!.buffer.asUint8List());
      });
    });
  }
}
