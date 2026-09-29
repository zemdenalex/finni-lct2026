import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/text_floor.dart';
import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// ТЗ 3.6.4: на каждом экране нового мира текст не мельче [textFloor]
/// (`test/support/text_floor.dart` — как считается видимый кегль).
void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  forEachWorld((WorldKind kind) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final MapEntry<String, (Widget, World Function())> s
          in worldScreens(kind).entries) {
        testWidgets('${s.key} · ${o.key}: текст не мельче $textFloor sp',
            (WidgetTester tester) async {
          await pumpListedScreen(tester, s.key, s.value, size: o.value);
          expect(tester.takeException(), isNull);
          final List<String> small = textsBelowFloor(tester);
          expect(small, isEmpty, reason: 'мелкий текст: $small');
        });
      }
    }
  });
}
