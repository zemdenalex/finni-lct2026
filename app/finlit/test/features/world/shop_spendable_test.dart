import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Магазин говорит, сколько можно потратить, и куда делись остальные монеты
/// из шапки.
///
/// Защищает: ребёнок с «760 монетами» в шапке и плакатом за 200 видит, что
/// потратить можно 20, а 740 лежат в «Нужном» на еду и счета. Было (путь
/// ребёнка rc-7d, D1, 4 прогона): шапка «760», на карточке «Не хватает 180»,
/// и мелкая строка «В «Хочу» 20, в заработке 0» без слова о 740. Уронит:
/// сумма «можно потратить» или объяснение про «Нужное» пропали или ушли за
/// край экрана. Что считается тратой, тест не трогает: отказ — тот же.
void main() {
  setUpAll(loadAppFonts);

  WorldGame planned() {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    // «Как советует Финни» на первой неделе: 740 · 20 · 60.
    ok(w.plan(needs: 740, wants: 20, goal: 60));
    if (w.pendingEvent case final PendingEvent e) {
      ok(w.resolveEvent(
          e.choices.firstWhere((PendingEventChoice c) => c.available).id));
    }
    return w;
  }

  for (final (String tab, int index) in <(String, int)>[
    ('Уют и декор', 1),
    ('Мебель', 3),
  ]) {
    testWidgets('$tab, 360×800: «можно потратить 20», 740 — в части «Нужно»',
        (WidgetTester tester) async {
      final WorldGame w = planned();
      final ResourceSnapshot s = w.snapshot;
      expect(s.available, 760, reason: 'шапка, как в прогоне');
      expect(s.want + s.free, 20);
      await pumpWorldScreen(tester, WorldShopScreen(initialTab: index),
          world: w, size: const Size(360, 800));
      await tester.pumpAndSettle();

      final Finder can = find.text('Можно потратить: 20');
      expect(can, findsOneWidget);
      final Finder rest = find.textContaining('740');
      expect(rest, findsOneWidget, reason: 'объяснение, где остальные');
      expect(tester.widget<Text>(rest).data, contains('в части «Нужно»'));
      // Видно сразу, до первой карточки, без прокрутки.
      expect(tester.getRect(rest).bottom, lessThan(800));
      expect(tester.getRect(can).top, greaterThan(0));

      // Отказ мира прежний: покупка только из «Хочу» и заработка.
      expect(w.canDo(WorldAction.buy, id: 'poster_city')?.text,
          index == 1 ? contains('Не хватает 180') : anything);
      expect(tester.takeException(), isNull);
    });
  }
}
