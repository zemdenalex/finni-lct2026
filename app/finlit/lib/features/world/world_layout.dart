import 'package:flutter/widgets.dart';

/// Ориентация экранов нового мира.
///
/// Решение команды 27.09: основная — **альбомная**, но портрет от 360 dp
/// обязан работать (ТЗ §3.1 п. 2: альбомная — преимущество). Экраны S0–S11
/// раскладываются под альбомную (сцена слева, панель справа), в портрете —
/// столбиком. Проверяются обе: 640 × 360 и 360 × 640, масштаб шрифта 1 и 1,3.
abstract final class WorldLayout {
  /// Самый тесный альбомный экран, под который раскладываем (16:9, 360 dp).
  static const Size landscapeMin = Size(640, 360);

  /// Самый узкий портрет, который обязан работать.
  static const Size portraitMin = Size(360, 640);

  /// Альбомная раскладка: ширина больше высоты. Решается по размеру окна,
  /// а не по датчику — так же ведут себя разделённый экран и web-демо.
  static bool isLandscape(BuildContext context) {
    final Size s = MediaQuery.sizeOf(context);
    return s.width > s.height;
  }
}

/// Две раскладки одного экрана: [landscape] — основная, [portrait] — узкая.
class OrientationSplit extends StatelessWidget {
  const OrientationSplit({
    super.key,
    required this.landscape,
    required this.portrait,
  });

  final WidgetBuilder landscape;
  final WidgetBuilder portrait;

  @override
  Widget build(BuildContext context) =>
      WorldLayout.isLandscape(context) ? landscape(context) : portrait(context);
}
