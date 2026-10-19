import 'dart:convert';
import 'dart:io';

import 'package:finlit/features/world/city/city_geometry.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/city/city_walk.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Маршруты города с флагом `city.smooth_walk` и сам флаг
/// (`docs/final/gorod-dvizhenie.md`).
///
/// Защищает: из любой точки, где Финни может стоять, до двери каждого
/// здания есть путь по земле мимо домов, и шаг джойстика по нему не
/// застревает; флаг включён в сборке, без ключа — выключен, выключенный —
/// ходьба как на 068ed67.
/// Уронит: узлы обхода не видят друг друга (дом без пути), путь режет угол
/// дома или выходит с поля, шаг вдоль пути упирается; флаг читается не
/// оттуда или по умолчанию true.
void main() {
  final CityGeometry geo = isoGeometry;
  final CityWalk walk = CityWalk(geo);

  /// Своя формула дома (не код движения): ромб клетки, ужатый до 0,75.
  String? inHouse(Offset p) {
    for (final MapEntry<String, CityCell> e in geo.cells.entries) {
      final Offset c = geo.center(e.value);
      if ((p.dx - c.dx).abs() / (geo.tileW / 2 * 0.75) +
              (p.dy - c.dy).abs() / (geo.tileH / 2 * 0.75) <
          1) {
        return e.key;
      }
    }
    return null;
  }

  test('из каждой точки до каждой двери — путь мимо домов, без застревания',
      () {
    final List<Offset> starts = <Offset>[
      for (final CityBuilding b in cityBuildings) walk.door(b.id),
      for (double x = 2; x < geo.base.width; x += 12)
        for (double y = 2; y < geo.base.height; y += 12)
          if (walk.free(Offset(x, y))) Offset(x, y),
    ];
    // Левый угол поля — туда Финни доезжает вдоль края (Д1).
    starts.add(Offset(5, geo.center((0, geo.grid - 1)).dy));
    expect(starts.length, greaterThan(200), reason: 'точек старта мало');
    final List<String> bad = <String>[];
    int longest = 0;
    for (final Offset s in starts) {
      for (final CityBuilding b in cityBuildings) {
        final Offset door = walk.door(b.id);
        final List<Offset> path = walk.route(s, door);
        if (path.last != door) {
          bad.add('$s → ${b.id}: путь не к двери');
          continue;
        }
        // Каждый отрезок — по земле и мимо домов (через 1 px).
        Offset a = s;
        for (final Offset q in path) {
          final int n = ((q - a).distance).ceil().clamp(1, 100000);
          for (int i = 0; i <= n; i++) {
            final Offset p = Offset.lerp(a, q, i / n)!;
            final String? h = inHouse(p);
            if (h != null || !geo.onGround(p)) {
              bad.add('$s → ${b.id}: $p ${h ?? 'вне поля'}');
              break;
            }
          }
          a = q;
        }
        // Шаг джойстика по пути: за 2000 шагов по 2,5 px — у двери.
        Offset p = s;
        int ticks = 0;
        for (final Offset q in path) {
          while ((q - p).distance > 0.5 && ticks < 2000) {
            final Offset d = q - p;
            final Offset next = walk.step(
                p, d / d.distance * (d.distance < 2.5 ? d.distance : 2.5));
            ticks++;
            if (next == p) {
              ticks = 2000;
              break;
            }
            p = next;
          }
        }
        if ((p - door).distance > 0.5) bad.add('$s → ${b.id}: застрял у $p');
        if (ticks > longest) longest = ticks;
      }
    }
    expect(bad.take(10).toList(), isEmpty, reason: '${bad.length} плохих');
    expect(longest, lessThan(2000));
  });

  test('двери — на земле и вне домов; у Магазина — слева от угла', () {
    for (final CityBuilding b in cityBuildings) {
      final Offset d = walk.door(b.id);
      expect(geo.onGround(d), isTrue, reason: b.id);
      expect(inHouse(d), isNull, reason: b.id);
      expect((d - geo.anchor(geo.cells[b.id]!)).distance,
          lessThan(geo.tileW * 0.3),
          reason: '${b.id}: дверь у переднего угла — там кнопка «войти»');
    }
    expect(walk.door('grocery').dx,
        lessThan(geo.anchor(geo.cells['grocery']!).dx));
  });

  test('шаг не длиннее CityWalk.maxStep: дверь не проскочить', () {
    final Offset from = walk.door('home');
    final Offset to = walk.step(from, const Offset(300, 0));
    expect((to - from).distance, lessThanOrEqualTo(CityWalk.maxStep + 1e-6));
    expect((to - from).distance, greaterThan(1), reason: 'и всё-таки шагнул');
  });

  group('флаг city.smooth_walk', () {
    setUp(rootBundle.clear);

    test('сборка: включён; нет ключа — выключен', () {
      expect(contentScript.citySmoothWalk, isTrue);
      final Map<String, Object?> j =
          jsonDecode(File(OnboardingScript.path).readAsStringSync())
              as Map<String, Object?>;
      (j['city']! as Map<String, Object?>).remove('smooth_walk');
      expect(OnboardingScript.parse(jsonEncode(j)).citySmoothWalk, isFalse);
    });

    // Выключен — шаг снова только по осям: у косого края Финни встаёт,
    // как на 068ed67 (Д1 там же падал с x = 262).
    testWidgets('выключен — ходьба как раньше', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const CityScreen(smoothWalk: false),
            world: livingWorld(worldKinds.last), size: landscape);
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.pump();
      final Finder stick = find.byKey(const ValueKey<String>('city:joystick'));
      final TestGesture g = await tester.startGesture(tester.getCenter(stick));
      await g.moveBy(const Offset(-20, 0));
      await g.moveBy(const Offset(-28, 0));
      // Поле 8 × 8: до края у Дома — дальше, чем на прежнем 5 × 5.
      for (int t = 0; t < 6000; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await g.up();
      await tester.pump();
      final double k = CityCamera.scale(CityVariant.iso);
      final Rect map =
          tester.getRect(find.byKey(const ValueKey<String>('city:map')));
      final double x = (tester
                  .getRect(find.byKey(const ValueKey<String>('city:finni')))
                  .left -
              map.left) /
          k;
      // Поле 8 × 8: у косого края на высоте Дома x ≈ 69; скользя вдоль
      // края, Финни доезжает до левого угла (x ≈ 1).
      expect(x, greaterThan(40), reason: 'встал у края, не скользит');
    });
  });
}
