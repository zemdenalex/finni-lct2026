import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
}

/// Строка цели в верхней плашке — настоящими шрифтами игры (ширина текста
/// зависит от шрифта; без них тест меряет квадратный Ahem).
void main() {
  setUpAll(loadAppFonts);
  // Ловит (29.09): строка цели «Финни копит: Кв…» на 360 dp — цель не
  // прочитать. Теперь ⚑ + название; первое слово видно целиком даже при
  // шрифте ×1,3, подпись TalkBack — полная.
  for (final WorldKind kind in worldKinds) {
    testWidgets('$kind · цель в строке: первое слово целиком при ×1,3',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 100, goal: 50));
      ok(w.chooseGoal('home_flat'));
      final String title = w.catalogItem('home_flat')!.title;
      await pumpWorldScreen(tester, const RoomScreen(),
          world: w, size: const Size(360, 640), textScale: 1.3);
      await _settle(tester);
      final Finder t = find.byKey(const ValueKey<String>('room:goal:title'));
      expect(tester.widget<Text>(t).data, title);
      final RenderParagraph p = tester.renderObject<RenderParagraph>(
          find.descendant(of: t, matching: find.byType(RichText)));
      final TextStyle style = tester.widget<Text>(t).style!;
      final double firstWord = (TextPainter(
        text: TextSpan(text: '${title.split(' ').first}…', style: style),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
        maxLines: 1,
      )..layout())
          .width;
      // При обычном шрифте (на экране он не крупнее ×1 — фишки и строка
      // цели его не растят) название на 360 dp — целиком.
      expect(p.textScaler.scale(16) <= 16 ? !p.didExceedMaxLines : true, isTrue,
          reason: 'на 360 dp «$title» должно влезать целиком');
      expect(!p.didExceedMaxLines || firstWord <= p.size.width + 0.5, isTrue,
          reason: 'первое слово «$title» не влезает: $firstWord > '
              '${p.size.width}');
      expect(find.bySemanticsLabel(RegExp('^Цель: ${RegExp.escape(title)}')),
          findsOneWidget);
      expect(find.textContaining('копит:'), findsNothing);
    });
  }

  // Ловит (проход RC 17.10): в альбомной вторая строка «Сейчас» резалась
  // многоточием («на счета не хв…») — причина шага не читалась.
  testWidgets('альбомная: причина «Сейчас» видна целиком',
      (WidgetTester tester) async {
    final WorldGame w = contentDayWorld()..startWeek();
    // Всё в копилку: монет на руках меньше счёта — «Сейчас» с причиной.
    ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(),
          world: w, size: landscape);
    });
    await _settle(tester);
    final Finder why = find.byKey(const ValueKey<String>('room:now:why'));
    expect(why, findsOneWidget, reason: 'на счета не хватает — есть причина');
    expect(
        tester
            .renderObject<RenderParagraph>(
                find.descendant(of: why, matching: find.byType(RichText)))
            .didExceedMaxLines,
        isFalse);
  });
}
