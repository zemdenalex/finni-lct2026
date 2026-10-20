/// Iso room (V2, flag `room.view: "iso"`): grid <-> screen projection.
///
/// Ported from room-lab A (`final/room-iso-demo-a`, `lib/roomlab/iso.dart`).
/// Projection is 2:1 dimetric, the same family as the city
/// (`features/world/city/city_geometry.dart`, tile 128x64). Sizes come from
/// `room_layout_iso.json`, not from code.
library;

import 'dart:ui';

/// Which back wall: left is the plane x = 0 (u runs along y), right is the
/// plane y = 0 (u runs along x).
enum IsoWall { left, right }

/// A point on a back wall: [u] cells along the wall from the back corner,
/// [h] logical px above the floor.
class IsoWallPoint {
  const IsoWallPoint(this.side, this.u, this.h);
  final IsoWall side;
  final double u;
  final double h;
}

/// Grid <-> content-space projection. Content space is the room's own logical
/// px before the camera scale; (0,0) is the top-left of the content box.
class IsoGrid {
  const IsoGrid({
    required this.cols,
    required this.rows,
    required this.tileW,
    required this.tileH,
    required this.wallH,
  });

  /// Floor size in cells: x runs along the right back wall, y along the left.
  final int cols;
  final int rows;

  /// Full diamond width and height of one floor cell, logical px.
  final double tileW;
  final double tileH;

  /// Height of the two back walls, logical px.
  final double wallH;

  double get halfW => tileW / 2;
  double get halfH => tileH / 2;

  /// Slots along a wall (one slot = one cell of floor edge).
  int wallLen(IsoWall side) => side == IsoWall.left ? rows : cols;

  /// Screen position of the floor's back corner (grid point 0,0).
  Offset get origin => Offset(rows * halfW, wallH);

  /// Size of the whole room drawing: floor diamond plus the walls above it.
  Size get contentSize =>
      Size((cols + rows) * halfW, wallH + (cols + rows) * halfH);

  /// Grid point (continuous cell units) -> content px.
  Offset toScreen(double x, double y) =>
      origin + Offset((x - y) * halfW, (x + y) * halfH);

  /// Content px -> continuous grid point (inverse of [toScreen]).
  ({double x, double y}) toGrid(Offset p) {
    final double u = (p.dx - origin.dx) / halfW;
    final double v = (p.dy - origin.dy) / halfH;
    return (x: (v + u) / 2, y: (v - u) / 2);
  }

  /// Floor cell under a content point, or null outside the floor.
  (int, int)? cellAt(Offset p) {
    final ({double x, double y}) g = toGrid(p);
    final int cx = g.x.floor();
    final int cy = g.y.floor();
    if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) return null;
    return (cx, cy);
  }

  /// Centre of a floor cell in content px.
  Offset cellCenter(int cx, int cy) => toScreen(cx + 0.5, cy + 0.5);

  /// The four corners of a footprint [x0,x1)x[y0,y1): top, right, bottom, left.
  List<Offset> footprint(double x0, double y0, double x1, double y1) =>
      <Offset>[
        toScreen(x0, y0),
        toScreen(x1, y0),
        toScreen(x1, y1),
        toScreen(x0, y1),
      ];

  /// Bounding box of a footprint on screen.
  Rect footprintRect(double x0, double y0, double x1, double y1) =>
      Rect.fromLTRB(
        toScreen(x0, y1).dx,
        toScreen(x0, y0).dy,
        toScreen(x1, y0).dx,
        toScreen(x1, y1).dy,
      );

  /// Wall point -> content px.
  Offset wallToScreen(IsoWall side, double u, double h) {
    final Offset base = side == IsoWall.left ? toScreen(0, u) : toScreen(u, 0);
    return base.translate(0, -h);
  }

  /// One cell of depth off [side] toward the room, content px: the left
  /// wall faces +x, the right wall faces +y. Negative — into the wall.
  Offset wallNormal(IsoWall side) =>
      side == IsoWall.left ? Offset(halfW, halfH) : Offset(-halfW, halfH);

  /// Content px -> wall point, or null if the point is not on a wall face.
  IsoWallPoint? wallAt(Offset p) {
    for (final IsoWall side in IsoWall.values) {
      final double u = side == IsoWall.left
          ? (origin.dx - p.dx) / halfW
          : (p.dx - origin.dx) / halfW;
      final int len = wallLen(side);
      if (u < 0 || u > len) continue;
      final double baseY = origin.dy + u * halfH;
      final double h = baseY - p.dy;
      if (h >= 0 && h <= wallH) return IsoWallPoint(side, u, h);
    }
    return null;
  }
}
