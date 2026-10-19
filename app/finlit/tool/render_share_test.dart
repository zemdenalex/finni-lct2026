// Рендер страницы вариантов «Отправить родителю» (консультация 16.10, п. 4):
// docs/final/otpravit-roditelyu/. Настоящий экран «Прогресс»,
// варианты — переключатель [shareLook].
//   flutter test tool/render_share_test.dart  → build/share/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/history/parent_share.dart';
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

/// Неделя 1 закрыта (смена, урок, счета), неделя 2 идёт — как в проходе
/// пути ребёнка (docs/final/put-rebenka).
World _world() {
  final World w = contentWorld()..startWeek();
  w.plan(needs: 300, wants: 50, goal: 50);
  w.chooseGoal('pet_fish');
  w.completeJob('consultant', score: 1);
  w.sleep();
  w.payBills();
  w.startWeek();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  return w;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  tearDown(() => shareLook = ShareLook.none);
  for (final ShareLook look in ShareLook.values) {
    for (final bool open in <bool>[false, true]) {
      if (open && look == ShareLook.none) continue;
      final String name = '${look.name}-${open ? '2-preview' : '1-progress'}';
      testWidgets(name, (WidgetTester tester) async {
        shareLook = look;
        tester.view.physicalSize = const Size(360, 640) * 2;
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
                  home: const WorldTheme(child: HistoryScreen()),
                ),
              ),
            ),
          ));
          Future<void> settle() async {
            for (int i = 0; i < 6; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 40));
              await tester.pump(const Duration(milliseconds: 300));
            }
          }

          await settle();
          if (open) {
            await tester
                .tap(find.byKey(const ValueKey<String>('history:share')));
            await settle();
          }
          final RenderRepaintBoundary b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final ui.Image img = await b.toImage(pixelRatio: 2);
          final ByteData? png =
              await img.toByteData(format: ui.ImageByteFormat.png);
          final File out = File('build/share/$name.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}
