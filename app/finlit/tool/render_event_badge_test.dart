import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры кнопки «Событие ждёт» в комнате (флаг `room.event_badge`, движок с
/// днями из сборки): `flutter test tool/render_event_badge_test.dart` →
/// `build/kadry-event-badge/`.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldGame _world({required bool badge}) {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  eco['room'] = <String, Object?>{
    ...(eco['room']! as Map<String, Object?>),
    'event_badge': badge,
  };
  final WorldGame w = WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
    roomItems: _read('room_items.json'),
  )));
  w.startWeek();
  w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
  for (int i = 0; i < 7 && w.pendingEvent == null; i++) {
    w.sleep();
  }
  if (w.pendingEvent == null) throw StateError('нет события');
  return w;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  for (final (String name, Size size, double scale, bool badge)
      in <(String, Size, double, bool)>[
    ('port-badge-1.3', const Size(360, 640), 1.3, true),
    ('land-badge-1.3', const Size(640, 360), 1.3, true),
    ('port-off-1.3', const Size(360, 640), 1.3, false),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final GlobalKey key = GlobalKey();
      await tester.runAsync(() async {
        final WorldState ws = WorldState(_world(badge: badge));
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: Provider<JobGames>.value(
            value: contentJobGames,
            child: Provider<OnboardingScript>.value(
              value: contentScript,
              child: ChangeNotifierProvider<WorldState>.value(
                value: ws,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildAppTheme(),
                  routes: worldRoutes,
                  builder: (BuildContext context, Widget? child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: const WorldTheme(child: RoomScreen()),
                ),
              ),
            ),
          ),
        ));
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await tester.pump(const Duration(milliseconds: 300));
        }
        final RenderRepaintBoundary b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ui.Image img = await b.toImage(pixelRatio: 2);
        final ByteData? png =
            await img.toByteData(format: ui.ImageByteFormat.png);
        final File out = File('build/kadry-event-badge/$name.png');
        await out.create(recursive: true);
        await out.writeAsBytes(png!.buffer.asUint8List());
      });
    });
  }
}
