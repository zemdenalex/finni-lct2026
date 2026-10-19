import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart'
    show contentDayWorld, contentScript, contentWorld;
import 'test_fonts.dart';

/// Кадры комнаты и города на четырёх размерах (камера и адаптив, финал):
///
///     flutter test tool/render_camera_adaptive_test.dart  →  build/camera-adaptive/*.png
///
/// `ONLY=room` — только комната, `SCALE=1.3` — крупный шрифт системы. На CI не гоняется.
World _living() {
  final World w = contentWorld()..startWeek();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  w.chooseGoal('pet_fish');
  w.completeJob('consultant', score: 1);
  return w;
}

World _livingAt(WorldStage stage) {
  final WorldGame w = contentWorld();
  WorldAutopilot(w).playToStage(stage);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  final String only = Platform.environment['ONLY'] ?? '';
  // Шрифт системы (SCALE=1.3): кадры крупного шрифта.
  final double scale =
      double.tryParse(Platform.environment['SCALE'] ?? '') ?? 1;
  for (final (String name, Widget screen, World Function() world)
      in <(String, Widget, World Function())>[
    ('room', const RoomScreen(), _living),
    (
      'room-day',
      const RoomScreen(),
      () {
        final World w = contentDayWorld()..startWeek();
        w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
        return w;
      }
    ),
    ('room-town', const RoomScreen(), () => _livingAt(WorldStage.town)),
    ('room-moscow', const RoomScreen(), () => _livingAt(WorldStage.moscow)),
    ('city', const CityScreen(smoothWalk: true), _living),
    (
      'city-town',
      const CityScreen(smoothWalk: true),
      () => _livingAt(WorldStage.town)
    ),
    (
      'city-moscow',
      const CityScreen(smoothWalk: true),
      () => _livingAt(WorldStage.moscow)
    ),
  ]) {
    if (only.isNotEmpty && !name.startsWith(only)) continue;
    for (final Size size in <Size>[
      // Обзор всей карты (FULL=1): окно больше карты города.
      if (Platform.environment['FULL'] != null) const Size(2900, 1500),
      const Size(360, 640),
      const Size(360, 800),
      const Size(640, 360),
      const Size(768, 1024),
      const Size(1440, 900),
    ]) {
      final String tag = '${size.width.toInt()}x${size.height.toInt()}'
          '${scale == 1 ? '' : '-$scale'}';
      testWidgets('$name-$tag', (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.reset);
        final GlobalKey key = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: Provider<OnboardingScript>.value(
              value: contentScript,
              child: ChangeNotifierProvider<WorldState>.value(
                value: WorldState(world()),
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
          final ui.Image img = await b.toImage(pixelRatio: 1);
          final ByteData? png =
              await img.toByteData(format: ui.ImageByteFormat.png);
          final File out = File('build/camera-adaptive/$name-$tag.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}
