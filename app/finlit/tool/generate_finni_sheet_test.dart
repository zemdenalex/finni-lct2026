import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/core/finni_art.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';

/// Лист превью питомца для визуальной проверки. Не тест поведения:
/// он существует, чтобы на рисунок можно было ПОСМОТРЕТЬ, а не рассуждать
/// о нём по коду.
///
/// 🔴 Известное: PNG пишется за секунду, а прогон после этого не
/// завершается и висит до таймаута. Проверено — от размера поверхности,
/// множителя растра, `dispose()` картинки и `pumpAndSettle` это не зависит;
/// `generate_icon_sheet_test.dart` с той же механикой выходит нормально,
/// так что дело в чём-то внутри `FinniView`. На гейт это не влияет: CI
/// гоняет `flutter test` без аргументов, то есть только каталог `test/`.
/// Пользуясь инструментом, просто прервите его после появления файла.
void main() {
  testWidgets('лист превью Финни', (WidgetTester tester) async {
    await loadAppFonts();
    const List<PetMeters> moods = <PetMeters>[
      PetMeters(fullness: 2, cleanliness: 3, mood: 2),
      PetMeters(fullness: 6, cleanliness: 6, mood: 5),
      PetMeters(fullness: 10, cleanliness: 9, mood: 9),
    ];

    final Widget sheet = ColoredBox(
      color: const Color(0xFFF5F7FC),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final PetSpecies sp in PetSpecies.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final PetStage st in PetStage.values)
                    for (final PetMeters m in moods)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          FinniView(
                            species: sp,
                            palette: PetPalette
                                .values[sp.index % PetPalette.values.length],
                            stage: st,
                            meters: m,
                            accessories: st == PetStage.planner
                                ? const <String>{'hat'}
                                : const <String>{},
                            size: 84,
                          ),
                          Text('${st.name} · ${m.mood}',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF5A6486))),
                        ],
                      ),
                ],
              ),
          ],
        ),
      ),
    );

    // 🔴 Поверхность обычного размера. При 3300×1300 прогон записывал PNG
    // за секунду, а потом ещё минуты не завершался — и это выглядело как
    // зависший тест без единой строки ошибки.
    tester.view.physicalSize = const Size(920, 400);
    tester.view.devicePixelRatio = 1.0;
    // 🔴 Сбрасывать по отдельности, а не `view.reset()`: полный сброс
    // вместе с прочими свойствами вида оставлял прогон висеть после
    // записи PNG — тест выглядел зависшим без единой строки ошибки.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: RepaintBoundary(key: key, child: sheet)),
    ));
    // 🔴 `pump`, а не `pumpAndSettle`: у питомца теперь есть анимации,
    // и ждать их завершения здесь незачем — лист снимается со статики.
    await tester.pump();

    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // 🔴 `ui.Image` держит ресурс GPU, и без dispose() тест пишет PNG,
    // а потом висит до таймаута — выглядит как зависший прогон без ошибки.
    // 🔴 Множитель 1.0, а не 2.0. При 2.0 лист выходил 6600×2600 — это
    // 68 МБ несжатого растра, и прогон после записи файла ещё минуты
    // разбирался с ним, выглядя зависшим. Для просмотра глазами хватает
    // исходного размера.
    final ui.Image image = await boundary.toImage();
    final ByteData? png =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final File out = File('build/finni-sheet.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('лист: ${out.absolute.path}');
  });
}
