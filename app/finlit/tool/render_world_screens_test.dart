import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/glossary/glossary_screen.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/event/event_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/leisure/leisure_screen.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:finlit/features/world/shop/pet_shop_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:finlit/features/world/demo/world_demo_screen.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:finlit/features/world/onboarding/onboarding_script.dart';

import '../test/support/world_harness.dart'
    show contentDayWorld, contentScript, contentWorld;
import 'test_fonts.dart';

/// Стенд экранов нового мира в обеих ориентациях:
///
///     flutter test tool/render_world_screens_test.dart  →  build/world/*.png
///
/// `*-land.png` — 640×360 (основная), `*-port.png` — 360×640, `*-land800`/`*-port800` —
/// 800×360 и 360×800 (узкие телефоны 20:9). На CI не гоняется.
///
/// Мир — настоящий движок на числах из контента (`contentWorld`), как в
/// приложении.
World _living() {
  final World w = contentWorld()..startWeek();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  w.chooseGoal('pet_fish');
  w.completeJob('consultant', score: 1);
  return w;
}

World _review() => _living()..sleep();

/// Магазин 29.09: всё в ХОЧУ, куплены тумбочка и кровать (скины комнаты).
World _furnished() {
  final World w = contentWorld()..startWeek();
  w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
  w.completeJob('consultant', score: 1);
  w.buy('skin_cabinet__20v');
  w.buy('skin_bed__4a');
  w.buy('skin_cabinet__19v');
  return w;
}

/// Знакомство: ник и облик выбраны, неделя 1 ждёт плана — сценки в комнате.
World _scenes() {
  final World w = contentWorld(
      onboarding: const OnboardingProgress(
          step: OnboardingProgress.stepMoney,
          nickname: 'Звёздочка',
          finniSpecies: 'finni-a2',
          finniLook: 3));
  w.startWeek();
  return w;
}

/// Сценки знакомства в мире с днями, как в релизе: на неделю 820, счета 740
/// (план — «Как советует Финни», Денис 17.10, чат 1898).
World _scenesDay() {
  final World w = contentDayWorld(
      onboarding: const OnboardingProgress(
          step: OnboardingProgress.stepMoney,
          nickname: 'Звёздочка',
          finniSpecies: 'finni-a2',
          finniLook: 3));
  w.startWeek();
  return w;
}

/// План недели из комнаты в мире с днями.
World _planningDay() => contentDayWorld()..startWeek();

/// Знакомство: план подтверждён, сценка первой цели.
World _scenesGoal() {
  final World w = _scenes();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  return w;
}

/// Регистрация: ник есть, шаг облика и имени.
World _look() => contentWorld(
    onboarding: const OnboardingProgress(
        step: OnboardingProgress.stepFinni, nickname: 'Звёздочка'));

/// Стадия «В Москве»: автопилот демо доигрывает до неё настоящими неделями —
/// за городом встают башни Москва-Сити.
World _moscow() {
  final WorldGame w = contentWorld();
  WorldAutopilot(w).playToStage(WorldStage.moscow);
  return w;
}

/// Комната стадии посреди недели: автопилот доигрывает до [stage], потом
/// неделя начата и спланирована — кровать, дверь и копилка в деле.
World _livingAt(WorldStage stage) {
  final WorldGame w = contentWorld();
  WorldAutopilot(w).playToStage(stage);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}

/// Комната с купленными вещами (трек арта 2, 29.09): мишка и книги — каждая
/// на своём месте общей раскладки.
World _decorated() {
  // Первая неделя: план — всё свободное в ХОЧУ, потом покупки.
  final World w = contentWorld()..startWeek();
  w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
  w.chooseGoal('pet_fish');
  for (final String id in <String>['decor_bear', 'decor_books']) {
    w.buy(id);
  }
  return w;
}

/// Купленный вид мебели (финал 15.10, критерии комнаты): автопилот копит,
/// неделя спланирована в «хочу», куплены кровать, стол и тумба.
World _looks() {
  final WorldGame w = contentWorld();
  WorldAutopilot(w).playToStage(WorldStage.town);
  WorldAutopilot(w).playWeeks(3);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
  }
  for (final String id in <String>[
    'skin_cabinet__19a',
    'skin_desk__10a',
    'skin_bed__4a',
  ]) {
    w.buy(id);
  }
  return w;
}

/// Итоги открыты после оплаты счетов — видно план против факта.
World _paid() => _review()..payBills();

/// Город с «Куда идти» (`city.guide`): до плана недели — домой.
World _planning() => contentWorld()..startWeek();

/// Город с «Куда идти»: всё в копилку, на счета не хватает — на работу.
World _short() {
  final World w = contentWorld()..startWeek();
  w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated);
  return w;
}

/// Две недели: вторая идёт — смена и перекус.
World _history() {
  final World w = _paid()..startWeek();
  w.plan(needs: 200, wants: 100, goal: 50);
  w.completeJob('cashier', score: 1);
  w.buy('snack');
  return w;
}

final Map<String, (Widget, World Function())> _screens =
    <String, (Widget, World Function())>{
  's00-onboarding': (const WorldOnboardingScreen(), contentWorld),
  's00-look': (const WorldOnboardingScreen(), _look),
  's00-scene-hello': (const WorldOnboardingScreen(), _scenes),
  's00-scene-envelopes': (const WorldOnboardingScreen(), _scenes),
  's00-scene-piggy': (const WorldOnboardingScreen(), _scenes),
  's00-scene-fridge': (const WorldOnboardingScreen(), _scenes),
  's00-scene-door': (const WorldOnboardingScreen(), _scenes),
  's00-scene-plan': (const WorldOnboardingScreen(), _scenes),
  's00-scene-plan-day': (const WorldOnboardingScreen(), _scenesDay),
  's00-scene-plan-advice': (const WorldOnboardingScreen(), _scenesDay),
  's01-plan-sheet': (const RoomScreen(), _planningDay),
  's01-plan-sheet-advice': (const RoomScreen(), _planningDay),
  's00-scene-goal': (const WorldOnboardingScreen(), _scenesGoal),
  's01-room': (const RoomScreen(), _living),
  's01-room-town': (const RoomScreen(), () => _livingAt(WorldStage.town)),
  's01-room-moscow': (const RoomScreen(), () => _livingAt(WorldStage.moscow)),
  's01-room-decor': (const RoomScreen(), _decorated),
  // Реакция питомца A: Финни погладили — сердечки, радость, причина.
  's01-room-pet': (const RoomScreen(), () => _livingAt(WorldStage.town)),
  // Сообщение комнаты над панелью разделов, а не поверх (Саша, 15.10).
  's01-room-msg': (const RoomScreen(), _living),
  's01-room-looks': (const RoomScreen(), _looks),
  's02-city': (const CityScreen(), _living),
  's02-city-moscow': (const CityScreen(), _moscow),
  's02-city-guide-plan': (const CityScreen(), _planning),
  's02-city-guide-short': (const CityScreen(), _short),
  's02-city-guide-off': (const CityScreen(guide: false), _living),
  // Варианты раскладки города (Денис, 29.09): A — вертикально, B — как
  // Clash of Clans; по стадии на каждый.
  for (final (String v, CityVariant cv) in <(String, CityVariant)>[
    ('a', CityVariant.vertical),
    ('b', CityVariant.iso),
  ]) ...<String, (Widget, World Function())>{
    's02-city-$v-village': (CityScreen(variant: cv), _living),
    's02-city-$v-town': (
      CityScreen(variant: cv),
      () => _livingAt(WorldStage.town)
    ),
    's02-city-$v-moscow': (
      CityScreen(variant: cv),
      () => _livingAt(WorldStage.moscow)
    ),
  },
  's04-shop': (const WorldShopScreen(), _living),
  's04-shop-want': (const WorldShopScreen(initialTab: 1), _living),
  's04-shop-clothes': (const WorldShopScreen(initialTab: 2), _living),
  'shop-want': (const WorldShopScreen(initialTab: 1), _living),
  'shop-furniture': (const WorldShopScreen(initialTab: 3), _living),
  'shop-tech': (const WorldShopScreen(initialTab: 4), _living),
  'shop-bought': (const WorldShopScreen(initialTab: 3), _furnished),
  'shop-room-skins': (const RoomScreen(), _furnished),
  's05-petshop': (const PetShopScreen(), _living),
  's06-jobs': (const JobBoardScreen(), _living),
  's07-job': (const JobPlayScreen(args: JobPlayArgs('cashier')), _living),
  's08-leisure': (const LeisureScreen(place: 'cinema'), _living),
  's09-piggy': (const PiggyScreen(), _living),
  's10-event': (const EventScreen(), _living),
  's11-review': (const WeekReviewScreen(), _review),
  's11-review-paid': (const WeekReviewScreen(), _paid),
  's12-history': (const HistoryScreen(), _history),
  's13-glossary': (const GlossaryScreen(allOpen: true), _living),
  's14-adult': (const WorldAdultScreen(), _living),
  's15-settings': (const WorldSettingsScreen(), _living),
  's16-demo': (const WorldDemoScreen(), _living),
};

/// Сценки знакомства: сколько раз нажать «Дальше» (или «Пропустить») до
/// снимка.
final Map<String, List<String>> _taps = <String, List<String>>{
  's00-scene-envelopes': <String>['onboarding-next'],
  's01-room-pet': <String>['room:finni'],
  's01-room-msg': <String>['room:nav:week', 'room:week:plan'],
  's00-scene-piggy': <String>['onboarding-next', 'onboarding-next'],
  's00-scene-fridge': <String>[
    for (int i = 0; i < 3; i++) 'onboarding-next',
  ],
  's00-scene-door': <String>[
    for (int i = 0; i < 5; i++) 'onboarding-next',
  ],
  's00-scene-plan': <String>['onboarding:skip'],
  's00-scene-plan-day': <String>['onboarding:skip'],
  's00-scene-plan-advice': <String>['onboarding:skip', 'plan:advice'],
  's01-plan-sheet': <String>['room:now'],
  's01-plan-sheet-advice': <String>['room:now', 'plan:advice'],
};

/// Экраны, которым нужен профиль старой игры (AppState): настройки, словарик.
const Set<String> _withProfile = <String>{'s13-glossary', 's15-settings'};

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  final String only = Platform.environment['ONLY'] ?? '';
  for (final MapEntry<String, (Widget, World Function())> s
      in _screens.entries) {
    if (only.isNotEmpty && !s.key.contains(only)) continue;
    for (final (String tag, Size size) in <(String, Size)>[
      ('land', const Size(640, 360)),
      ('port', const Size(360, 640)),
      ('land800', const Size(800, 360)),
      ('port800', const Size(360, 800)),
      // Фидбек 15.10 [1555]: S25 Ultra (1440×3120 физ., ≈412×891 dp) и
      // браузер на 1440×3120 css-px (веб-демо).
      if (Platform.environment['TALL'] != null) ...<(String, Size)>[
        ('s25', const Size(412, 891)),
        ('s25land', const Size(891, 412)),
        ('web1440', const Size(1440, 3120)),
      ],
    ]) {
      testWidgets('${s.key}-$tag', (WidgetTester tester) async {
        final double dpr = size.width > 1000 ? 1 : 2;
        tester.view.physicalSize = size * dpr;
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        final GlobalKey key = GlobalKey();
        await tester.runAsync(() async {
          final AppState? app =
              _withProfile.contains(s.key) ? AppState(MemoryStorage()) : null;
          await app?.boot();
          // Сценарий знакомства — как в main.dart, до первого кадра: иначе
          // кадр ловит его загрузку («Дальше» ещё погашена).
          final Widget screen = Provider<OnboardingScript>.value(
            value: contentScript,
            child: ChangeNotifierProvider<WorldState>.value(
              value: WorldState(s.value.$2()),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(),
                routes: worldRoutes,
                home: WorldTheme(child: s.value.$1),
              ),
            ),
          );
          await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: app == null
                ? screen
                : ChangeNotifierProvider<AppState>.value(
                    value: app, child: screen),
          ));
          for (int i = 0; i < 8; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump();
          }
          for (final String tap in _taps[s.key] ?? const <String>[]) {
            await tester.tap(find.byKey(ValueKey<String>(tap)));
            for (int i = 0; i < 6; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 40));
              await tester.pump(const Duration(milliseconds: 400));
            }
          }
          final RenderRepaintBoundary b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final ui.Image img = await b.toImage(pixelRatio: 2);
          final ByteData? png =
              await img.toByteData(format: ui.ImageByteFormat.png);
          final File out = File('build/world/${s.key}-$tag.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}
