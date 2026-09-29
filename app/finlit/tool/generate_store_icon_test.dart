import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/core/finni_art.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';

/// Генератор иконки для карточки RuStore.
///
/// Это не тест, а инструмент: он лежит в `tool/`, а не в `test/`, поэтому
/// на CI не запускается. Запуск вручную:
///
///     flutter test tool/generate_store_icon_test.dart
///
/// 🔴 Зачем так, а не отрисовать картинку в редакторе. Иконка обязана быть тем
/// же Финни, что и в приложении: если их рисуют отдельно, они расходятся на
/// первой же правке персонажа. Здесь используется ровно тот `FinniView`, что
/// и на главном экране, — расхождение невозможно по построению. Заодно снимается
/// §3.3 ТЗ про права на изображения: рисовали сами, и это видно в исходниках.
///
/// Требования RuStore (страницы документации противоречат друг другу, берём
/// строгий вариант): PNG ровно 512 × 512, **без прозрачных участков**, ≤ 1 МБ.
void main() {
  testWidgets('иконка 512×512 для карточки RuStore', (WidgetTester tester) async {
    await loadAppFonts();
    const double size = 512;
    final GlobalKey key = GlobalKey();

    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            width: size,
            height: size,
            // Сплошной фон на всю площадь: RuStore требует «фоновое заполнение
            // по всей площади, без прозрачных или незаполненных участков
            // по контуру».
            // Небо и холм — те же цвета, что у сцены в приложении: иконка
            // обещает ровно тот мир, который откроется.
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[SceneColors.skyTop, SceneColors.skyLow],
              ),
            ),
            child: Stack(
              children: <Widget>[
                // Крупный план: на экране телефона иконка — 48 dp, и
                // маленький персонаж на пустом небе превращался в пятно.
                const Positioned(
                  left: (size - 500) / 2 + 12,
                  top: size * 0.04,
                  child: FinniView(
                    species: PetSpecies.squirrel,
                    palette: PetPalette.apricot,
                    stage: PetStage.saver,
                    meters: PetMeters(fullness: 8, cleanliness: 8, mood: 9),
                    // 🔴 Питомец не должен упираться в край: на круглой
                    // маске Android срезаются углы.
                    size: 500,
                  ),
                ),
                Positioned(
                  left: -size * 0.2,
                  right: -size * 0.2,
                  top: size * 0.84,
                  height: size * 0.6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: SceneColors.leaf,
                      borderRadius:
                          BorderRadius.all(Radius.elliptical(size, size * 0.3)),
                      border: Border.all(color: AppColors.ink, width: 6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.runAsync(() async {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage();
      final ByteData? png =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List bytes = png!.buffer.asUint8List();

      final File out = File('assets/store/icon-512.png');
      await out.create(recursive: true);
      await out.writeAsBytes(bytes);

      // ignore: avoid_print
      print('Иконка записана: ${out.path}, '
          '${image.width}×${image.height}, '
          '${(bytes.length / 1024).toStringAsFixed(0)} КБ');

      expect(image.width, 512);
      expect(image.height, 512);
      expect(bytes.length, lessThan(1024 * 1024),
          reason: 'RuStore: иконка не тяжелее 1 МБ');
    });
  });

  testWidgets('передний слой адаптивной иконки Android',
      (WidgetTester tester) async {
    await loadAppFonts();

    // 🔴 Android рисует иконку приложения по своей маске: холст 108 dp,
    // видно центральные 72 dp, гарантированно не срежется только 66 dp.
    // Пока в проекте лежал один квадратный PNG без слоёв, лаунчер вписывал
    // его в круг «как есть» — на экране телефона получалась наклейка внутри
    // белого кольца. Это видно только на устройстве: в тестах и на карточке
    // магазина иконка выглядела нормально.
    const double canvas = 432; // 108 dp × 4 (xxxhdpi)
    const double safe = canvas * 0.62; // с запасом внутри безопасной зоны
    final GlobalKey key = GlobalKey();

    tester.view.physicalSize = const Size(canvas, canvas);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: canvas,
            height: canvas,
            // Передний слой прозрачен: фон — отдельный слой, его задаёт
            // система, и именно он позволяет маске быть любой формы.
            child: const Center(
              child: FinniView(
                species: PetSpecies.squirrel,
                palette: PetPalette.apricot,
                stage: PetStage.saver,
                meters: PetMeters(fullness: 8, cleanliness: 8, mood: 9),
                size: safe,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.runAsync(() async {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage();
      final ByteData? png =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final File out = File('build/ic_launcher_foreground.png');
      await out.create(recursive: true);
      await out.writeAsBytes(png!.buffer.asUint8List());
      // ignore: avoid_print
      print('Передний слой: ${out.path}, ${image.width}×${image.height}');
      expect(image.width, 432);
    });
  });
}