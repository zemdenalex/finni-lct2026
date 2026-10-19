// Рендер карточки «Сегодня» (дела дня, вариант A) на настоящем мире с днями
// и включённым флагом day_cycle.daily_activities.
//   flutter test tool/render_today_test.dart → build/today/*.png
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/daily/daily_layer.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart' show contentScript;
import 'test_fonts.dart';

WorldGame _world() {
  final Map<String, Object?> eco = jsonDecode(
          File('${WorldContentLoader.base}/economy.json').readAsStringSync())
      as Map<String, Object?>;
  eco['day_cycle'] = <String, Object?>{
    ...(eco['day_cycle'] as Map<String, Object?>? ?? <String, Object?>{}),
    'daily_activities': true,
  };
  String read(String f) =>
      File('${WorldContentLoader.base}/$f').readAsStringSync();
  final WorldGame w = WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
          economy: jsonEncode(eco),
          jobs: read('jobs.json'),
          events: read('events.json'))));
  w.startWeek();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  w.chooseGoal('pet_fish');
  return w;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  for (final String name in <String>[
    '1-card',
    '2-sheet',
    '3-card-landscape',
    '4-done-landscape-1.3',
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      tester.view.physicalSize = (name.contains('landscape')
              ? const Size(640, 360)
              : const Size(360, 640)) *
          2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final GlobalKey key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: Provider<OnboardingScript>.value(
            value: contentScript,
            child: ChangeNotifierProvider<WorldState>.value(
              value: WorldState(_world()),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(),
                routes: worldRoutes,
                builder: (BuildContext c, Widget? child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(
                      textScaler:
                          TextScaler.linear(name.endsWith('1.3') ? 1.3 : 1.0)),
                  child: child!,
                ),
                home: const WorldTheme(child: DailyLayer(child: RoomScreen())),
              ),
            ),
          ),
        ));
        for (int i = 0; i < 12; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await tester.pump(const Duration(milliseconds: 50));
        }
        if (name.startsWith('4-')) {
          await tester.tap(find.byKey(const ValueKey<String>('daily:rest')));
          for (int i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        if (name == '2-sheet') {
          await tester.tap(find.byKey(const ValueKey<String>('daily:shop')));
          for (int i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        final RenderRepaintBoundary b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ui.Image img = await b.toImage(pixelRatio: 2);
        final ByteData? png =
            await img.toByteData(format: ui.ImageByteFormat.png);
        final File out = File('build/today/$name.png');
        await out.create(recursive: true);
        await out.writeAsBytes(png!.buffer.asUint8List());
      });
    });
  }
}
