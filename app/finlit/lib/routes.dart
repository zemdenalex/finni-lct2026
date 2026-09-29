import 'package:flutter/material.dart';

import 'app.dart';
import 'features/adult/adult_screen.dart';
import 'features/demo/demo_screen.dart';
import 'features/glossary/glossary_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/pet/pet_create_screen.dart';
import 'features/plan/plan_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/savings/savings_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shop/shop_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/world/world_routes.dart';

/// Именованные маршруты на обычном `Navigator`, без go_router.
///
/// go_router окупается deep links и вложенными shell-маршрутами, которых
/// у офлайнового детского приложения нет. Лишняя зависимость — это ещё и
/// второе, что учить человеку, осваивающему Dart на ходу.
abstract final class AppRoutes {
  static const String boot = '/';
  static const String onboarding = '/onboarding';
  static const String petCreate = '/pet';
  static const String home = '/home';
  static const String plan = '/plan';
  static const String shop = '/shop';
  static const String savings = '/savings';
  static const String tasks = '/tasks';
  static const String progress = '/progress';
  static const String glossary = '/glossary';
  static const String adult = '/adult';
  static const String settings = '/settings';
  static const String demo = '/demo';
}

final Map<String, WidgetBuilder> appRoutes = <String, WidgetBuilder>{
  AppRoutes.boot: (_) => const BootScreen(),
  AppRoutes.onboarding: (_) => const OnboardingScreen(),
  AppRoutes.petCreate: (_) => const PetCreateScreen(),
  AppRoutes.home: (_) => const HomeScreen(),
  AppRoutes.plan: (_) => const PlanScreen(),
  AppRoutes.shop: (_) => const ShopScreen(),
  AppRoutes.savings: (_) => const SavingsScreen(),
  AppRoutes.tasks: (_) => const TasksScreen(),
  AppRoutes.progress: (_) => const ProgressScreen(),
  AppRoutes.glossary: (_) => const GlossaryScreen(),
  AppRoutes.adult: (_) => const AdultScreen(),
  AppRoutes.settings: (_) => const SettingsScreen(),
  AppRoutes.demo: (_) => const DemoScreen(),
  ...worldRoutes,
};
