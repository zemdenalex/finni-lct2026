import 'dart:math';

import 'package:finlit/features/world/room_iso/iso_depth.dart';
import 'package:flutter_test/flutter_test.dart';

// Depth order of the iso room (V2). Cases T1–T6 come from
// the team room-iso design notes, section 6; each one fails on a known wrong
// rule (asymmetric inFront, single x1+y1 key, flipped axis sign, tie-break).
// Ported from room-lab A (test/roomlab/depth_test.dart).

IsoBox box(String id, int x0, int x1, int y0, int y1) =>
    IsoBox(id, x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble());

List<String> ids(List<IsoBox> boxes) =>
    isoDepthOrder(boxes).order.map((IsoBox b) => b.id).toList();

const double r = 0.25;

void main() {
  test(
      'T1: boxes separated in opposite directions get no edge; order is the tie-break, both ways',
      () {
    final IsoBox a = box('a', 1, 2, 0, 1);
    final IsoBox b = box('b', 0, 1, 5, 6);
    expect(isoFrontOf(a, b), 0);
    expect(isoFrontOf(b, a), 0);
    expect(ids(<IsoBox>[a, b]), <String>['a', 'b']);
    expect(ids(<IsoBox>[b, a]), <String>['a', 'b']);
  });

  test(
      'T2: long box behind a short one: b after a (single x1+y1 key would say a after b)',
      () {
    final IsoBox a = box('a', 0, 1, 0, 3);
    final IsoBox b = box('b', 1, 2, 0, 1);
    expect(isoFrontOf(b, a), 1);
    expect(isoFrontOf(a, b), -1);
    expect(ids(<IsoBox>[b, a]), <String>['a', 'b']);
    expect(ids(<IsoBox>[a, b]), <String>['a', 'b']);
  });

  test('T3: Finni in front of the sofa long side is drawn after it', () {
    final IsoBox sofa = box('sofa', 0, 3, 0, 1);
    final IsoBox finni = IsoBox.mover('finni', 0.5, 1.4, r);
    expect(ids(<IsoBox>[finni, sofa]), <String>['sofa', 'finni']);
  });

  test('T4: Finni at the sofa end is drawn after it', () {
    final IsoBox sofa = box('sofa', 0, 3, 0, 1);
    final IsoBox finni = IsoBox.mover('finni', 3.3, 0.5, r);
    expect(ids(<IsoBox>[finni, sofa]), <String>['sofa', 'finni']);
  });

  test('T5: Finni behind the sofa is drawn before it', () {
    final IsoBox sofa = box('sofa', 0, 3, 2, 3);
    final IsoBox finni = IsoBox.mover('finni', 2.5, 1.5, r);
    expect(ids(<IsoBox>[sofa, finni]), <String>['finni', 'sofa']);
  });

  test('pinwheel of four boxes around an empty cell has one valid order', () {
    final IsoBox a = box('a', 0, 2, 0, 1);
    final IsoBox b = box('b', 2, 3, 0, 2);
    final IsoBox c = box('c', 1, 3, 2, 3);
    final IsoBox d = box('d', 0, 1, 1, 3);
    final IsoDepthResult res = isoDepthOrder(<IsoBox>[c, d, b, a]);
    expect(res.hadCycle, isFalse);
    expect(res.order.map((IsoBox x) => x.id).toList(),
        <String>['a', 'd', 'b', 'c']);
  });

  test('three boxes around a corner: order respects every edge', () {
    final IsoBox wardrobe = box('w', 0, 1, 0, 3);
    final IsoBox bed = box('b', 1, 3, 0, 1);
    final IsoBox chair = box('c', 1, 2, 1, 2);
    final List<String> got = ids(<IsoBox>[chair, bed, wardrobe]);
    expect(got.indexOf('w') < got.indexOf('b'), isTrue);
    expect(got.indexOf('w') < got.indexOf('c'), isTrue);
    expect(got.indexOf('b') < got.indexOf('c'), isTrue);
  });

  test('T6: every pair of footprints 1x1..3x3 on a 6x6 floor is antisymmetric',
      () {
    final List<IsoBox> all = <IsoBox>[];
    for (int w = 1; w <= 3; w++) {
      for (int d = 1; d <= 3; d++) {
        if (w * d > 6) continue;
        for (int x = 0; x + w <= 6; x++) {
          for (int y = 0; y + d <= 6; y++) {
            all.add(box('$w$d@$x,$y', x, x + w, y, y + d));
          }
        }
      }
    }
    bool disjoint(IsoBox a, IsoBox b) =>
        a.x0 >= b.x1 || b.x0 >= a.x1 || a.y0 >= b.y1 || b.y0 >= a.y1;
    int pairs = 0;
    for (final IsoBox a in all) {
      for (final IsoBox b in all) {
        if (identical(a, b) || !disjoint(a, b)) continue;
        expect(isoFrontOf(a, b), -isoFrontOf(b, a), reason: '$a vs $b');
        pairs++;
      }
    }
    expect(pairs, greaterThan(10000));
  });

  test(
      'T6: random floors with Finni boxes sort without cycles and respect every edge',
      () {
    final Random rnd = Random(6);
    for (int run = 0; run < 400; run++) {
      final List<List<bool>> taken =
          List<List<bool>>.generate(6, (_) => List<bool>.filled(6, false));
      final List<IsoBox> boxes = <IsoBox>[];
      for (int k = 0; k < 14; k++) {
        final int w = 1 + rnd.nextInt(3);
        final int d = 1 + rnd.nextInt(2);
        final bool swap = rnd.nextBool();
        final int fw = swap ? d : w;
        final int fd = swap ? w : d;
        final int x = rnd.nextInt(7 - fw);
        final int y = rnd.nextInt(7 - fd);
        bool free = true;
        for (int i = x; i < x + fw; i++) {
          for (int j = y; j < y + fd; j++) {
            free = free && !taken[i][j];
          }
        }
        if (!free) continue;
        for (int i = x; i < x + fw; i++) {
          for (int j = y; j < y + fd; j++) {
            taken[i][j] = true;
          }
        }
        boxes.add(box('i$k', x, x + fw, y, y + fd));
      }
      int movers = 0;
      for (int i = 0; i < 6 && movers < 2; i++) {
        for (int j = 0; j < 6 && movers < 2; j++) {
          if (taken[i][j] || rnd.nextInt(4) != 0) continue;
          boxes.add(IsoBox.mover('m$movers', i + 0.25 + rnd.nextDouble() * 0.5,
              j + 0.25 + rnd.nextDouble() * 0.5, r));
          movers++;
        }
      }
      final IsoDepthResult res = isoDepthOrder(boxes);
      expect(res.hadCycle, isFalse, reason: 'run $run: $boxes');
      expect(res.order.length, boxes.length);
      final Map<String, int> at = <String, int>{
        for (int i = 0; i < res.order.length; i++) res.order[i].id: i,
      };
      for (final IsoBox a in boxes) {
        for (final IsoBox b in boxes) {
          if (isoFrontOf(a, b) > 0) {
            expect(at[a.id]! > at[b.id]!, isTrue,
                reason: 'run $run: $a must be after $b');
          }
        }
      }
    }
  });
}
