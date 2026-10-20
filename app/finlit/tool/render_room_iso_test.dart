import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/home/room_skins.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/room_iso/iso_room_scene.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart' show contentScript, weekMode;
import 'test_fonts.dart';

/// Кадры iso-комнаты (V2, ветка final/room-iso-v2):
///
///     flutter test tool/render_room_iso_test.dart  →  build/room-iso/*.png
///
/// `screen-*` — настоящий экран комнаты с флагом `room.view: "iso"`;
/// `scene-*` — сама сцена со всем декором и скинами: вся комната, «К Финни»,
/// перетаскивание (призрак зелёный и красный). На CI не гоняется.

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldConfig _isoConfig() {
  final Map<String, Object?> eco =
      jsonDecode(weekMode(_read('economy.json'))) as Map<String, Object?>;
  eco['room'] = <String, Object?>{
    ...(eco['room'] as Map<String, Object?>? ?? const <String, Object?>{}),
    'customize': true,
    'view': 'iso',
  };
  return worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
    roomItems: _read('room_items.json'),
  ));
}

World _isoWorld() {
  final WorldGame w = WorldGame(config: _isoConfig());
  WorldAutopilot(w).playToStage(WorldStage.town);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}

/// One bought id per decor place and one skin per piece of furniture.
(List<String>, Map<String, String>) _bought(World w) {
  final List<String> ids = <String>[
    for (final WorldCatalogItem i in w.catalog) i.id,
  ];
  final Map<String, String> bySlot = <String, String>{};
  for (final String id in ids.where(isDecorId)) {
    bySlot.putIfAbsent(decorPlace(id).slot, () => id);
  }
  final Map<String, String> skins = furnitureSkins(equippedSkins(
      ids.where((String id) => id.startsWith('skin_')).toList(),
      const <String, String>{}));
  return (bySlot.values.toList(), skins);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final RenderRepaintBoundary b =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image img = await b.toImage(pixelRatio: 1);
  final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
  final File out = File('build/room-iso/$name.png');
  await out.create(recursive: true);
  await out.writeAsBytes(png!.buffer.asUint8List());
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  const List<Size> sizes = <Size>[Size(360, 640), Size(768, 1024)];

  for (final Size size in sizes) {
    final String tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('screen-$tag', (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final GlobalKey key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: Provider<OnboardingScript>.value(
            value: contentScript,
            child: ChangeNotifierProvider<WorldState>.value(
              value: WorldState(_isoWorld()),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(),
                routes: worldRoutes,
                home: WorldTheme(child: const RoomScreen()),
              ),
            ),
          ),
        ));
        await _settle(tester);
        await _shot(tester, key, 'screen-$tag');
      });
    });

    // Nothing bought: the furniture of each stage as a child first sees it.
    for (final WorldStage stage in WorldStage.values) {
      testWidgets('scene-default-${stage.name}-$tag',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final GlobalKey key = GlobalKey();
        await tester.runAsync(() async {
          final RoomArt art = await RoomArt.load();
          await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: Material(
                child: IsoRoomScene(
                  art: art,
                  stage: stage,
                  species: 'finni-a2',
                  idleTag: 'idle-1',
                  finniName: 'Финни',
                  happiness: 60,
                  topInset: 88,
                ),
              ),
            ),
          ));
          await _settle(tester);
          await _shot(tester, key, 'scene-default-${stage.name}-$tag');
        });
      });
    }

    for (final String frame in <String>[
      'all',
      'finni',
      'drag-ok',
      'drag-bad'
    ]) {
      testWidgets('scene-$frame-$tag', (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final GlobalKey key = GlobalKey();
        final World w = _isoWorld();
        final (List<String> decor, Map<String, String> skins) = _bought(w);
        await tester.runAsync(() async {
          final RoomArt art = await RoomArt.load();
          await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: Material(
                child: IsoRoomScene(
                  art: art,
                  stage: WorldStage.town,
                  species: 'finni-a2',
                  idleTag: 'idle-1',
                  finniName: 'Финни',
                  happiness: 60,
                  decorIds: decor,
                  furnitureSkins: skins,
                  topInset: 88,
                  arrange: frame.startsWith('drag'),
                  onSelect: (_) {},
                ),
              ),
            ),
          ));
          await _settle(tester);
          if (frame == 'finni') {
            await tester
                .tap(find.byKey(const ValueKey<String>('room:iso:camera')));
            await _settle(tester);
          }
          TestGesture? g;
          if (frame.startsWith('drag')) {
            Offset cell(int x, int y) => tester
                .getCenter(find.byKey(ValueKey<String>('room:iso:cell:$x:$y')));
            // The globe (5,1): to a free cell, or onto the bed.
            final Offset from = cell(5, 1);
            final Offset to = frame == 'drag-ok' ? cell(3, 4) : cell(1, 0);
            g = await tester.startGesture(from);
            for (int i = 1; i <= 8; i++) {
              await g.moveTo(Offset.lerp(from, to, i / 8)!);
              await tester.pump();
            }
            await _settle(tester);
          }
          await _shot(tester, key, 'scene-$frame-$tag');
          await g?.up();
        });
      });
    }
  }
}
