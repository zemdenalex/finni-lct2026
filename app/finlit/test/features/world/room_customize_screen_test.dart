import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/tap_target_guideline.dart';
import '../../support/text_floor.dart';
import '../../support/world_harness.dart';

/// Кастомизация комнаты на сетке (каркас 17.10) — экраны за флагом
/// `economy.json → room.customize`: вкладка «Комната» в магазине и режим
/// «Расставить» в комнате.

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Числа сборки (режим «неделя», как у экранных тестов) с включённым
/// флагом — тем же путём, что в приложении: файл → конфиг.
final WorldConfig _roomOn = () {
  final Map<String, Object?> eco =
      jsonDecode(weekMode(_read('economy.json'))) as Map<String, Object?>;
  eco['room'] = <String, Object?>{
    ...(eco['room']! as Map<String, Object?>),
    'customize': true,
  };
  return worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
    roomItems: _read('room_items.json'),
  ));
}();

/// Неделя идёт, карманные в «Хочу», смены — пока хватает на [buy]; вещи
/// куплены.
WorldGame _world({bool flag = true, List<String> buy = const <String>[]}) {
  final WorldGame w = flag ? WorldGame(config: _roomOn) : contentWorld();
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0));
  final int sum =
      buy.fold<int>(0, (int a, String id) => a + w.room.item(id)!.price);
  for (int i = 0; i < 20 && w.snapshot.want + w.snapshot.free < sum; i++) {
    w.completeJob('consultant', score: 1);
  }
  for (final String id in buy) {
    ok(w.buyRoomItem(id));
  }
  return w;
}

Future<void> _pump(WidgetTester tester, Widget screen, World w,
    {double textScale = 1, Size size = portrait}) async {
  await tester.runAsync(() async {
    await pumpWorldScreen(tester, screen,
        world: w, textScale: textScale, size: size);
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  // Комната ждёт свой арт (раскладку), чтобы сетка легла на настоящий фон,
  // а не на запасные слоты: загрузка идёт в настоящем времени.
  final Finder scene = find.byType(RoomScene);
  for (int i = 0; i < 80 && scene.evaluate().isNotEmpty; i++) {
    if (tester.widget<RoomScene>(scene.first).art != null) break;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await _step(tester);
}

Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _step(tester);
}

/// Комната в режиме «Расставить».
Future<void> _arrange(WidgetTester tester) async {
  await _tap(tester, 'room:menu');
  await _tap(tester, 'room:arrange');
  expect(
      find.byKey(const ValueKey<String>('room:arrange:tray')), findsOneWidget);
}

Finder _k(String key) => find.byKey(ValueKey<String>(key));

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  // Уронит: вкладка или режим видны без флага (всё должно быть как раньше)
  // или не появляются с ним.
  for (final bool flag in <bool>[false, true]) {
    testWidgets(
        'флаг ${flag ? 'включён' : 'выключен'}: вкладка «Комната» '
        'и «Расставить вещи» ${flag ? 'есть' : 'нет'}',
        (WidgetTester tester) async {
      await _pump(tester, const WorldShopScreen(), _world(flag: flag));
      expect(_k('tab:room'), flag ? findsOneWidget : findsNothing);
      expect(_k('tab:clothes'), findsOneWidget);

      await _pump(tester, const RoomScreen(), _world(flag: flag));
      await _tap(tester, 'room:menu');
      expect(_k('room:arrange'), flag ? findsOneWidget : findsNothing);
      expect(_k('room:settings'), findsOneWidget);
    });
  }

  // Уронит: кнопка «Купить» вкладки не доходит до buyRoomItem.
  testWidgets('вкладка «Комната»: карточка с ценой, «Купить» покупает',
      (WidgetTester tester) async {
    final WorldGame w = _world();
    await _pump(tester, const WorldShopScreen(initialTab: 6), w);
    expect(_k('card:room_toybox'), findsOneWidget);
    expect(_k('where:room_toybox'), findsOneWidget);
    await _tap(tester, 'buy:room_toybox');
    await tester.tap(find.text('Купить').last); // подтверждение
    await _step(tester);
    expect(w.snapshot.roomOwned, contains('room_toybox'));
  });

  // Уронит: касание клетки не ставит выбранную вещь или ставит не туда.
  testWidgets('касание клетки ставит выбранную вещь; «Убрать» снимает',
      (WidgetTester tester) async {
    final WorldGame w = _world(buy: <String>['room_toybox']);
    await _pump(tester, const RoomScreen(), w);
    expect(
        tester.widget<RoomScene>(find.byType(RoomScene)).art?.layout, isNotNull,
        reason: 'сетка — на настоящей раскладке комнаты');
    await _arrange(tester);
    expect(_k('room:cell:2:4'), findsOneWidget);
    await _tap(tester, 'room:arrange:item:room_toybox');
    await _tap(tester, 'room:cell:2:4');
    expect(w.snapshot.roomPlaced, <String, RoomCell>{
      'room_toybox': (x: 2, y: 4),
    });
    expect(_k('room:item:room_toybox'), findsOneWidget);
    // Стена не подходит: отказ словами, вещь на месте.
    await _tap(tester, 'room:cell:1:0');
    expect(w.snapshot.roomPlaced['room_toybox'], (x: 2, y: 4));
    expect(find.textContaining('ставится на пол'), findsOneWidget);
    // Мебель в режиме «Расставить» не ведёт на экраны: касание кровати —
    // не сон (Финни никуда не идёт, диалога нет).
    await tester.tap(_k('room:bed'), warnIfMissed: false);
    await _step(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(_k('room:arrange:tray'), findsOneWidget);
    await _tap(tester, 'room:arrange:remove');
    expect(w.snapshot.roomPlaced, isEmpty);
    await _tap(tester, 'room:arrange:done');
    expect(_k('room:arrange:tray'), findsNothing);
    expect(_k('room:cell:2:4'), findsNothing);
  });

  // ТЗ 3.6.3, 3.6.4 и шрифт ×1,3 на 360 dp: режим и вкладка без
  // переполнений, цели касания ≥ 48 dp, текст не мельче нормы.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets(
        '«Расставить» · ${o.key} · шрифт ×1,3: без исключений, '
        'цели ≥ 48 dp', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      final WorldGame w =
          _world(buy: <String>['room_toybox', 'room_clock', 'room_lamp']);
      ok(w.placeRoomItem('room_clock', 1, 0));
      await _pump(tester, const RoomScreen(), w, size: o.value, textScale: 1.3);
      await _arrange(tester);
      await _tap(tester, 'room:arrange:item:room_toybox');
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(edgeTapTargetGuideline));
      expect(textsBelowFloor(tester), isEmpty);
      sem.dispose();
    });

    testWidgets('вкладка «Комната» · ${o.key} · шрифт ×1,3: без исключений',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await _pump(tester, const WorldShopScreen(initialTab: 6), _world(),
          size: o.value, textScale: 1.3);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(textsBelowFloor(tester), isEmpty);
      sem.dispose();
    });
  }
}
