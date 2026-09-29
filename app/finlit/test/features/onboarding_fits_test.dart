import 'package:finlit/app.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_fonts.dart';

// §3.6.4. Фраза знакомства — единственное объяснение правил до первой недели.
// При системном шрифте 1,5 она уходила под точки страниц и обрезалась на
// полуслове: страница прокручивается, но ребёнок не знает, что её надо
// листать вниз. Проверяется не контраст (обрезанный текст он не видит),
// а геометрия: низ фразы выше низа области страниц.
void main() {
  setUpAll(loadAppFonts);

  for (final Size size in <Size>[const Size(360, 640), const Size(360, 760)]) {
    testWidgets(
        'фраза каждой страницы видна целиком: '
        '${size.width.toInt()}×${size.height.toInt()}, '
        'шрифт ×${FinniApp.maxTextScale}', (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (BuildContext c, Widget? child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
              textScaler: const TextScaler.linear(FinniApp.maxTextScale)),
          child: child!,
        ),
        home: const OnboardingScreen(),
      ));
      await tester.pumpAndSettle();

      final Rect pages = tester.getRect(find.byType(PageView));
      for (int i = 0; i < 4; i++) {
        final Finder phrase = find.descendant(
          of: find.byType(PageView),
          matching: find.byWidgetPredicate((Widget w) =>
              w is Text &&
              (w.style?.fontSize ?? 0) == 20 &&
              w.style?.height == 1.4),
        );
        expect(phrase, findsOneWidget, reason: 'страница ${i + 1}');
        final Rect r = tester.getRect(phrase);
        expect(r.bottom, lessThanOrEqualTo(pages.bottom),
            reason: 'страница ${i + 1}: фраза обрезана на '
                '${(r.bottom - pages.bottom).toStringAsFixed(0)} px');
        if (i < 3) {
          await tester.tap(find.text('Дальше'));
          await tester.pumpAndSettle();
        }
      }
    });
  }
}
