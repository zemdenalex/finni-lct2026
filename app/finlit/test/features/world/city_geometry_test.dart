import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_filler.dart';
import 'package:finlit/features/world/city/city_geometry.dart';
import 'package:finlit/features/world/city/city_screen.dart';
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
}
