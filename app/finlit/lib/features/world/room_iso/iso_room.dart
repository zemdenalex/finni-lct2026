/// Iso room (V2): data of `room_layout_iso.json`, placement rules, the
/// resolver of saved positions and the walking path. Rules and BFS are ported
/// from room-lab A (`lib/roomlab/room_model.dart`).
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../../domain/world/room_grid.dart';
import 'iso_depth.dart';
import 'iso_grid.dart';

/// Where a slot lives: on the floor (furniture), on the floor under
/// everything (a rug), or on a back wall.
enum IsoLayer { floor, rug, wall }

/// Height band of a wall item: a poster, a lamp under the ceiling, or a thing
/// on the window sill (only inside the window).
enum IsoBand { normal, high, sill }

/// One place of the room from the data file.
class IsoSlotSpec {
  const IsoSlotSpec({
    required this.id,
    required this.layer,
    this.x = 0,
    this.y = 0,
    this.w = 1,
    this.d = 1,
    this.side,
    this.u = 0,
    this.len = 1,
    this.band = IsoBand.normal,
    this.sprite,
    this.fit = 1,
  });

  final String id;
  final IsoLayer layer;

  /// Floor and rug: default origin cell and footprint.
  final int x, y, w, d;

  /// Wall: default side, slot and length in slots.
  final IsoWall? side;
  final int u, len;
  final IsoBand band;

  /// Default picture id (`{stage}` is replaced); null — a decor place that
  /// shows only a bought item.
  final String? sprite;

  /// Picture width as a share of the footprint's screen width.
  final double fit;

  bool get isWall => layer == IsoLayer.wall;

  /// Default position as a saved spot.
  RoomIsoSpot get home =>
      isWall ? (plane: side!.name, x: u, y: 0) : (plane: 'floor', x: x, y: y);
}

/// A fixed wall feature (door, window).
class IsoFeature {
  const IsoFeature(this.id, this.side, this.u, this.len,
      {this.bottom = 0, this.top = 0});
  final String id;
  final IsoWall side;
  final int u, len;
  final double bottom, top;
}

/// `room_layout_iso.json` parsed.
class IsoRoomSpec {
  const IsoRoomSpec({
    required this.grid,
    required this.slots,
    required this.door,
    required this.window,
    required this.finniX,
    required this.finniY,
    required this.finniH,
    required this.finniR,
    required this.petH,
    required this.bandBottom,
    required this.bandTop,
    required this.highBottom,
    required this.highTop,
  });

  static const String asset = 'assets/content/world/room_layout_iso.json';

  final IsoGrid grid;
  final Map<String, IsoSlotSpec> slots;
  final IsoFeature door, window;
  final int finniX, finniY;
  final double finniH, finniR, petH;
  final double bandBottom, bandTop, highBottom, highTop;

  List<IsoFeature> get features => <IsoFeature>[door, window];

  /// Wall band of [band]: bottom and top px above the floor.
  (double, double) bandOf(IsoBand band) => switch (band) {
        IsoBand.normal => (bandBottom, bandTop),
        IsoBand.high => (highBottom, highTop),
        IsoBand.sill => (window.bottom - 2, window.bottom + 26),
      };

  static IsoRoomSpec parse(String text) {
    final Map<String, Object?> j = jsonDecode(text) as Map<String, Object?>;
    Map<String, Object?> m(Object? o) => o! as Map<String, Object?>;
    double n(Object? o) => (o! as num).toDouble();
    int i(Object? o) => (o! as num).toInt();
    IsoWall side(Object? o) =>
        IsoWall.values.firstWhere((IsoWall s) => s.name == o,
            orElse: () => throw FormatException('room_layout_iso: стена «$o»'));
    final Map<String, Object?> g = m(j['grid']);
    final IsoGrid grid = IsoGrid(
      cols: i(g['cols']),
      rows: i(g['rows']),
      tileW: n(g['tile_w']),
      tileH: n(g['tile_h']),
      wallH: n(g['wall_h']),
    );
    final Map<String, IsoSlotSpec> slots = <String, IsoSlotSpec>{};
    for (final MapEntry<String, Object?> e in m(j['slots']).entries) {
      final Map<String, Object?> s = m(e.value);
      final String plane = s['plane']! as String;
      final bool wall = plane != 'floor';
      slots[e.key] = IsoSlotSpec(
        id: e.key,
        layer: wall
            ? IsoLayer.wall
            : (s['layer'] == 'rug' ? IsoLayer.rug : IsoLayer.floor),
        x: wall ? 0 : i(s['x']),
        y: wall ? 0 : i(s['y']),
        w: wall ? 1 : i(s['w']),
        d: wall ? 1 : i(s['d']),
        side: wall ? side(plane) : null,
        u: wall ? i(s['u']) : 0,
        len: wall ? i(s['len']) : 1,
        band: switch (s['band']) {
          'high' => IsoBand.high,
          'sill' => IsoBand.sill,
          _ => IsoBand.normal,
        },
        sprite: s['sprite'] as String?,
        fit: s['fit'] == null ? 1 : n(s['fit']),
      );
    }
    final Map<String, Object?> f = m(j['features']);
    IsoFeature feature(String id) {
      final Map<String, Object?> o = m(f[id]);
      return IsoFeature(id, side(o['side']), i(o['u']), i(o['len']),
          bottom: o['bottom'] == null ? 0 : n(o['bottom']),
          top: o['top'] == null ? n(o['height']) : n(o['top']));
    }

    final Map<String, Object?> fi = m(j['finni']);
    final Map<String, Object?> band = m(j['wall_band']);
    return IsoRoomSpec(
      grid: grid,
      slots: slots,
      door: feature('door'),
      window: feature('window'),
      finniX: i(fi['x']),
      finniY: i(fi['y']),
      finniH: n(fi['height']),
      finniR: n(fi['r']),
      petH: n(m(j['pet'])['height']),
      bandBottom: n(band['bottom']),
      bandTop: n(band['top']),
      highBottom: n(band['high_bottom']),
      highTop: n(band['high_top']),
    );
  }
}

/// Where one slot stands now.
class IsoPlacement {
  const IsoPlacement.floor(this.spec, this.x, this.y)
      : side = null,
        u = 0;
  const IsoPlacement.wall(this.spec, IsoWall this.side, this.u)
      : x = 0,
        y = 0;

  final IsoSlotSpec spec;
  final int x, y;
  final IsoWall? side;
  final int u;

  String get id => spec.id;
  int get x1 => x + spec.w;
  int get y1 => y + spec.d;
  bool get isWall => side != null;

  bool covers(int cx, int cy) => cx >= x && cx < x1 && cy >= y && cy < y1;

  IsoBox get box =>
      IsoBox(id, x.toDouble(), y.toDouble(), x1.toDouble(), y1.toDouble());

  RoomIsoSpot get spot =>
      isWall ? (plane: side!.name, x: u, y: 0) : (plane: 'floor', x: x, y: y);

  /// The same slot moved to a saved [s]; null if the plane does not fit the
  /// slot (a wall item on the floor).
  IsoPlacement? at(RoomIsoSpot s) {
    if (spec.isWall) {
      if (s.plane == 'floor') return null;
      final IsoWall side =
          IsoWall.values.firstWhere((IsoWall w) => w.name == s.plane);
      return IsoPlacement.wall(spec, side, s.x);
    }
    if (s.plane != 'floor') return null;
    return IsoPlacement.floor(spec, s.x, s.y);
  }
}

/// Why a placement is refused.
enum IsoBlock { ok, outside, overlap, feature, hero }

/// The room as it stands: placements of the present slots.
class IsoArrangement {
  IsoArrangement(this.spec);

  final IsoRoomSpec spec;
  final Map<String, IsoPlacement> placed = <String, IsoPlacement>{};

  IsoGrid get grid => spec.grid;

  /// Floor rule: inside the room, no overlap with an item of the same layer
  /// (rugs only clash with rugs), not on the hero's cells.
  IsoBlock checkFloor(IsoPlacement p,
      {Set<(int, int)> hero = const <(int, int)>{}}) {
    if (p.x < 0 || p.y < 0 || p.x1 > grid.cols || p.y1 > grid.rows) {
      return IsoBlock.outside;
    }
    final bool rug = p.spec.layer == IsoLayer.rug;
    for (final IsoPlacement o in placed.values) {
      if (o.id == p.id || o.isWall) continue;
      if ((o.spec.layer == IsoLayer.rug) != rug) continue;
      if (o.x < p.x1 && p.x < o.x1 && o.y < p.y1 && p.y < o.y1) {
        return IsoBlock.overlap;
      }
    }
    if (!rug) {
      for (final (int, int) c in hero) {
        if (p.covers(c.$1, c.$2)) return IsoBlock.hero;
      }
    }
    return IsoBlock.ok;
  }

  /// Wall rule: inside the wall; a sill thing only inside the window, any
  /// other wall thing off the door and the window; no overlap on one side.
  IsoBlock checkWall(IsoPlacement p) {
    final IsoWall side = p.side!;
    final int len = p.spec.len;
    if (p.u < 0 || p.u + len > grid.wallLen(side)) return IsoBlock.outside;
    final IsoFeature w = spec.window;
    if (p.spec.band == IsoBand.sill) {
      if (side != w.side || p.u < w.u || p.u + len > w.u + w.len) {
        return IsoBlock.feature;
      }
    } else {
      for (final IsoFeature f in spec.features) {
        if (f.side == side && f.u < p.u + len && p.u < f.u + f.len) {
          return IsoBlock.feature;
        }
      }
    }
    for (final IsoPlacement o in placed.values) {
      if (o.id == p.id || o.side != side) continue;
      if ((o.spec.band == IsoBand.sill) != (p.spec.band == IsoBand.sill)) {
        continue;
      }
      if (o.u < p.u + len && p.u < o.u + o.spec.len) return IsoBlock.overlap;
    }
    return IsoBlock.ok;
  }

  IsoBlock check(IsoPlacement p,
          {Set<(int, int)> hero = const <(int, int)>{}}) =>
      p.isWall ? checkWall(p) : checkFloor(p, hero: hero);

  /// Cells blocked for walking: everything standing except rugs.
  Set<(int, int)> blockedCells() => <(int, int)>{
        for (final IsoPlacement p in placed.values)
          if (!p.isWall && p.spec.layer != IsoLayer.rug)
            for (int cx = p.x; cx < p.x1; cx++)
              for (int cy = p.y; cy < p.y1; cy++) (cx, cy),
      };

  /// Floor item on a cell (furniture first, then a rug), or null.
  IsoPlacement? itemAtCell(int cx, int cy) {
    IsoPlacement? rug;
    for (final IsoPlacement p in placed.values) {
      if (p.isWall || !p.covers(cx, cy)) continue;
      if (p.spec.layer == IsoLayer.rug) {
        rug = p;
      } else {
        return p;
      }
    }
    return rug;
  }

  /// The room for [present] slots: each at its saved spot from [saved] if it
  /// fits, else at its default place, else at the first free place on its
  /// plane. Nothing bought disappears: every present slot gets a place while
  /// any is free. Saved spots are tried first in a fixed order (the slot
  /// order of the data file), so the result does not depend on map order.
  static IsoArrangement resolve(
    IsoRoomSpec spec,
    Iterable<String> present,
    Map<String, RoomIsoSpot> saved,
  ) {
    final IsoArrangement a = IsoArrangement(spec);
    final Set<String> want = present.toSet();
    final List<IsoSlotSpec> order = <IsoSlotSpec>[
      for (final IsoSlotSpec s in spec.slots.values)
        if (want.contains(s.id)) s,
    ];
    final List<IsoSlotSpec> later = <IsoSlotSpec>[];
    for (final IsoSlotSpec s in order) {
      final RoomIsoSpot? spot = saved[s.id];
      final IsoPlacement? p =
          spot == null ? null : IsoPlacement.floor(s, s.x, s.y).at(spot);
      if (p != null && a.check(p) == IsoBlock.ok) {
        a.placed[s.id] = p;
      } else {
        later.add(s);
      }
    }
    for (final IsoSlotSpec s in later) {
      final IsoPlacement home = s.isWall
          ? IsoPlacement.wall(s, s.side!, s.u)
          : IsoPlacement.floor(s, s.x, s.y);
      if (a.check(home) == IsoBlock.ok) {
        a.placed[s.id] = home;
        continue;
      }
      final IsoPlacement? free = a.firstFree(s);
      if (free != null) a.placed[s.id] = free;
    }
    return a;
  }

  /// First place for [s] that passes the rules, nearest to its default.
  IsoPlacement? firstFree(IsoSlotSpec s) {
    final List<IsoPlacement> all = <IsoPlacement>[
      if (s.isWall)
        for (final IsoWall side in IsoWall.values)
          for (int u = 0; u < grid.wallLen(side); u++)
            IsoPlacement.wall(s, side, u)
      else
        for (int x = 0; x < grid.cols; x++)
          for (int y = 0; y < grid.rows; y++) IsoPlacement.floor(s, x, y),
    ];
    int dist(IsoPlacement p) => p.isWall
        ? (p.side == s.side ? 0 : 100) + (p.u - s.u).abs()
        : (p.x - s.x).abs() + (p.y - s.y).abs();
    all.sort((IsoPlacement a, IsoPlacement b) => dist(a).compareTo(dist(b)));
    for (final IsoPlacement p in all) {
      if (check(p) == IsoBlock.ok) return p;
    }
    return null;
  }
}

/// Shortest 4-connected path over free cells, excluding [from], including
/// [to]. Null when [to] is blocked, outside or unreachable. No diagonal
/// steps: the hero's box would clip furniture corners.
List<(int, int)>? isoPath(
  (int, int) from,
  (int, int) to,
  Set<(int, int)> blocked, {
  required int cols,
  required int rows,
}) {
  bool inside((int, int) c) =>
      c.$1 >= 0 && c.$2 >= 0 && c.$1 < cols && c.$2 < rows;
  if (!inside(to) || blocked.contains(to)) return null;
  if (from == to) return <(int, int)>[];
  final Map<(int, int), (int, int)> prev = <(int, int), (int, int)>{};
  final Queue<(int, int)> q = Queue<(int, int)>()..add(from);
  final Set<(int, int)> seen = <(int, int)>{from};
  const List<(int, int)> steps = <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)];
  while (q.isNotEmpty) {
    final (int, int) c = q.removeFirst();
    if (c == to) break;
    for (final (int, int) s in steps) {
      final (int, int) n = (c.$1 + s.$1, c.$2 + s.$2);
      if (!inside(n) || blocked.contains(n) || !seen.add(n)) continue;
      prev[n] = c;
      q.add(n);
    }
  }
  if (!prev.containsKey(to)) return null;
  final List<(int, int)> path = <(int, int)>[];
  for ((int, int)? c = to; c != null && c != from; c = prev[c]) {
    path.add(c);
  }
  return path.reversed.toList();
}

/// Free floor cell next to [p] where Finni stands to use it: the nearest to
/// [from] among the cells touching the footprint (front sides first). Wall
/// items: the cell under the slot. Null — no free cell around.
(int, int)? isoStandCell(IsoArrangement a, IsoPlacement p, (int, int) from) {
  final Set<(int, int)> blocked = a.blockedCells();
  final IsoGrid g = a.grid;
  final List<(int, int)> around = p.isWall
      ? <(int, int)>[
          for (int k = 0; k < p.spec.len; k++)
            for (int depth = 0; depth < 3; depth++)
              p.side == IsoWall.left ? (depth, p.u + k) : (p.u + k, depth),
        ]
      : <(int, int)>[
          for (int cx = p.x; cx < p.x1; cx++) (cx, p.y1),
          for (int cy = p.y; cy < p.y1; cy++) (p.x1, cy),
          for (int cx = p.x; cx < p.x1; cx++) (cx, p.y - 1),
          for (int cy = p.y; cy < p.y1; cy++) (p.x - 1, cy),
          if (p.spec.layer == IsoLayer.rug)
            for (int cx = p.x; cx < p.x1; cx++)
              for (int cy = p.y; cy < p.y1; cy++) (cx, cy),
        ];
  (int, int)? best;
  int bestD = 1 << 30;
  for (final (int, int) c in around) {
    if (c.$1 < 0 || c.$2 < 0 || c.$1 >= g.cols || c.$2 >= g.rows) continue;
    if (blocked.contains(c) && c != from) continue;
    final int d = (c.$1 - from.$1).abs() + (c.$2 - from.$2).abs();
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best;
}

/// A free step of the hero by the joystick (continuous cell units): from
/// [from] toward [to], feet a square of half-size [r]. Stays on the floor and
/// out of every standing thing (rugs are walked on). A blocked step slides
/// along the free axis, as along a wall; fully blocked — stays.
({double x, double y}) isoSlide(
  IsoArrangement a,
  ({double x, double y}) from,
  ({double x, double y}) to,
  double r,
) {
  bool free(double x, double y) {
    if (x < r || y < r || x > a.grid.cols - r || y > a.grid.rows - r) {
      return false;
    }
    for (final IsoPlacement p in a.placed.values) {
      if (p.isWall || p.spec.layer == IsoLayer.rug) continue;
      if (x + r > p.x && x - r < p.x1 && y + r > p.y && y - r < p.y1) {
        return false;
      }
    }
    return true;
  }

  if (free(to.x, to.y)) return to;
  if (free(to.x, from.y)) return (x: to.x, y: from.y);
  if (free(from.x, to.y)) return (x: from.x, y: to.y);
  return from;
}

/// A joystick direction on the screen (dp, any length) as a unit direction on
/// the floor: «up» on the screen is into the room, along both axes.
({double x, double y}) isoStickDir(IsoGrid g, Offset screen) {
  final double u = screen.dx / g.halfW, v = screen.dy / g.halfH;
  final double x = (v + u) / 2, y = (v - u) / 2;
  final double n = math.sqrt(x * x + y * y);
  return n == 0 ? (x: 0, y: 0) : (x: x / n, y: y / n);
}

/// Thing of the room the hero stands next to ([reach] cells from its base),
/// the nearest one; the door counts as a thing on its wall. Null — none.
String? isoNearThing(IsoRoomSpec spec, IsoArrangement a,
    ({double x, double y}) feet, Iterable<String> things,
    {double reach = 0.75}) {
  String? best;
  double bestD = reach;
  for (final String id in things) {
    final double d;
    if (id == 'door') {
      final IsoFeature f = spec.door;
      final double along = f.side == IsoWall.left ? feet.y : feet.x;
      final double off = f.side == IsoWall.left ? feet.x : feet.y;
      final double out =
          math.max(0, math.max(f.u - along, along - (f.u + f.len)));
      d = math.sqrt(out * out + off * off);
    } else {
      final IsoPlacement? p = a.placed[id];
      if (p == null || p.isWall) continue;
      final double dx = math.max(0, math.max(p.x - feet.x, feet.x - p.x1));
      final double dy = math.max(0, math.max(p.y - feet.y, feet.y - p.y1));
      d = math.sqrt(dx * dx + dy * dy);
    }
    if (d <= bestD) {
      bestD = d;
      best = id;
    }
  }
  return best;
}

/// A free cell one step further in front of the floor thing [p] (two cells
/// from its front edge), the nearest to [from]; null — none free.
(int, int)? isoStandBack(IsoArrangement a, IsoPlacement p, (int, int) from) {
  if (p.isWall) return null;
  final Set<(int, int)> blocked = a.blockedCells();
  (int, int)? best;
  int bestD = 1 << 30;
  for (int cx = p.x; cx < p.x1; cx++) {
    final (int, int) c = (cx, p.y1 + 1);
    if (c.$2 >= a.grid.rows || (blocked.contains(c) && c != from)) continue;
    final int d = (c.$1 - from.$1).abs() + (c.$2 - from.$2).abs();
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best;
}
