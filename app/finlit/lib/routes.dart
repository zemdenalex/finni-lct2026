import 'package:flutter/material.dart';

import 'app.dart';
import 'features/world/world_routes.dart';

/// Именованные маршруты на обычном `Navigator`, без go_router.
///
/// go_router окупается deep links и вложенными shell-маршрутами, которых
/// у офлайнового детского приложения нет. Лишняя зависимость — это ещё и
/// второе, что учить человеку, осваивающему Dart на ходу.
abstract final class AppRoutes {
  static const String boot = '/';
}

final Map<String, WidgetBuilder> appRoutes = <String, WidgetBuilder>{
  AppRoutes.boot: (_) => const BootScreen(),
  ...worldRoutes,
};
