import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/shop/shop_kit.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

// Ловит (смоуки 29.09): на карточках магазина 360 dp названия блюд рвались
// посреди слова («Котлета с карто|шкой»), а после первой правки обрезались
// многоточием («Котлета с картошк…»). Название из economy.json читается
// целиком: без многоточия и обрезки, слова не рвутся, не больше двух строк,
// шрифт не меньше 14. Экран — в WorldTheme, как в приложении.
void main() {
  setUpAll(loadAppFonts);

  // Ловит: подбор отдаёт размер, при котором название не встаёт в две
  // строки или рвётся слово, либо не самый крупный из подходящих.
  testWidgets('fitWordsFontSize: самый крупный размер, при котором две строки',
      (WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Builder(builder: (BuildContext c) {
              ctx = c;
              return const SizedBox();
            }))));
    const String t = 'Котлета с картошкой';
    bool fits(String s, double size, double width, int lines) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
            text: s,
            style: DefaultTextStyle.of(ctx)
                .style
                .merge(kitTitle)
                .copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(1.3),
        maxLines: lines,
      )..layout(maxWidth: width);
      final bool ok = !tp.didExceedMaxLines && tp.width <= width;
      tp.dispose();
      return ok;
    }

    bool fitsAll(double size, double width) =>
        fits('картошкой', size, width, 1) && fits(t, size, width, 2);
    final Set<double> seen = <double>{};
    for (double width = 100; width <= 400; width += 5) {
      final double s = fitWordsFontSize(ctx, t, kitTitle, width);
      seen.add(s);
      if (s > 14) expect(fitsAll(s, width), isTrue, reason: 'w=$width');
      for (final double bigger in <double>[20, 18, 16, 14]) {
        if (bigger > s) {
          expect(fitsAll(bigger, width), isFalse, reason: 'w=$width');
        }
      }
    }
    expect(seen, containsAll(<double>[20, 18, 16]));
    expect(fitWordsFontSize(ctx, t, kitTitle, 10), 14);
  });

  final List<String> names = <String>[
    for (final Object? f in ((jsonDecode(
                File('assets/content/world/economy.json').readAsStringSync())
            as Map<String, Object?>)['food']!
        as Map<String, Object?>)['options']! as List<Object?>)
      (f! as Map<String, Object?>)['name']! as String,
  ];

  for (final (String name, Size size, double scale) in <(String, Size, double)>[
    ('портрет 360×640', portrait, 1.0),
    ('портрет 360×640', portrait, 1.3),
    ('альбомная 640×360', landscape, 1.3),
  ]) {
    testWidgets('названия блюд целиком, без многоточия: $name, ×$scale',
        (WidgetTester tester) async {
      final World w = worldKinds.last.make(); // мир из content/
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await tester.runAsync(() async {
        await pumpWorldScreen(
            tester, const WorldTheme(child: WorldShopScreen()),
            world: w, textScale: scale, size: size);
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      final List<WorldCatalogItem> food = <WorldCatalogItem>[
        for (final WorldCatalogItem i in w.catalog)
          if (i.category == WorldCatalogCategory.food) i,
      ];
      expect(<String>{
        for (final WorldCatalogItem f in food) f.title
      }, names.toSet(), reason: 'все блюда economy.json на вкладке «Еда»');
      for (final WorldCatalogItem f in food) {
        final Finder t = find.byKey(ValueKey<String>('title:${f.id}'));
        await tester.ensureVisible(t);
        await tester.pump();
        final RenderParagraph p = tester.renderObject<RenderParagraph>(
            find.descendant(of: t, matching: find.byType(RichText)));
        expect(p.text.toPlainText(), f.title);
        expect(p.maxLines, isNull, reason: f.id);
        expect(p.overflow, isNot(TextOverflow.ellipsis), reason: f.id);
        expect(p.didExceedMaxLines, isFalse, reason: f.id);
        expect(p.text.style?.fontSize ?? 20, greaterThanOrEqualTo(14),
            reason: f.id);
        final Set<double> lines = <double>{
          for (final TextBox b in p.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: f.title.length)))
            b.top,
        };
        expect(lines.length, lessThanOrEqualTo(2),
            reason: '${f.id}: больше двух строк');
        int start = 0;
        for (final String word in f.title.split(' ')) {
          final List<TextBox> boxes = p.getBoxesForSelection(TextSelection(
              baseOffset: start, extentOffset: start + word.length));
          expect(<double>{for (final TextBox b in boxes) b.top}, hasLength(1),
              reason: '${f.id}: «$word» разорвано');
          start += word.length + 1;
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
