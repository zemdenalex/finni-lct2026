import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Джойстик в городе — ввод, а не анимация (решение pm 17.10).
///
/// Защищает: при «Уменьшить движение» в телефоне и при «Анимации: выкл.» в
/// игре джойстик виден (портрет и альбомная, крупный шрифт), а Финни идёт
/// за ручкой шагами раз в 250 мс, без тикера, с той же скоростью, что и с
/// анимациями. Уронит: экран снова прячет джойстик за `motionOn`; ход без
/// анимаций снова на тикере (плавно); шаг без анимаций снова режется до
/// `CityWalk.maxStep` (Финни втрое медленнее).
void main() {
  setUp(rootBundle.clear);

  /// «Уменьшить движение» в настройках телефона.
  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  Future<void> pumpCity(WidgetTester tester,
      {Size size = portrait,
      double textScale = 1,
      bool gameAnimations = true}) async {
    await tester.runAsync(() async {
      AppState? app;
      if (!gameAnimations) {
        app = AppState(MemoryStorage());
        await app.boot();
        await app.updateProfile(app.game.profile
            .copyWith(settings: const GameSettings(animationsOn: false)));
      }
      await pumpWorldScreen(tester, const CityScreen(),
          world: livingWorld(worldKinds.last),
          size: size,
          textScale: textScale,
          app: app);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  final Finder stick = find.byKey(const ValueKey<String>('city:joystick'));

  /// Где Финни на карте, а не на экране: камера везёт карту за ним.
  Offset onMap(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('city:finni'))).topLeft -
      tester.getRect(find.byKey(const ValueKey<String>('city:map'))).topLeft;

  /// Палец на ручке, ручка до упора в [dir].
  Future<TestGesture> grab(WidgetTester tester, Offset dir) async {
    final TestGesture g = await tester.startGesture(tester.getCenter(stick));
    await g.moveBy(dir * 20);
    await g.moveBy(dir * 28);
    await tester.pump();
    return g;
  }

  Future<void> wait(WidgetTester tester, int ms) async {
    for (int t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Сколько Финни прошёл по карте за [ms], держа ручку вправо.
  Future<double> walkRight(WidgetTester tester, int ms) async {
    final Offset start = onMap(tester);
    final TestGesture g = await grab(tester, const Offset(1, 0));
    await wait(tester, ms);
    final double went = (onMap(tester) - start).distance;
    await g.up();
    await tester.pump();
    return went;
  }

  const Map<String, Size> sizes = <String, Size>{
    'портрет 360×640': Size(360, 640),
    'альбомная 640×360': Size(640, 360),
    'альбомная 800×360': Size(800, 360),
  };

  // (a) «Уменьшить движение» — джойстик на месте.
  for (final MapEntry<String, Size> o in sizes.entries) {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets(
          '${o.key} · шрифт ×$scale, «Уменьшить движение»: джойстик виден',
          (WidgetTester tester) async {
        reduceMotion(tester);
        await pumpCity(tester, size: o.value, textScale: scale);
        expect(stick, findsOneWidget);
      });
    }
  }

  // (b) Без анимаций Финни идёт шагами по таймеру, без тикера.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets(
        '${o.key}, «Уменьшить движение»: ручка вправо — Финни идёт '
        'шагами, без тикера', (WidgetTester tester) async {
      reduceMotion(tester);
      await pumpCity(tester, size: o.value);
      final Offset start = onMap(tester);
      final TestGesture g = await grab(tester, const Offset(1, 0));
      await wait(tester, 100);
      expect((onMap(tester) - start).distance, lessThan(0.5),
          reason: 'до первого шага (250 мс) не плавно');
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'ход без анимаций не просит кадров');
      await wait(tester, 200);
      expect(onMap(tester).dx - start.dx, greaterThan(5),
          reason: 'первый шаг сделан, вправо');
      expect(tester.binding.transientCallbackCount, 0);
      await g.up();
      await tester.pump();
      final Offset stop = onMap(tester);
      await wait(tester, 600);
      expect(onMap(tester), stop, reason: 'отпустил — стоит');
    });
  }

  // (b) + (c): с анимациями ход как раньше — плавно, на тикере; без них —
  // не медленнее.
  testWidgets(
      'без анимаций Финни за секунду проходит столько же, сколько с ними',
      (WidgetTester tester) async {
    reduceMotion(tester);
    await pumpCity(tester, size: landscape);
    final double stepped = await walkRight(tester, 1000);
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pumpWidget(const SizedBox());
    await pumpCity(tester, size: landscape);
    final Offset start = onMap(tester);
    final TestGesture g = await grab(tester, const Offset(1, 0));
    await wait(tester, 100);
    expect((onMap(tester) - start).distance, greaterThan(0.5),
        reason: 'с анимациями идёт плавно, сразу');
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'с анимациями ход на тикере');
    await wait(tester, 900);
    final double smooth = (onMap(tester) - start).distance;
    await g.up();
    await tester.pump();
    expect(smooth, greaterThan(20));
    expect(stepped, greaterThanOrEqualTo(0.7 * smooth),
        reason: 'шагами $stepped px, плавно $smooth px');
  });

  // (d) «Анимации: выкл.» в настройках игры — то же.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('${o.key}, «Анимации: выкл.» в игре: джойстик виден, ведёт',
        (WidgetTester tester) async {
      await pumpCity(tester, size: o.value, gameAnimations: false);
      expect(stick, findsOneWidget);
      expect(await walkRight(tester, 600), greaterThan(5));
    });
  }
}
