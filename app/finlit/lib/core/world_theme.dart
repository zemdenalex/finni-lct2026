import 'package:flutter/material.dart';

import '../domain/models/envelope.dart';
import 'icons.dart';
import 'theme.dart';

/// Токены нового мира — палитра «Уютный вечер» сданной версии 29.09
/// (cf9dc0e1, 0.1.0+1): тёмно-синий `#151833` + золото `#F4C542`.
/// ratify 20.10 (Денис, фидбек 11:51 «судьям понравился изначально наш
/// старый цвет»): вернули её вместо «Леса» Алины (84e57b8a, 18.10).
/// Вёрстка шагов 2–6 стиля Алины (фон-комната, нижнее меню, HUD в строку,
/// окна) осталась — вернулся только цвет. Откат — revert этого коммита.
///
/// Мир — пиксель-арт высокого разрешения, интерфейс поверх него — гладкие
/// тёмно-синие панели с золотом. Пёстрая тёплая сцена и холодная тёмная
/// панель не сливаются, и текст никогда не лежит прямо на картинке.
///
/// Имена токенов — из «Леса» (их читают сотни мест и параллельные ветки);
/// токены, которых 29.09 не было, взяли значения из прежнего кода или
/// производные от палитры 29.09 — помечено у каждого.
///
/// 🔴 Действует только на маршрутах `/w/…` ([WorldTheme]). Старые экраны
/// живут на [AppColors] и своих тестах контраста — их палитра не
/// переворачивается.
///
/// Контраст каждой пары текст/фон проверяет `world_palette_test.dart`:
/// все ≥ 4,5:1 (ТЗ), с полупрозрачным фоном — поверх белого (худший случай).
/// Значения 29.09 как есть дают 7 пар ниже 4,5 (подложки конвертов, «нет
/// денег» на карточке) — три токена сдвинуты минимально, помечено ⚠.
abstract final class WorldColors {
  /// Фон экрана за панелями и подложка без сцены (29.09).
  static const Color night = Color(0xFF151833);

  /// Панели, окна, листы (29.09).
  static const Color panel = Color(0xFF1F2344);

  /// Плитки, тихие кнопки, поля ввода, всплывашки (29.09). Для карточек на
  /// фоне экрана — [surface].
  static const Color raised = Color(0xFF2B3060);

  /// Тонкая рамка и разделитель (29.09). Декоративная: границу кнопки
  /// задают заливка и уступ, поэтому её 1,9:1 не нарушает §3.6.
  static const Color line = Color(0xFF454B82);

  /// Основной текст на тёмном (29.09).
  static const Color text = Color(0xFFF5F2EA);

  /// Заголовок экрана и окна — 29.09 заголовки были цвета [text].
  static const Color textTitle = text;

  /// Пояснение (29.09).
  static const Color textSoft = Color(0xFFC3C7E4);

  /// Третьестепенное: никогда не несёт смысл одно (29.09).
  static const Color textMute = Color(0xFF9DA2C9);

  /// Сноска только на [night] / [panel] — 29.09 её не было, = [textMute].
  static const Color textFaint = textMute;

  /// Надзаголовок, выбранный вариант, «верно» — 29.09 «верно» было
  /// мятным, = [needs].
  static const Color accentLime = needs;

  /// Монетка, ЦЕЛЬ и главная кнопка — одним золотом сознательно: главное
  /// действие в игре всегда про монетки и цель (29.09).
  static const Color gold = Color(0xFFF4C542);
  static const Color goldEdge = Color(0xFFC9921A);
  static const Color onGold = Color(0xFF2A1D00);

  /// Крупные суммы и активный раздел нижнего меню — 29.09 токена не было;
  /// светлое золото прежнего `AlinaColors.gold` (до 84e57b8a).
  static const Color goldText = Color(0xFFF5C877);

  /// Конверт НУЖНО (29.09).
  static const Color needs = Color(0xFF4FD1A5);

  /// Конверт ХОЧУ (29.09).
  static const Color wants = Color(0xFFFF8C7A);

  /// Конверт ЦЕЛЬ — то же золото, что монетка.
  static const Color goal = gold;

  /// Силы и настроение (29.09).
  static const Color energy = Color(0xFF7CC4FF);
  static const Color mood = Color(0xFFFF8DBE);

  /// Сытость — 29.09 токена не было; прежний `AlinaColors.okDot`.
  static const Color fullness = Color(0xFFC9DA8C);

  /// «Не хватает», предупреждение — всегда вместе со словом.
  /// ⚠ 29.09 `#FF7A7A` → `#FF7D7D`: на карточке поверх фона экрана 4,46:1.
  static const Color danger = Color(0xFFFF7D7D);

  /// Подложки конвертов на тёмном: цвет конверта, разбавленный панелью.
  /// ⚠ НУЖНО и ЦЕЛЬ темнее 29.09 (`#1E4A4F` → `#193F43`, `#4A4232` →
  /// `#40392B`): на 29.09-значениях [textMute], [wants], [danger] давали
  /// 3,9–4,4:1.
  static const Color needsBg = Color(0xFF193F43);
  static const Color wantsBg = Color(0xFF4A2E45);
  static const Color goalBg = Color(0xFF40392B);

  /// Затемнение сцены под окном (29.09).
  static const Color scrim = Color(0x99151833);

  /// Уступ тихой кнопки и плитки (29.09).
  static const Color raisedEdge = Color(0xFF1A1D3A);

  // ── фон экранов (шаг 2: затемнённая комната) ──

  /// Затемнение комнаты под экраном: сверху и снизу (вёрстка Алины, шаг 2;
  /// цвет — [night] → [panel] 29.09 при её прозрачности 91 / 97 %).
  static const Color backdropTop = Color(0xE8151833);
  static const Color backdropBottom = Color(0xF71F2344);

  /// Тёмная карточка прямо на фоне экрана (её `.panel` `#ffffff09`).
  static const Color surface = Color(0x0FFFFFFF);

  /// Строка списка и вариант ответа на фоне экрана (её `.choice`).
  static const Color surfaceRow = Color(0x0AFFFFFF);

  /// Нижнее меню на экранах (вёрстка Алины; цвет — [panel] 29.09 при её
  /// прозрачности 93 %).
  static const Color dock = Color(0xED1F2344);

  // ── светлые «бумажные» карточки (её доска, магазин, итог) ──
  // Фон экрана остаётся тёмным; светлые только карточки. Считать ли их
  // «кремовым фоном» из design-bans — решает Денис (спека §3).
  // 20.10: в пакете не рисуются (PanelTone.paper никто не передаёт) —
  // палитрой 29.09 не тронуты.

  /// Карточка работы (`.work-offer`).
  static const Color paper = Color(0xFFECE3C9);

  /// Карточка товара (`.product`).
  static const Color paperProduct = Color(0xFFEEE5D1);

  /// Текст на бумаге (её `#384638`).
  static const Color onPaper = Color(0xFF384638);

  /// Подпись на бумаге — её `#879078` (3,0:1) затемнена до 4,5:1.
  static const Color onPaperSoft = Color(0xFF5A6650);

  /// Кнопка на бумаге — её шалфей и тёмно-зелёный текст (5,25:1).
  static const Color sage = Color(0xFFA9CB8C);
  static const Color onSage = Color(0xFF2A4D35);

  /// Части плана на бумаге (`.allocation*`): фон и акцент.
  static const Color needsPaper = Color(0xFFE4E9D6);
  static const Color wantsPaper = Color(0xFFF1DFD1);
  static const Color goalPaper = Color(0xFFDCE9E5);

  // ── город (подложка карты; в пакете не читаются) ──
  static const Color cityGround = Color(0xFF829E6D);
  static const Color cityPath = Color(0xFFC8BF8E);

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

/// Отступы мира (спека §2.4): шаг 4.
abstract final class WorldSpacing {
  /// Поле экрана по бокам (у неё 18, на ≤ 380 — 14; держим 16 по правилу
  /// 375 px).
  static const double gutter = 16;

  /// Внутри карточки.
  static const double cardPad = 16;

  /// Между карточками.
  static const double gap = 12;

  /// Между строками списка.
  static const double row = 8;

  /// Между блоками экрана.
  static const double section = 20;
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
    // Фон экрана рисует [WorldBackdrop] (затемнённая комната, шаг 2 стиля
    // Алины): Scaffold и шапка прозрачные поверх него.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: WorldColors.panel,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    // Плотность всегда стандартная: на вебе с компьютера Flutter сам берёт
    // компактную (−8 dp), и кнопки с областью касания сжимались до 40 dp
    // (путь ребёнка rc-7d, D6; ТЗ 3.6.3 — не меньше 48).
    visualDensity: VisualDensity.standard,
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
      // Заголовок лежит прямо на фоне экрана (её `.page-heading`).
      backgroundColor: Colors.transparent,
      foregroundColor: WorldColors.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: AppType.title(20, color: WorldColors.textTitle),
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
        // Контур из [quietShape]: без него кнопка на карточке того же цвета
        // (`raised`) видна только полоской снизу и читается как текст
        // («☆ Копить» в копилке, скриншот Саши 15.10).
        side: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            BorderSide(
                color: s.contains(WidgetState.disabled)
                    ? WorldColors.raised
                    : WorldColors.line,
                width: 1.5)),
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
      titleTextStyle: AppType.title(22, color: WorldColors.textTitle),
      contentTextStyle: body,
      // Её окно (спека §2.7): ширина экрана − 24, поля 22/16/16, кнопки в
      // ряд под текстом.
      insetPadding:
          const EdgeInsets.symmetric(horizontal: Gap.sm + Gap.xs, vertical: 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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

/// Фон экранов мира — затемнённая комната (стиль Алины, pages.css:L2
/// `.game:not(.in-room):before`): картинка комнаты на весь экран и поверх
/// градиент [WorldColors.backdropTop] → [WorldColors.backdropBottom]
/// (91–97 % непрозрачности). Комната только угадывается; текст читается и
/// над самой светлой стеной (`world_palette_test`).
///
/// Комната и город рисуют свою сцену поверх — фон под ними не виден.
class WorldBackdrop extends StatelessWidget {
  const WorldBackdrop({super.key, required this.child});

  final Widget child;

  /// Комната деревни (первая стадия) — одна на все экраны: так её
  /// раскодирует кэш картинок один раз. Какую комнату брать (по стадии или
  /// одну) — вкусовое, вопрос в `stil-alina-flutter.md`.
  static const String image = 'assets/art/hires/room/gen-village@3x.webp';

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(
            key: ValueKey<String>('world:backdrop'),
            color: WorldColors.night,
          ),
          Image.asset(
            image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  WorldColors.backdropTop,
                  WorldColors.backdropBottom,
                ],
              ),
            ),
          ),
          child,
        ],
      );
}

/// Оборачивает экран мира в его тему.
///
/// Маршруты `/w/…` строятся через [WorldTheme], поэтому кнопки, диалоги и
/// листы внутри них — тёмные с золотом, а старые экраны остаются как были.
/// Под экраном — [WorldBackdrop].
class WorldTheme extends StatelessWidget {
  const WorldTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: buildWorldTheme(),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: WorldColors.text),
          child: WorldBackdrop(child: child),
        ),
      );
}
