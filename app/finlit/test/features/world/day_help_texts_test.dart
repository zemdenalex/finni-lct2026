import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Справки комнаты и магазина в режиме дней (как в релизе) говорят про день,
/// а не про неделю: ⚡ — на день, «Спать» кончает день, домашняя еда —
/// вечером. Запасной режим «неделя» сохраняет прежние слова.
///
/// Уронит: строку вернули к «закончить неделю пораньше» или условие режима
/// перевернули — в дневном мире ребёнок читает недельное правило, которого
/// в игре уже нет (замечание front3 по RC 17.10).
Finder _text(String s) => find.textContaining(s, findRichText: true);

Future<void> _openHelp(
  WidgetTester tester,
  Widget screen,
  WorldGame world,
  String key,
) async {
  await pumpWorldScreen(tester, screen, world: world);
  await tester.tap(find.byKey(ValueKey<String>(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(rootBundle.clear);

  testWidgets('комната, режим дней: силы на день, «Спать» кончает день', (
    WidgetTester tester,
  ) async {
    await _openHelp(tester, const RoomScreen(), contentDayWorld(), 'room:help');
    expect(_text('силы на день'), findsOneWidget);
    expect(_text('«Спать» — закончить день'), findsOneWidget);
    expect(_text('закончить неделю пораньше'), findsNothing);
    expect(_text('осталось до конца недели'), findsOneWidget);
  });

  testWidgets('комната, режим «неделя»: прежние слова', (
    WidgetTester tester,
  ) async {
    await _openHelp(tester, const RoomScreen(), contentWorld(), 'room:help');
    expect(_text('силы на неделю'), findsOneWidget);
    expect(_text('закончить неделю пораньше'), findsOneWidget);
  });

  testWidgets('магазин, режим дней: домашняя еда — вечером', (
    WidgetTester tester,
  ) async {
    await _openHelp(
      tester,
      const WorldShopScreen(),
      contentDayWorld(),
      'shop:help',
    );
    expect(_text('вечером Финни поест дома'), findsOneWidget);
    expect(_text('перейдёт на следующую неделю'), findsNothing);
  });

  testWidgets('магазин, режим «неделя»: еда дома в конце недели', (
    WidgetTester tester,
  ) async {
    await _openHelp(
      tester,
      const WorldShopScreen(),
      contentWorld(),
      'shop:help',
    );
    expect(_text('перейдёт на следующую неделю'), findsOneWidget);
  });
}
