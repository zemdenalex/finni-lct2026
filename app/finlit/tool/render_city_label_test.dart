import 'package:finlit/core/theme.dart';
import 'package:finlit/features/world/city/city_guide.dart' show cityLabelScale;
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры подписей города (DEN-30): как сдано и вариант A (`city.label_scale`):
///
///     flutter test --update-goldens tool/render_city_label_test.dart
///       →  build/kadry-city-label/*.png
void main() {
  setUpAll(loadAppFonts);
  for (final (String name, Size size, bool on) in <(String, Size, bool)>[
    ('01-kak-sdano-portret', const Size(360, 640), false),
    ('02-shkala-portret', const Size(360, 640), true),
    ('03-shkala-albom', const Size(640, 360), true),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      cityLabelScale = on;
      addTearDown(() => cityLabelScale = false);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final WorldState state = WorldState(contentDayWorld()..startWeek());
      await tester.runAsync(() async {
        await tester.pumpWidget(ChangeNotifierProvider<WorldState>.value(
          value: state,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: const CityScreen()),
        ));
        for (int i = 0; i < 25; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
      await tester.pump();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-city-label/$name.png'));
    });
  }
}
