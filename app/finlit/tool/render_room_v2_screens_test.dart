import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
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
    show contentDayConfig, contentScript, roomOnConfig;
import 'test_fonts.dart';

/// Кадры экрана комнаты в сборке (`room.view: "iso"` по умолчанию, 20.10):
///
///     flutter test tool/render_room_v2_screens_test.dart  →  build/room-v2/*.png
///
/// Три стадии × телефон 360×640, телефон на боку 800×360, телефон 1440×3120
/// (физические px, плотность 3,5 → 411×891 dp), планшет 768×1024 и 1024×768;
/// шрифт ×1,0 и ×1,3; плюс «Расставить» на 360×640. Мир — числа сборки с
/// днями, автопилот доводит до стадии. На CI не гоняется.

World _worldAt(WorldStage stage, {bool customize = false}) {
  // «Расставить вещи» — только при room.customize (как в 0.1.3).
  final WorldGame w =
      WorldGame(config: customize ? roomOnConfig : contentDayConfig);
  WorldAutopilot(w).playToStage(stage);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}

typedef _Device = ({String tag, Size physical, double dpr});

const List<_Device> _devices = <_Device>[
  (tag: '360x640', physical: Size(360, 640), dpr: 1),
  (tag: '800x360', physical: Size(800, 360), dpr: 1),
  (tag: '1440x3120', physical: Size(1440, 3120), dpr: 3.5),
  (tag: 'tab768x1024', physical: Size(768, 1024), dpr: 1),
  (tag: 'tab1024x768', physical: Size(1024, 768), dpr: 1),
];

Future<void> _shot(GlobalKey key, String name, double dpr) async {
  final RenderRepaintBoundary b =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image img = await b.toImage(pixelRatio: dpr);
  final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
  final File out = File('build/room-v2/$name.png');
  await out.create(recursive: true);
  await out.writeAsBytes(png!.buffer.asUint8List());
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<GlobalKey> _pumpRoom(
    WidgetTester tester, World w, _Device d, double font) async {
  tester.view.physicalSize = d.physical;
  tester.view.devicePixelRatio = d.dpr;
  tester.platformDispatcher.textScaleFactorTestValue = font;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
          home: WorldTheme(child: const RoomScreen()),
        ),
      ),
    ),
  ));
  await _settle(tester);
  return key;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final WorldStage stage in WorldStage.values) {
    for (final _Device d in _devices) {
      for (final double font in <double>[1.0, 1.3]) {
        final String name =
            '${stage.name}-${d.tag}-f${font == 1 ? '10' : '13'}';
        testWidgets(name, (WidgetTester tester) async {
          await tester.runAsync(() async {
            final GlobalKey key =
                await _pumpRoom(tester, _worldAt(stage), d, font);
            await _shot(key, name, d.dpr);
          });
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('${stage.name}-360x640-f13-arrange',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final GlobalKey key = await _pumpRoom(
            tester, _worldAt(stage, customize: true), _devices.first, 1.3);
        await tester.tap(find.byKey(const ValueKey<String>('room:menu')));
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey<String>('room:arrange')));
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey<String>('room:bed')));
        await _settle(tester);
        await _shot(key, '${stage.name}-360x640-f13-arrange', 1);
        // Drop the bed on a free cell by touch (select → cell): the words
        // under the room change; the room must not jump (D3).
        await tester
            .tap(find.byKey(const ValueKey<String>('room:iso:cell:3:4')));
        await _settle(tester);
        await _shot(key, '${stage.name}-360x640-f13-arrange-after', 1);
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('${stage.name}-360x640-f10-zoom', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final GlobalKey key =
            await _pumpRoom(tester, _worldAt(stage), _devices.first, 1.0);
        await tester.tap(find.byKey(const ValueKey<String>('room:iso:camera')));
        await _settle(tester);
        await _shot(key, '${stage.name}-360x640-f10-zoom', 1);
      });
      expect(tester.takeException(), isNull);
    });
  }
}
