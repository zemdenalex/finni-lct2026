import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
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
    show contentDayConfig, contentScript;
import 'test_fonts.dart';

/// Кадры пакета n6-room (20.10): iso-комната на 360×800, 800×360, 1440×900
/// по трём стадиям, плюс комната / город / «Мой путь» на широких экранах —
/// где стоит меню. Финни — два кадра через 0,6 с (живёт ли он):
///
///     RENDER_TAG=do flutter test tool/render_room_n6_test.dart
///       →  build/room-n6/<RENDER_TAG>/*.png
///
/// На CI не гоняется.

final String _tag = Platform.environment['RENDER_TAG'] ?? 'now';

World _worldAt(WorldStage stage) {
  final WorldGame w = WorldGame(config: contentDayConfig);
  WorldAutopilot(w).playToStage(stage);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}

const List<Size> _sizes = <Size>[
  Size(360, 800),
  Size(800, 360),
  Size(1440, 900),
];

Future<void> _shot(GlobalKey key, String name) async {
  final RenderRepaintBoundary b =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image img = await b.toImage(pixelRatio: 1);
  final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
  final File out = File('build/room-n6/$_tag/$name.png');
  await out.create(recursive: true);
  await out.writeAsBytes(png!.buffer.asUint8List());
}

Future<void> _settle(WidgetTester tester, [int n = 12]) async {
  for (int i = 0; i < n; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<GlobalKey> _pump(
    WidgetTester tester, World w, Size size, Widget screen) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: Provider<OnboardingScript>.value(
      value: contentScript,
      child: ChangeNotifierProvider<WorldState>.value(
        value: WorldState(w),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          routes: worldRoutes,
          home: WorldTheme(child: screen),
        ),
      ),
    ),
  ));
  await _settle(tester);
  return key;
}

String _sz(Size s) => '${s.width.toInt()}x${s.height.toInt()}';

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final WorldStage stage in WorldStage.values) {
    for (final Size s in _sizes) {
      final String name = 'room-${stage.name}-${_sz(s)}';
      testWidgets(name, (WidgetTester tester) async {
        await tester.runAsync(() async {
          final GlobalKey key =
              await _pump(tester, _worldAt(stage), s, const RoomScreen());
          await _shot(key, name);
          // Второй кадр через 0,6 с: Финни должен смениться (idle).
          await _settle(tester, 6);
          await _shot(key, '$name-t2');
        });
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Меню на широких экранах: комната и два пункта меню.
  for (final Size s in <Size>[
    const Size(800, 360),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    for (final (String, Widget) e in <(String, Widget)>[
      ('room', const RoomScreen()),
      ('city', const CityScreen()),
      ('history', const HistoryScreen()),
    ]) {
      final String name = 'menu-${e.$1}-${_sz(s)}';
      testWidgets(name, (WidgetTester tester) async {
        await tester.runAsync(() async {
          final GlobalKey key =
              await _pump(tester, _worldAt(WorldStage.town), s, e.$2);
          await _shot(key, name);
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
}
