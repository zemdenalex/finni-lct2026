import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Кастомизация комнаты на сетке (каркас 17.10): покупка вещи комнаты по
/// общему счёту покупок, расстановка по правилам сетки, журнал.
///
/// Сетка и вещи — настоящие, из `room_items.json` сборки: ящик с игрушками
/// 2 × 1 на пол, часы 1 × 1 на стену; пол в рядах 3–5.

/// Неделя идёт, все карманные — в «Хочу».
WorldGame _living() {
  final WorldGame w = WorldGame(config: roomOnConfig)..startWeek();
  w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
  expect(w.phase, WeekPhase.living);
  return w;
}

/// Смены, пока «Хочу» и заработка не хватит на [coins].
WorldGame _rich(int coins) {
  final WorldGame w = _living();
  for (int i = 0; i < 20 && w.snapshot.want + w.snapshot.free < coins; i++) {
    w.completeJob('consultant', score: 1);
    if (w.phase != WeekPhase.living) break;
  }
  expect(w.snapshot.want + w.snapshot.free, greaterThanOrEqualTo(coins),
      reason: 'настройка: денег на покупки');
  return w;
}

WorldGame _withItems(List<String> ids) {
  final WorldGame w0 = WorldGame(config: roomOnConfig);
  final int sum =
      ids.fold<int>(0, (int a, String id) => a + w0.room.item(id)!.price);
  final WorldGame w = _rich(sum);
  for (final String id in ids) {
    final WorldResult r = w.buyRoomItem(id);
    expect(r.ok, isTrue, reason: 'настройка: ${r.reason}');
  }
  return w;
}

Directory _dir() {
  final Directory d = Directory.systemTemp.createTempSync('finlit_room_');
  addTearDown(() {
    try {
      d.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows держит файл хранилища до конца процесса.
    }
  });
  return d;
}

/// Файлы сборки, но с включённой кастомизацией (в сборке флаг выключен).
Future<String> _read(String path) async {
  final String s = await File(path).readAsString();
  return path.endsWith('economy.json') ? roomCustomizeOn(s) : s;
}

void main() {
  test('данные: вещи и сетка из room_items.json, флаг выключен', () {
    final RoomCatalog c = contentWorld().room;
    expect(c.enabled, isFalse, reason: 'по умолчанию всё как раньше');
    expect(c.items.length, inInclusiveRange(6, 8));
    for (final RoomItemSpec i in c.items) {
      expect(File(i.sprite).existsSync(), isTrue, reason: i.sprite);
    }
  });

  // Уронит: проверка пересечения пропускает чужую вещь — две вещи в одной
  // клетке. Откат: цикл по `placed` в roomPlaceBlock.
  test('пересечение отклоняется, журнал не меняется', () {
    final WorldGame w = _withItems(<String>['room_toybox', 'room_armchair']);
    expect(w.placeRoomItem('room_toybox', 2, 4).ok, isTrue); // (2,4) и (3,4)
    final int before = w.journal.length;
    final WorldResult r = w.placeRoomItem('room_armchair', 3, 4);
    expect(r.ok, isFalse);
    expect(r.reasonCode, 'room.busy');
    expect(r.reason, contains('Ящик с игрушками'));
    expect(w.journal.length, before);
    expect(w.snapshot.roomPlaced.containsKey('room_armchair'), isFalse);
    // Своё прежнее место не мешает передвинуть вещь на клетку.
    expect(w.placeRoomItem('room_toybox', 2, 5).ok, isTrue);
  });

  // Уронит: вещь шире одной клетки вылезает за край сетки. Откат: проверка
  // границ в roomPlaceBlock (без неё отказ был бы «не то место», не «out»).
  test('выход за границу сетки отклоняется', () {
    final WorldGame w = _withItems(<String>['room_toybox']);
    final int before = w.journal.length;
    for (final (int x, int y) in <(int, int)>[(4, 3), (-1, 3), (2, 6)]) {
      final WorldResult r = w.placeRoomItem('room_toybox', x, y);
      expect(r.reasonCode, 'room.out', reason: '$x,$y');
    }
    expect(w.journal.length, before);
  });

  // Уронит: часы встают на пол. Откат: проверка slot_type в roomPlaceBlock.
  test('неверный тип места отклоняется', () {
    final WorldGame w = _withItems(<String>['room_clock']);
    final WorldResult r = w.placeRoomItem('room_clock', 2, 4); // пол
    expect(r.ok, isFalse);
    expect(r.reasonCode, 'room.slot');
    expect(r.reason, contains('на стену'));
    expect(w.placeRoomItem('room_clock', 1, 0).ok, isTrue); // стена
  });

  // Уронит: покупка не списывает или списывает при нехватке. Откат:
  // `want: -pay.want` в записи roomItemBought; проверка «не хватает».
  test('покупка списывает из «Хочу»; при нехватке — отказ без списания', () {
    final WorldGame w = _living();
    final ResourceSnapshot s0 = w.snapshot;
    final int price = w.room.item('room_clock')!.price;
    expect(s0.want, greaterThanOrEqualTo(price));
    final WorldResult r = w.buyRoomItem('room_clock');
    expect(r.ok, isTrue, reason: r.reason);
    expect(w.snapshot.want, s0.want - price);
    expect(w.snapshot.free, s0.free);
    expect(w.snapshot.roomOwned, contains('room_clock'));
    // Причина настроения — как у обновки, а не сырой ключ записи.
    expect(w.snapshot.moodReason.code, 'mood.new_thing');
    expect(w.buyRoomItem('room_clock').reasonCode, 'buy.owned');

    final ResourceSnapshot s1 = w.snapshot;
    final int before = w.journal.length;
    final WorldResult no = w.buyRoomItem('room_shelf'); // 700 > остатка
    expect(no.ok, isFalse);
    expect(no.reasonCode, 'buy.short');
    expect(no.reason,
        'Не хватает ${w.room.item('room_shelf')!.price - s1.want - s1.free}.');
    expect(w.snapshot.want, s1.want);
    expect(w.snapshot.free, s1.free);
    expect(w.journal.length, before);
    expect(w.snapshot.roomOwned, isNot(contains('room_shelf')));
    // Тот же отказ заранее — для кнопки.
    expect(
        w.canDo(WorldAction.buyRoomItem, id: 'room_shelf')?.code, 'buy.short');
  });

  // Уронит: трата вещи комнаты не попадает в факт «Хочу» недели.
  test('покупка видна в истории недели', () {
    final WorldGame w = _living();
    w.buyRoomItem('room_clock');
    final WeekPlanFact week = w.weekHistory.last;
    expect(
        week.purchases.map((WeekItem i) => i.title), contains('Часы на стену'));
  });

  // Уронит: расстановка живёт в памяти, журнал её не сворачивает. Откат:
  // ветка roomItemPlaced в WorldState.apply.
  test('после перезапуска вещи на местах', () async {
    final Directory dir = _dir();
    final SavedWorld first =
        await openSavedWorld(read: _read, storage: FileStorage(dir));
    final WorldGame w = first.world..startWeek();
    w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
    expect(w.buyRoomItem('room_toybox').ok, isTrue);
    // Нехватка денег — в тесте выше: здесь она зависела бы от карманных
    // профиля баланса (400 → 820 с b2eaa35).
    expect(w.placeRoomItem('room_toybox', 1, 3).ok, isTrue);
    expect(w.placeRoomItem('room_toybox', 2, 4).ok, isTrue); // передвинули
    await first.flush();
    final SavedWorld again =
        await openSavedWorld(read: _read, storage: FileStorage(dir));
    expect(again.world.snapshot.roomOwned, <String>{'room_toybox'});
    expect(again.world.snapshot.roomPlaced,
        <String, RoomCell>{'room_toybox': (x: 2, y: 4)});
    expect(again.world.removeRoomItem('room_toybox').ok, isTrue);
    expect(again.world.snapshot.roomPlaced, isEmpty);
    expect(again.world.snapshot.roomOwned, <String>{'room_toybox'},
        reason: 'убранная вещь остаётся купленной');
  });

  // Старое сохранение — журнал без записей комнаты: инвентарь пуст, мир
  // читается целиком. Падает только если свёртка не умеет пустое — см.
  // отчёт: откатом правки эта проверка не роняется (её поведение по
  // умолчанию и есть «пусто»).
  test('старый журнал без записей комнаты — пустой инвентарь', () {
    final WorldGame old = _living()..completeJob('consultant', score: 1);
    final WorldGame back =
        WorldGame.fromJson(old.toJson(), config: contentConfig);
    expect(back.unreadable, 0);
    expect(back.snapshot.roomOwned, isEmpty);
    expect(back.snapshot.roomPlaced, isEmpty);
    expect(back.snapshot.want, old.snapshot.want);
  });

  // Уронит: вещь комнаты покупается при выключенной кастомизации (в сборке
  // `room.customize` = false) — монеты уходят, +😊 приходит, а вещи не видно.
  test('флаг выключен: покупка вещи комнаты отклоняется, ничего не списано',
      () {
    final WorldGame w = contentWorld()..startWeek();
    w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
    expect(w.room.enabled, isFalse, reason: 'в сборке флаг выключен');
    final ResourceSnapshot before = w.snapshot;
    final int entries = w.journal.length;
    final WorldResult r = w.buyRoomItem('room_clock');
    expect(r.ok, isFalse);
    expect(r.reasonCode, 'room.off');
    expect(
        w.canDo(WorldAction.buyRoomItem, id: 'room_clock')?.code, 'room.off');
    expect(w.snapshot.want, before.want);
    expect(w.snapshot.happiness, before.happiness);
    expect(w.snapshot.roomOwned, isEmpty);
    expect(w.journal.length, entries);
  });
}
