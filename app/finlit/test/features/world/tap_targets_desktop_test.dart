import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/features/world/home/plan_amount.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Цели касания 48 dp и на вебе с компьютера (ТЗ 3.6.3).
///
/// Защищает: кнопки не сжимаются до 40 dp, когда платформа — Windows, macOS
/// или Linux. Веб-демо экспертам открывается в браузере на компьютере, а
/// Flutter там по умолчанию берёт компактную плотность (−8 dp у кнопок и у
/// области касания). Было (путь ребёнка rc-7d, D6): «Как советует Финни» —
/// 40 px на экране, касание на 3 px выше или ниже кнопки — мимо, хотя в коде
/// `minimumSize: Size(48, 48)`. Обычный `tap_targets_test` идёт под Android,
/// где плотность стандартная, и этого не видит.
/// Уронит: тема снова без `visualDensity: VisualDensity.standard`.
void main() {
  setUp(rootBundle.clear);

  final TargetPlatformVariant desktop =
      TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets('«Как советует Финни»: 48 dp и касание у края попадает',
      (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: WorldTheme(
        child: Scaffold(
          body: Center(
            child: PlanAdviceButton(name: 'Финни', onPressed: () => taps++),
          ),
        ),
      ),
    ));
    final Finder b = find.byKey(const ValueKey<String>('plan:advice'));
    expect(tester.getSize(b).height, greaterThanOrEqualTo(48));
    // Касание в 22 dp от центра — внутри 48 dp, но мимо кнопки в 40.
    await tester.tapAt(tester.getCenter(b) + const Offset(0, 22));
    await tester.tapAt(tester.getCenter(b) - const Offset(0, 22));
    expect(taps, 2);
  }, variant: desktop);

  // Диалог подтверждения (Съесть, Купить, Изменить план — одно окно
  // `confirmAction`): «Отмена» и «Да» были по 40 dp.
  testWidgets('окно «Съесть»: обе кнопки не ниже 48 dp',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, const WorldShopScreen(),
        world: livingWorld(worldKinds.last));
    await tester.pumpAndSettle();
    final Finder eat = find.byKey(const ValueKey<String>('eat:food_simple'));
    await tester.ensureVisible(eat);
    await tester.pumpAndSettle();
    await tester.tap(eat);
    await tester.pumpAndSettle();
    for (final String k in <String>['confirm:yes', 'confirm:no']) {
      expect(tester.getSize(find.byKey(ValueKey<String>(k))).height,
          greaterThanOrEqualTo(48),
          reason: k);
    }
  }, variant: desktop);

  // Экраны, где путь ребёнка нашёл кнопки в 40 px: знакомство с планом,
  // комната, магазин («Съесть», «Готовить дома», «Купить»), копилка, смена.
  // Меряется сама кнопка (её область касания), а не только семантика.
  for (final String name in <String>[
    'S0 сценки',
    'S1 комната',
    'S4 магазин',
    'S7 смена',
    'S9 копилка',
  ]) {
    testWidgets('$name · портрет на компьютере: кнопки не меньше 48 dp',
        (WidgetTester tester) async {
      await pumpListedScreen(tester, name, worldScreens(worldKinds.last)[name]!,
          size: portrait);
      expect(tester.takeException(), isNull);
      final List<String> small = <String>[
        for (final Element e in find
            .byWidgetPredicate(
                (Widget w) => w is ButtonStyleButton || w is IconButton)
            .evaluate())
          if ((e.renderObject! as RenderBox).size case final Size s
              when s.height < 48 || s.width < 48)
            '${e.widget.key ?? e.widget.runtimeType}: $s',
      ];
      expect(small, isEmpty);
    }, variant: desktop);
  }
}
