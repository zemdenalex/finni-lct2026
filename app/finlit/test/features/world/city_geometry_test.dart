import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_filler.dart';
import 'package:finlit/features/world/city/city_geometry.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/city/city_walk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ловит: декор (куст, фонарь, дерево, забор) на какой-то стадии
/// заходит на здание или значок над ним — прячет то, что нажимают, — или
/// вылезает за карту. Виджетный тест в `walking_test` видит только деревню;
/// здесь — все стадии обоих вариантов, по размерам спрайтов из реестра.
void main() {
  final Map<String, Object?> reg =
      jsonDecode(File('assets/art/registry.json').readAsStringSync())
          as Map<String, Object?>;
  final Map<String, Object?> buildings =
      reg['buildings']! as Map<String, Object?>;

  Size spriteOf(String id) {
    final List<Object?> s =
        (buildings[id]! as Map<String, Object?>)['size_px']! as List<Object?>;
    return Size((s[0]! as num).toDouble(), (s[1]! as num).toDouble());
  }

  for (final CityVariant v in CityVariant.values) {
    final CityGeometry geo = CityGeometry.of(v);
    for (final WorldStage stage in WorldStage.values) {
      test('декор не на зданиях и в пределах карты · ${v.name} · ${stage.name}',
          () {
        final Map<String, Rect> taken = <String, Rect>{};
        for (final CityBuilding b in cityBuildings) {
          final Offset a = geo.anchor(geo.cells[b.id]!);
          final Size s = spriteOf(b.id);
          final Rect house = Rect.fromLTWH(
              a.dx - s.width / 2, a.dy - s.height, s.width, s.height);
          taken[b.id] = house;
          // Значок роли 32 над верхом здания.
          taken['${b.id}:icon'] = Rect.fromCenter(
              center: Offset(house.center.dx, house.top),
              width: 32,
              height: 32);
        }
        final Rect map = Offset.zero & geo.base;
        final List<CityDecor> decor = geo.decor(stage);
        expect(decor.length, greaterThanOrEqualTo(10),
            reason: 'город наполнен');
        for (final CityDecor d in decor) {
          final Rect r = cityDecorRect(d).deflate(0.5);
          expect(map.intersect(r), r, reason: '${d.kind} $r за картой');
          for (final MapEntry<String, Rect> t in taken.entries) {
            final Rect x = r.intersect(t.value);
            expect(x.width <= 0 || x.height <= 0, isTrue,
                reason: '${d.kind} ${d.x},${d.y} на ${t.key} ${t.value}');
          }
        }
      });
    }
  }

  // Ловит: клумба посреди площади, забор и фонари на дорожках (Денис,
  // скрин 18.10, ящик с цветами на дороге под Домом). После роста поля до
  // 8 × 8 часть декора оказалась на клетках-дорогах. Проверяется точка, на
  // которой предмет стоит (низ-центр): строго внутри ромба дороги — на
  // дороге. Кромка (фонари на углах перекрёстка) — не дорога.
  final CityGeometry geo = isoGeometry;
  final CityWalk walk = CityWalk(geo);
  double diamond(CityCell c, Offset p, [double f = 1]) {
    final Offset m = geo.center(c);
    return (p.dx - m.dx).abs() / (geo.tileW / 2 * f) +
        (p.dy - m.dy).abs() / (geo.tileH / 2 * f);
  }

  for (final WorldStage stage in WorldStage.values) {
    test('декор не на дорогах и не у дверей · ${stage.name}', () {
      final List<String> bad = <String>[];
      final List<CityDecor> decor = geo.decor(stage);
      for (int i = 0; i < decor.length; i++) {
        final CityDecor d = decor[i];
        final String at = '#$i ${d.kind.name} (${d.x}, ${d.y})';
        for (final CityCell c in geo.roads) {
          // 0,95: точка хотя бы на 5 % ромба внутри дороги.
          if (diamond(c, d.bottom) < 0.95) bad.add('$at → дорога $c');
        }
        for (final MapEntry<String, CityCell> b in geo.cells.entries) {
          // Пятно здания — его ромб, ужатый как для ходьбы.
          if (diamond(b.value, d.bottom, CityWalk.footprint) < 1) {
            bad.add('$at → участок ${b.key} ${b.value}');
          }
          final Offset door = walk.door(b.key);
          // Финни стоит у двери: предмет не накрывает её и стоит не ближе
          // 12 px (полшага Финни).
          if (cityDecorRect(d).inflate(4).contains(door) ||
              (d.bottom - door).distance < 12) {
            bad.add('$at → дверь ${b.key} $door');
          }
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  }
}
