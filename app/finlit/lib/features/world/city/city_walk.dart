import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'city_geometry.dart';

/// Как Финни ходит по городу с флагом `city.smooth_walk`
/// (`docs/final/gorod-dvizhenie.md`): дома — препятствие, вдоль края
/// поля и вдоль дома Финни скользит, а не встаёт; касание здания ведёт в
/// обход домов, по их углам, к двери.
///
/// Всё в пикселях карты при 1×. Без состояния: экран спрашивает, город
/// отвечает.
class CityWalk {
  CityWalk(this.geo)
      : _solid = geo.iso
            // A (вертикально) — вся земля и есть здания: препятствий нет.
            ? Set<CityCell>.of(geo.cells.values)
            : <CityCell>{},
        _u1 = _unit(Offset(geo.tileW / 2, geo.tileH / 2)),
        _u2 = _unit(Offset(geo.tileW / 2, -geo.tileH / 2));

  final CityGeometry geo;

  /// Клетки зданий: туда не ходят.
  final Set<CityCell> _solid;

  /// Направления кромок ромба: «\» и «/».
  final Offset _u1, _u2;

  /// Дом занимает ромб своей клетки, ужатый до этой доли: между домом и
  /// краем поля остаётся улица.
  static const double footprint = 0.8;

  /// Больше этого за кадр Финни не проходит: шаг не проскакивает дверь
  /// (зона «войти» — 0,3 клетки) и тонкий угол дома.
  static const double maxStep = 12;

  /// Подшаг проверки столкновений.
  static const double _sub = 3;

  static const double _eps = 1e-6;

  static Offset _unit(Offset o) => o / o.distance;

  double _diamond(CityCell c, Offset p, double f) {
    final Offset m = geo.center(c);
    return (p.dx - m.dx).abs() / (geo.tileW / 2 * f) +
        (p.dy - m.dy).abs() / (geo.tileH / 2 * f);
  }

  /// На земле (край поля — тоже земля).
  bool onGround(Offset p) {
    for (final CityCell c in geo.ground) {
      if (_diamond(c, p, 1) <= 1 + _eps) return true;
    }
    return false;
  }

  /// Внутри дома.
  bool blocked(Offset p) {
    for (final CityCell c in _solid) {
      if (_diamond(c, p, footprint) < 1 - _eps) return true;
    }
    return false;
  }

  /// Здесь можно стоять.
  bool free(Offset p) => onGround(p) && !blocked(p);

  /// Дверь здания [id]: справа от переднего угла, как раньше; если там нет
  /// земли (Магазин у правого края поля) — слева от угла.
  /// У зданий из [CityGeometry.doorLeft] — слева, где была и до того, как
  /// поле выросло.
  Offset door(String id) {
    final Offset a = geo.anchor(geo.cells[id]!);
    final Offset right = a + Offset(geo.tileW * 0.26, 2);
    final Offset left = a + Offset(-geo.tileW * 0.26, 2);
    if (geo.doorLeft.contains(id) && free(left)) return left;
    if (free(right)) return right;
    return free(left) ? left : right;
  }

  /// Шаг джойстика на [d]: не длиннее [maxStep], по земле и мимо домов.
  /// Упёрся — скользит вдоль кромки (косой край поля, стена дома), а не
  /// встаёт; встаёт только во внутреннем углу.
  Offset step(Offset from, Offset d) {
    if (d.distance > maxStep) d = d / d.distance * maxStep;
    if (!free(from)) {
      // Стоит не там, где можно (старое сохранение, поворот) — шаг только
      // на землю.
      final Offset to = from + d;
      return free(to) ? to : from;
    }
    final int n = math.max(1, (d.distance / _sub).ceil());
    final Offset s = d / n.toDouble();
    Offset p = from;
    for (int i = 0; i < n; i++) {
      final Offset next = _slide(p, s);
      if (next == p) break;
      p = next;
    }
    return p;
  }

  Offset _slide(Offset p, Offset s) {
    final double a = s.dx * _u1.dx + s.dy * _u1.dy;
    final double b = s.dx * _u2.dx + s.dy * _u2.dy;
    final List<Offset> tries = <Offset>[
      s,
      // Вдоль кромки, у которой проекция длиннее, — потом вдоль другой.
      if (a.abs() >= b.abs()) ...<Offset>[_u1 * a, _u2 * b],
      if (a.abs() < b.abs()) ...<Offset>[_u2 * b, _u1 * a],
      Offset(s.dx, 0),
      Offset(0, s.dy),
    ];
    for (final Offset t in tries) {
      if (t.distance < 1e-3) continue;
      if (free(p + t)) return p + t;
    }
    return p;
  }

  /// Отрезок целиком по свободной земле (проверка через 2 px).
  bool clear(Offset a, Offset b) {
    final int n = math.max(1, ((b - a).distance / 2).ceil());
    for (int i = 0; i <= n; i++) {
      if (!free(Offset.lerp(a, b, i / n)!)) return false;
    }
    return true;
  }

  /// Узлы обхода: углы домов чуть снаружи (ромб клетки, ужатый до
  /// [_corner]), если там земля. Между домом и краем поля — тоже узел: по
  /// такой улице Финни проходит и джойстиком.
  static const double _corner = 0.9;

  late final List<Offset> _nodes = <Offset>[
    for (final CityCell c in _solid)
      for (final Offset v in <Offset>[
        Offset(geo.tileW / 2 * _corner, 0),
        Offset(-geo.tileW / 2 * _corner, 0),
        Offset(0, geo.tileH / 2 * _corner),
        Offset(0, -geo.tileH / 2 * _corner),
      ])
        if (free(geo.center(c) + v)) geo.center(c) + v,
  ];

  /// Какие узлы видят друг друга: длина отрезка или бесконечность.
  late final List<List<double>> _seen = <List<double>>[
    for (int i = 0; i < _nodes.length; i++)
      <double>[
        for (int j = 0; j < _nodes.length; j++)
          i != j && clear(_nodes[i], _nodes[j])
              ? (_nodes[i] - _nodes[j]).distance
              : double.infinity,
      ],
  ];

  /// Путь от [from] к [to] — точки поворота, последняя — [to]. Прямо, если
  /// прямая свободна; иначе кратчайший по углам домов (граф видимости:
  /// узел к узлу — только по свободному отрезку). Пути нет — прямая (как
  /// было до флага).
  List<Offset> route(Offset from, Offset to) {
    if (clear(from, to)) return <Offset>[to];
    final int n = _nodes.length;
    // 0…n-1 — узлы, n — цель.
    final List<double> dist = <double>[
      for (int i = 0; i < n; i++)
        clear(from, _nodes[i]) ? (_nodes[i] - from).distance : double.infinity,
      double.infinity,
    ];
    final List<int> prev = List<int>.filled(n + 1, -1);
    final List<bool> done = List<bool>.filled(n + 1, false);
    final List<bool> toGoal = <bool>[
      for (int i = 0; i < n; i++) clear(_nodes[i], to),
    ];
    while (true) {
      int u = -1;
      for (int i = 0; i <= n; i++) {
        if (!done[i] && dist[i].isFinite && (u < 0 || dist[i] < dist[u])) {
          u = i;
        }
      }
      if (u < 0 || u == n) break;
      done[u] = true;
      for (int v = 0; v < n; v++) {
        final double d = dist[u] + _seen[u][v];
        if (d < dist[v]) {
          dist[v] = d;
          prev[v] = u;
        }
      }
      if (toGoal[u]) {
        final double d = dist[u] + (to - _nodes[u]).distance;
        if (d < dist[n]) {
          dist[n] = d;
          prev[n] = u;
        }
      }
    }
    if (!dist[n].isFinite) return <Offset>[to];
    final List<Offset> out = <Offset>[to];
    for (int i = prev[n]; i >= 0; i = prev[i]) {
      out.insert(0, _nodes[i]);
    }
    return out;
  }

  /// Длина пути [route] от [from].
  static double length(Offset from, List<Offset> route) {
    double sum = 0;
    Offset p = from;
    for (final Offset q in route) {
      sum += (q - p).distance;
      p = q;
    }
    return sum;
  }
}
