import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/features/world/city/city_guide.dart' show cityLabelScale;
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/world_harness.dart';

/// DEN-30, вариант A за флагом `city.label_scale`: подписи зданий на карте —
/// радиус из шкалы проекта (`Radii.label`), а не «пилюля» (радиус ≥ половины
/// высоты, запрет design-bans). Защищает: флаг выключен — прежняя подпись
/// (`Radii.chip` 12, в шкале мира стиля Алины — `WorldRadii.button` 14, шаг 3);
/// включён — у каждой подписи радиус шкалы и меньше половины
/// её высоты. Уронит: флаг не действует, радиус вне шкалы, подпись снова
/// пилюлей.
Future<void> _pumpCity(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final WorldState state = WorldState(contentDayWorld()..startWeek());
  await tester.runAsync(() async {
    await tester.pumpWidget(ChangeNotifierProvider<WorldState>.value(
      value: state,
      child: MaterialApp(
          theme: buildAppTheme(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
          home: const CityScreen()),
    ));
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();
}

List<(double radius, double height)> _labels(WidgetTester tester) {
  final Finder labels = find.byWidgetPredicate((Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('city:label:'));
  expect(labels, findsWidgets);
  return <(double, double)>[
    for (final Element e in labels.evaluate())
      () {
        final DecoratedBox box = tester.widget<DecoratedBox>(find
            .descendant(
                of: find.byWidget(e.widget),
                matching: find.byType(DecoratedBox))
            .first);
        final BorderRadius r =
            (box.decoration as BoxDecoration).borderRadius! as BorderRadius;
        return (r.topLeft.x, tester.getSize(find.byWidget(e.widget)).height);
      }(),
  ];
}

void main() {
  tearDown(() => cityLabelScale = false);

  // Стиль Алины, шаг 3: радиусы мира сведены к шкале 6/10/14/20, прежний
  // `Radii.chip` 12 стал `WorldRadii.button` 14. Ветка «выключен» — та же
  // прежняя подпись, в новой шкале; проверяет, что флаг действует (14 ≠ 6).
  testWidgets('флаг выключен — прежняя подпись (WorldRadii.button)',
      (WidgetTester tester) async {
    cityLabelScale = false;
    await _pumpCity(tester, const Size(360, 640));
    for (final (double r, double _) in _labels(tester)) {
      expect(r, WorldRadii.button);
    }
  });

  for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
    testWidgets(
        'флаг включён — радиус шкалы, не пилюля · '
        '${size.width.toInt()}×${size.height.toInt()}',
        (WidgetTester tester) async {
      cityLabelScale = true;
      await _pumpCity(tester, size);
      expect(tester.takeException(), isNull);
      for (final (double r, double h) in _labels(tester)) {
        expect(r, Radii.label);
        expect(r, lessThan(h / 2), reason: 'высота $h — не пилюля');
      }
    });
  }
}
