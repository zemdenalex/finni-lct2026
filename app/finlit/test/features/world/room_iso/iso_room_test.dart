import 'dart:io';
import 'dart:math' as math;

import 'package:finlit/domain/world/room_grid.dart';
import 'package:finlit/features/world/home/room_skins.dart';
import 'package:finlit/features/world/room_iso/iso_grid.dart';
import 'package:finlit/features/world/room_iso/iso_room.dart';
import 'package:flutter_test/flutter_test.dart';

/// Iso room (V2): projection, placement rules, the resolver of saved spots
/// and the path. Ported from room-lab A (test/roomlab/room_model_test.dart)
/// onto the game's data file `room_layout_iso.json`.

/// The 11 places that hold things a child can already own: 8 decor places
/// (`decorPlace` in room_scene.dart) and 3 skin places (`skinSlots`). Written
/// out here, not read from the iso file: a place deleted from the file must
/// fail this test, not shrink the expectation.
const List<String> boughtSlots = <String>[
  'decor_wall',
  'decor_floor',
  'decor_ceiling',
  'item_sill',
  'decor_books',
  'decor_globe',
  'decor_bear',
  'decor_rug',
  'bed',
  'desk_chair',
  'bedside_cabinet',
];

IsoRoomSpec _spec() => IsoRoomSpec.parse(
    File('assets/content/world/room_layout_iso.json').readAsStringSync());

void main() {
  final IsoRoomSpec spec = _spec();
  final IsoGrid grid = spec.grid;

  test('копия в сборке совпадает с content/room_layout_iso.json', () {
    expect(File('assets/content/world/room_layout_iso.json').readAsStringSync(),
        File('../../content/room_layout_iso.json').readAsStringSync());
  });

  test('у iso-раскладки есть все места фронтальной: 8 декора и 3 скина', () {
    // Independent source: the skin table of the game.
    expect(skinSlots.values.toSet().difference(boughtSlots.toSet()), isEmpty);
    for (final String id in boughtSlots) {
      expect(spec.slots.containsKey(id), isTrue, reason: id);
    }
    // Every place the domain lets move is described in the file.
    expect(roomIsoSlots.difference(spec.slots.keys.toSet()), isEmpty);
  });

  test('defaults: all places of the file fit the room together', () {
    final IsoArrangement a = IsoArrangement.resolve(
        spec, spec.slots.keys, const <String, RoomIsoSpot>{});
    expect(a.placed.keys.toSet(), spec.slots.keys.toSet());
    for (final IsoPlacement p in a.placed.values) {
      expect(p.spot, p.spec.home, reason: '${p.id} moved off its default');
    }
    // Finni's home cell is free and the door is reachable from it.
    final Set<(int, int)> blocked = a.blockedCells();
    final (int, int) home = (spec.finniX, spec.finniY);
    expect(blocked.contains(home), isFalse);
    expect(
        isoPath(home, (0, spec.door.u), blocked,
            cols: grid.cols, rows: grid.rows),
        isNotNull);
  });

  group('projection', () {
    test('every cell centre maps to the screen and back to the same cell', () {
      for (int x = 0; x < grid.cols; x++) {
        for (int y = 0; y < grid.rows; y++) {
          expect(grid.cellAt(grid.cellCenter(x, y)), (x, y));
        }
      }
    });

    test('points near a cell corner stay in their own cell (floor, not round)',
        () {
      expect(grid.cellAt(grid.toScreen(3.1, 4.1)), (3, 4));
      expect(grid.cellAt(grid.toScreen(3.9, 4.9)), (3, 4));
      expect(grid.cellAt(grid.toScreen(-0.1, 2)), isNull);
      expect(grid.cellAt(grid.toScreen(grid.cols + 0.05, 2)), isNull);
    });

    test('2:1 diamond: one step in x is +halfW, +halfH on screen', () {
      final Offset a = grid.toScreen(2, 2);
      expect(grid.toScreen(3, 2) - a, Offset(grid.tileW / 2, grid.tileH / 2));
      expect(grid.toScreen(2, 3) - a, Offset(-grid.tileW / 2, grid.tileH / 2));
    });

    test('wall points map back to the same wall, slot and height', () {
      for (final IsoWall side in IsoWall.values) {
        for (double u = 0.5; u < grid.wallLen(side); u += 1) {
          final IsoWallPoint? w = grid.wallAt(grid.wallToScreen(side, u, 70));
          expect(w?.side, side);
          expect(w!.u, closeTo(u, 1e-9));
          expect(w.h, closeTo(70, 1e-9));
        }
      }
      expect(grid.wallAt(grid.cellCenter(3, 3)), isNull);
    });
  });

  group('rules', () {
    IsoPlacement floor(String id, int x, int y) =>
        IsoPlacement.floor(spec.slots[id]!, x, y);
    IsoPlacement wall(String id, IsoWall s, int u) =>
        IsoPlacement.wall(spec.slots[id]!, s, u);

    test('outside the floor is refused on every side', () {
      final IsoArrangement a = IsoArrangement(spec);
      expect(a.check(floor('bed', grid.cols - 1, 0)), IsoBlock.outside);
      expect(a.check(floor('bed', grid.cols - 2, grid.rows - 1)), IsoBlock.ok);
      expect(a.check(floor('bed', -1, 3)), IsoBlock.outside);
      expect(a.check(floor('bed', 2, grid.rows)), IsoBlock.outside);
    });

    test('furniture cannot overlap furniture, but may stand on a rug', () {
      final IsoArrangement a = IsoArrangement(spec)
        ..placed['bed'] = floor('bed', 2, 2)
        ..placed['decor_rug'] = floor('decor_rug', 0, 4);
      expect(a.check(floor('decor_globe', 3, 2)), IsoBlock.overlap);
      expect(a.check(floor('decor_globe', 4, 2)), IsoBlock.ok);
      expect(a.check(floor('decor_globe', 1, 5)), IsoBlock.ok); // on the rug
      expect(a.check(floor('bed', 3, 2)), IsoBlock.ok); // itself, moved
    });

    test('the hero cell is refused for furniture but not for a rug', () {
      final IsoArrangement a = IsoArrangement(spec);
      expect(a.check(floor('decor_bear', 4, 4), hero: <(int, int)>{(4, 4)}),
          IsoBlock.hero);
      expect(a.check(floor('decor_rug', 3, 3), hero: <(int, int)>{(4, 4)}),
          IsoBlock.ok);
    });

    test(
        'wall things stay off the door and the window; sill only in the window',
        () {
      final IsoArrangement a = IsoArrangement(spec);
      final IsoFeature door = spec.door, win = spec.window;
      expect(a.check(wall('decor_wall', door.side, door.u)), IsoBlock.feature);
      expect(a.check(wall('decor_ceiling', win.side, win.u)), IsoBlock.feature);
      expect(a.check(wall('item_sill', win.side, win.u)), IsoBlock.ok);
      expect(a.check(wall('item_sill', win.side, win.u + win.len)),
          IsoBlock.feature);
      expect(a.check(wall('decor_ceiling', IsoWall.left, grid.rows)),
          IsoBlock.outside);
      a.placed['decor_wall'] = wall('decor_wall', IsoWall.left, 0);
      expect(a.check(wall('decor_ceiling', IsoWall.left, 1)), IsoBlock.overlap);
    });
  });

  group('resolver of saved spots', () {
    test('a valid saved spot wins over the default', () {
      final IsoArrangement a = IsoArrangement.resolve(spec, boughtSlots,
          <String, RoomIsoSpot>{'decor_globe': (plane: 'floor', x: 3, y: 4)});
      expect(a.placed['decor_globe']!.spot, (plane: 'floor', x: 3, y: 4));
    });

    test('broken saves keep every bought place in the room', () {
      final Map<String, RoomIsoSpot> bad = <String, RoomIsoSpot>{
        'decor_globe': (plane: 'floor', x: 40, y: 1), // bigger old room
        'decor_bear': (plane: 'floor', x: 9, y: 9), // outside
        'decor_wall': (plane: 'floor', x: 1, y: 1), // wall thing on the floor
        'item_sill': (plane: 'left', x: 0, y: 0), // sill off the window
        'decor_books': (plane: 'right', x: 2, y: 0), // floor thing on a wall
        'nonsense': (plane: 'floor', x: 1, y: 1),
      };
      final IsoArrangement a = IsoArrangement.resolve(spec, boughtSlots, bad);
      expect(a.placed.keys.toSet(), boughtSlots.toSet());
      for (final IsoPlacement p in a.placed.values) {
        final IsoArrangement others = IsoArrangement(spec)
          ..placed.addAll(a.placed);
        expect(others.check(p), IsoBlock.ok, reason: p.id);
      }
      expect(a.placed['decor_globe']!.spot, spec.slots['decor_globe']!.home);
    });

    test('a saved spot on a default place pushes that place to a free cell',
        () {
      // The globe is moved onto the bear's default cell: the bear still gets
      // a place.
      final IsoSlotSpec bear = spec.slots['decor_bear']!;
      final IsoArrangement a = IsoArrangement.resolve(
          spec, boughtSlots, <String, RoomIsoSpot>{
        'decor_globe': (plane: 'floor', x: bear.x, y: bear.y)
      });
      expect(a.placed['decor_globe']!.spot, bear.home);
      expect(a.placed['decor_bear'], isNotNull);
      expect(a.placed['decor_bear']!.spot, isNot(bear.home));
    });
  });

  // Joystick on the iso floor (finni 20.10: 0.1.3 had it). Would fail on:
  // feet entering furniture or leaving the floor, a blocked step that does
  // not slide along the wall, «up» on the screen not leading into the room.
  group('joystick', () {
    final IsoArrangement a = IsoArrangement.resolve(
        spec, spec.slots.keys, const <String, RoomIsoSpot>{});
    const double r = 0.25;

    test('a step into the bed stops at its edge, a step off the floor too', () {
      final IsoPlacement bed = a.placed['bed']!;
      final ({double x, double y}) at = (x: bed.x + 1.5, y: bed.y1 + 0.5);
      final ({double x, double y}) got =
          isoSlide(a, at, (x: at.x, y: bed.y1 - 0.2), r);
      expect(got, at, reason: 'в кровать не заходит');
      final ({double x, double y}) edge =
          isoSlide(a, (x: 5.5, y: 3.5), (x: grid.cols + 0.3, y: 3.5), r);
      expect(edge, (x: 5.5, y: 3.5), reason: 'за пол не выходит');
    });

    test('a blocked diagonal slides along the free axis', () {
      // From the middle toward the back corner: y is blocked by the bed row,
      // x still moves.
      final IsoPlacement bed = a.placed['bed']!;
      final ({double x, double y}) at = (x: 1.5, y: bed.y1 + r + 0.01);
      final ({double x, double y}) got =
          isoSlide(a, at, (x: 1.3, y: bed.y1.toDouble()), r);
      expect(got.x, closeTo(1.3, 1e-9));
      expect(got.y, at.y);
    });

    test('up on the screen is into the room, right is along x', () {
      final ({double x, double y}) up = isoStickDir(grid, const Offset(0, -1));
      expect(up.x, lessThan(0));
      expect(up.y, lessThan(0));
      final ({double x, double y}) right =
          isoStickDir(grid, const Offset(1, 0));
      expect(right.x, greaterThan(0));
      expect(right.y, lessThan(0));
      expect(math.sqrt(up.x * up.x + up.y * up.y), closeTo(1, 1e-9));
    });

    test('next to the bed the bed is near; in the middle nothing', () {
      final IsoPlacement bed = a.placed['bed']!;
      expect(
          isoNearThing(spec, a, (x: bed.x + 1.5, y: bed.y1 + 0.3),
              <String>['bed', 'fridge', 'door']),
          'bed');
      expect(isoNearThing(spec, a, (x: 3.5, y: 3.5), <String>['bed', 'door']),
          isNull);
      expect(
          isoNearThing(
              spec, a, (x: 0.3, y: spec.door.u + 1.0), <String>['door']),
          'door');
    });
  });

  group('path', () {
    test('walks around furniture with 4-connected steps', () {
      final Set<(int, int)> blocked = <(int, int)>{
        for (int y = 0; y < 4; y++) (2, y),
      };
      final List<(int, int)> path =
          isoPath((0, 0), (4, 0), blocked, cols: 6, rows: 6)!;
      expect(path.last, (4, 0));
      (int, int) at = (0, 0);
      for (final (int, int) c in path) {
        expect(blocked.contains(c), isFalse);
        expect((c.$1 - at.$1).abs() + (c.$2 - at.$2).abs(), 1);
        at = c;
      }
      expect(path.length, 12);
    });

    test('unreachable or blocked target gives no path', () {
      final Set<(int, int)> wall = <(int, int)>{
        for (int y = 0; y < 6; y++) (3, y)
      };
      expect(isoPath((0, 0), (5, 5), wall, cols: 6, rows: 6), isNull);
      expect(isoPath((0, 0), (3, 1), wall, cols: 6, rows: 6), isNull);
      expect(isoPath((0, 0), (9, 1), const <(int, int)>{}, cols: 6, rows: 6),
          isNull);
      expect(isoPath((1, 1), (1, 1), const <(int, int)>{}, cols: 6, rows: 6),
          isEmpty);
    });

    test('Finni stands on a free cell next to each default place', () {
      final IsoArrangement a = IsoArrangement.resolve(
          spec, spec.slots.keys, const <String, RoomIsoSpot>{});
      final Set<(int, int)> blocked = a.blockedCells();
      for (final IsoPlacement p in a.placed.values) {
        final (int, int)? c = isoStandCell(a, p, (spec.finniX, spec.finniY));
        expect(c, isNotNull, reason: p.id);
        expect(blocked.contains(c), isFalse, reason: p.id);
      }
    });
  });
}
