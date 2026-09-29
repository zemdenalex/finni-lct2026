import 'package:flutter/material.dart';

import '../domain/models/envelope.dart';
import 'icons.dart';

/// Токены оформления. Направление — «Своё дерево», см.
/// `docs/dizayn-napravlenie.md`.
///
/// Коротко: приложение — это дерево, в котором живёт Финни. Главный экран —
/// комната в разрезе ствола, и всё, что ребёнок оставил себе, стоит в ней.
/// Интерфейс вокруг сцены держится тихо: светлый «утренний» фон, белые
/// поверхности, чернила одного цвета и четыре смысловых цвета — три конверта
/// и золото монетки. Смелость потрачена на одно место — на сцену и Финни.
///
/// 🔴 Тема только светлая. Тёмная означала бы второй набор цветов и второй
/// прогон проверки контраста — при том, что дети играют днём, а §3.6
/// требует единообразного контраста, а не двух тем. Это осознанный отказ,
/// записанный в журнал решений.
abstract final class AppColors {
  /// Фон приложения — утренний воздух в лесу: почти белый с лёгкой зеленью.
  /// 🔴 Не крем и не бумага. Тёплый бежевый — самый частый фон
  /// сгенерированного макета, а прохладная «тетрадь» прошлой версии была
  /// отвергнута как безликая. Здесь фон — продолжение сцены: воздух вокруг
  /// дерева.
  static const Color paper = Color(0xFFEFF4EC);
  static const Color surface = Color(0xFFFFFFFF);

  /// Подложка под числами и мелкими плашками внутри белых поверхностей.
  static const Color grid = Color(0xFFE3EBE1);

  /// Чернила. Одни на весь продукт: ими написан текст и ими же обведены
  /// Финни, вещи в комнате и пиктограммы. Одна линия — главное, что
  /// связывает иллюстрацию и интерфейс в одну вещь.
  static const Color ink = Color(0xFF1D2B2F);
  static const Color inkSoft = Color(0xFF4C5B5E);
  static const Color line = Color(0xFFCAD5CB);

  /// Нейтральный интерактивный цвет: пиктограммы в шапке, точки показателей,
  /// рамки второстепенных кнопок. Тёмная хвоя, а не синий: синий в прошлой
  /// версии был «цветом ничего» — им красилось всё, что не знало своего цвета.
  static const Color primary = Color(0xFF24474C);

  /// У каждого конверта свой цвет — но цвет **никогда не единственный**
  /// носитель смысла (§3.6.5): рядом всегда пиктограмма и подпись словами.
  static const Color needs = Color(0xFF1C7552);
  static const Color wants = Color(0xFFC42B5F);
  static const Color savings = Color(0xFF4B3BB5);

  static const Color needsBg = Color(0xFFE0F0E6);
  static const Color wantsBg = Color(0xFFFBE5ED);
  static const Color savingsBg = Color(0xFFE8E5F8);

  /// Золото монетки. Им же залита главная кнопка: в игре главное действие —
  /// всегда про монетки, и ребёнок видит это по цвету ещё до чтения.
  static const Color coin = Color(0xFFF5B83D);
  static const Color coinDeep = Color(0xFFB47814);

  /// Главная кнопка: золото с тёмным краем снизу.
  static const Color action = Color(0xFFFFC53F);
  static const Color actionEdge = Color(0xFFD08E0E);
  static const Color onAction = ink;

  static Color of(Envelope e) => switch (e) {
        Envelope.needs => needs,
        Envelope.wants => wants,
        Envelope.savings => savings,
      };

  static Color bgOf(Envelope e) => switch (e) {
        Envelope.needs => needsBg,
        Envelope.wants => wantsBg,
        Envelope.savings => savingsBg,
      };

  /// 🔴 Токены не выдают `IconData`. Material-иконки нарисованы для
  /// взрослых интерфейсов: «Нужное» выглядело столовым прибором из ресторана,
  /// а монетка — долларом. Весь набор рисуется вектором, см. `icons.dart`.
  static Pic picOf(Envelope e) => switch (e) {
        Envelope.needs => Pic.bowl,
        // Сердце, а не мячик: мячик — конкретная вещь из «Хочу», и
        // категория с вещью выглядели одинаково.
        Envelope.wants => Pic.heart,
        Envelope.savings => Pic.jar,
      };
}

/// Цвета сцены — дерева, в котором живёт Финни. Живут отдельно от цветов
/// интерфейса: на них не пишут текст, и контраст для них не считается.
/// Всё, что на сцене читается словами, лежит на белой плашке поверх.
abstract final class SceneColors {
  static const Color skyTop = Color(0xFFBFE2F4);
  static const Color skyLow = Color(0xFFE4F3FA);
  static const Color cloud = Color(0xFFFFFFFF);
  static const Color leaf = Color(0xFF55AE6E);
  static const Color leafDark = Color(0xFF2F8150);
  static const Color bark = Color(0xFF8E5F3D);
  static const Color barkDark = Color(0xFF6A4328);
  static const Color wall = Color(0xFFF5E1C0);
  static const Color wallLine = Color(0xFFE6CB9E);
  static const Color floor = Color(0xFFCF9863);
  static const Color floorLine = Color(0xFFB37D4B);
  static const Color rug = Color(0xFF4B3BB5);
  static const Color blueprint = Color(0xFF3A6FB0);
}

/// Шкала отступов. Отдельные числа в виджетах запрещены: иначе «сделать
/// покрупнее для семилеток» превращается в охоту по файлам.
abstract final class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Скругления назначены по роли, а не одно на всё.
///
/// Одинаковый радиус на карточке, кнопке и поле ввода — тот самый «набор
/// одинаковых карточек», по которому макет и опознаётся как шаблонный.
abstract final class Radii {
  /// Сцена и крупные поверхности.
  static const double scene = 28;

  /// Карточки предметов и панели.
  static const double envelope = 20;

  /// Кнопки: собраннее.
  static const double button = 16;

  /// Поля, чипы и мелкие плашки.
  static const double chip = 12;
}

/// Минимальные размеры интерактивных элементов.
///
/// §3.6.3 рекомендует 48×48 dp. Для семилетки этого мало: берём 56 как
/// минимум и 64 для главных игровых кнопок. Это выше и требования ТЗ,
/// и уровня AAA WCAG.
abstract final class TapSize {
  static const double min = 56;
  static const double primary = 64;
}

/// Тайминги и кривые движения (§6 «Визуального направления»).
///
/// 🔴 Из диапазонов Material 3 здесь всегда взята **верхняя** граница.
/// Взрослому хватает 200 мс, чтобы понять, что произошло; семилетке нужно
/// успеть проследить за предметом глазами — иначе движение не объясняет
/// изменение, а просто мелькает.
///
/// 🔴 Ни одна из этих длительностей не берётся напрямую: экран спрашивает
/// `context.motion(Motion.x)` — там решается, движение сейчас разрешено
/// или длительность обнуляется (`lib/core/feel.dart`).
abstract final class Motion {
  /// Нажатие, галочка: подтверждение касания.
  static const Duration tap = Duration(milliseconds: 180);

  /// Смена состояния карточки.
  static const Duration state = Duration(milliseconds: 300);

  /// Появление элемента.
  static const Duration enter = Duration(milliseconds: 380);

  /// Перелёт монетки из рук в конверт.
  static const Duration flight = Duration(milliseconds: 500);

  /// Одна точка показателя. Общая длительность — столько на каждую
  /// загоревшуюся точку, а не на всю шкалу.
  static const Duration meterDot = Duration(milliseconds: 180);

  /// Счётчик суммы досчитывает до нового числа.
  static const Duration count = Duration(milliseconds: 360);

  /// Финни освоил новое умение: новая стадия.
  static const Duration stageUp = Duration(milliseconds: 520);

  /// Финни отвечает на действие ребёнка — один подскок.
  static const Duration nod = Duration(milliseconds: 460);

  /// Цель набрана: единственный праздник за игру.
  static const Duration cheer = Duration(milliseconds: 600);

  /// Кривая нажатия.
  static const Curve tapCurve = Easing.standard;

  /// Предмет летит и останавливается в новом месте.
  static const Curve travel = Easing.emphasizedDecelerate;

  /// Новая стадия: перелёт и возврат, «живое» движение.
  static const Curve stageCurve = Curves.elasticOut;

  /// Подскок: короткий перелёт через положение покоя.
  static const Curve nodCurve = Curves.easeOutBack;
}

/// Глубина: сплошной сдвинутый край вместо размытия.
///
/// 🔴 Размытая серая тень `rgba(0,0,0,.1)` под каждой карточкой — признак
/// шаблонного макета, а на API 26–28 ещё и лишний проход размытия в Skia.
/// Здесь у всего, что можно нажать, есть твёрдый нижний край — как у
/// игровой кнопки или деревянной плашки. Нажатие «вдавливает» её.
abstract final class Paper {
  static List<BoxShadow> cut(Color edge, {double depth = 4}) =>
      <BoxShadow>[BoxShadow(color: edge, offset: Offset(0, depth))];

  /// Край для белой поверхности на фоне приложения.
  static const Color edge = Color(0xFFCBD7CC);
}

/// Форма «с уступом»: скруглённый прямоугольник с тёмной полосой по нижнему
/// краю внутри формы.
///
/// 🔴 Уступ рисуется внутри границы, а не тенью снаружи: так он не меняет
/// размер кнопки, не требует лишнего слоя и остаётся на месте, когда
/// Material перекрашивает фон при нажатии. Без размытия — см. [Paper].
class LedgeBorder extends OutlinedBorder {
  const LedgeBorder({
    this.radius = Radii.button,
    this.depth = 4,
    this.edge = AppColors.actionEdge,
    super.side,
  });

  final double radius;
  final double depth;
  final Color edge;

  RRect _rrect(Rect rect) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(bottom: depth);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect).deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final RRect r = _rrect(rect);
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.bottom - depth, rect.right, rect.bottom),
      Paint()..color = edge,
    );
    canvas.restore();
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(r.deflate(side.width / 2), side.toPaint());
    }
  }

  @override
  LedgeBorder copyWith({BorderSide? side}) => LedgeBorder(
      radius: radius, depth: depth, edge: edge, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => LedgeBorder(
      radius: radius * t, depth: depth * t, edge: edge, side: side.scale(t));
}

/// Гарнитуры приложения.
///
/// Две и только две, и роли у них не пересекаются:
/// - **Onest** — всё, что читают: фразы, подписи, кнопки.
/// - **Unbounded** — числа монеток и короткие заголовки. Широкая, уверенная,
///   «не детсадовская»: 11-летнему не стыдно, 7-летнему крупно.
///
/// 🔴 Unbounded не ставится на текст длиннее пары слов. Она на треть шире
/// Onest, и фраза в ней на 360 dp рвётся на три строки.
abstract final class AppType {
  static const String family = 'Onest';

  /// Знаки, которых нет в Onest (минус U+2212 — ревью 29.09: «−50» читалось
  /// как «50»), берутся из Unbounded — тот же OFL, уже в приложении.
  static const List<String> fallback = <String>['Unbounded'];
  static const String display = 'Unbounded';

  /// Число монеток и прочие крупные числа.
  static TextStyle number(double size, {Color color = AppColors.ink}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.1,
        color: color,
      );

  /// Короткий заголовок: имя питомца, название экрана, заголовок листа.
  static TextStyle title(double size, {Color color = AppColors.ink}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: color,
      );
}

/// Тема приложения — один экземпляр на всё время работы.
///
/// 🔴 Не собирать заново на каждый вызов. Состояния кнопок заданы
/// замыканиями `WidgetStateProperty.resolveWith`, а два разных замыкания
/// никогда не равны: две «одинаковые» темы оказываются разными, и
/// `MaterialApp` при перестроении запускает анимированный переход темы —
/// лишние кадры на слабом Android и «само задёргалось» в тестах движения.
ThemeData buildAppTheme() => _theme;

final ThemeData _theme = _buildTheme();

ThemeData _buildTheme() {
  const String family = AppType.family;
  const List<String> fontFallback = AppType.fallback;
  const ColorScheme scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.savings,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: Color(0xFFB3261E),
    onError: Colors.white,
  );

  // Главная кнопка — золото с уступом. Выключенная — плоская серая: уступ
  // у неё пропадает, и это второй, не цветовой признак «сейчас нельзя».
  final WidgetStateProperty<OutlinedBorder> actionShape =
      WidgetStateProperty.resolveWith((Set<WidgetState> s) {
    if (s.contains(WidgetState.disabled)) {
      return RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button));
    }
    // Нажатие вдавливает кнопку: уступ становится тоньше.
    final bool down = s.contains(WidgetState.pressed);
    return LedgeBorder(depth: down ? 1.5 : 5);
  });

  final WidgetStateProperty<OutlinedBorder> quietShape =
      WidgetStateProperty.resolveWith((Set<WidgetState> s) {
    final bool down = s.contains(WidgetState.pressed);
    final bool off = s.contains(WidgetState.disabled);
    return LedgeBorder(
      depth: down || off ? 1.5 : 4,
      edge: AppColors.line,
      side: BorderSide(color: off ? AppColors.grid : AppColors.line, width: 2),
    );
  });

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    fontFamily: family,
    fontFamilyFallback: fontFallback,
    // §3.6.4 требует не менее 16 sp для основного текста. Здесь основной
    // 18–20, а заголовки набраны второй гарнитурой.
    textTheme: TextTheme(
      displaySmall: AppType.title(28).copyWith(fontWeight: FontWeight.w800),
      headlineMedium: AppType.title(24),
      headlineSmall: AppType.title(21),
      titleLarge: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
      titleMedium: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink),
      bodyLarge:
          const TextStyle(fontSize: 20, height: 1.45, color: AppColors.ink),
      bodyMedium:
          const TextStyle(fontSize: 18, height: 1.45, color: AppColors.ink),
      bodySmall:
          const TextStyle(fontSize: 16, height: 1.4, color: AppColors.inkSoft),
      labelLarge: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    // 🔴 Стрелка «назад» и крестик — свои, а не системные: у AppBar по
    // умолчанию Material-иконки, и они стояли в шапке каждого экрана —
    // ровно то «офисное» место, где их видно первыми.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (BuildContext context) => Transform.flip(
        flipX: true,
        child: const Pictogram(Pic.arrowRight, size: 28, color: AppColors.ink),
      ),
      closeButtonIconBuilder: (BuildContext context) =>
          const Pictogram(Pic.cross, size: 28, color: AppColors.ink),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      // 🔴 Семейство указывается здесь явно: ThemeData.fontFamily применяется
      // к textTheme, но не к отдельным TextStyle внутри тем компонентов.
      titleTextStyle: AppType.title(20),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 28),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      // Тот же уступ, что у панелей: карточка на любом экране — «плашка на
      // столе», и экран, собранный из Card, не выпадает из языка.
      shape: const LedgeBorder(
        radius: Radii.envelope,
        depth: 4,
        edge: Paper.edge,
        side: BorderSide(color: Paper.edge, width: 1.5),
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
                ? AppColors.grid
                : AppColors.action),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.disabled)
                ? AppColors.inkSoft
                : AppColors.onAction),
        overlayColor: const WidgetStatePropertyAll<Color>(Color(0x14000000)),
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
        backgroundColor: const WidgetStatePropertyAll<Color>(AppColors.surface),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.disabled)
                ? AppColors.inkSoft
                : AppColors.ink),
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
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
            fontFamily: family,
            fontFamilyFallback: fontFallback,
            fontSize: 18,
            fontWeight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.line,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.scene)),
      titleTextStyle: AppType.title(21),
      contentTextStyle: const TextStyle(
          fontFamily: family,
          fontFamilyFallback: fontFallback,
          fontSize: 18,
          height: 1.45,
          color: AppColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        borderSide: const BorderSide(color: AppColors.line, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        borderSide: const BorderSide(color: AppColors.line, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected) ? Colors.white : AppColors.inkSoft),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected) ? AppColors.needs : AppColors.grid),
      trackOutlineColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
          s.contains(WidgetState.selected)
              ? AppColors.needs
              : AppColors.inkSoft),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
  );
}

/// 🔴 Про кегль. §3.6.4 требует «не менее 16 sp», и это пол, а не норма.
/// Единственный типографский параметр с сильной доказательной базой у детей —
/// именно размер: Wilkins и др. (2009) на детях 7–9 лет получили +9 % скорости
/// понимания от увеличения кегля на 19 %, а Hughes & Wilkins (2000) показали,
/// что на мелком тексте растёт число ошибок во всех возрастах. Поэтому основной
/// текст здесь 18–20 sp, а не 16.
///
/// Обратное решение, тоже по данным: **межбуквенный интервал не трогаем**.
/// Разрядка помогает только детям с дислексией, а Galliussi и др. (2020) на 128
/// детях показали, что увеличенный межбуквенный без межсловного — худший из
/// четырёх вариантов и замедляет всех. Значение по умолчанию оставлено как есть.
