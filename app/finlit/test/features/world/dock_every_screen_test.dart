import 'dart:async';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Нижнее меню на каждом экране ребёнка (стиль Алины, спека §2.7 и §5 шаг 4):
/// Дом · Город · План · Мой путь · Ещё, раздел экрана подсвечен по её
/// `navGroup()`.
///
/// Защищает: меню есть не только в комнате, текущий раздел верный, переход
/// по разделу не копит стек (назад после раздела — комната). Уронит: экран
/// без меню, раздел не того экрана, переход, который кладёт экран поверх
/// экрана. Переполнение и цели касания с меню — `adaptive_sweep_test` (4
/// размера × шрифт 1,0/1,3, меню внутри экранов).
///
/// Размеры: портрет 360×640 при шрифте 1,0 и 1,3, столбец слева на 1440×900,
/// и 640×360 — там у экранов меню нет (см. `WithDock.shown`).
///
/// Словарик получает меню в таблице маршрутов (он общий со старой игрой),
/// поэтому здесь его нет.

/// Раздел экрана: имя строки [worldScreens] → подпись раздела.
String? _sectionOf(String screen) {
  if (screen.startsWith('S1 ')) return 'Дом';
  for (final String p in <String>['S2', 'S4', 'S5', 'S6', 'S7', 'S8', 'S10']) {
    if (screen.startsWith('$p ')) return 'Город';
  }
  if (screen.startsWith('S9 ') || screen.startsWith('S11 ')) return 'План';
  if (screen.startsWith('S12 ')) return 'Мой путь';
  if (screen.startsWith('S15 ')) return 'Ещё';
  return null;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  final Map<String, (Widget, World Function())> screens =
      worldScreens(worldKinds.last);
  for (final MapEntry<String, (Widget, World Function())> e
      in screens.entries) {
    final String? section = _sectionOf(e.key);
    if (section == null) continue;
    for (final (Size, double) v in <(Size, double)>[
      (const Size(360, 640), 1),
      (const Size(360, 640), 1.3),
      (const Size(1440, 900), 1.3),
      // Телефон боком (~800 × 360) с полосой состояния: столбец меню по
      // высоте 336 dp, «Мой путь» в две строки при шрифте ×1,3.
      (const Size(800, 360), 1.3),
      (const Size(640, 360), 1),
    ]) {
      testWidgets('${e.key}: меню, раздел «$section» · ${v.$1} · ${v.$2}',
          (WidgetTester tester) async {
        if (v.$1.width > v.$1.height) {
          tester.view.padding = const FakeViewPadding(top: 24);
        }
        await pumpListedScreen(tester, e.key, e.value,
            size: v.$1, textScale: v.$2);
        final bool room = section == 'Дом';
        // Телефон в альбомной 640×360: раскладки экранов рассчитаны на всю
        // ширину — столбца меню нет, остаются «назад» и меню комнаты.
        if (!room && v.$1 == const Size(640, 360)) {
          expect(find.byKey(const ValueKey<String>('dock')), findsNothing);
          expect(tester.takeException(), isNull);
          return;
        }
        // Итоги недели в портрете — без меню (ratify finni 19.10): поток до
        // «Новой недели», вывод недели без прокрутки (review_fits_test).
        // В альбомной столбец есть — проверки ниже.
        if (e.key.startsWith('S11 ') && v.$1.width <= v.$1.height) {
          expect(find.byKey(const ValueKey<String>('dock')), findsNothing);
          expect(tester.takeException(), isNull);
          return;
        }
        expect(find.byKey(ValueKey<String>(room ? 'room:dock' : 'dock')),
            findsOneWidget);
        final String prefix = room ? 'room' : 'dock';
        for (final String id in <String>[
          'home',
          'city',
          'week',
          'progress',
          'more',
        ]) {
          expect(
              find.byKey(ValueKey<String>('$prefix:nav:$id')), findsOneWidget,
              reason: '${e.key}: нет пункта $id');
        }
        if (section != 'Ещё') {
          expect(find.bySemanticsLabel('$section — ты здесь'), findsOneWidget,
              reason: '${e.key}: текущий раздел не «$section»');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('раздел с экрана не копит стек: назад — в комнату',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(),
          world: livingWorld(worldKinds.last));
    });
    await tester.pump(const Duration(milliseconds: 300));
    // Комната → город → доска работ (как ребёнок: через город).
    await tapKey(tester, 'room:nav:city');
    expect(find.byType(CityScreen), findsOneWidget);
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    unawaited(nav.pushNamed(WorldRoutes.jobs));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(JobBoardScreen), findsOneWidget);
    // «Город» с доски — назад до города, а не новый город поверх доски.
    await tapKey(tester, 'dock:nav:city');
    expect(find.byType(CityScreen), findsOneWidget);
    expect(find.byType(JobBoardScreen), findsNothing);
    // «Мой путь» с города — поверх комнаты; назад — комната.
    await tapKey(tester, 'dock:nav:progress');
    expect(find.byKey(const ValueKey<String>('dock')), findsOneWidget);
    expect(find.bySemanticsLabel('Мой путь — ты здесь'), findsOneWidget);
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('room:dock')), findsOneWidget);
    // «Дом» с экрана — в ту же комнату, без второй комнаты в стеке.
    await tapKey(tester, 'room:nav:city');
    await tapKey(tester, 'dock:nav:home');
    expect(find.byType(CityScreen), findsNothing);
    expect(nav.canPop(), isFalse, reason: 'комната — дно стека');
  });

  testWidgets('«План» с экрана — тот же лист «Неделя», «Копилка» — копилка',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const JobBoardScreen(),
          world: livingWorld(worldKinds.last));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tapKey(tester, 'dock:nav:week');
    expect(
        find.byKey(const ValueKey<String>('dock:week:plan')), findsOneWidget);
    await tapKey(tester, 'dock:week:piggy');
    expect(find.bySemanticsLabel('План — ты здесь'), findsOneWidget);
  });
}
