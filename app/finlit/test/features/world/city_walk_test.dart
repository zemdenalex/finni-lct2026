import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_geometry.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Движение Финни по городу (`docs/final/gorod-dvizhenie.md`): каждый
/// тест — дефект, воспроизведённый на 068ed67 (до флага `city.smooth_walk`).
///
/// Защищает: Финни не встаёт намертво у косого края карты, не уходит с
/// карты от двери Магазина, не проходит сквозь дома (ни джойстиком, ни
/// касанием здания) и не телепортируется к зданию, от которого отошёл.
/// Уронит: шаг снова только по осям; дверь Магазина вне земли; путь касания
/// снова прямой линией; «уже там» по последнему зданию, а не по месту.
void main() {
  setUp(rootBundle.clear);

  final CityGeometry geo = isoGeometry;
  final double k = CityCamera.scale(CityVariant.iso);

  Future<void> pumpCity(WidgetTester tester,
      {Size size = landscape, World? world}) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const CityScreen(),
          world: world ?? livingWorld(worldKinds.last), size: size);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  final Finder stick = find.byKey(const ValueKey<String>('city:joystick'));

  /// Ноги Финни в пикселях карты при 1× — камера едет, экран не мерило.
  Offset feet(WidgetTester tester) {
    final Rect map =
        tester.getRect(find.byKey(const ValueKey<String>('city:map')));
    final Offset at = tester
        .getRect(find.byKey(const ValueKey<String>('city:finni')))
        .topLeft;
    return (at - map.topLeft) / k;
  }

  /// Внутри ромба клетки здания, ужатого до 0,7 (своя формула, не код
  /// движения): там стоит дом, ходить нельзя.
  String? insideHouse(Offset p) {
    for (final MapEntry<String, CityCell> e in geo.cells.entries) {
      final Offset c = geo.center(e.value);
      final double v = (p.dx - c.dx).abs() / (geo.tileW / 2 * 0.7) +
          (p.dy - c.dy).abs() / (geo.tileH / 2 * 0.7);
      if (v < 1) return e.key;
    }
    return null;
  }

  /// Держит ручку в [dir] [ms] мс; [each] — после каждого кадра 20 мс.
  Future<void> hold(WidgetTester tester, Offset dir, int ms,
      {void Function()? each}) async {
    final TestGesture g = await tester.startGesture(tester.getCenter(stick));
    await g.moveBy(dir * 20);
    await g.moveBy(dir * 28);
    for (int t = 0; t < ms; t += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      each?.call();
    }
    await g.up();
    await tester.pump();
  }

  // Д1. Край поля — косой (ромб), а шаг проверялся только по осям: ручка
  // влево у нижнего левого края — Финни встаёт, хотя вдоль края идти можно.
  testWidgets('Д1: джойстик влево у косого края — Финни скользит вдоль него',
      (WidgetTester tester) async {
    await pumpCity(tester);
    await hold(tester, const Offset(-1, 0), 2500);
    expect(feet(tester).dx, lessThan(120),
        reason: 'дошёл вдоль края к левому углу поля, ${feet(tester)}');
  });

  // Д2. Дверь Магазина (клетка 4,0) — справа от угла, а справа клетки нет:
  // Финни стоит вне земли, и шаг джойстика вне земли не проверяется.
  testWidgets('Д2: от Магазина джойстиком — не уходит с карты',
      (WidgetTester tester) async {
    await pumpCity(tester);
    final Finder shop =
        find.byKey(const ValueKey<String>('city:button:grocery'));
    await tester.ensureVisible(shop);
    await tester.pump();
    await tester.tap(shop);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(geo.onGround(feet(tester)), isTrue,
        reason: 'дверь Магазина на земле, ${feet(tester)}');
    await hold(tester, const Offset(1, 0), 3000);
    expect(geo.onGround(feet(tester)), isTrue,
        reason: 'не ушёл с поля, ${feet(tester)}');
  });

  // Д3. Дома — не препятствие: джойстик вверх от двери Дома ведёт Финни
  // прямо сквозь дом.
  testWidgets('Д3: джойстик вверх от Дома — в обход дома, не сквозь',
      (WidgetTester tester) async {
    await pumpCity(tester);
    final List<String> hits = <String>[];
    await hold(tester, const Offset(0, -1), 1200, each: () {
      final String? h = insideHouse(feet(tester));
      if (h != null) hits.add('$h ${feet(tester)}');
    });
    expect(hits, isEmpty);
    expect(feet(tester).dy, lessThan(geo.anchor(geo.cells['home']!).dy),
        reason: 'и всё-таки ушёл за Дом');
  });

  // Д4. Путь касания — прямая от двери к двери: из Дома в Парк Финни идёт
  // сквозь сам Дом.
  testWidgets('Д4: касание Парка — путь в обход домов',
      (WidgetTester tester) async {
    await pumpCity(tester);
    final List<String> hits = <String>[];
    Offset last = feet(tester);
    await tester.tapAt(pointOn(tester, 'city:building:park'));
    await tester.pump();
    for (int t = 0; t < 1000; t += 4) {
      await tester.pump(const Duration(milliseconds: 4));
      if (find.byKey(const ValueKey<String>('city:finni')).evaluate().isEmpty) {
        break;
      }
      final Offset now = feet(tester);
      for (final double f in <double>[0.5, 1]) {
        final String? h = insideHouse(Offset.lerp(last, now, f)!);
        if (h != null) hits.add('$h ${Offset.lerp(last, now, f)}');
      }
      last = now;
    }
    expect(hits, isEmpty);
  });

  // Д5. «Финни уже там» решалось по последнему зданию, у которого он
  // стоял, а не по месту: отошёл джойстиком, нажал Дом — экран сразу,
  // Финни прыгает к двери.
  testWidgets('Д5: отошёл от Дома джойстиком, нажал Дом — идёт, не прыгает',
      (WidgetTester tester) async {
    await pumpCity(tester);
    // Вправо по улице: дальше 0,3 клетки от двери, к другим зданиям — нет.
    await hold(tester, const Offset(1, 0), 400);
    await tester.pump(const Duration(milliseconds: 300));
    final Offset away = feet(tester);
    await tester.tapAt(pointOn(tester, 'city:building:home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RoomScreen), findsNothing,
        reason: 'сначала Финни идёт к двери');
    expect((feet(tester) - away).distance, greaterThan(1),
        reason: 'в пути, $away → ${feet(tester)}');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RoomScreen), findsOneWidget);
  });

  // Д6. Поворот экрана: камера заново встаёт между Финни и «!» (или
  // центром) — Финни у дальнего края не должен уйти за окно.
  for (final (String where, Future<void> Function(WidgetTester) go)
      in <(String, Future<void> Function(WidgetTester))>[
    (
      'у Магазина',
      (WidgetTester tester) async {
        final Finder shop =
            find.byKey(const ValueKey<String>('city:button:grocery'));
        await tester.ensureVisible(shop);
        await tester.pump();
        await tester.tap(shop);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
    ),
    (
      'в правом углу поля',
      (WidgetTester tester) async {
        await hold(tester, const Offset(1, 0), 3500);
      }
    ),
    (
      'в левом углу поля',
      (WidgetTester tester) async {
        await hold(tester, const Offset(-1, 0), 3500);
      }
    ),
  ]) {
    testWidgets('Д6: поворот $where — Финни остаётся в окне',
        (WidgetTester tester) async {
      // Движок на числах контента, событие недели ждёт — «!» над зданием.
      final World w = contentWorld()..startWeek();
      w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
      w.chooseGoal('pet_fish');
      w.completeJob('consultant', score: 1);
      expect(w.eventBuildingId, isNotNull, reason: 'нужен «!»');
      await pumpCity(tester, world: w);
      await go(tester);
      tester.view.physicalSize = portrait;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final Rect view =
          tester.getRect(find.byKey(const ValueKey<String>('city:cam-x')));
      final Offset at = tester
          .getRect(find.byKey(const ValueKey<String>('city:finni')))
          .topLeft;
      expect(at.dx, inInclusiveRange(view.left, view.right),
          reason: 'Финни $at, окно $view, ${feet(tester)}');
      expect(at.dy, inInclusiveRange(view.top + 30, view.bottom),
          reason: 'Финни $at, окно $view');
    });
  }
}
