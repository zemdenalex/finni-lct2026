import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/features/world/dev/sprite_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Ловит: спрайт не грузится из бандла (путь в pubspec не объявлен) или
/// анимация не переключает кадры.
void main() {
  testWidgets('Финни и котёнок на тестовом экране меняют кадры',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const SpriteTestScreen(),
          size: const Size(800, 1600));
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pump();

    final Finder finni = find.byKey(const ValueKey<String>('finni:finni-a1'));
    final Finder kitten =
        find.byKey(const ValueKey<String>('pet:pet_kitten:sleep'));
    expect(finni, findsOneWidget);
    expect(kitten, findsOneWidget);

    CustomPaint paintOf(Finder f) => tester.widget<CustomPaint>(
        find.descendant(of: f, matching: find.byType(CustomPaint)).first);
    // Кадр загрузился: у картинки есть размер (hi-res кадр вписан в 120 px).
    expect(tester.getSize(finni).height, closeTo(120, 0.01));

    final CustomPainter before = paintOf(kitten).painter!;
    await tester.pump(const Duration(milliseconds: 700));
    final CustomPainter after = paintOf(kitten).painter!;
    expect(after.shouldRepaint(before), isTrue,
        reason: 'через 700 мс котёнок должен показать следующий кадр sleep');
    expect(find.byType(SpriteAnim), findsWidgets);
  });
}
