// Кадры настоящей обучалки (lib/features/world/tutorial/) — все шаги, три
// вида, портрет и альбомная. Для страницы docs/final/tutorial/ и
// визуальной проверки.
//   flutter test tool/render_tutorial_live_test.dart  → build/tutorial-live/*.png
//   ONLY=spotlight-land  — только кадры, чьё имя содержит строку.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/tutorial/tutorial_gate.dart';
import 'package:finlit/features/world/tutorial/tutorial_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  final String only = Platform.environment['ONLY'] ?? '';
  const Map<String, Size> sizes = <String, Size>{
    'port': Size(360, 640),
    'land': Size(640, 360),
    'tab': Size(800, 1280),
    'tab768': Size(768, 1024),
  };
  // Шрифт системы: SCALE=1.3 — кадры крупного шрифта (имя с «-1.3»).
  final double scale =
      double.tryParse(Platform.environment['SCALE'] ?? '') ?? 1;
  for (final TutorialLook look in <TutorialLook>[
    TutorialLook.spotlight,
    TutorialLook.dialog,
    TutorialLook.hints,
  ]) {
    for (final MapEntry<String, Size> sz in sizes.entries) {
      final String base =
          '${look.name}-${sz.key}${scale == 1 ? '' : '-$scale'}';
      if (only.isNotEmpty && !base.contains(only)) continue;
      testWidgets(base, (WidgetTester tester) async {
        final WorldGame w = contentDayWorld(
            onboarding:
                const OnboardingProgress(step: OnboardingProgress.stepDone));
        if (w.phase != WeekPhase.living) ok(w.startWeek());
        if (w.phase == WeekPhase.planning) {
          ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
        }
        final GlobalKey shot = GlobalKey();
        await tester.runAsync(() async {
          await pumpWorldScreen(
              tester,
              RepaintBoundary(
                  key: shot,
                  child: TutorialGate(look: look, child: const RoomScreen())),
              world: w,
              size: sz.value * 2,
              textScale: scale);
          tester.view.devicePixelRatio = 2;
          for (int i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 50));
          }
          for (int i = 0; i < tutorialSteps.length; i++) {
            // Камера едет к предмету шага (дверь) — дождаться.
            for (int j = 0; j < 15; j++) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              await tester.pump(const Duration(milliseconds: 30));
            }
            final RenderRepaintBoundary b = shot.currentContext!
                .findRenderObject()! as RenderRepaintBoundary;
            final ui.Image img = await b.toImage(pixelRatio: 2);
            final ByteData? png =
                await img.toByteData(format: ui.ImageByteFormat.png);
            final File out = File(
                'build/tutorial-live/$base-${i + 1}-${tutorialSteps[i].id}.png');
            await out.create(recursive: true);
            await out.writeAsBytes(png!.buffer.asUint8List());
            final Finder next =
                find.byKey(const ValueKey<String>('tutorial:next'));
            if (next.evaluate().isEmpty) break;
            await tester.tap(next, warnIfMissed: false);
          }
        });
      });
    }
  }
}
