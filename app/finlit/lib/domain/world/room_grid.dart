/// Кастомизация комнаты на сетке (каркас 17.10, ветка `final/room-customize`):
/// вещи из `content/room_items.json` покупаются в магазине (вкладка
/// «Комната») и ставятся в клетки сетки комнаты.
///
/// Чистый Dart: правила одни у `WorldGame` и фейка. Сетка, вещи и цены —
/// данные из файла; код чисел не пишет.
library;

import 'contract.dart' show BlockReason;

/// Куда встаёт вещь: на пол, на стену или на стол (подоконник, полку).
enum RoomSlotType {
  floor,
  wall,
  table;

  /// Буква клетки в карте сетки (`grid.cells`): `f`, `w`, `t`.
  static RoomSlotType? fromLetter(String c) => switch (c) {
        'f' => floor,
        'w' => wall,
        't' => table,
        _ => null,
      };

  /// По имени из файла (`slot_type`): `floor`, `wall`, `table`.
  static RoomSlotType? byName(String s) {
    for (final RoomSlotType t in values) {
      if (t.name == s) return t;
    }
    return null;
  }

  /// Для подсказки ребёнку: «на пол», «на стену», «на стол».
  String get where => switch (this) {
        floor => 'на пол',
        wall => 'на стену',
        table => 'на стол или подоконник',
      };
}

/// Клетка сетки: столбец [x] слева направо, ряд [y] сверху вниз, с 0.
typedef RoomCell = ({int x, int y});

/// Вещь комнаты из `room_items.json`.
class RoomItemSpec {
  const RoomItemSpec({
    required this.id,
    required this.name,
    required this.w,
    required this.h,
    required this.price,
    required this.sprite,
    required this.slot,
  });

  final String id;
  final String name;

  /// Сколько клеток занимает: [w] по ширине, [h] по высоте (`size_cells`).
  final int w, h;

  /// Монет; платим из «Хочу», потом из заработка — как за прочие вещи.
  final int price;

  /// Путь к картинке в сборке. Новый арт — одна строка в файле.
  final String sprite;
  final RoomSlotType slot;
}

/// Сетка комнаты: [cols] × [rows] клеток; клетка — квадрат со стороной
/// [cell] (доля стороны квадратного фона), левый верхний угол сетки —
/// ([originX], [originY]) в долях фона. Тип каждой клетки — буква карты
/// [map] (`f` пол, `w` стена, `t` стол, `.` — места нет: дверь, окно,
/// нарисованная мебель).
class RoomGrid {
  const RoomGrid({
    required this.cols,
    required this.rows,
    required this.originX,
    required this.originY,
    required this.cell,
    required this.map,
  });

  static const RoomGrid none = RoomGrid(
      cols: 0, rows: 0, originX: 0, originY: 0, cell: 0, map: <String>[]);

  final int cols, rows;
  final double originX, originY, cell;
  final List<String> map;

  bool contains(int x, int y) => x >= 0 && y >= 0 && x < cols && y < rows;

  /// Тип клетки; null — за сеткой или места нет.
  RoomSlotType? typeAt(int x, int y) {
    if (!contains(x, y) || y >= map.length || x >= map[y].length) return null;
    return RoomSlotType.fromLetter(map[y][x]);
  }

  /// Клетки, которые займёт вещь [w] × [h], поставленная левым верхним
  /// углом в ([x], [y]).
  Iterable<RoomCell> footprint(int x, int y, int w, int h) sync* {
    for (int dy = 0; dy < h; dy++) {
      for (int dx = 0; dx < w; dx++) {
        yield (x: x + dx, y: y + dy);
      }
    }
  }
}

/// Отказ покупки вещи комнаты, пока кастомизация выключена (`room.customize`).
const BlockReason roomOffBlock =
    BlockReason('room.off', 'Вещей для комнаты пока нет в магазине.');

/// Всё про кастомизацию комнаты: включена ли (флаг `room.customize` в
/// `economy.json`), сетка, вещи и 😊 за новую вещь.
class RoomCatalog {
  const RoomCatalog({
    this.enabled = false,
    this.grid = RoomGrid.none,
    this.items = const <RoomItemSpec>[],
    this.happinessOnce = 0,
    this.eventBadge = false,
    this.petName = petNameDefault,
  });

  static const RoomCatalog empty = RoomCatalog();

  /// `room.pet_name` без ключа в файле — то же, что в сборке (DEN-25 A,
  /// Денис 18.10).
  static const bool petNameDefault = true;

  /// Флаг экрана `room.event_badge`: в комнате кнопка «Событие ждёт», пока
  /// у мира есть событие без ответа (раньше его было видно только по «!»
  /// у здания в городе). Не про кастомизацию: от [enabled] не зависит.
  final bool eventBadge;

  /// Флаг экрана `room.pet_name` (DEN-25, A; ТЗ 2.5.2.2): имя, которое
  /// выбрал ребёнок, — в строке над Финни: «Имя · состояние».
  final bool petName;

  /// Флаг экрана: вкладка «Комната» в магазине и режим расстановки.
  /// Домен работает и без него (сохранения с прежними записями читаются).
  final bool enabled;
  final RoomGrid grid;
  final List<RoomItemSpec> items;

  /// 😊 за каждую новую вещь, один раз (как у декора).
  final int happinessOnce;

  RoomItemSpec? item(String id) {
    for (final RoomItemSpec i in items) {
      if (i.id == id) return i;
    }
    return null;
  }
}

/// Почему вещь [id] нельзя поставить левым верхним углом в ([x], [y]):
/// не куплена · за сеткой · не тот тип места · занято другой вещью. null —
/// можно. Своё прежнее место вещи не мешает (её передвигают). Одно правило
/// у мира и фейка; экран по нему подсвечивает клетки.
BlockReason? roomPlaceBlock(
  RoomCatalog catalog,
  String id,
  int x,
  int y, {
  required Iterable<String> owned,
  required Map<String, RoomCell> placed,
}) {
  final RoomItemSpec? it = catalog.item(id);
  if (it == null) {
    return BlockReason('room.unknown', 'Такой вещи нет: $id.');
  }
  if (!owned.contains(id)) {
    return const BlockReason('room.not_owned', 'Эту вещь ещё не купили.',
        nextStep: 'Магазин, вкладка «Комната»');
  }
  final RoomGrid g = catalog.grid;
  final Set<RoomCell> mine = g.footprint(x, y, it.w, it.h).toSet();
  for (final RoomCell c in mine) {
    if (!g.contains(c.x, c.y)) {
      return const BlockReason('room.out', 'Вещь сюда не помещается.',
          nextStep: 'Выбери клетку ближе к середине');
    }
  }
  for (final RoomCell c in mine) {
    if (g.typeAt(c.x, c.y) != it.slot) {
      return BlockReason('room.slot', '${it.name} ставится ${it.slot.where}.',
          nextStep: 'Выбери подсвеченную клетку');
    }
  }
  for (final MapEntry<String, RoomCell> e in placed.entries) {
    if (e.key == id) continue;
    final RoomItemSpec? other = catalog.item(e.key);
    if (other == null) continue;
    for (final RoomCell c
        in g.footprint(e.value.x, e.value.y, other.w, other.h)) {
      if (mine.contains(c)) {
        return BlockReason('room.busy', 'Здесь уже стоит: ${other.name}.',
            nextStep: 'Выбери свободную клетку');
      }
    }
  }
  return null;
}
