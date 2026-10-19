import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
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

/// Кадры мини-решения смены (настоящий экран, движок с днями из сборки):
/// `flutter test tool/render_shift_choices_test.dart` → `build/kadry-choices/`.
///
/// Выгульщик собак (игра «Сделать»): журнал подбирается взносами по 1 монете,
/// пока у смены не выпадет вопрос с монетами.
WorldGame _world() {
  for (int deposits = 0; deposits < 40; deposits++) {
    final WorldGame w = contentDayWorld();
    w.startWeek();
    w.plan(needs: 0, wants: 0, goal: 0);
    if (w.pendingEvent case final PendingEvent e) {
      w.resolveEvent(
          e.choices.firstWhere((PendingEventChoice c) => c.available).id);
    }
    w.demoUnlockAllJobs();
    for (int i = 0; i < deposits; i++) {
      w.depositToGoal(1);
    }
    final ShiftChoice? q = w.offer('dog_walker')?.choice;
    if (q != null && q.id == 'dog_walker_second') return w;
  }
  throw StateError('нет вопроса');
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  for (final (String name, Size size, double scale, bool result)
      in <(String, Size, double, bool)>[
    ('port-offer-1.3-top', const Size(360, 640), 1.3, false),
    ('port-offer-1.3', const Size(360, 640), 1.3, false),
    ('port-result-1.3', const Size(360, 640), 1.3, true),
    ('port-offer-1.0', const Size(360, 640), 1.0, false),
    ('land-offer-1.3', const Size(640, 360), 1.3, false),
    ('land-result-1.3', const Size(640, 360), 1.3, true),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final GlobalKey key = GlobalKey();
      await tester.runAsync(() async {
        final WorldState ws = WorldState(_world());
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: Provider<JobGames>.value(
            value: contentJobGamesDogStub,
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
                  home: const WorldTheme(
                      child: JobPlayScreen(args: JobPlayArgs('dog_walker'))),
                ),
              ),
            ),
          ),
        ));
        Future<void> settle() async {
          for (int i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 300));
          }
        }

        Future<void> tap(String k) async {
          final Finder f = find.byKey(ValueKey<String>(k));
          await tester.ensureVisible(f);
          await settle();
          await tester.tap(f);
          await settle();
        }

        await settle();
        if (result) {
          await tap('job:choice:two');
          await tap('game:placeholder:do');
          // Строка «Выбор: …» — в кадре (урок над ней обязателен).
          await tester.ensureVisible(
              find.byKey(const ValueKey<String>('job:result:choice')));
          await settle();
        } else if (!name.endsWith('-top')) {
          // Вопрос целиком: прокрутка до блока вопроса.
          await tester.ensureVisible(
              find.byKey(const ValueKey<String>('job:choice')));
          await settle();
        }
        final RenderRepaintBoundary b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ui.Image img = await b.toImage(pixelRatio: 2);
        final ByteData? png =
            await img.toByteData(format: ui.ImageByteFormat.png);
        final File out = File('build/kadry-choices/$name.png');
        await out.create(recursive: true);
        await out.writeAsBytes(png!.buffer.asUint8List());
      });
    });
  }
}
