import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Правило текстов 7А (Настя, 16.10): подсказка «Что здесь?» — не больше
/// трёх коротких предложений, подробности — в Словарике. Ребёнок 7–8 лет
/// дочитывает, озвучка читает за несколько секунд, а не минуту.
///
/// Уронит: подсказку экрана снова раздули абзацами; новый экран пришёл с
/// длинной справкой. Не проверяет: правила мини-игр (S7, «Как играть»),
/// знакомство (S0, лист по шагам), раздел взрослого (S14) и проверку (S16).
const Set<String> _screens = <String>{
  'S1 комната',
  'S2 город',
  'S4 магазин',
  'S5 зоомагазин',
  'S6 доска',
  'S8 досуг',
  'S9 копилка',
  'S10 событие',
  'S11 итоги',
  'S12 прогресс',
  'S15 настройки',
};

/// Конец предложения: точка, «!», «?» или «…» перед пробелом или концом.
final RegExp _end = RegExp(r'[.!?…]+[»)]*(?=\s|$)');

bool _isHelp(Widget w) =>
    w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>).value.endsWith(':help');

void main() {
  setUp(rootBundle.clear);

  final WorldKind kind = worldKinds.last;
  for (final MapEntry<String, (Widget, World Function())> s
      in worldScreens(kind).entries) {
    if (!_screens.contains(s.key)) continue;
    testWidgets('${s.key}: «Что здесь?» — не больше трёх предложений',
        (WidgetTester tester) async {
      await pumpListedScreen(tester, s.key, s.value, size: portrait);
      await tester.tap(find.byWidgetPredicate(_isHelp));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final String text = tester
          .widget<PicText>(find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(PicText)))
          .text;
      expect(_end.allMatches(text.trim()).length, inInclusiveRange(1, 3),
          reason: text);
      expect(text.length, lessThanOrEqualTo(260), reason: text);
    });
  }
}
