import 'dart:collection';

import 'package:finlit/features/world/city/city_geometry.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/city/city_walk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Город вырос (ночь 18.10, Денис: «town is too small»): поле 8 × 8 вместо
/// 5 × 5, прежний квартал с домами — внутри.
///
/// Защищает: от места появления Финни (дверь Дома) по проходимой земле
/// (BFS по точкам через 8 px, соседи — только по свободному отрезку
/// [CityWalk.clear]) можно дойти до двери каждого здания и до каждого
/// нового квартала; проходимой земли не меньше двух прежних кварталов.
/// Уронит: улицу закрыли (клетки земли выпали — квартал отрезан), дверь
/// оказалась в доме или за полем, город снова маленький.
void main() {
  final CityGeometry geo = isoGeometry;
  final CityWalk walk = CityWalk(geo);
  const double step = 8;

  // Точки сетки на свободной земле: ключ — (i, j).
  final Map<(int, int), Offset> nodes = <(int, int), Offset>{
    for (int i = 0; i * step < geo.base.width; i++)
      for (int j = 0; j * step < geo.base.height; j++)
        if (walk.free(Offset(i * step, j * step)))
          (i, j): Offset(i * step, j * step),
  };

  (int, int)? near(Offset p) {
    (int, int)? best;
    double d = double.infinity;
    for (final MapEntry<(int, int), Offset> e in nodes.entries) {
      final double x = (e.value - p).distance;
      if (x < d && x <= 2 * step && walk.clear(p, e.value)) {
        d = x;
        best = e.key;
      }
    }
    return best;
  }

  Set<(int, int)> reach(Offset from) {
    final (int, int)? start = near(from);
    if (start == null) return <(int, int)>{};
    final Set<(int, int)> seen = <(int, int)>{start};
    final Queue<(int, int)> q = Queue<(int, int)>()..add(start);
    while (q.isNotEmpty) {
      final (int, int) u = q.removeFirst();
      for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
          final (int, int) v = (u.$1 + di, u.$2 + dj);
          if (seen.contains(v) || !nodes.containsKey(v)) continue;
          if (!walk.clear(nodes[u]!, nodes[v]!)) continue;
          seen.add(v);
          q.add(v);
        }
      }
    }
    return seen;
  }

  final Set<(int, int)> reached = reach(walk.door('home'));

  test('от Дома — до двери каждого здания', () {
    expect(reached, isNotEmpty, reason: 'дверь Дома не на земле');
    for (final CityBuilding b in cityBuildings) {
      final (int, int)? d = near(walk.door(b.id));
      expect(d, isNotNull, reason: 'дверь ${b.id} не на земле');
      expect(reached.contains(d), isTrue, reason: 'до ${b.id} не дойти');
    }
  });

  test('от Дома — в каждый новый квартал', () {
    for (final CityCell c in <CityCell>[
      (7, 0), (7, 4), (7, 7), (5, 7), (0, 7), (0, 5), (5, 5), (5, 0), //
    ]) {
      final (int, int)? n = near(geo.center(c));
      expect(n, isNotNull, reason: 'центр клетки $c не на земле');
      expect(reached.contains(n), isTrue, reason: 'в квартал $c не дойти');
    }
  });

  test('проходимой земли не меньше двух прежних кварталов 5 × 5', () {
    // Прежний квартал — клетки 0…4 по обеим осям.
    bool old(Offset p) {
      for (int c = 0; c < 5; c++) {
        for (int r = 0; r < 5; r++) {
          if (geo.inCell((c, r), p)) return true;
        }
      }
      return false;
    }

    final int oldArea = reached.where((k) => old(nodes[k]!)).length;
    expect(oldArea, greaterThan(500), reason: 'прежний квартал проходим');
    expect(reached.length, greaterThanOrEqualTo(2 * oldArea),
        reason: 'проходимо ${reached.length}, прежний квартал $oldArea');
  });
}
