import 'package:finlit/features/world/city/city_geometry.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Финни в городе рисуется по глубине там, где он сейчас, а не там, куда
/// идёт (Настя 20.10, тема 11: «почему Финни может проходить сквозь здания
/// в городе?»).
///
/// Защищает: на каждом кадре пути Финни нарисован перед зданием, если его
/// ноги ниже нижнего угла здания, и за ним — если выше (простое 2.5D).
/// Уронит: глубина Финни снова берётся у двери назначения на весь путь
/// касания — он идёт за домом, а нарисован поверх него, будто сквозь стену.
/// Почему не ловят city_walk*: они проверяют, где ноги (путь в обход), а
/// не в каком порядке слои; путь был верный, неверным был порядок.
void main() {
  setUp(rootBundle.clear);

  final CityGeometry geo = isoGeometry;
  final double k = CityCamera.scale(CityVariant.iso);

  Future<void> pumpCity(WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const CityScreen(),
          world: livingWorld(worldKinds.last), size: landscape);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  final Finder finni = find.byKey(const ValueKey<String>('city:finni'));

  Offset feet(WidgetTester tester) {
    final Rect map =
        tester.getRect(find.byKey(const ValueKey<String>('city:map')));
    return (tester.getRect(finni).topLeft - map.topLeft) / k;
  }

  /// Нарушения порядка слоёв на этом кадре: здание, перед которым Финни
  /// должен быть (или за которым), а нарисован наоборот.
  List<String> wrongOrder(WidgetTester tester) {
    final Stack s = tester.widget<Stack>(find
        .ancestor(
            of: find.byKey(const ValueKey<String>('city:layer:home')),
            matching: find.byType(Stack))
        .first);
    int at(bool Function(Key? k) test) => s.children.indexWhere(
        (Widget w) => test(w.key));
    final int f = at((Key? key) =>
        key is ValueKey<String> && key.value.startsWith('city:finni:frame:'));
    expect(f, isNonNegative, reason: 'слой Финни в стопке');
    final Offset p = feet(tester);
    final List<String> bad = <String>[];
    for (final CityBuilding b in cityBuildings) {
      final double y = geo.anchor(geo.cells[b.id]!).dy;
      // У самой линии порядок не виден и зависит от округления.
      if ((p.dy - y).abs() < 2) continue;
      final int i = at((Key? key) => key == ValueKey<String>('city:layer:${b.id}'));
      final bool front = f > i, shouldFront = p.dy > y;
      if (front != shouldFront) {
        bad.add('${b.id}: ноги ${p.dy.toStringAsFixed(1)}, угол '
            '${y.toStringAsFixed(1)}, ${front ? 'поверх' : 'за ним'}');
      }
    }
    return bad;
  }

  // Из Дома (нижний ряд) к дальним зданиям: путь уходит вверх, за дома
  // ближе к зрителю, — на старом коде Финни поверх них весь путь.
  for (final String to in <String>['park', 'cinema', 'grocery', 'piggy-bank']) {
    testWidgets('касание «$to»: на каждом кадре пути — верный порядок слоёв',
        (WidgetTester tester) async {
      await pumpCity(tester);
      final Set<String> bad = <String>{};
      // Магазин у правого края — за окном 640 × 360: камеру к нему.
      await tester.ensureVisible(
          find.byKey(ValueKey<String>('city:building:$to')));
      await tester.pump();
      await tester.tapAt(pointOn(tester, 'city:building:$to'));
      await tester.pump();
      for (int t = 0; t < 1000; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        if (finni.evaluate().isEmpty) break;
        bad.addAll(wrongOrder(tester));
      }
      expect(bad, isEmpty);
    });
  }

  testWidgets('джойстик вверх-влево за дома: порядок слоёв верный',
      (WidgetTester tester) async {
    await pumpCity(tester);
    final Finder stick = find.byKey(const ValueKey<String>('city:joystick'));
    final Set<String> bad = <String>{};
    for (final Offset dir in <Offset>[
      const Offset(-1, -0.5),
      const Offset(0, -1),
      const Offset(1, -0.5),
    ]) {
      final TestGesture g = await tester.startGesture(tester.getCenter(stick));
      await g.moveBy(dir * 20);
      await g.moveBy(dir * 28);
      for (int t = 0; t < 1200; t += 20) {
        await tester.pump(const Duration(milliseconds: 20));
        bad.addAll(wrongOrder(tester));
      }
      await g.up();
      await tester.pump();
    }
    expect(bad, isEmpty);
  });
}
