import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/games/dog_walker_game.dart';
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

/// Кадры мини-игры выгульщика собак (настоящий экран смены, мир из сборки):
/// `flutter test tool/render_dogwalk_test.dart` → `build/kadry-dogwalk/`.
///
/// Ступень — по числу смен за игру: перед кадром ступени N мир делает N
/// смен других работ. «mid» — после нескольких шагов кратчайшего пути и
/// нажатия на препятствие (видна подсказка урока), «done» — собака дома.
World _world(int round) {
  final World w = worldKinds.last.make();
  w.startWeek();
  w.plan(needs: 100, wants: 100, goal: 0);
  w.demoUnlockAllJobs();
  for (int i = 0; i < round; i++) {
    w.completeJob(const <String>['cashier', 'consultant'][i], score: 1);
    if (w.pendingLesson case final LessonOffer l) {
      w.resolveLesson(l.choices.first.id);
    }
  }
  return w;
}

/// Ходы для кадра: (клетка) по порядку; препятствие — шаг не считается.
const Map<String, List<(int, int)>> _mid = <String, List<(int, int)>>{
  // Короткая: два шага вправо, нажатие на лужу.
  'short': <(int, int)>[(0, 1), (0, 2), (0, 3)],
  // Двор: вниз к монете, нажатие на забор.
  'yard': <(int, int)>[(1, 0), (2, 0), (2, 1), (1, 1)],
  // Парк: монета, нажатие на лужу.
  'park': <(int, int)>[(0, 1), (0, 2), (1, 2)],
};

/// Кратчайший путь короткой прогулки (best_steps 8).
const List<(int, int)> _shortDone = <(int, int)>[
  (1, 0),
  (2, 0),
  (2, 1),
  (2, 2),
  (1, 2),
  (1, 3),
  (2, 3),
  (3, 3),
];

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  final List<DogWalkLevel> levels = contentJobGames.dogWalker.levels;
  for (int round = 0; round < levels.length; round++) {
    final String id = levels[round].id;
    for (final (String name, Size size, List<(int, int)> moves)
        in <(String, Size, List<(int, int)>)>[
      ('$round-$id-port-start', const Size(360, 640), const <(int, int)>[]),
      ('$round-$id-port-mid', const Size(360, 640), _mid[id]!),
      ('$round-$id-land-mid', const Size(640, 360), _mid[id]!),
      if (id == 'short') ...<(String, Size, List<(int, int)>)>[
        ('$round-$id-port-done', const Size(360, 640), _shortDone),
        ('$round-$id-land-done', const Size(640, 360), _shortDone),
      ],
    ]) {
      testWidgets(name, (WidgetTester tester) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final GlobalKey key = GlobalKey();
        await tester.runAsync(() async {
          final WorldState ws = WorldState(_world(round));
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
                    builder: (BuildContext context, Widget? child) =>
                        MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(1.3)),
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
            for (int i = 0; i < 6; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              await tester.pump(const Duration(milliseconds: 400));
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
          await tap('job:start');
          for (final (int r, int c) in moves) {
            await tap('dogwalk:cell:$r:$c');
          }
          // Портрет: кадр со счётом над полем (после шагов прокрутка могла уехать
          // к подсказке). «done» — как оставил экран: докручен до кнопки.
          if (size.width < size.height && !name.endsWith('done')) {
            await tester.ensureVisible(
                find.byKey(const ValueKey<String>('dogwalk:status')));
            await settle();
          }
          final RenderRepaintBoundary b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final ui.Image img = await b.toImage(pixelRatio: 2);
          final ByteData? png =
              await img.toByteData(format: ui.ImageByteFormat.png);
          final File out = File('build/kadry-dogwalk/$name.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}
