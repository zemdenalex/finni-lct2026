import 'package:flutter/material.dart';

import '../domain/models/envelope.dart';
import 'icons.dart';
import 'theme.dart';

/// Токены нового мира — «Уютный вечер», см. `docs/design-system.md`.
///
/// Мир — пиксель-арт высокого разрешения, интерфейс поверх него — гладкие
/// тёмно-синие панели с золотом (макет Алины «Финни — уютный город»,
/// 27.09). Пёстрая тёплая сцена и холодная тёмная панель не сливаются, и
/// текст читается на любой картинке, потому что никогда не лежит прямо
/// на ней.
///
/// 🔴 Действует только на маршрутах `/w/…` ([WorldTheme]). Старые экраны
/// живут на [AppColors] и своих тестах контраста — их палитра не
/// переворачивается.
///
/// Контраст каждой пары посчитан (таблица в `docs/design-system.md` §2):
/// все ≥ 4,5:1.
abstract final class WorldColors {
  /// Фон экрана за панелями и подложка без сцены.
  static const Color night = Color(0xFF151833);

  /// Панели, модалки, HUD.
  static const Color panel = Color(0xFF1F2344);

  /// Плитки и карточки внутри панели.
  static const Color raised = Color(0xFF2B3060);

  /// Тонкая рамка панели. Декоративная: границу кнопки задают заливка и
  /// уступ, поэтому её 1,9:1 не нарушает §3.6.
  static const Color line = Color(0xFF454B82);

  static const Color text = Color(0xFFF5F2EA);
  static const Color textSoft = Color(0xFFC3C7E4);

  /// Третьестепенное: никогда не несёт смысл одно.
  static const Color textMute = Color(0xFF9DA2C9);

  /// Монетка, ЦЕЛЬ и главная кнопка — одним золотом сознательно: главное
  /// действие в игре всегда про монетки и цель.
  static const Color gold = Color(0xFFF4C542);
  static const Color goldEdge = Color(0xFFC9921A);
  static const Color onGold = Color(0xFF2A1D00);

  /// Конверт НУЖНО.
  static const Color needs = Color(0xFF4FD1A5);

  /// Конверт ХОЧУ.
  static const Color wants = Color(0xFFFF8C7A);

  /// Конверт ЦЕЛЬ — то же золото, что монетка.
  static const Color goal = gold;

  static const Color energy = Color(0xFF7CC4FF);
  static const Color mood = Color(0xFFFF8DBE);

  /// «Не хватает», предупреждение — всегда вместе со словом.
  static const Color danger = Color(0xFFFF7A7A);

  /// Подложки конвертов на тёмном: цвет конверта, разбавленный панелью.
  static const Color needsBg = Color(0xFF1E4A4F);
  static const Color wantsBg = Color(0xFF4A2E45);
  static const Color goalBg = Color(0xFF4A4232);

  /// Затемнение сцены под модалкой.
  static const Color scrim = Color(0x99151833);

  /// Уступ тихой кнопки и плитки.
  static const Color raisedEdge = Color(0xFF1A1D3A);

  /// Цвет конверта. Никогда не единственный признак: рядом слово и иконка.
  static Color of(Envelope e) => switch (e) {
        Envelope.needs => needs,
        Envelope.wants => wants,
        Envelope.savings => goal,
      };

  static Color bgOf(Envelope e) => switch (e) {
        Envelope.needs => needsBg,
        Envelope.wants => wantsBg,
        Envelope.savings => goalBg,
      };
}

/// Скругления мира — одна шкала 6 · 10 · 14 · 20.
///
/// ❌ Полностью скруглённых «пилюль» нет (`design-bans.md`): у Алины вкладки
/// и «Купить» — пилюли, здесь они получают [button].
abstract final class WorldRadii {
  static const double tag = 6;
  static const double tile = 10;
  static const double button = 14;
  static const double panel = 20;
}

/// Тема нового мира — одна на всё время работы (почему — у [buildAppTheme]).
ThemeData buildWorldTheme() => _worldTheme;

final ThemeData _worldTheme = _buildWorldTheme();

ThemeData _buildWorldTheme() {
  const String family = AppType.family;
  const List<String> fontFallback = AppType.fallback;
  const ColorScheme scheme = ColorScheme.dark(
    primary: WorldColors.gold,
    onPrimary: WorldColors.onGold,
    secondary: WorldColors.needs,
    onSecondary: WorldColors.night,
    surface: WorldColors.panel,
    onSurface: WorldColors.text,
    surfaceContainerHighest: WorldColors.raised,
    onSurfaceVariant: WorldColors.textSoft,
    outline: WorldColors.line,
    error: WorldColors.danger,
    onError: WorldColors.night,
  );

  final WidgetStateProperty<OutlinedBorder> actionShape =
      WidgetStateProperty.resolveWith((Set<WidgetState> s) {
    if (s.contains(WidgetState.disabled)) {
      return RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorldRadii.button));
    }
    final bool down = s.contains(WidgetState.pressed);
    return LedgeBorder(
      radius: WorldRadii.button,
      depth: down ? 1.5 : 5,
      edge: WorldColors.goldEdge,
    );
  });

  final WidgetStateProperty<OutlinedBorder> quietShape =
      WidgetStateProperty.resolveWith((Set<WidgetState> s) {
    final bool down = s.contains(WidgetState.pressed);
    final bool off = s.contains(WidgetState.disabled);
    return LedgeBorder(
      radius: WorldRadii.button,
      depth: down || off ? 1.5 : 4,
      edge: WorldColors.raisedEdge,
      side: BorderSide(
          color: off ? WorldColors.raised : WorldColors.line, width: 1.5),
    );
  });

  const TextStyle body = TextStyle(
      fontFamily: family,
      fontFamilyFallback: fontFallback,
      fontSize: 18,
      height: 1.45,
      color: WorldColors.text);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: WorldColors.night,
    canvasColor: WorldColors.panel,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    fontFamily: family,
    fontFamilyFallback: fontFallback,
    textTheme: TextTheme(
      displaySmall: AppType.title(28, color: WorldColors.text)
          .copyWith(fontWeight: FontWeight.w800),
      headlineMedium: AppType.title(24, color: WorldColors.text),
      headlineSmall: AppType.title(21, color: WorldColors.text),
      titleLarge: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: WorldColors.text),
      titleMedium: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: WorldColors.text),
      bodyLarge:
          const TextStyle(fontSize: 20, height: 1.45, color: WorldColors.text),
      bodyMedium:
          const TextStyle(fontSize: 18, height: 1.45, color: WorldColors.text),
      bodySmall: const TextStyle(
          fontSize: 16, height: 1.4, color: WorldColors.textSoft),
      labelLarge: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: WorldColors.text),
    ),
    iconTheme: const IconThemeData(color: WorldColors.text, size: 28),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (BuildContext context) => Transform.flip(
        flipX: true,
        child:
            const Pictogram(Pic.arrowRight, size: 28, color: WorldColors.text),
      ),
      closeButtonIconBuilder: (BuildContext context) =>
          const Pictogram(Pic.cross, size: 28, color: WorldColors.text),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: WorldColors.panel,
      foregroundColor: WorldColors.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: AppType.title(20, color: WorldColors.text),
      iconTheme: const IconThemeData(color: WorldColors.text, size: 28),
    ),
    cardTheme: CardThemeData(
      color: WorldColors.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorldRadii.tile),
        side: const BorderSide(color: WorldColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(
            Size.fromHeight(TapSize.primary)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm + 4)),
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.disabled)
                ? WorldColors.raised
                : WorldColors.gold),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.disabled)
                ? WorldColors.textMute
                : WorldColors.onGold),
        overlayColor: const WidgetStatePropertyAll<Color>(Color(0x1A000000)),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: actionShape,
        textStyle: const WidgetStatePropertyAll<TextStyle>(TextStyle(
            fontFamily: family,
            fontFamilyFallback: fontFallback,
            fontSize: 19,
            fontWeight: FontWeight.w800)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll<Size>(Size.fromHeight(TapSize.min)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm + 3)),
        backgroundColor:
            const WidgetStatePropertyAll<Color>(WorldColors.raised),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.disabled)
                ? WorldColors.textMute
                : WorldColors.text),
        overlayColor: const WidgetStatePropertyAll<Color>(Color(0x1AFFFFFF)),
        side: const WidgetStatePropertyAll<BorderSide>(BorderSide.none),
        shape: quietShape,
        textStyle: const WidgetStatePropertyAll<TextStyle>(TextStyle(
            fontFamily: family,
            fontFamilyFallback: fontFallback,
            fontSize: 18,
            fontWeight: FontWeight.w700)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(TapSize.min, TapSize.min),
        foregroundColor: WorldColors.gold,
        textStyle: const TextStyle(
            fontFamily: family,
            fontFamilyFallback: fontFallback,
            fontSize: 18,
            fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      // Размер — по умолчанию Material (48 с отступом): HUD в альбомной
      // 640×360 рассчитан под него, лишние 8 dp съедали высоту комнаты.
      style: IconButton.styleFrom(foregroundColor: WorldColors.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: WorldColors.panel,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: WorldColors.scrim,
      dragHandleColor: WorldColors.line,
      shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(WorldRadii.panel))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: WorldColors.panel,
      surfaceTintColor: Colors.transparent,
      barrierColor: WorldColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorldRadii.panel),
        side: const BorderSide(color: WorldColors.line),
      ),
      titleTextStyle: AppType.title(21, color: WorldColors.text),
      contentTextStyle: body,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: WorldColors.raised,
      contentTextStyle: body,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      linearTrackColor: WorldColors.raised,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: WorldColors.raised,
      selectedColor: WorldColors.goalBg,
      labelStyle: const TextStyle(
          fontFamily: family,
          fontFamilyFallback: fontFallback,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: WorldColors.text),
      side: const BorderSide(color: WorldColors.line),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorldRadii.button)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: WorldColors.gold,
      unselectedLabelColor: WorldColors.textSoft,
      indicatorColor: WorldColors.gold,
      dividerColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WorldColors.raised,
      hintStyle: const TextStyle(color: WorldColors.textMute),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorldRadii.tile),
        borderSide: const BorderSide(color: WorldColors.line, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorldRadii.tile),
        borderSide: const BorderSide(color: WorldColors.line, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorldRadii.tile),
        borderSide: const BorderSide(color: WorldColors.gold, width: 2.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected)
              ? WorldColors.night
              : WorldColors.textSoft),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected)
              ? WorldColors.needs
              : WorldColors.raised),
      trackOutlineColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected)
              ? WorldColors.needs
              : WorldColors.textMute),
    ),
    dividerTheme: const DividerThemeData(color: WorldColors.line, thickness: 1),
  );
}

/// Оборачивает экран мира в его тему.
///
/// Маршруты `/w/…` строятся через [WorldTheme], поэтому кнопки, диалоги и
/// листы внутри них — тёмные с золотом, а старые экраны остаются как были.
class WorldTheme extends StatelessWidget {
  const WorldTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: buildWorldTheme(),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: WorldColors.text),
          child: child,
        ),
      );
}
