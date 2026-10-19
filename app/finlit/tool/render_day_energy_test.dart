// Рендер страницы вариантов «день по энергии» (ночь 16.10):
// docs/final/hud-day-energy/. Настоящая комната, моковые сытость и
// время суток ([dayMock]). Запуск:
//   flutter test tool/render_day_energy_test.dart  → build/day/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/day_energy_looks.dart';
import 'package:finlit/features/world/home/room_screen.dart';
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

World _town() {
  final WorldGame w = contentWorld();
  WorldAutopilot(w).playToStage(WorldStage.town);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}

/// (файл, вид HUD, мок дня).
final List<(String, HudLook, DayMock)> _cases = <(String, HudLook, DayMock)>[
  ('0-asis', HudLook.asIs, const DayMock()),
  ('A-day', HudLook.fedOnFinni, const DayMock()),
  ('B-day', HudLook.doubleBar, const DayMock()),
  ('C-day', HudLook.moodOnFinni, const DayMock()),
  ('D-day', HudLook.fedWhenLow, const DayMock()),
  // Время суток: одна комната, три времени (вариант A).
  ('time-day', HudLook.fedOnFinni, const DayMock(time: DayTime.day)),
  ('time-evening', HudLook.fedOnFinni, const DayMock(time: DayTime.evening)),
  ('time-night', HudLook.fedOnFinni, const DayMock(time: DayTime.night)),
  // Голодный Финни: как каждый вариант показывает низкую сытость.
  ('A-hungry', HudLook.fedOnFinni, const DayMock(fed: 0.15)),
  ('B-hungry', HudLook.doubleBar, const DayMock(fed: 0.15)),
  ('C-hungry', HudLook.moodOnFinni, const DayMock(fed: 0.15)),
  ('D-hungry', HudLook.fedWhenLow, const DayMock(fed: 0.15)),
];

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  tearDown(() {
    hudLook = HudLook.fedOnFinni;
    dayMock = null;
    progressNew = 0;
  });
  final String only = Platform.environment['ONLY'] ?? '';
  for (final (String name, HudLook look, DayMock mock) in _cases) {
    if (only.isNotEmpty && !name.contains(only)) continue;
    testWidgets(name, (WidgetTester tester) async {
      hudLook = look;
      dayMock = mock;
      // Новые награды на «Прогрессе» — у вариантов (как на странице 16.10).
      progressNew = look == HudLook.asIs ? 0 : 2;
      tester.view.physicalSize = const Size(360, 640) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final GlobalKey key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: Provider<OnboardingScript>.value(
              value: contentScript,
              child: ChangeNotifierProvider<WorldState>.value(
                value: WorldState(_town()),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildAppTheme(),
                  routes: worldRoutes,
                  home: const WorldTheme(child: RoomScreen()),
                ),
              ),
            ),
          ),
        );
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await tester.pump(const Duration(milliseconds: 50));
        }
        final RenderRepaintBoundary b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ui.Image img = await b.toImage(pixelRatio: 2);
        final ByteData? png = await img.toByteData(
          format: ui.ImageByteFormat.png,
        );
        final File out = File('build/day/$name.png');
        await out.create(recursive: true);
        await out.writeAsBytes(png!.buffer.asUint8List());
      });
    });
  }
}
