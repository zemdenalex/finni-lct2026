/// Iso room: draw order of everything standing on the floor.
///
/// Ported from room-lab A (`lib/roomlab/depth.dart`). Scheme from
/// `docs/final/room-iso-razbor.md` §6:
/// 1. One scale: every object is a footprint box [x0,x1) x [y0,y1) in
///    continuous cell units. Finni and a pet are small boxes around the feet.
/// 2. Axis test: sx = +1 if a.x0 >= b.x1, -1 if b.x0 >= a.x1, else 0; same
///    for sy. `a` is in front of `b` when sx + sy > 0.
/// 3. A pair is compared only when their screen intervals on (x - y) overlap
///    strictly.
/// 4. Order = edges "b before a" + Kahn's topological sort with a fixed
///    tie-break (x0 + y0, then id). Not `List.sort` with a non-transitive
///    comparator.
/// 5. Disjoint footprints on one floor have no cycles (Guibas–Yao). If a
///    cycle still appears (bad input), it is broken by the tie-break and
///    reported through [IsoDepthResult.hadCycle].
library;

class IsoBox {
  const IsoBox(this.id, this.x0, this.y0, this.x1, this.y1);

  /// Box of a point-like mover (Finni, a pet) standing at (fx, fy).
  factory IsoBox.mover(String id, double fx, double fy, double r) =>
      IsoBox(id, fx - r, fy - r, fx + r, fy + r);

  final String id;
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  /// Screen interval along x - y (proportional to screen x).
  double get lo => x0 - y1;
  double get hi => x1 - y0;

  @override
  String toString() => '$id[$x0,$x1)x[$y0,$y1)';
}

int _axis(double aLo, double aHi, double bLo, double bHi) {
  if (aLo >= bHi) return 1;
  if (bLo >= aHi) return -1;
  return 0;
}

/// True when the two boxes can overlap on screen (strict: touching is not).
bool isoScreenOverlap(IsoBox a, IsoBox b) => a.lo < b.hi && b.lo < a.hi;

/// +1: a is drawn after b (in front); -1: b in front; 0: no constraint.
int isoFrontOf(IsoBox a, IsoBox b) {
  if (!isoScreenOverlap(a, b)) return 0;
  final int s = _axis(a.x0, a.x1, b.x0, b.x1) + _axis(a.y0, a.y1, b.y0, b.y1);
  return s > 0 ? 1 : (s < 0 ? -1 : 0);
}

int _tie(IsoBox a, IsoBox b) {
  final int k = (a.x0 + a.y0).compareTo(b.x0 + b.y0);
  return k != 0 ? k : a.id.compareTo(b.id);
}

class IsoDepthResult {
  const IsoDepthResult(this.order, this.hadCycle);

  /// Back to front: draw in this order.
  final List<IsoBox> order;
  final bool hadCycle;
}

/// Back-to-front order of [boxes]. O(n^2) pairs; a room has < 30 objects.
IsoDepthResult isoDepthOrder(List<IsoBox> boxes) {
  final int n = boxes.length;
  final List<List<int>> after = List<List<int>>.generate(n, (_) => <int>[]);
  final List<int> indeg = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      final int f = isoFrontOf(boxes[i], boxes[j]);
      if (f > 0) {
        after[j].add(i);
        indeg[i]++;
      } else if (f < 0) {
        after[i].add(j);
        indeg[j]++;
      }
    }
  }
  final List<bool> done = List<bool>.filled(n, false);
  final List<IsoBox> out = <IsoBox>[];
  bool cycle = false;
  while (out.length < n) {
    int pick = -1;
    for (int i = 0; i < n; i++) {
      if (done[i] || indeg[i] != 0) continue;
      if (pick < 0 || _tie(boxes[i], boxes[pick]) < 0) pick = i;
    }
    if (pick < 0) {
      // Cycle: take the best remaining node by the tie-break.
      cycle = true;
      for (int i = 0; i < n; i++) {
        if (done[i]) continue;
        if (pick < 0 || _tie(boxes[i], boxes[pick]) < 0) pick = i;
      }
    }
    done[pick] = true;
    out.add(boxes[pick]);
    for (final int k in after[pick]) {
      indeg[k]--;
    }
  }
  return IsoDepthResult(out, cycle);
}
