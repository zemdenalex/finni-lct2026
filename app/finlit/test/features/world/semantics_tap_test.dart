// ignore_for_file: deprecated_member_use
// hasFlag/pipelineOwner устарели, но для проверки достаточны; перевод на
// flagsCollection — отдельной правкой.
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/shop/pet_shop_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Кнопка, у которой в дереве доступности нет действия «нажать», для TalkBack
/// и для веб-сборки — просто надпись. Так было у плиток выбора героя, ячеек
/// HUD и зданий города: `Semantics(button: true, excludeSemantics: true)`
/// отсекал касание дочернего `InkWell`, а тесты жали пальцем и не замечали.
void main() {
  final Map<String, Widget> screens = <String, Widget>{
    'комната': const RoomScreen(),
    'город': const CityScreen(),
    'магазин': const WorldShopScreen(),
    'зоомагазин': const PetShopScreen(),
    'прогресс': const HistoryScreen(),
  };
  for (final MapEntry<String, Widget> s in screens.entries) {
    testWidgets('${s.key}: у каждой кнопки есть действие «нажать»',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final World w = contentWorld()..startWeek();
      await pumpWorldScreen(tester, s.value, world: w, size: landscape);
      await tester.pump(const Duration(milliseconds: 300));
      final List<String> mute = <String>[];
      void visit(SemanticsNode n) {
        final SemanticsData d = n.getSemanticsData();
        if (d.hasFlag(SemanticsFlag.isButton) &&
            (!d.hasFlag(SemanticsFlag.hasEnabledState) ||
                d.hasFlag(SemanticsFlag.isEnabled)) &&
            !d.hasAction(SemanticsAction.tap)) {
          mute.add(d.label);
        }
        n.visitChildren((SemanticsNode c) {
          visit(c);
          return true;
        });
      }

      visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      expect(mute, isEmpty, reason: 'кнопки без касания: $mute');
      h.dispose();
    });
  }
}
