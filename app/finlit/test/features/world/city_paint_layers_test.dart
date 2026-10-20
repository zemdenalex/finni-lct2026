import 'package:finlit/features/world/city/city_filler.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Ходьба по городу не перерисовывает неподвижное (Денис 20.10: «очень
/// лагает хождение по городу»).
///
/// Защищает: пока Финни идёт джойстиком или по касанию и камера едет за ним,
/// земля (~2300 травинок, дороги) и декор не рисуются заново — у них свой
/// слой, кадр только сдвигает его.
/// Уронит: снятый RepaintBoundary у земли или декора — тогда каждый кадр
/// ходьбы заново рисует всю карту (замер до правки: 150 перерисовок земли и
/// 4500 спрайтов декора на 150 кадров).
/// Почему не ловят другие тесты: они проверяют, где Финни и что нарисовано,
/// а не сколько раз; лишняя перерисовка вида не меняет.
void main() {
  setUp(rootBundle.clear);

  Future<void> pumpCity(WidgetTester tester, Size size) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const CityScreen(),
          world: livingWorld(worldKinds.last), size: size);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  /// Ближайший слой над объектом отрисовки.
  RenderRepaintBoundary layerOf(RenderObject r) {
    RenderObject? o = r.parent;
    while (o is! RenderRepaintBoundary) {
      o = o!.parent;
    }
    return o;
  }

  /// Что слой нарисовал в последний раз: перерисовка заменяет картинку
  /// слоя новой, сдвиг кадра — нет.
  Layer? drawn(RenderRepaintBoundary b) => b.debugLayer!.firstChild;

  /// Слои земли и всего декора на карте.
  List<RenderRepaintBoundary> still(WidgetTester tester) {
    final RenderCustomPaint ground = tester
        .renderObjectList<RenderCustomPaint>(find.byType(CustomPaint))
        .firstWhere((RenderCustomPaint r) => r.painter is CityGroundPainter);
    return <RenderRepaintBoundary>[
      layerOf(ground),
      for (final Element e in find.byType(CityDecorView).evaluate())
        layerOf(e.renderObject!),
    ];
  }

  for (final MapEntry<String, Size> s in bothOrientations.entries) {
    testWidgets('${s.key}: джойстик — земля и декор не перерисовываются',
        (WidgetTester tester) async {
      await pumpCity(tester, s.value);
      final List<RenderRepaintBoundary> layers = still(tester);
      expect(layers.length, greaterThan(1), reason: 'земля и декор на карте');
      final List<Layer?> before = layers.map(drawn).toList();
      final Offset start = tester
          .getRect(find.byKey(const ValueKey<String>('city:finni')))
          .bottomCenter;
      final Finder stick = find.byKey(const ValueKey<String>('city:joystick'));
      for (final Offset dir in <Offset>[
        const Offset(-1, -0.5),
        const Offset(1, -0.5),
      ]) {
        final TestGesture g =
            await tester.startGesture(tester.getCenter(stick));
        await g.moveBy(dir * 20);
        await g.moveBy(dir * 28);
        for (int t = 0; t < 1000; t += 16) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pump();
      }
      // Проверка, которая может не пройти: Финни правда шёл.
      final Offset end = tester
          .getRect(find.byKey(const ValueKey<String>('city:finni')))
          .bottomCenter;
      expect((end - start).distance, greaterThan(20), reason: 'Финни шёл');
      final List<Layer?> after = layers.map(drawn).toList();
      expect(<int>[
        for (int i = 0; i < layers.length; i++)
          if (!identical(before[i], after[i])) i
      ], isEmpty, reason: 'перерисованные слои (0 — земля)');
    });

    testWidgets('${s.key}: касание здания — земля и декор не перерисовываются',
        (WidgetTester tester) async {
      await pumpCity(tester, s.value);
      final List<RenderRepaintBoundary> layers = still(tester);
      final List<Layer?> before = layers.map(drawn).toList();
      await tester.tapAt(pointOn(tester, 'city:building:park'));
      // Путь — до 850 мс; дальше город закрывает экран места.
      for (int t = 0; t < 800; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final List<Layer?> after = layers.map(drawn).toList();
      expect(<int>[
        for (int i = 0; i < layers.length; i++)
          if (!identical(before[i], after[i])) i
      ], isEmpty, reason: 'перерисованные слои (0 — земля)');
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
