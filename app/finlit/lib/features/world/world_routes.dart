import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/world_theme.dart';
import '../glossary/glossary_screen.dart';

import 'adult/world_adult_screen.dart';
import 'city/city_screen.dart';
import 'demo/world_demo_screen.dart';
import 'dev/sprite_test_screen.dart';
import 'event/event_screen.dart';
import 'history/history_screen.dart';
import 'home/room_screen.dart';
import 'jobs/job_board_screen.dart';
import 'jobs/job_play_screen.dart';
import 'leisure/leisure_screen.dart';
import 'onboarding/world_onboarding_screen.dart';
import 'piggy/piggy_screen.dart';
import 'review/week_review_screen.dart';
import 'world_state.dart';
import 'settings/world_settings_screen.dart';
import 'shop/pet_shop_screen.dart';
import 'shop/world_shop_screen.dart';

/// Маршруты нового мира (поток B). Номера экранов — `docs/game/`.
///
/// Каждая карточка правит только свой экран; таблица маршрутов здесь уже
/// полная, чтобы правки не конфликтовали в одном файле.
abstract final class WorldRoutes {
  static const String onboarding = '/w/onboarding'; // S0 · B1
  static const String room = '/w/room'; // S1 · B2
  static const String city = '/w/city'; // S2 · B3
  static const String shop = '/w/shop'; // S4 · B4
  static const String petShop = '/w/pet-shop'; // S5 · B4
  static const String jobs = '/w/jobs'; // S6 · B5

  /// S7 · B6/B7. Аргумент — [JobPlayArgs].
  static const String job = '/w/job';
  static const String leisure = '/w/leisure'; // S8 · B8
  static const String piggy = '/w/piggy'; // S9 · B4
  static const String event = '/w/event'; // S10 · B8
  static const String review = '/w/review'; // S11 · B8
  static const String history = '/w/history'; // S12
  static const String sprites = '/w/dev/sprites'; // B0
  static const String adult = '/w/adult'; // S14 · B9
  static const String demo = '/w/demo'; // S16 · B9

  /// Звук и анимации (ТЗ 3.6.7) — открывается из комнаты без барьера.
  static const String settings = '/w/settings'; // S15

  /// Словарик (ТЗ 2.5.11.2) — из «Словарик» в каждой подсказке «?».
  static const String glossary = '/w/glossary'; // S13
}

/// Аргумент маршрута [WorldRoutes.job]: какую смену играть.
class JobPlayArgs {
  const JobPlayArgs(this.jobId, {this.variant});

  final String jobId;
  final String? variant;
}

final Map<String, WidgetBuilder> worldRoutes = <String, WidgetBuilder>{
  WorldRoutes.onboarding: (_) =>
      const WorldTheme(child: WorldOnboardingScreen()),
  WorldRoutes.room: (_) => const WorldTheme(child: RoomScreen()),
  WorldRoutes.city: (_) => const WorldTheme(child: CityScreen()),
  WorldRoutes.shop: (_) => const WorldTheme(child: WorldShopScreen()),
  WorldRoutes.petShop: (_) => const WorldTheme(child: PetShopScreen()),
  WorldRoutes.jobs: (_) => const WorldTheme(child: JobBoardScreen()),
  WorldRoutes.job: (_) => const WorldTheme(child: JobPlayScreen()),
  WorldRoutes.leisure: (_) => const WorldTheme(child: LeisureScreen()),
  WorldRoutes.piggy: (_) => const WorldTheme(child: PiggyScreen()),
  WorldRoutes.event: (_) => const WorldTheme(child: EventScreen()),
  WorldRoutes.review: (_) => const WorldTheme(child: WeekReviewScreen()),
  WorldRoutes.history: (_) => const WorldTheme(child: HistoryScreen()),
  WorldRoutes.sprites: (_) => const WorldTheme(child: SpriteTestScreen()),
  WorldRoutes.adult: (_) => const WorldTheme(child: WorldAdultScreen()),
  WorldRoutes.demo: (_) => const WorldTheme(child: WorldDemoScreen()),
  WorldRoutes.settings: (_) => const WorldTheme(child: WorldSettingsScreen()),
  WorldRoutes.glossary: (BuildContext context) => WorldTheme(
          child: GlossaryScreen(allOpen: true, learned: <String>{
        for (final ({String id, String term}) w
            in context.read<WorldState>().world.learning.words)
          w.id,
      })),
};
