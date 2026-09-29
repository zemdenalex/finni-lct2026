import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подключает настоящий шрифт приложения в виджет-тест.
///
/// 🔴 Без этого `flutter test` рисует подстановочным шрифтом, и всё, что
/// отрендерено из теста — скриншоты магазина, кадры видео, лист иконок —
/// выходит в квадратах вместо букв. На экране приложения при этом всё
/// в порядке, поэтому дефект видно только на картинке.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final String weight in <String>[
    'Regular',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final File f = File('assets/fonts/Onest-$weight.ttf');
    if (!f.existsSync()) continue;
    await (FontLoader('Onest')
          ..addFont(Future<ByteData>.value(
              ByteData.sublistView(f.readAsBytesSync()))))
        .load();
  }
  for (final String weight in <String>['SemiBold', 'ExtraBold']) {
    final File f = File('assets/fonts/Unbounded-$weight.ttf');
    if (!f.existsSync()) continue;
    await (FontLoader('Unbounded')
          ..addFont(Future<ByteData>.value(
              ByteData.sublistView(f.readAsBytesSync()))))
        .load();
  }
  // Material-иконки тоже шрифт: без него каждая `Icon` на скриншоте —
  // пустой квадрат. Файл лежит в кеше Flutter SDK рядом с flutter_tester
  // (…/bin/cache/artifacts/engine/<платформа>/flutter_tester).
  final File icons = File.fromUri(File(Platform.resolvedExecutable)
      .parent
      .parent
      .parent
      .uri
      .resolve('material_fonts/materialicons-regular.otf'));
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future<ByteData>.value(
              ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}
