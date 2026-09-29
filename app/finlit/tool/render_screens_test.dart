import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/core/world_art.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/demo_autopilot.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:finlit/features/adult/adult_screen.dart';
import 'package:finlit/features/demo/demo_screen.dart';
import 'package:finlit/features/glossary/glossary_screen.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:finlit/features/onboarding/onboarding_screen.dart';
import 'package:finlit/features/pet/pet_create_screen.dart';
import 'package:finlit/features/plan/plan_screen.dart';
import 'package:finlit/features/progress/progress_screen.dart';
import 'package:finlit/features/savings/savings_screen.dart';
import 'package:finlit/features/settings/settings_screen.dart';
import 'package:finlit/features/shop/shop_screen.dart';
import 'package:finlit/features/tasks/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_fonts.dart';

/// Рабочий стенд дизайна: экраны в нескольких состояниях игры, 360 dp.
///
///     flutter test tool/render_screens_test.dart   →   build/screens/*.png
///
/// Для каждого экрана два снимка: `*-phone.png` — видимая часть телефона
/// 360×760 dp, и `*-full.png` — высокое окно, где видна вся прокрутка.
/// Нужен, чтобы после каждой правки на экран можно было посмотреть глазами,
/// а не судить по коду. На CI не гоняется.
Future<void> _shot(
  WidgetTester tester,
  AppState app,
  String name,
  Widget screen, {
  bool full = true,
  Future<void> Function(WidgetTester t)? interact,
  double textScale = 1.0,
}) async {
  for (final bool tall in <bool>[false, if (full) true]) {
    tester.view.physicalSize = Size(1080, tall ? 1080 * 5.0 : 760 * 3.0);
    tester.view.devicePixelRatio = 3.0;
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            builder: (BuildContext c, Widget? child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: screen,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    if (interact != null) {
      await interact(tester);
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.runAsync(() async {
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 3.0);
      final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
      final File out = File('build/screens/$name-${tall ? 'full' : 'phone'}.png');
      await out.create(recursive: true);
      await out.writeAsBytes(png!.buffer.asUint8List());
    });
  }
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Future<AppState> _fresh() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  return app;
}

/// Середина недели: план подтверждён, куплены вещи, выполнено задание.
Future<AppState> _midWeek({bool fox = false}) async {
  final AppState app = await _fresh();
  if (fox) {
    await app.updateProfile(app.game.profile.copyWith(
        species: PetSpecies.fox, palette: PetPalette.apricot));
  } else {
    await app.updateProfile(
        app.game.profile.copyWith(palette: PetPalette.apricot));
  }
  await app.act((Game g) => g.startPeriod());
  await app.act((Game g) => g.completeTask(app.content.tasks.first, best: true));
  app.game.chooseGoal('house');
  final int all = app.game.snapshot.wallet.unallocated;
  await app.act((Game g) =>
      g.confirmPlan(Allocation(needs: 4, wants: 4, savings: all - 8)));
  CatalogItem item(String id) =>
      app.content.catalog.firstWhere((CatalogItem i) => i.id == id);
  await app.act((Game g) => g.buy(item('porridge')));
  await app.act((Game g) => g.buy(item('ball')));
  await app.act((Game g) => g.buy(item('stickers')));
  return app;
}

void main() {
  setUp(rootBundle.clear);
  setUpAll(loadAppFonts);

  final Set<String> only = (Platform.environment['SCREENS'] ?? '')
      .split(',')
      .where((String s) => s.isNotEmpty)
      .toSet();
  bool want(String n) => only.isEmpty || only.contains(n);

  testWidgets('первый запуск', (WidgetTester tester) async {
    final AppState app = await _fresh();
    if (want('onboarding')) {
      for (int i = 0; i < 4; i++) {
        await _shot(tester, app, 'onboarding-$i', const OnboardingScreen(),
            full: false, interact: (WidgetTester t) async {
          for (int k = 0; k < i; k++) {
            await t.drag(find.byType(PageView), const Offset(-400, 0));
            await t.pumpAndSettle();
          }
        });
      }
    }
    if (want('pet')) {
      await _shot(tester, app, 'pet', const PetCreateScreen());
    }
    await app.act((Game g) => g.startPeriod());
    if (want('home0')) await _shot(tester, app, 'home0', const HomeScreen());
    if (want('plan')) await _shot(tester, app, 'plan', const PlanScreen());
  });

  testWidgets('середина недели', (WidgetTester tester) async {
    final AppState app = await _midWeek();
    if (want('home')) await _shot(tester, app, 'home', const HomeScreen());
    if (want('home13')) {
      await _shot(tester, app, 'home13', const HomeScreen(),
          full: false, textScale: 1.3);
    }
    if (want('shop')) await _shot(tester, app, 'shop', const ShopScreen());
    if (want('savings')) {
      await _shot(tester, app, 'savings', const SavingsScreen());
    }
    if (want('tasks')) await _shot(tester, app, 'tasks', const TasksScreen());
    // Каждое задание своим экраном — после правки контента смотреть надо
    // на то, что увидит ребёнок, а не на JSON. Только по запросу:
    // SCREENS=players.
    if (only.contains('players')) {
      for (final GameTask t in app.content.tasks) {
        await _shot(tester, app, 'task-${t.id}', taskPlayer(t), full: false);
      }
    }
    if (want('planfact')) {
      await _shot(tester, app, 'planfact', const PlanScreen());
    }
    if (want('bought')) {
      await _shot(tester, app, 'bought', const ShopScreen(), full: false,
          interact: (WidgetTester t) async {
        final BuildContext c = t.element(find.byType(ShopScreen));
        unawaited(showFeedback(c, app.lastFeedback!,
            room: RoomScene(
              stage: app.game.snapshot.stage,
              keepsakes: app.game.keepsakes,
              goal: app.game.goal,
              saved: app.game.snapshot.wallet.savings,
              fresh: 'star',
            )));
        await t.pumpAndSettle();
      });
    }
  });

  testWidgets('несколько недель спустя', (WidgetTester tester) async {
    final AppState app = await _midWeek(fox: true);
    for (int w = 0; w < 3; w++) {
      await app.closePeriod();
      await app.act((Game g) => g.startPeriod());
      final int all = app.game.snapshot.wallet.unallocated;
      // Реалистичная неделя: еда и вода, немного на «Хочу», остальное
      // в копилку — Хранитель копилки откладывает.
      await app.act((Game g) =>
          g.confirmPlan(Allocation(needs: 3, wants: 1, savings: all - 4)));
      await app.act((Game g) => g.buy(app.content.catalog
          .firstWhere((CatalogItem i) => i.id == 'porridge')));
      await app.act((Game g) => g.buy(
          app.content.catalog.firstWhere((CatalogItem i) => i.id == 'water')));
    }
    if (want('homeLate')) {
      await _shot(tester, app, 'homeLate', const HomeScreen());
    }
    if (want('progress')) {
      await _shot(tester, app, 'progress', const ProgressScreen());
    }
    if (want('glossary')) {
      await _shot(tester, app, 'glossary', const GlossaryScreen());
    }
    if (want('settings')) {
      await _shot(tester, app, 'settings', const SettingsScreen());
    }
    if (want('adult')) await _shot(tester, app, 'adult', const AdultScreen());
    if (want('demo')) await _shot(tester, app, 'demo', const DemoScreen());
  });

  // Стадия «Хранитель копилки»: Финни предлагает раскладку. SCREENS=keeper.
  testWidgets('хранитель копилки', (WidgetTester tester) async {
    if (!only.contains('keeper')) return;
    final AppState app = await _fresh();
    await app.setDemoMode(true);
    await app.act((Game g) {
      DemoAutopilot.playTo(g, PetStage.planner);
      return const ActionResult(title: '', text: '', nextStep: '');
    });
    await _shot(tester, app, 'keeper-plan', const PlanScreen());
    await _shot(tester, app, 'keeper-home', const HomeScreen());
  });
}
