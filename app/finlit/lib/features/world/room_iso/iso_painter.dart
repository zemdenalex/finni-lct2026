import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'iso_grid.dart';
import 'iso_room.dart';

/// Iso room colours (placeholders until Denis's iso backgrounds): walls and
/// floor follow the warm room of the 29.09 palette («Уютный вечер», back
/// 20.10). Taste is Denis's — these are not a chosen palette (ratify).
abstract final class IsoColors {
  // «Уютный вечер» (палитра 29.09, ratify n6-style 20.10): тёплая комната
  // под тёмно-синим интерфейсом. Стены и пол — тона фронтальной комнаты 29.09
  // (room_layout.json edge_wall / edge_floor), фон — WorldColors.night 29.09.
  static const Color back = Color(0xFF151833);
  static const Color wallLeft = Color(0xFFDAA879);
  static const Color wallRight = Color(0xFFC8956A);
  static const Color wallStripe = Color(0x14FFFFFF);
  static const Color baseboard = Color(0xFF6E3F27);
  static const Color floorA = Color(0xFFA8643F);
  static const Color floorB = Color(0xFF9C5A39);
  static const Color slab = Color(0xFF5E3422);
  static const Color gridLine = Color(0x22000000);
  static const Color gridEdit = Color(0x88FFF1D7);
  static const Color ink = Color(0xC8151833);
  static const Color ok = Color(0xFF43C46B);
  static const Color gold = Color(0xFFF4C542);
  static const Color wood = Color(0xFF8E5F3D);
  static const Color skyTop = Color(0xFF7CC4EE);
  static const Color skyLow = Color(0xFFD6F0FB);
  static const Color bad = Color(0xFFE5534B);

  // Depth, code only (Денис 19.10: «полки, окна, двери — плоско»): shades
  // of the colours above, not new colours.
  /// Shadow a wall thing casts on the wall.
  static const Color wallShadow = Color(0x40000000);

  /// Multiplier for the body of a wall thing (its thickness).
  static const Color body = Color(0xFF8A8A8A);

  /// Shadow of furniture on the floor.
  static const Color contact = Color(0x30000000);

  /// Inside of an opening (door, window), away from the light.
  static const Color jamb = Color(0xFF8A6244);
}

/// How deep the door leaf and the window glass sit in the wall, cells.
const double isoDoorRecess = 0.2;
const double _windowRecess = 0.22;

/// How far the window sill sticks out into the room, cells.
const double _sillOut = 0.22;

/// Wall thickness seen on the top edge and the front ends, cells.
const double _wallThick = 0.2;

Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

/// A wall point [d] cells off the wall toward the room (negative — into it).
Offset _wp(IsoGrid g, IsoWall side, double u, double h, [double d = 0]) =>
    g.wallToScreen(side, u, h) + g.wallNormal(side) * d;

/// The quad [u0, u1] × [lo, hi] on a wall, [d] cells off it.
List<Offset> _wallQuad(
        IsoGrid g, IsoWall side, double u0, double u1, double lo, double hi,
        [double d = 0]) =>
    <Offset>[
      _wp(g, side, u0, lo, d),
      _wp(g, side, u1, lo, d),
      _wp(g, side, u1, hi, d),
      _wp(g, side, u0, hi, d),
    ];

/// A board sticking out of a wall: [u0, u1] along it, [lo, hi] high, from
/// the wall to [out] cells into the room. Top face light, front face and
/// the end the viewer sees (at [u1]) darker; a shadow on the wall below.
void _ledge(Canvas c, IsoGrid g, IsoWall side, double u0, double u1, double lo,
    double hi, double out, Color wood) {
  c.drawPath(_poly(_wallQuad(g, side, u0, u1, lo - 10, lo)),
      Paint()..color = const Color(0x24000000));
  c.drawPath(_poly(_wallQuad(g, side, u0, u1, lo, hi, out)),
      Paint()..color = _shade(wood, -0.18));
  c.drawPath(
      _poly(<Offset>[
        _wp(g, side, u1, lo),
        _wp(g, side, u1, lo, out),
        _wp(g, side, u1, hi, out),
        _wp(g, side, u1, hi),
      ]),
      Paint()..color = _shade(wood, -0.32));
  c.drawPath(
      _poly(<Offset>[
        _wp(g, side, u0, hi),
        _wp(g, side, u1, hi),
        _wp(g, side, u1, hi, out),
        _wp(g, side, u0, hi, out),
      ]),
      Paint()..color = _shade(wood, 0.22));
}

/// A wooden frame on the wall plane around [u0, u1] × [lo, hi]: [w] slots
/// wide at the sides, [hw] px at the top and bottom.
void _casing(Canvas c, IsoGrid g, IsoWall side, double u0, double u1, double lo,
    double hi, double w, double hw, Color wood) {
  final Path ring = Path()
    ..fillType = PathFillType.evenOdd
    ..addPolygon(_wallQuad(g, side, u0 - w, u1 + w, lo - hw, hi + hw), true)
    ..addPolygon(_wallQuad(g, side, u0, u1, lo, hi), true);
  c.drawPath(ring, Paint()..color = wood);
  // Inner edge: a darker line where the frame meets the opening.
  c.drawPath(
      _poly(_wallQuad(g, side, u0, u1, lo, hi)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _shade(wood, -0.35));
}

Color _shade(Color c, double t) =>
    t >= 0 ? Color.lerp(c, Colors.white, t)! : Color.lerp(c, Colors.black, -t)!;

/// Runs [draw] in a unit square mapped onto a wall area: [len] slots from
/// [u0], top edge [hTop] px above the floor, [height] px tall.
void _onWall(Canvas c, IsoGrid g, IsoWall side, double u0, double len,
    double hTop, double height, void Function(Canvas c) draw) {
  final Offset tl = side == IsoWall.left
      ? g.wallToScreen(side, u0 + len, hTop)
      : g.wallToScreen(side, u0, hTop);
  final Offset tr = side == IsoWall.left
      ? g.wallToScreen(side, u0, hTop)
      : g.wallToScreen(side, u0 + len, hTop);
  final Offset a = tr - tl;
  c.save();
  c.transform(Float64List.fromList(<double>[
    a.dx, a.dy, 0, 0, //
    0, height, 0, 0,
    0, 0, 1, 0,
    tl.dx, tl.dy, 0, 1,
  ]));
  draw(c);
  c.restore();
}

/// Floor, walls, window, grid and the «Расставить» highlights, in screen
/// px ([offset] + content × [k]).
class IsoShellPainter extends CustomPainter {
  const IsoShellPainter({
    required this.spec,
    required this.k,
    required this.offset,
    this.arrange = false,
    this.okCells = const <(int, int)>{},
    this.okWall = const <(IsoWall, int)>{},
    this.selected,
    this.ghost,
    this.ghostOk = true,
    this.grounded = const <IsoPlacement>[],
  });

  final IsoRoomSpec spec;
  final double k;
  final Offset offset;
  final bool arrange;
  final Set<(int, int)> okCells;
  final Set<(IsoWall, int)> okWall;
  final IsoPlacement? selected;

  /// Where a dragged thing would land, green if it may, red if not.
  final IsoPlacement? ghost;
  final bool ghostOk;

  /// Floor things that get a shadow under them.
  final List<IsoPlacement> grounded;

  @override
  void paint(Canvas c, Size size) {
    final IsoGrid g = spec.grid;
    c.save();
    c.translate(offset.dx, offset.dy);
    c.scale(k);
    final double cols = g.cols.toDouble(), rows = g.rows.toDouble();
    const double slab = 10;
    c.drawPath(
        _poly(<Offset>[
          g.toScreen(0, rows),
          g.toScreen(cols, rows),
          g.toScreen(cols, 0),
          g.toScreen(cols, 0).translate(0, slab),
          g.toScreen(cols, rows).translate(0, slab),
          g.toScreen(0, rows).translate(0, slab),
        ]),
        Paint()..color = IsoColors.slab);
    for (int x = 0; x < g.cols; x++) {
      for (int y = 0; y < g.rows; y++) {
        c.drawPath(
            _poly(g.footprint(x.toDouble(), y.toDouble(), x + 1.0, y + 1.0)),
            Paint()
              ..color = (x + y).isEven ? IsoColors.floorA : IsoColors.floorB);
      }
    }
    // Walls.
    for (final IsoWall side in IsoWall.values) {
      final double len = g.wallLen(side).toDouble();
      final Color col =
          side == IsoWall.left ? IsoColors.wallLeft : IsoColors.wallRight;
      c.drawPath(
          _poly(<Offset>[
            g.wallToScreen(side, 0, 0),
            g.wallToScreen(side, len, 0),
            g.wallToScreen(side, len, g.wallH),
            g.wallToScreen(side, 0, g.wallH),
          ]),
          Paint()..color = col);
      _onWall(c, g, side, 0, len, g.wallH, g.wallH, (Canvas u) {
        final int stripes = (len * 2).round();
        for (int s = 0; s < stripes; s += 2) {
          u.drawRect(Rect.fromLTWH(s / stripes, 0, 1 / stripes, 1),
              Paint()..color = IsoColors.wallStripe);
        }
        u.drawRect(const Rect.fromLTRB(0, 0.94, 1, 1),
            Paint()..color = IsoColors.baseboard);
      });
    }
    c.drawLine(
        g.wallToScreen(IsoWall.left, 0, 0),
        g.wallToScreen(IsoWall.left, 0, g.wallH),
        Paint()
          ..color = const Color(0x33000000)
          ..strokeWidth = 1.5);
    _wallEdges(c, g);
    _doorOpening(c, g);
    _window(c, g);
    // Shadows under furniture: the footprint, a little smaller.
    for (final IsoPlacement p in grounded) {
      const double i = 0.06;
      c.drawPath(_poly(g.footprint(p.x + i, p.y + i, p.x1 - i, p.y1 - i)),
          Paint()..color = IsoColors.contact);
    }
    // Grid lines: faint, brighter in «Расставить».
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arrange ? 1.2 : 0.8
      ..color = arrange ? IsoColors.gridEdit : IsoColors.gridLine;
    for (int s = 0; s <= g.cols; s++) {
      c.drawLine(
          g.toScreen(s.toDouble(), 0), g.toScreen(s.toDouble(), rows), grid);
    }
    for (int s = 0; s <= g.rows; s++) {
      c.drawLine(
          g.toScreen(0, s.toDouble()), g.toScreen(cols, s.toDouble()), grid);
    }
    // Where the selected thing can go: green diamonds / wall slots.
    for (final (int, int) cell in okCells) {
      final Path p = _poly(g.footprint(cell.$1.toDouble(), cell.$2.toDouble(),
          cell.$1 + 1.0, cell.$2 + 1.0));
      c.drawPath(p, Paint()..color = IsoColors.ok.withValues(alpha: 0.28));
    }
    for (final (IsoWall, int) w in okWall) {
      final Path p = _poly(<Offset>[
        g.wallToScreen(w.$1, w.$2.toDouble(), spec.bandBottom),
        g.wallToScreen(w.$1, w.$2 + 1.0, spec.bandBottom),
        g.wallToScreen(w.$1, w.$2 + 1.0, spec.bandTop),
        g.wallToScreen(w.$1, w.$2.toDouble(), spec.bandTop),
      ]);
      c.drawPath(p, Paint()..color = IsoColors.ok.withValues(alpha: 0.32));
    }
    final IsoPlacement? s = selected;
    if (s != null) {
      final Path p = s.isWall
          ? _poly(<Offset>[
              g.wallToScreen(s.side!, s.u.toDouble(), spec.bandBottom - 4),
              g.wallToScreen(
                  s.side!, s.u + s.spec.len.toDouble(), spec.bandBottom - 4),
              g.wallToScreen(
                  s.side!, s.u + s.spec.len.toDouble(), spec.highTop + 2),
              g.wallToScreen(s.side!, s.u.toDouble(), spec.highTop + 2),
            ])
          : _poly(g.footprint(s.x.toDouble(), s.y.toDouble(), s.x1.toDouble(),
              s.y1.toDouble()));
      c.drawPath(p, Paint()..color = IsoColors.gold.withValues(alpha: 0.35));
      c.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = IsoColors.gold);
    }
    final IsoPlacement? gh = ghost;
    if (gh != null) {
      c.drawPath(
          _ghostPath(spec, gh),
          Paint()
            ..color = (ghostOk ? IsoColors.ok : IsoColors.bad)
                .withValues(alpha: 0.4));
    }
    c.restore();
  }

  /// The walls have a thickness: a light band on the top edge (with the
  /// back corner) and a darker face at each front end.
  void _wallEdges(Canvas c, IsoGrid g) {
    const double t = _wallThick;
    final double h = g.wallH;
    final Paint cap = Paint()..color = _shade(IsoColors.wallLeft, 0.3);
    for (final IsoWall side in IsoWall.values) {
      final double len = g.wallLen(side).toDouble();
      c.drawPath(
          _poly(<Offset>[
            _wp(g, side, 0, h),
            _wp(g, side, len, h),
            _wp(g, side, len, h, -t),
            _wp(g, side, 0, h, -t),
          ]),
          cap);
      c.drawPath(
          _poly(<Offset>[
            _wp(g, side, len, 0),
            _wp(g, side, len, h),
            _wp(g, side, len, h, -t),
            _wp(g, side, len, 0, -t),
          ]),
          Paint()
            ..color = _shade(
                side == IsoWall.left ? IsoColors.wallLeft : IsoColors.wallRight,
                -0.3));
    }
    final Offset corner = g.wallToScreen(IsoWall.left, 0, h);
    final Offset l = g.wallNormal(IsoWall.left) * -t;
    final Offset r = g.wallNormal(IsoWall.right) * -t;
    c.drawPath(
        _poly(<Offset>[corner, corner + l, corner + l + r, corner + r]), cap);
  }

  /// The door opening: dark inside, a lit threshold. The leaf (a picture)
  /// is drawn over it, set back by [isoDoorRecess]; the frame comes after.
  void _doorOpening(Canvas c, IsoGrid g) {
    final IsoFeature d = spec.door;
    final double u0 = d.u + 0.15, u1 = d.u + d.len - 0.15;
    c.drawPath(_poly(_wallQuad(g, d.side, u0, u1, 0, d.top)),
        Paint()..color = IsoColors.jamb);
    c.drawPath(
        _poly(<Offset>[
          _wp(g, d.side, u0, 0),
          _wp(g, d.side, u1, 0),
          _wp(g, d.side, u1, 0, -isoDoorRecess),
          _wp(g, d.side, u0, 0, -isoDoorRecess),
        ]),
        Paint()..color = _shade(IsoColors.floorB, -0.12));
  }

  /// The window, set into the wall: dark jambs, a lit inner sill, the glass
  /// at the back of the opening, a wooden frame and a sill sticking out
  /// into the room with a shadow under it.
  void _window(Canvas c, IsoGrid g) {
    final IsoFeature w = spec.window;
    final IsoWall side = w.side;
    final double u0 = w.u.toDouble(), u1 = (w.u + w.len).toDouble();
    final double lo = w.bottom, hi = w.top;
    const double r = _windowRecess;
    final Path opening = _poly(_wallQuad(g, side, u0, u1, lo, hi));
    c.drawPath(opening, Paint()..color = IsoColors.jamb);
    c.save();
    c.clipPath(opening);
    // Inner sill (faces up, lit).
    c.drawPath(
        _poly(<Offset>[
          _wp(g, side, u0, lo),
          _wp(g, side, u1, lo),
          _wp(g, side, u1, lo, -r),
          _wp(g, side, u0, lo, -r),
        ]),
        Paint()..color = _shade(IsoColors.wallRight, 0.25));
    // Glass at the back, with its cross.
    final Offset back = g.wallNormal(side) * -r;
    c.translate(back.dx, back.dy);
    _onWall(c, g, side, u0, u1 - u0, hi, hi - lo, (Canvas u) {
      const Rect glass = Rect.fromLTRB(0.04, 0.05, 0.96, 0.97);
      u.drawRect(
          glass,
          Paint()
            ..shader = ui.Gradient.linear(glass.topCenter, glass.bottomCenter,
                const <Color>[IsoColors.skyTop, IsoColors.skyLow]));
      u.drawRect(const Rect.fromLTRB(0.48, 0, 0.52, 1),
          Paint()..color = IsoColors.wood);
      u.drawRect(const Rect.fromLTRB(0, 0.47, 1, 0.52),
          Paint()..color = IsoColors.wood);
      // A pale streak of light on the glass.
      u.drawPath(
          Path()
            ..moveTo(0.12, 0.9)
            ..lineTo(0.3, 0.1)
            ..lineTo(0.38, 0.1)
            ..lineTo(0.2, 0.9)
            ..close(),
          Paint()..color = const Color(0x33FFFFFF));
    });
    c.restore();
    _casing(c, g, side, u0, u1, lo, hi, 0.08, 4, IsoColors.wood);
    _ledge(c, g, side, u0 - 0.14, u1 + 0.14, lo - 6, lo, _sillOut,
        _shade(IsoColors.wood, 0.1));
  }

  // The scene rebuilds only when something moved (walk, camera, arrange);
  // the shell is a few dozen paths, so it repaints with it.
  @override
  bool shouldRepaint(IsoShellPainter old) => true;
}

/// Frame of the door over the edges of its leaf: casing on the wall plane
/// and a sill board at the floor, in screen px ([offset] + content × [k]).
class IsoDoorFramePainter extends CustomPainter {
  const IsoDoorFramePainter(
      {required this.spec, required this.k, required this.offset});

  final IsoRoomSpec spec;
  final double k;
  final Offset offset;

  @override
  void paint(Canvas c, Size size) {
    final IsoGrid g = spec.grid;
    final IsoFeature d = spec.door;
    final double u0 = d.u + 0.15, u1 = d.u + d.len - 0.15;
    c.save();
    c.translate(offset.dx, offset.dy);
    c.scale(k);
    final Color wood = _shade(IsoColors.wood, -0.05);
    // Casing: sides and the head, no bottom (the floor is there).
    final Path ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addPolygon(_wallQuad(g, d.side, u0 - 0.1, u1 + 0.1, 0, d.top + 6), true)
      ..addPolygon(_wallQuad(g, d.side, u0, u1, 0, d.top), true);
    c.drawPath(ring, Paint()..color = wood);
    // The casing stands a little off the wall: its visible end edge.
    c.drawPath(
        _poly(<Offset>[
          _wp(g, d.side, u1 + 0.1, 0),
          _wp(g, d.side, u1 + 0.1, d.top + 6),
          _wp(g, d.side, u1 + 0.1, d.top + 6, 0.06),
          _wp(g, d.side, u1 + 0.1, 0, 0.06),
        ]),
        Paint()..color = _shade(wood, -0.3));
    c.drawPath(
        _poly(<Offset>[
          _wp(g, d.side, u0 - 0.1, d.top + 6),
          _wp(g, d.side, u1 + 0.1, d.top + 6),
          _wp(g, d.side, u1 + 0.1, d.top + 6, 0.06),
          _wp(g, d.side, u0 - 0.1, d.top + 6, 0.06),
        ]),
        Paint()..color = _shade(wood, 0.25));
    // Head shadow on the leaf.
    c.drawPath(_poly(_wallQuad(g, d.side, u0, u1, d.top - 8, d.top)),
        Paint()..color = const Color(0x2A000000));
    c.restore();
  }

  @override
  bool shouldRepaint(IsoDoorFramePainter old) =>
      old.k != k || old.offset != offset || old.spec != spec;
}

/// Stand-in for a thing without a picture: a wooden box (rug: a flat mat).
class IsoStubPainter extends CustomPainter {
  const IsoStubPainter(this.rug);
  final bool rug;

  @override
  void paint(Canvas c, Size s) {
    final Paint p = Paint()
      ..color = rug ? const Color(0xFFC85A4A) : IsoColors.wood;
    if (rug) {
      c.drawOval(Offset.zero & s, p);
    } else {
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(s.width * 0.15, s.height * 0.2, s.width * 0.7,
                  s.height * 0.8),
              const Radius.circular(4)),
          p);
    }
  }

  @override
  bool shouldRepaint(IsoStubPainter old) => old.rug != rug;
}

/// Door without a picture.
class IsoDoorPainter extends CustomPainter {
  const IsoDoorPainter();

  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = _shade(IsoColors.wood, -0.2));
    c.drawRect(
        Rect.fromLTRB(s.width * 0.1, s.height * 0.06, s.width * 0.9, s.height),
        Paint()..color = IsoColors.wood);
    c.drawCircle(Offset(s.width * 0.8, s.height * 0.55), s.width * 0.04,
        Paint()..color = IsoColors.gold);
  }

  @override
  bool shouldRepaint(IsoDoorPainter old) => false;
}

Path _ghostPath(IsoRoomSpec spec, IsoPlacement gh) {
  final IsoGrid g = spec.grid;
  final (double lo, double hi) = spec.bandOf(gh.spec.band);
  return gh.isWall
      ? _poly(_wallQuad(
          g, gh.side!, gh.u.toDouble(), gh.u + gh.spec.len.toDouble(), lo, hi))
      : _poly(g.footprint(gh.x.toDouble(), gh.y.toDouble(), gh.x1.toDouble(),
          gh.y1.toDouble()));
}

/// Outline of the drag ghost over everything (the fill is under the
/// furniture, in [IsoShellPainter]).
class IsoGhostPainter extends CustomPainter {
  const IsoGhostPainter({
    required this.spec,
    required this.k,
    required this.offset,
    required this.ghost,
    required this.ok,
  });

  final IsoRoomSpec spec;
  final double k;
  final Offset offset;
  final IsoPlacement ghost;
  final bool ok;

  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.translate(offset.dx, offset.dy);
    c.scale(k);
    final Color col = ok ? IsoColors.ok : IsoColors.bad;
    final Path p = _ghostPath(spec, ghost);
    if (!ok) c.drawPath(p, Paint()..color = col.withValues(alpha: 0.25));
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 / k * 1.2
          ..color = col);
    c.restore();
  }

  @override
  bool shouldRepaint(IsoGhostPainter old) =>
      old.ghost.spot != ghost.spot ||
      old.ok != ok ||
      old.k != k ||
      old.offset != offset;
}
