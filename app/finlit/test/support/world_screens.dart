import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
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
import 'package:finlit/features/glossary/glossary_screen.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:finlit/features/world/demo/world_demo_screen.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'world_harness.dart';

// Карта экранов нового мира S0–S16 с миром, в котором каждый из них
// показывает содержимое. Одна на все тесты «по всем экранам»: ориентация и
// масштаб (`orientation_test.dart`), цели касания (`tap_targets_test.dart`).

World livingWorld(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  ok(w.chooseGoal('pet_fish'));
  return w;
}

/// Ник и облик выбраны, неделя 1 ждёт плана: знакомство идёт сценками в
/// комнате.
World scenesWorld(WorldKind kind) {
  final World w = kind.make(
      onboarding: const OnboardingProgress(
          step: OnboardingProgress.stepMoney, nickname: 'Кот'));
  ok(w.startWeek());
  return w;
}

World reviewWorld(WorldKind kind) {
  final World w = livingWorld(kind);
  ok(w.sleep());
  return w;
}

/// Счета недели 1 оплачены: итоги с планом против факта, история из двух
/// недель (вторая идёт).
World paidWorld(WorldKind kind) {
  final World w = reviewWorld(kind);
  ok(w.payBills());
  return w;
}

World twoWeeksWorld(WorldKind kind) {
  final World w = paidWorld(kind);
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return w;
}

Map<String, (Widget, World Function())> worldScreens(WorldKind kind) {
  World living() => livingWorld(kind);
  return <String, (Widget, World Function())>{
    'S0 онбординг': (const WorldOnboardingScreen(), kind.make),
    'S0 сценки': (const WorldOnboardingScreen(), () => scenesWorld(kind)),
    'S1 комната': (const RoomScreen(), living),
    'S2 город': (const CityScreen(), living),
    'S4 магазин': (const WorldShopScreen(), living),
    'S5 зоомагазин': (const PetShopScreen(), living),
    'S6 доска': (const JobBoardScreen(), living),
    'S7 смена': (
      const JobPlayScreen(args: JobPlayArgs('cashier')),
      living,
    ),
    'S8 досуг': (const LeisureScreen(place: 'cinema'), living),
    'S9 копилка': (const PiggyScreen(), living),
    'S10 событие': (const EventScreen(), living),
    'S10 событие · нет события': (const EventScreen(), kind.make),
    'S11 итоги': (const WeekReviewScreen(), () => reviewWorld(kind)),
    'S11 итоги · оплачено': (const WeekReviewScreen(), () => paidWorld(kind)),
    'S12 прогресс': (const HistoryScreen(), () => twoWeeksWorld(kind)),
    'S12 прогресс · пусто': (const HistoryScreen(), kind.make),
    'S13 словарик': (const GlossaryScreen(allOpen: true), living),
    'S14 взрослым': (const WorldAdultScreen(), living),
    'S15 настройки': (const WorldSettingsScreen(), living),
    'S16 проверка': (const WorldDemoScreen(), living),
  };
}

/// Экраны, которым нужен профиль с настройками (AppState).
const Set<String> screensWithProfile = <String>{
  'S13 словарик',
  'S15 настройки',
};

/// Экран из [worldScreens] на [size] и масштабе шрифта [textScale]: профиль
/// с настройками, если экрану он нужен, и несколько кадров, чтобы отработали
/// асинхронная загрузка и первые анимации.
Future<void> pumpListedScreen(
  WidgetTester tester,
  String name,
  (Widget, World Function()) entry, {
  required Size size,
  double textScale = 1,
}) async {
  await tester.runAsync(() async {
    final AppState? app =
        screensWithProfile.contains(name) ? AppState(MemoryStorage()) : null;
    await app?.boot();
    await pumpWorldScreen(tester, entry.$1,
        world: entry.$2(), size: size, textScale: textScale, app: app);
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 400));
}
