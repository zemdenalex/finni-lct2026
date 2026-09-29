import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/theme.dart';
import 'domain/world/contract.dart';
import 'features/world/world_routes.dart';
import 'features/world/world_state.dart';
import 'routes.dart';

class FinniApp extends StatelessWidget {
  const FinniApp({super.key});

  /// Потолок системного увеличения шрифта (§3.6.4). Тесты доступности
  /// проверяют каждый экран ровно на этом масштабе, поэтому число живёт
  /// в одном месте: поднять его, не прогнав их, нельзя.
  static const double maxTextScale = 1.5;

  @override
  Widget build(BuildContext context) {
    // ТЗ 3.6.7: «Анимации: выкл.» гасят и переходы между экранами — они
    // берутся из темы приложения, а не из темы мира (WorldTheme стоит
    // внутри страницы). select, а не watch: иначе MaterialApp
    // перестраивался бы на каждое действие в игре.
    final bool motion = context.select<AppState, bool>(
        (AppState a) => !a.ready || a.game.profile.settings.animationsOn);
    return MaterialApp(
      title: 'Финни',
      debugShowCheckedModeBanner: false,
      theme: motion ? buildAppTheme() : _stillTheme,
      // Смена темы при переключении — тоже анимация (AnimatedTheme): с
      // выключенными анимациями она мгновенная.
      themeAnimationDuration: motion ? kThemeAnimationDuration : Duration.zero,
      // Приложение только на русском: TalkBack должен говорить «Назад»,
      // а не «Back».
      locale: const Locale('ru'),
      supportedLocales: const <Locale>[Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // 🔴 Тёмной темы нет намеренно — см. комментарий в core/theme.dart.
      initialRoute: AppRoutes.boot,
      // В браузере начальный маршрут берётся из адресной строки: после
      // перезагрузки на `#/home` стек собирался бы как [заставка, /home],
      // и заставка заменяла бы верхний экран, а не себя. Запуск всегда идёт
      // через заставку — она сама решает, куда дальше, как на телефоне.
      onGenerateInitialRoutes: (String _) => <Route<void>>[
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.boot),
          builder: appRoutes[AppRoutes.boot]!,
        ),
      ],
      routes: appRoutes,
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          // §3.6.4: «читаемость сохраняется при системном увеличении шрифта».
          // Масштаб не отключается, а ограничивается: базовый текст здесь уже
          // 18 sp, и при 1,5 это 27 — крупнее, чем у большинства приложений
          // при 2×. Выше детская вёрстка с крупными кнопками начинает
          // переполняться, и вместо читаемости получается обрезанный текст.
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: maxTextScale,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}

/// Тема приложения без переходов между экранами (анимации выключены).
final ThemeData _stillTheme = buildAppTheme().copyWith(
  pageTransitionsTheme: PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      for (final TargetPlatform p in TargetPlatform.values)
        p: const _NoTransition(),
    },
  ),
);

/// Экран сменяется сразу: ни сдвига, ни затухания, ни длительности.
class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// Экран загрузки: решает, куда вести.
///
/// Вход — новый мир: знакомство (S0), пока онбординг не пройден, иначе
/// комната (S1). Мир уже прочитан с диска в `main.dart` (`openSavedWorld`).
///
/// Старый профиль ([AppState]) по-прежнему читается: из него берутся
/// настройки звука и движения (`core/feel.dart`). Экраны старой игры
/// остаются в маршрутах, но с заставки туда больше не ведут.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  /// Куда вести с заставки: знакомство или комната нового мира.
  static String targetFor(OnboardingProgress onboarding) =>
      onboarding.done ? WorldRoutes.room : WorldRoutes.onboarding;

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final AppState app = context.read<AppState>();
    await app.boot();
    if (!mounted) return;
    final String target =
        BootScreen.targetFor(context.read<WorldState>().onboarding);
    await Navigator.of(context).pushReplacementNamed<void, void>(target);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        // Статичная заставка без анимации: бесконечный индикатор не даёт
        // виджет-тестам сойтись и зря будит GPU на старте, который по §3.4
        // обязан укладываться в пять секунд.
        body: Center(child: Text('Финни', style: _bootTitle)),
      );
}

/// Надпись заставки — той же гарнитурой, что заголовки в игре.
final TextStyle _bootTitle = AppType.title(34);
