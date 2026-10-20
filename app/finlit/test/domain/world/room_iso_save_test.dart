import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/content_loader.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Iso-комната (V2): перестановка — тот же `roomItemPlaced`, но с `plane`.
///
/// Защищает: запись iso живёт в своей карте ([ResourceSnapshot.roomIso]) и
/// переживает перезапуск; фронтальная сетка (`roomPlaced`) её не видит —
/// на этом держится откат флагом `room.view: "front"`. Уронит: свёртка
/// журнала кладёт iso в `roomPlaced` или теряет `plane`.

Future<String> _read(String path) => File(path).readAsString();

/// The shipped files with `room.view` set to [view] and the room shop on
/// (`room.customize`), so the front grid gets a record of its own.
ReadAsset _readAs(String view) => (String path) async {
      final String text = await File(path).readAsString();
      if (!path.endsWith('economy.json')) return text;
      final Map<String, Object?> eco = jsonDecode(text) as Map<String, Object?>;
      eco['room'] = <String, Object?>{
        ...(eco['room']! as Map<String, Object?>),
        'view': view,
        'customize': true,
      };
      return jsonEncode(eco);
    };

Directory _dir() {
  final Directory d = Directory.systemTemp.createTempSync('finlit_iso_');
  addTearDown(() {
    try {
      d.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows держит файл хранилища до конца процесса.
    }
  });
  return d;
}

void main() {
  test('iso-место: своя карта, фронтальная сетка пустая, отказ — без записи',
      () {
    final WorldGame w = contentWorld();
    expect(w.placeRoomIso('decor_globe', 'floor', 3, 4).ok, isTrue);
    expect(w.placeRoomIso('decor_wall', 'left', 0, 0).ok, isTrue);
    expect(w.snapshot.roomIso, <String, RoomIsoSpot>{
      'decor_globe': (plane: 'floor', x: 3, y: 4),
      'decor_wall': (plane: 'left', x: 0, y: 0),
    });
    expect(w.snapshot.roomPlaced, isEmpty);
    final int n = w.journal.length;
    expect(w.placeRoomIso('sofa', 'floor', 1, 1).ok, isFalse);
    expect(w.placeRoomIso('decor_bear', 'ceiling', 1, 1).ok, isFalse);
    expect(w.placeRoomIso('decor_bear', 'floor', -1, 1).ok, isFalse);
    expect(w.journal.length, n, reason: 'отказ не пишет в журнал');
  });

  test('после перезапуска iso-места на местах', () async {
    final Directory dir = _dir();
    final SavedWorld first =
        await openSavedWorld(read: _read, storage: FileStorage(dir));
    final WorldGame w = first.world;
    expect(w.placeRoomIso('bed', 'floor', 1, 3).ok, isTrue);
    expect(w.placeRoomIso('bed', 'floor', 2, 4).ok, isTrue); // передвинули
    await first.flush();
    final SavedWorld again =
        await openSavedWorld(read: _read, storage: FileStorage(dir));
    expect(again.world.snapshot.roomIso,
        <String, RoomIsoSpot>{'bed': (plane: 'floor', x: 2, y: 4)});
    expect(again.world.snapshot.roomPlaced, isEmpty);
  });

  // Rollback by the flag (финал 20.10): the save is one journal for both
  // views. Would fail on: an iso move folded into the front grid (or the
  // other way), a purchase that the other view drops, a skin choice lost.
  test(
      'сейв фронтальной комнаты открывается в iso и обратно — ничего не '
      'пропадает', () async {
    final Directory dir = _dir();
    final SavedWorld front =
        await openSavedWorld(read: _readAs('front'), storage: FileStorage(dir));
    expect(front.config.room.iso, isFalse, reason: 'настройка');
    final WorldGame w = front.world;
    expect(w.startWeek().ok, isTrue);
    expect(w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0).ok, isTrue);
    const List<String> buy = <String>[
      'decor_books',
      'skin_cabinet__19a',
    ];
    for (int i = 0; i < 40 && w.snapshot.want + w.snapshot.free < 800; i++) {
      w.completeJob('consultant', score: 1);
    }
    for (final String id in buy) {
      expect(w.buy(id).ok, isTrue, reason: id);
    }
    expect(w.buyRoomItem('room_toybox').ok, isTrue);
    expect(w.placeRoomItem('room_toybox', 2, 4).ok, isTrue);
    await front.flush();
    final ResourceSnapshot was = w.snapshot;
    expect(was.owned, containsAll(buy), reason: 'настройка');

    // Open the same save as iso: everything bought is there, the front
    // grid's record is kept untouched, iso has nothing moved yet.
    final SavedWorld iso =
        await openSavedWorld(read: _readAs('iso'), storage: FileStorage(dir));
    expect(iso.config.room.iso, isTrue, reason: 'настройка');
    final ResourceSnapshot a = iso.world.snapshot;
    expect(a.owned, was.owned);
    expect((a.free, a.want, a.saved), (was.free, was.want, was.saved));
    expect(a.roomOwned, was.roomOwned);
    expect(a.roomPlaced, <String, RoomCell>{'room_toybox': (x: 2, y: 4)});
    expect(a.roomIso, isEmpty);
    expect(iso.world.placeRoomIso('decor_books', 'floor', 4, 3).ok, isTrue);
    expect(iso.world.placeRoomIso('bedside_cabinet', 'floor', 5, 5).ok, isTrue);
    await iso.flush();

    // Back to front: the front grid is as it was, the iso moves are kept
    // for the next time iso is on.
    final SavedWorld back =
        await openSavedWorld(read: _readAs('front'), storage: FileStorage(dir));
    final ResourceSnapshot b = back.world.snapshot;
    expect(b.owned, was.owned);
    expect((b.free, b.want, b.saved), (was.free, was.want, was.saved));
    expect(b.chosenSkins, was.chosenSkins);
    expect(b.roomPlaced, <String, RoomCell>{'room_toybox': (x: 2, y: 4)});
    expect(b.roomIso, <String, RoomIsoSpot>{
      'decor_books': (plane: 'floor', x: 4, y: 3),
      'bedside_cabinet': (plane: 'floor', x: 5, y: 5),
    });

    // And iso once more: the moves are where the child left them.
    final SavedWorld again =
        await openSavedWorld(read: _readAs('iso'), storage: FileStorage(dir));
    expect(again.world.snapshot.roomIso, b.roomIso);
    expect(again.world.snapshot.owned, was.owned);
  });
}
