import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/fridge_stock.dart';
import '../finni_walker.dart';
import 'room_layout.dart';

/// Слоты комнаты из `room/slots.json`: точки в пикселях фона.
///
/// Точка слота — низ по центру: ноги Финни, лежанка питомца, подоконник.
class RoomSlots {
  const RoomSlots(this.size, this.points,
      {this.floorY,
      this.edgeWall,
      this.edgeFloor,
      this.taps = const <String, Rect>{},
      this.objects = const <String, RoomObjectSlot>{},
      this.walk,
      this.interest,
      this.boxes = const <String, Rect>{},
      this.furniture = const <String, Rect>{},
      this.actions = const <String, String>{},
      this.restSpan,
      this.depth});

  /// Слоты из общей раскладки ([RoomLayout], `content/room_layout.json`):
  /// доли картинки → px фона размером [size] (size_px фона в реестре). Все предметы с
  /// действием — зоны касания по id предмета ([RoomLayout.objectOf]);
  /// мебель — места спрайтов ([furniture]); декор — коробки ([boxes]).
  factory RoomSlots.fromLayout(RoomLayout l, LayoutStage stage, Size size) {
    final double sw = size.width, s = size.height;
    Rect px(Rect r) =>
        Rect.fromLTWH(r.left * sw, r.top * s, r.width * sw, r.height * s);
    Offset pt(Offset o) => Offset(o.dx * sw, o.dy * s);
    final Rect? pet = l.slots['pet_corner']?.rect;
    Rect? interest;
    for (final LayoutSlot slot in l.slots.values) {
      if (slot.action == null && !identical(slot.rect, pet)) continue;
      interest = interest == null
          ? px(slot.rect)
          : interest.expandToInclude(px(slot.rect));
    }
    final Offset petAt =
        pet == null ? pt(l.finni) : px(pet).bottomCenter.translate(0, -2);
    return RoomSlots(
      size,
      <String, Offset>{
        'finni': pt(l.finni),
        'pet_floor': petAt,
        'pet_bed': petAt,
        for (final MapEntry<String, Rect> e in l.decor.entries)
          e.key: px(e.value).bottomCenter,
      },
      floorY: l.floorY * s,
      edgeWall: stage.edgeWall,
      edgeFloor: stage.edgeFloor,
      taps: <String, Rect>{
        // Сначала младшие: в стеке сцены старший слот (копилка) ляжет сверху.
        for (final MapEntry<String, LayoutSlot> e in l.tappable.reversed)
          RoomLayout.objectOf(e.key): px(e.value.rect),
      },
      walk: px(l.walk),
      interest: interest,
      restSpan: () {
        // Что видно при камере в центре: кровать и стол не меньше
        // [CameraSpec.foregroundShown] своей ширины.
        final double v = l.camera.foregroundShown;
        final Rect? bed = l.slots['bed']?.rect,
            desk = l.slots['desk_chair']?.rect;
        if (v <= 0 || bed == null || desk == null) return null;
        final double a = (bed.left + (1 - v) * bed.width) * sw;
        final double b = (desk.right - (1 - v) * desk.width) * sw;
        return b > a ? Rect.fromLTRB(a, 0, b, s) : null;
      }(),
      boxes: <String, Rect>{
        for (final MapEntry<String, Rect> e in l.decor.entries)
          e.key: px(e.value),
      },
      furniture: <String, Rect>{
        for (final MapEntry<String, LayoutSlot> e in l.slots.entries)
          e.key: px(e.value.rect),
      },
      actions: <String, String>{
        for (final MapEntry<String, LayoutSlot> e in l.tappable)
          RoomLayout.objectOf(e.key): e.value.action!,
      },
      depth: l.depth,
    );
  }

  factory RoomSlots.parse(String json) {
    final Object? root = jsonDecode(json);
    if (root is! Map<String, Object?>) return fallback;
    final Object? size = root['size'];
    final Object? slots = root['slots'];
    if (size is! List<Object?> || size.length != 2 || slots is! Map) {
      return fallback;
    }
    final Object? floor = root['floor_y'];
    final Object? taps = root['taps'];
    final Object? objects = root['objects'];
    return RoomSlots(
      floorY: floor is num ? floor.toDouble() : null,
      edgeWall: _hex(root['edge_wall']),
      edgeFloor: _hex(root['edge_floor']),
      taps: <String, Rect>{
        if (taps is Map)
          for (final MapEntry<Object?, Object?> e in taps.entries)
            if (e.value
                case {
                  'x': final num x,
                  'y': final num y,
                  'w': final num w,
                  'h': final num h
                })
              e.key! as String: Rect.fromLTWH(
                  x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
      },
      objects: <String, RoomObjectSlot>{
        if (objects is Map)
          for (final MapEntry<Object?, Object?> e in objects.entries)
            if (e.value
                case {
                  'side': final String side,
                  'order': final num order,
                  'bottom': final num bottom,
                  'limit': final num limit,
                } when side == 'left' || side == 'right')
              e.key! as String: RoomObjectSlot(
                  left: side == 'left',
                  order: order.toInt(),
                  bottom: bottom.toDouble(),
                  limit: limit.toDouble(),
                  shelves: _rects((e.value! as Map)['shelves'])),
      },
      Size((size[0]! as num).toDouble(), (size[1]! as num).toDouble()),
      <String, Offset>{
        for (final MapEntry<Object?, Object?> e in slots.entries)
          if (e.value case {'x': final num x, 'y': final num y})
            e.key! as String: Offset(x.toDouble(), y.toDouble()),
      },
    );
  }

  /// Нет файла слотов — раскладка по умолчанию, чтобы экран не ждал арта.
  static const RoomSlots fallback = RoomSlots(Size(272, 168), <String, Offset>{
    'finni': Offset(138, 160),
    'pet_bed': Offset(227, 90),
    'pet_floor': Offset(85, 156),
    'item_sill': Offset(136, 92),
  });

  final Size size;
  final Map<String, Offset> points;

  /// Линия пола (низ плинтуса) — по ней делятся поля по бокам узкого фона.
  final double? floorY;

  /// Цвета полей по бокам узкого фона: стена и пол в тени.
  final Color? edgeWall;
  final Color? edgeFloor;

  /// Зоны касания в арте фона (`bed`, `piggy`): прямоугольники в px фона.
  final Map<String, Rect> taps;

  /// Где стоят предметы-спрайты (`door`, `dresser`, `fridge`).
  final Map<String, RoomObjectSlot> objects;

  /// Общая раскладка ([RoomSlots.fromLayout]): где могут стоять ноги Финни.
  final Rect? walk;

  /// Общая раскладка: всё, что должно остаться в кадре (предметы с
  /// действием и место питомца) — по нему считается кадр ([roomFrame]).
  final Rect? interest;

  /// Общая раскладка: коробки декора по слоту (`decor_wall`, `decor_rug`…).
  final Map<String, Rect> boxes;

  /// Общая раскладка: места мебели по слоту раскладки (`bed`, `desk_chair`…).
  final Map<String, Rect> furniture;

  /// Общая раскладка: действие касания по id предмета (`city`, `sleep`,
  /// `jobs`, `piggy`, `food`) — из файла, сцена зовёт по нему обработчик.
  final Map<String, String> actions;

  /// Общая раскладка: полоса мира (px фона), которая целиком видна при
  /// камере в центре комнаты — ограничивает масштаб сверху. Нет — только
  /// по высоте.
  final Rect? restSpan;

  /// Общая раскладка: перспектива по y ног. Нет — масштаб 1.
  final DepthScale? depth;

  /// Масштаб Финни и питомца с ногами на [y] (px фона).
  double depthAt(double y) => depth?.at(y / size.height) ?? 1;

  /// Список `{x, y, w, h}` → прямоугольники; кривые элементы пропускаются.
  static List<Rect> _rects(Object? v) => <Rect>[
        if (v is List)
          for (final Object? r in v)
            if (r
                case {
                  'x': final num x,
                  'y': final num y,
                  'w': final num w,
                  'h': final num h
                })
              Rect.fromLTWH(
                  x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
      ];

  static Color? _hex(Object? v) {
    if (v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) return null;
    return Color(0xFF000000 | int.parse(v.substring(1), radix: 16));
  }

  Offset slot(String id) => points[id] ?? fallback.points[id] ?? Offset.zero;
}

/// Место предмета-спрайта у края сцены (фидбек дизайнера 28.09, п. 4).
///
/// Предмет стоит на полу ([bottom]) у левого или правого края сцены:
/// широкий экран — целиком в поле сбоку от комнаты, узкий — вдвинут в
/// комнату, за передний план (кровать, коробки), но не дальше [limit]
/// (окно, край стены). [order] 0 — самый внешний, у края экрана. Ряд — одна
/// сторона и одна линия пола: предмет с другим [bottom] (холодильник у
/// камеры в деревне) встаёт к краю сам по себе.
class RoomObjectSlot {
  const RoomObjectSlot({
    required this.left,
    required this.order,
    required this.bottom,
    required this.limit,
    this.shelves = const <Rect>[],
  });

  final bool left;
  final int order;
  final double bottom;
  final double limit;

  /// Полки холодильника: прямоугольники в px его спрайта, сверху вниз; еда
  /// стоит на нижнем крае.
  final List<Rect> shelves;
}

/// Прямоугольники предметов в px фона.
///
/// [sizes] — предметы, у которых есть арт; прочие места пропускаются (слот
/// холодильника ждёт спрайта). [sceneLeft] и [sceneRight] — края сцены в px
/// фона: поле сбоку — отрицательный x слева и больше ширины фона справа.
Map<String, Rect> placeRoomObjects(
  RoomSlots slots,
  Map<String, Size> sizes, {
  required double sceneLeft,
  required double sceneRight,
}) {
  final Map<String, Rect> out = <String, Rect>{};
  final Set<(bool, double)> rows = <(bool, double)>{
    for (final MapEntry<String, RoomObjectSlot> e in slots.objects.entries)
      if (sizes.containsKey(e.key)) (e.value.left, e.value.bottom),
  };
  for (final (bool left, double bottom) in rows) {
    final List<MapEntry<String, RoomObjectSlot>> row =
        <MapEntry<String, RoomObjectSlot>>[
      for (final MapEntry<String, RoomObjectSlot> e in slots.objects.entries)
        if (e.value.left == left &&
            e.value.bottom == bottom &&
            sizes.containsKey(e.key))
          e,
    ]..sort((MapEntry<String, RoomObjectSlot> a,
                MapEntry<String, RoomObjectSlot> b) =>
            a.value.order.compareTo(b.value.order));
    final double total = row.fold(
        0,
        (double w, MapEntry<String, RoomObjectSlot> e) =>
            w + sizes[e.key]!.width);
    if (left) {
      final double limit = row.map((e) => e.value.limit).reduce(math.min);
      double x = math.min(sceneLeft + total, limit) - total;
      for (final MapEntry<String, RoomObjectSlot> e in row) {
        final Size s = sizes[e.key]!;
        out[e.key] =
            Rect.fromLTWH(x, e.value.bottom - s.height, s.width, s.height);
        x += s.width;
      }
    } else {
      final double limit = row.map((e) => e.value.limit).reduce(math.max);
      double x = math.max(sceneRight - total, limit) + total;
      for (final MapEntry<String, RoomObjectSlot> e in row) {
        final Size s = sizes[e.key]!;
        x -= s.width;
        out[e.key] =
            Rect.fromLTWH(x, e.value.bottom - s.height, s.width, s.height);
      }
    }
  }
  return out;
}

/// Масштаб и сдвиг фона в сцене: [k] — px сцены на px фона, [left] и
/// [top] — где на сцене левый верхний угол фона.
typedef RoomFrame = ({double k, double left, double top});

/// Кадр комнаты в сцене [box] (логика [RoomScene], вынесена для проверки
/// раскладки без виджетов).
///
/// Прежний фон — в целом масштабе; потолок можно срезать до
/// [RoomScene.maxCeilingCrop]. Hi-res — в дробном: закрывает ширину, пока
/// срез по высоте не больше [RoomScene.maxHiresCrop]. По горизонтали — центр
/// между Финни и питомцем, по вертикали у hi-res под ногами Финни полоса
/// пола.
RoomFrame roomFrame(RoomSlots slots,
    {required Size box,
    required bool hires,
    bool hasPet = false,
    bool petAwake = false,
    bool cover = false,
    double topInset = 0}) {
  final double w = box.width, h = box.height;
  final double sw = slots.size.width, sh = slots.size.height;
  // Общая раскладка: квадрат cover-fit, но не крупнее, чем нужно, чтобы
  // все предметы с действием ([RoomSlots.interest]) остались в кадре.
  // Денис 29.09 (Paper Mario): масштаб постоянный — комната по высоте
  // сцены; шире экрана — по горизонтали её ведёт камера за Финни
  // ([_FollowCamera]), уже экрана — стоит по центру, камера не двигается.
  // [topInset] — полоса сверху под HUD поверх сцены: комната встаёт под
  // неё, предметы у задней стены не прячутся под плашками.
  if (slots.interest != null) {
    final double inset = topInset.clamp(0.0, h * 0.5).toDouble();
    // По высоте сцены, но не крупнее, чем нужно, чтобы кровать и стол в
    // покое были видны почти целиком ([RoomSlots.restSpan]); ниже высоты —
    // комната по центру под HUD ([topInset]); сверху — продолжение потолка,
    // снизу — зеркальная полоса пола, без пустой полосы.
    final Rect? rest = slots.restSpan;
    final double k = math.min(
        (h - inset) / sh, rest == null ? double.infinity : w / rest.width);
    final double rw = sw * k;
    final double left = rw <= w
        ? (w - rw) / 2
        : (w / 2 - sw / 2 * k).clamp(w - rw, 0.0).toDouble();
    // Ниже сцены — по центру между HUD и низом: сверху потолок, снизу пол
    // (сцена дорисовывает оба), без мёртвой полосы с одной стороны.
    final double rh = sh * k;
    return (k: k, left: left, top: inset + math.max(0.0, (h - inset - rh) / 2));
  }
  // [cover] — фон закрывает сцену целиком, без полей по бокам (сценки
  // знакомства: узкая полоса комнаты над планом не должна быть в швах).
  final double k = hires && cover
      ? math.max(h / sh, w / sw)
      : hires
          ? math.max(
              h / sh, math.min(w / sw, h / (sh * (1 - RoomScene.maxHiresCrop))))
          : pixelScaleFor(sh * (1 - RoomScene.maxCeilingCrop), h).toDouble();
  final double rw = sw * k;
  final double rh = sh * k;
  final Offset f = slots.slot('finni');
  final Offset p = slots.slot(petAwake ? 'pet_floor' : 'pet_bed');
  final double focus = (hasPet ? (f.dx + p.dx) / 2 : f.dx) * k;
  final double left =
      rw <= w ? (w - rw) / 2 : (w / 2 - focus).clamp(w - rw, 0.0).toDouble();
  // Ноги Финни — чуть выше низа кадра; в [cover] ещё и голова в кадре:
  // низкая полоса над планом показывала одни ноги (ревью 29.09).
  final double feetUp = h - (f.dy * k + h * 0.12);
  final double headIn = h * 0.04 - (f.dy - sh * RoomGeometry.height) * k;
  final double top = hires
      ? (cover ? math.max(feetUp, headIn) : feetUp)
          .clamp(h - rh, 0.0)
          .toDouble()
      : h - rh;
  return (k: k, left: left, top: top);
}

/// Где на полках холодильника стоят [count] порций: прямоугольники в px
/// спрайта. Две порции на полку, с нижней полки вверх — неделя съедает
/// сверху, и пустеет холодильник с верхних полок. Порций больше мест —
/// лишние не рисуются.
List<Rect> fridgeSpots(List<Rect> shelves, int count, {int perShelf = 2}) {
  final List<Rect> out = <Rect>[];
  for (final Rect shelf in shelves.reversed) {
    final double cell = shelf.width / perShelf;
    // Картинка еды чуть шире высоты (64 × 58): по высоте полки, не шире места.
    final double ih = math.min(shelf.height * 0.95, cell / 1.1);
    final double iw = math.min(ih * 1.1, cell);
    for (int i = 0; i < perShelf; i++) {
      if (out.length >= count) return out;
      out.add(Rect.fromLTWH(
          shelf.left + cell * i + (cell - iw) / 2, shelf.bottom - ih, iw, ih));
    }
  }
  return out;
}

/// Подпись холодильника для TalkBack: сколько приёмов пищи осталось на
/// неделю (после переделки еды на ветке правил 29.09 порция — приём пищи).
String fridgeLabel(FridgeStock f) =>
    'Холодильник, приёмов пищи осталось: ${f.portions}';

/// Прямоугольник предмета [id] в px фона — к нему подходит Финни в
/// сценке. Копилка — зона в арте (город, Москва) или комод (деревня).
/// Нет предмета в этой комнате — null.
Rect? focusRectOf(String? id, RoomSlots slots, Map<String, Rect> placed) =>
    switch (id) {
      'piggy' => slots.taps['piggy'] ?? placed['dresser'],
      'bed' => slots.taps['bed'],
      'desk' => slots.taps['desk'],
      'fridge' || 'door' => placed[id] ?? slots.taps[id],
      _ => null,
    };

/// Где стоит Финни у предмета [r] (x в px фона): сбоку от предмета со
/// стороны его места [home], на [gap] от края, внутри сцены
/// [sceneLeft]..[sceneRight] (поле сбоку — за краями фона).
double finniXNear(Rect r,
    {required double home,
    required double gap,
    required double sceneLeft,
    required double sceneRight}) {
  final double x = r.center.dx <= home ? r.right + gap : r.left - gap;
  final double lo = sceneLeft + gap, hi = sceneRight - gap;
  return lo > hi ? home : x.clamp(lo, hi).toDouble();
}

/// Комната для хода джойстиком — всё в px фона: где можно стоять ногами
/// ([walk]), где предметы ([objects]: `bed`, `piggy`, `fridge`, `door`),
/// где Финни стоит без джойстика ([feet]) и мера длины ([unit] — высота
/// фона).
@immutable
class RoomGeometry {
  const RoomGeometry({
    required this.walk,
    required this.objects,
    required this.feet,
    required this.unit,
    this.k = 1,
    this.origin = Offset.zero,
  });

  final Rect walk;
  final Map<String, Rect> objects;
  final Offset feet;
  final double unit;

  /// Масштаб и сдвиг фона в сцене: px фона → px сцены.
  final double k;
  final Offset origin;

  /// Полуширина и рост Финни в долях высоты фона.
  static const double halfWidth = 0.13;
  static const double height = 0.33;

  /// Где на сцене Финни с ногами в [at] (px сцены).
  Rect finniOnScreen(Offset at) {
    final Offset p = origin + at * k;
    return Rect.fromLTRB(p.dx - unit * halfWidth * k, p.dy - unit * height * k,
        p.dx + unit * halfWidth * k, p.dy);
  }

  /// Предмет, у которого стоит Финни в [at]: ближайший не дальше 0,12
  /// высоты фона от ног. Нет такого — null.
  String? nearest(Offset at) {
    // Расстояние — до места у предмета (низ по центру), а не до его
    // прямоугольника: зона кровати в арте широкая и накрывала дверь рядом.
    String? best;
    double bestD = unit * 0.18;
    for (final MapEntry<String, Rect> e in objects.entries) {
      final double d = (e.value.bottomCenter - at).distance;
      if (d <= bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is RoomGeometry &&
      other.walk == walk &&
      other.feet == feet &&
      other.unit == unit &&
      mapEquals(other.objects, objects);

  @override
  int get hashCode => Object.hash(walk, feet, unit, objects.length);
}

/// Всё, что комнате нужно прочитать из бандла, одним ожиданием.
class RoomArt {
  const RoomArt(this.registry, this.slots,
      {this.byRoom = const <String, RoomSlots>{}, this.layout});

  /// Общая раскладка комнаты на все стадии (`content/room_layout.json`).
  /// Нет файла — комнаты стадий по прежним слотам.
  final RoomLayout? layout;

  final AssetRegistry registry;

  /// Слоты комнаты `home` (прежней, горизонтальной).
  final RoomSlots slots;

  /// Слоты комнат стадий по id реестра (`village`, `town`, `moscow`).
  final Map<String, RoomSlots> byRoom;

  /// Слоты комнаты [id]; своих нет — прежние.
  RoomSlots slotsFor(String? id) => byRoom[id] ?? slots;

  /// Без статического кеша — см. [AssetRegistry.load].
  static Future<RoomArt> load() => () async {
        final AssetRegistry reg = await AssetRegistry.load();
        Future<RoomSlots?> read(String id) async {
          final String? path = reg.roomSlots(id: id);
          if (path == null) return null;
          try {
            return RoomSlots.parse(await rootBundle.loadString(path));
          } on Object {
            return null;
          }
        }

        final Map<String, RoomSlots> byRoom = <String, RoomSlots>{};
        for (final String id in roomIdByStage.values) {
          final RoomSlots? s = await read(id);
          if (s != null) byRoom[id] = s;
        }
        RoomLayout? layout;
        try {
          layout =
              RoomLayout.parse(await rootBundle.loadString(RoomLayout.asset));
        } on Object {
          layout = null;
        }
        return RoomArt(reg, await read('home') ?? RoomSlots.fallback,
            byRoom: byRoom, layout: layout);
      }();
}

/// Комната по стадии: id в группе `room` реестра. Какая картинка за id —
/// решает реестр (`assets/registry.json`, `_note`): деревня — пустая комната,
/// город — та же с мебелью, Москва — обставленная, за окном город побольше.
/// Нет id в реестре — прежняя комната `home`.
const Map<WorldStage, String> roomIdByStage = <WorldStage, String>{
  WorldStage.village: 'village',
  WorldStage.town: 'town',
  WorldStage.moscow: 'moscow',
};

/// Декор комнаты — по префиксу id вещи.
bool isDecorId(String id) =>
    id.startsWith('poster_') ||
    id.startsWith('plant_') ||
    id.startsWith('light_') ||
    id.startsWith('decor_');

/// Где в комнате стоит декор и какого он размера.
///
/// [slot] — точка в файле слотов (низ по центру); нет её в файле — вещь
/// встаёт на подоконник. [width] и [height] — коробка в долях высоты фона:
/// картинка вписывается в неё, так размер не зависит от плотности файла.
typedef DecorPlace = ({String slot, double width, double height});

/// Постеры — на стену, большое растение — на пол, маленькие — на
/// подоконник, свет — на окне (потолок на экране срезан).
DecorPlace decorPlace(String id) {
  if (id.startsWith('poster_')) {
    return (slot: 'decor_wall', width: 0.13, height: 0.13);
  }
  if (id == 'plant_floor') {
    return (slot: 'decor_floor', width: 0.1, height: 0.15);
  }
  // Вещи (глобус, книги, мишка, ковёр): у каждой своё место в общей
  // раскладке, слот назван её id; в прежней комнате — подоконник.
  if (id.startsWith('decor_')) {
    return (slot: id, width: 0.08, height: 0.08);
  }
  if (id.startsWith('light_')) {
    return id == 'light_bulb'
        ? (slot: 'decor_ceiling', width: 0.09, height: 0.13)
        : (slot: 'decor_ceiling', width: 0.24, height: 0.22);
  }
  return (slot: 'item_sill', width: 0.06, height: 0.07);
}

/// Что из купленного показать в комнате: на каждое место — последняя
/// купленная вещь (иначе постеры лягут друг на друга).
List<String> decorToShow(Iterable<String> owned) {
  final Map<String, String> bySlot = <String, String>{};
  for (final String id in owned) {
    if (isDecorId(id)) bySlot[decorPlace(id).slot] = id;
  }
  return bySlot.values.toList();
}

/// Комната сбоку: фон и слоты с Финни, питомцем и вещью.
///
/// Прежний фон — в целом масштабе. Hi-res фон (вертикальный, `@3x`) — в
/// дробном: закрывает ширину, пока срез по высоте не больше [maxHiresCrop],
/// дальше по бокам поля «стена / пол». Лишнее обрезается так, чтобы Финни и
/// питомец остались в кадре.
class RoomScene extends StatelessWidget {
  const RoomScene({
    super.key,
    required this.art,
    required this.stage,
    required this.species,
    required this.idleTag,
    required this.finniName,
    required this.happiness,
    this.petId,
    this.petAwake = false,
    this.decorIds = const <String>[],
    this.onFinniTap,
    this.onPetTap,
    this.onBedTap,
    this.onDoorTap,
    this.onPiggyTap,
    this.onDeskTap,
    this.piggySaved,
    this.fridge = FridgeStock.empty,
    this.onFridgeTap,
    this.focus,
    this.showName = true,
    this.cover = false,
    this.finniNear,
    this.walkTime,
    this.finniFree,
    this.finniMoving = false,
    this.onGeometry,
    this.topInset = 0,
  });

  /// Высота HUD поверх сцены сверху (общая раскладка): комната по высоте
  /// встаёт под него, над ней — цвет стены.
  final double topInset;

  final RoomArt? art;
  final WorldStage stage;
  final String species;
  final String idleTag;
  final String finniName;
  final int happiness;
  final String? petId;
  final bool petAwake;

  /// Декор в комнате ([decorToShow]): картинка из реестра, нет арта —
  /// значок-заглушка на подоконнике.
  final List<String> decorIds;
  final VoidCallback? onFinniTap;
  final VoidCallback? onPetTap;

  /// Предметы комнаты (фидбек дизайнера 28.09, п. 4): кровать — «Спать»,
  /// дверь — «В город», копилка — S9. Кнопки внизу остаются.
  final VoidCallback? onBedTap;
  final VoidCallback? onDoorTap;
  final VoidCallback? onPiggyTap;

  /// Стол (общая раскладка): работа — доска смен.
  final VoidCallback? onDeskTap;

  /// Сколько в копилке: табличка над копилкой (общая раскладка) и подпись
  /// копилки для TalkBack. null — без суммы (знакомство, старая комната).
  final int? piggySaved;

  /// Холодильник (этап 4, п. 7 фидбека): еда недели на полках, пустеет по
  /// ходу недели ([fridgeOf]). Касание — магазин на вкладке «Еда».
  final FridgeStock fridge;
  final VoidCallback? onFridgeTap;

  /// Предмет, к которому Финни подошёл сам (сценки знакомства): `piggy`,
  /// `fridge`, `door`, `bed`. Предмет подсвечен рамкой, Финни стоит рядом.
  /// `finni` или null — Финни на своём месте. Предмета нет в арте этой
  /// комнаты (или арт ещё не загрузился) — Финни тоже на своём месте.
  final String? focus;

  /// Табличка с именем в углу. Сценки знакомства пишут имя над репликой.
  final bool showName;

  /// Фон закрывает сцену без полей по бокам, даже ценой среза сверху и
  /// снизу ([roomFrame]).
  final bool cover;

  /// Куда подошёл Финни, если не к [focus]: тот же список предметов. Комната
  /// S1 — предмет, по которому ребёнок нажал (Финни идёт туда, потом
  /// действие); подсветки при этом нет.
  final String? finniNear;

  /// Сколько идёт Финни. null — по расстоянию (сценки знакомства). Выключены
  /// «Анимации» — ноль в любом случае.
  final Duration? walkTime;

  /// Где Финни стоит, если его водят джойстиком (ноги, px фона). Задано —
  /// сильнее [finniNear] и [focus]. Глубина (y) решает, кто кого закрывает:
  /// за линией кровати Финни уходит за неё, за линией холодильника — за
  /// холодильник (простое 2.5D, Денис 1001).
  final Offset? finniFree;

  /// Финни идёт от джойстика: кадры ходьбы, лицом по ходу.
  final bool finniMoving;

  /// Сцена разложена: где можно ходить, где предметы, где Финни сейчас —
  /// всё в px фона. Зовётся после кадра.
  final ValueChanged<RoomGeometry>? onGeometry;

  /// Ходьба в комнате S1: короче секунды (ТЗ §3.4 — отклик), и действие
  /// после неё не ждёт дольше.
  static const Duration roomWalk = Duration(milliseconds: 450);

  /// Какую долю высоты фона сверху можно не показать.
  static const double maxCeilingCrop = 0.25;

  /// Hi-res фон: какую долю высоты можно не показать (потолок и пол под
  /// ногами вместе). Больше — Финни занимает почти всю сцену.
  static const double maxHiresCrop = 0.45;

  @override
  Widget build(BuildContext context) {
    final AssetRegistry? reg = art?.registry;
    final String roomId = roomIdByStage[stage]!;
    // Общая раскладка (content/room_layout.json): её фон есть в реестре —
    // комната стадии строится по ней, иначе прежние слоты стадии.
    final LayoutStage? ls = art?.layout?.stages[roomId];
    final String? layoutBg = ls == null ? null : reg?.room(id: ls.background);
    final LayoutStage? lay = layoutBg == null ? null : ls;
    final String? stagePath = layoutBg ?? reg?.room(id: roomId);
    final String? bg = stagePath ?? reg?.room();
    final RoomSlots slots = lay != null
        ? RoomSlots.fromLayout(art!.layout!, lay,
            reg!.roomSize(lay.background) ?? RoomLayout.defaultWorld)
        : stagePath == null
            ? art?.slots ?? RoomSlots.fallback
            : art!.slotsFor(roomId);
    final bool hires = bg != null && artDensity(bg) > 1;
    final String? front =
        stagePath == null || lay != null ? null : reg?.roomFront(roomId);
    final Map<String, RoomObjectArt> things = <String, RoomObjectArt>{
      for (final String id in slots.objects.keys)
        if (reg?.roomObject(id) case final RoomObjectArt o) id: o,
    };
    // Мебель раскладки: картинка по слоту (пустой фон) — предметы
    // (night_items) или предметы комнаты (room_objects).
    String? sprite(String slot) {
      final String? id = lay?.furniture[slot];
      if (id == null) return null;
      return reg?.item(id) ?? reg?.roomObject(id)?.path;
    }

    final bool drawFurniture = lay != null && !lay.backgroundHasFurniture;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final double vw = box.maxWidth;
      final double h = box.maxHeight;
      // Прежний фон: целый масштаб; потолок можно срезать до четверти высоты —
      // иначе на телефоне комната 1× висит маленькой полоской посреди стены.
      // Hi-res: под ногами Финни остаётся полоса пола, остальное срезается
      // сверху. По горизонтали — центр между Финни и питомцем.
      final RoomFrame frame = roomFrame(slots,
          box: Size(vw, h),
          hires: hires,
          hasPet: petId != null,
          petAwake: petAwake,
          cover: cover,
          topInset: topInset);
      final double k = frame.k, top = frame.top;
      final double rw = slots.size.width * k;
      final double rh = slots.size.height * k;
      // Общая раскладка шире экрана — камера за Финни (Денис 29.09, как в
      // Paper Mario): сцена раскладывается во всю ширину комнаты, экран
      // смотрит на её часть ([_FollowCamera]). Зоны касания, ходьба и
      // глубина — в координатах мира.
      final bool camera = slots.interest != null && rw > vw + 0.5;
      final double w = camera ? rw : vw;
      final double left = camera ? 0 : frame.left;

      // Всё — в одном стеке размером со сцену: касание доходит только до
      // детей внутри границ стека, а дверь и комод стоят в полях сбоку.
      Rect onScreen(Rect r) => Rect.fromLTWH(
          left + r.left * k, top + r.top * k, r.width * k, r.height * k);

      Widget at(String slot, Widget child) {
        final Offset o = slots.slot(slot);
        return Positioned(
          left: left + o.dx * k,
          top: top + o.dy * k,
          child: FractionalTranslation(
              translation: const Offset(-0.5, -1), child: child),
        );
      }

      final SpriteRef? finni = reg?.finni(species);
      final SpriteRef? pet = petId == null ? null : reg?.pet(petId!);

      final Map<String, Rect> placed = placeRoomObjects(
        slots,
        <String, Size>{
          for (final MapEntry<String, RoomObjectArt> e in things.entries)
            e.key: Size(e.value.width, e.value.height),
        },
        sceneLeft: -left / k,
        sceneRight: (w - left) / k,
      );
      // Копилка: в арте города и Москвы она на полке; в деревне — на комоде.
      final bool piggyOnDresser =
          !slots.taps.containsKey('piggy') && placed.containsKey('dresser');

      // Предмет в фокусе — в px фона; Финни встаёт сбоку от него, со
      // стороны своего места, и не выходит за края сцены.
      final Rect? focusRect = focusRectOf(focus, slots, placed);
      final Rect? nearRect = focusRectOf(finniNear ?? focus, slots, placed);
      final Offset home = slots.slot('finni');
      final Rect? layoutWalk = slots.walk;
      final double finniX = nearRect == null
          ? home.dx
          : finniXNear(nearRect,
              home: home.dx,
              gap: slots.size.height * 0.07,
              sceneLeft: layoutWalk?.left ?? -left / k,
              sceneRight: layoutWalk?.right ?? (w - left) / k);
      final bool canWalk = reg?.finniHasTag(species, 'walk') ?? false;
      final SpriteRef? walkSheet = reg?.finniWalk(species);

      // Где можно ходить (ноги, px фона): пол от стены до низа кадра, по
      // ширине — видимая часть сцены с полями.
      final double sh = slots.size.height;
      // Поле — полуширина Финни (≈ 0,1 высоты фона): он целиком в кадре.
      final double margin = sh * RoomGeometry.halfWidth;
      final double? floorY = slots.floorY;
      final double yMin =
          floorY != null ? floorY + (sh - floorY) * 0.05 : home.dy - sh * 0.08;
      final double yMax =
          math.max(yMin, math.min(sh, (h - top) / k) - sh * 0.02);
      // Сверху: голова (рост Финни) не выше края кадра — у копилки на
      // полке уши срезались (ревью 29.09).
      final double headRoom = -top / k + sh * (RoomGeometry.height + 0.01);
      // Общая раскладка: зона ходьбы из файла, в пределах видимого кадра.
      final Rect visible =
          Rect.fromLTRB(-left / k, -top / k, (w - left) / k, (h - top) / k);
      final Rect walkArea = layoutWalk != null
          ? (layoutWalk.overlaps(visible)
              ? layoutWalk.intersect(visible)
              : layoutWalk)
          : Rect.fromLTRB(
              -left / k + margin,
              math.min(math.max(yMin, headRoom), home.dy),
              (w - left) / k - margin,
              math.max(yMax, home.dy));
      // У двери — её порог в глубине комнаты. Дверь стоит на линии пола за
      // кроватью; Финни у неё тоже за кроватью, а не поверх (смоук 29.09:
      // в портрете у двери он был нарисован на кровати).
      // Раскладка: у любого предмета — на уровне его низа, в зоне ходьбы.
      final double standY = nearRect != null &&
              (layoutWalk != null || (finniNear ?? focus) == 'door')
          ? nearRect.bottom.clamp(walkArea.top, walkArea.bottom).toDouble()
          : home.dy;
      final Offset stand = Offset(finniX, standY);
      final Duration walk = context.motion(walkTime ??
          Duration(
              milliseconds:
                  (((stand - home).distance / slots.size.width) * 1400 + 350)
                      .round()));
      final Offset feet = finniFree ?? stand;
      final RoomGeometry geometry = RoomGeometry(
        walk: walkArea,
        objects: <String, Rect>{
          for (final String id in <String>[
            'bed',
            'piggy',
            'fridge',
            'door',
            'desk'
          ])
            if (focusRectOf(id, slots, placed) case final Rect r) id: r,
        },
        feet: stand,
        unit: sh,
        k: k,
        origin: Offset(left, top),
      );
      if (onGeometry != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => onGeometry!(geometry));
      }
      // Глубина: середина кровати (передний план — кровать и коробки
      // упираются в низ кадра, её нижний край недостижим) и низ
      // холодильника.
      final Rect? bedZone = slots.taps['bed'];
      final double? frontLine =
          bedZone == null ? null : bedZone.top + bedZone.height * 0.75;
      final double? fridgeLine = placed['fridge']?.bottom;
      // По ногам — и у джойстика, и у места у предмета (порог двери).
      // Раскладка: кровать и стол — передний план у краёв кадра; Финни за
      // ними, пока его ноги выше их низа (сортировка по y ног).
      // По ширине Финни ([RoomGeometry.halfWidth]) — только если он с ней
      // перекрывается: посреди комнаты он перед мебелью у краёв.
      final double half = sh * RoomGeometry.halfWidth;
      final bool behindLayout = lay != null &&
          <String>['bed', 'desk_chair'].any((String id) {
            final Rect? r = slots.furniture[id];
            return r != null &&
                feet.dy < r.bottom &&
                feet.dx + half > r.left &&
                feet.dx - half < r.right;
          });
      final bool behindFront =
          lay != null ? behindLayout : frontLine != null && feet.dy < frontLine;
      // Перспектива: в глубине Финни и питомец чуть меньше.
      final double fk = k * slots.depthAt(feet.dy);
      final double pk =
          k * slots.depthAt(slots.slot(petAwake ? 'pet_floor' : 'pet_bed').dy);
      final bool behindFridge = fridgeLine != null && feet.dy < fridgeLine;

      Widget thing(String id, String key, String label, VoidCallback? onTap) =>
          Positioned.fromRect(
            rect: onScreen(placed[id]!),
            child: _RoomTap(
              key: ValueKey<String>(key),
              label: label,
              onTap: onTap,
              child: PixelImage(things[id]!.path, scale: k),
            ),
          );

      Widget zone(String id, String key, String label, VoidCallback? onTap) =>
          Positioned.fromRect(
            rect: _inside(_atLeast(onScreen(slots.taps[id]!), TapSize.min),
                Offset.zero & Size(w, h)),
            child: _RoomTap(
              key: ValueKey<String>(key),
              label: label,
              onTap: onTap,
              highlight: true,
              child: const SizedBox.expand(),
            ),
          );

      final double? floorY2 = floorY;
      // Имя, которое выбрал ребёнок (ТЗ 2.5.2.2), — табличка в углу
      // комнаты (при камере — в углу экрана, а не мира). TalkBack его не
      // читает второй раз: имя уже в подписи самого Финни.
      // Общая раскладка: под показателями ([topInset]), у потолка — не на
      // предметах. Касания не ловит.
      final Widget namePlate = Positioned(
        left: Gap.sm,
        top: (slots.interest != null ? topInset : 0) + Gap.sm,
        right: Gap.sm,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.topLeft,
            child: ExcludeSemantics(
              child: _NamePlate(
                  key: const ValueKey<String>('room:name'), name: finniName),
            ),
          ),
        ),
      );
      final Widget
          finniLayer = // Финни идёт только от предмета к предмету. Пришёл арт или
          // сменился размер сцены — встаёт на место сразу, а не едет
          // через экран из прежних координат.
          KeyedSubtree(
        key: ValueKey<String>('finni:frame:$bg:$w:$h'),
        child: FinniWalker(
          key: const ValueKey<String>('room:finni:spot'),
          duration: finniFree != null ? Duration.zero : walk,
          at: Offset(left + feet.dx * k, top + feet.dy * k),
          bob: 3 * fk,
          builder: (bool walking) => Semantics(
            button: true,
            label: '$finniName. Настроение $happiness',
            excludeSemantics: true,
            onTap:
                onFinniTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
            child: GestureDetector(
              key: const ValueKey<String>('room:finni'),
              behavior: HitTestBehavior.opaque,
              onTap: onFinniTap,
              child: finni == null
                  ? _SpriteStub(label: '🙂', size: 60.0 * fk)
                  : (walking || finniMoving) && walkSheet != null
                      // Кадры ходьбы своего облика (`finni_walk`, ветка арта).
                      ? SpriteAnim(
                          sprite: walkSheet,
                          tag: 'walk-${idleTag.replaceFirst('idle-', '')}',
                          scale: fk)
                      : SpriteAnim(
                          sprite: finni,
                          // Кадры ходьбы нарисованы для первого облика —
                          // остальные идут своим обликом, покачиваясь.
                          tag: (walking || finniMoving) &&
                                  canWalk &&
                                  idleTag == 'idle-1'
                              ? 'walk'
                              : idleTag,
                          scale: fk),
            ),
          ),
        ),
      );
      final Widget world = ClipRect(
        child: ColoredBox(
          // Hi-res комната продолжается полосами своей стены и пола; у старой
          // низкой комнаты поля — ночь мира, а не бежевая стена.
          color:
              hires ? slots.edgeWall ?? WorldColors.night : WorldColors.night,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              if (hires && floorY2 != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: top + floorY2 * k,
                  bottom: 0,
                  child: ColoredBox(
                      color: slots.edgeFloor ?? SceneColors.floorLine),
                ),
              // Общая раскладка: над комнатой (под HUD) — потолок: верхние
              // ряды фона растянуты по высоте полосы, без пустой полосы и без
              // повторов окна (29.09).
              if (slots.interest != null && top > 0.5)
                Positioned(
                  key: const ValueKey<String>('room:ceiling:more'),
                  left: left,
                  top: 0,
                  width: rw,
                  height: top,
                  child: IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: ClipRect(
                        child: SizedBox(
                          width: rw,
                          height: 4 * k,
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: rh,
                            maxHeight: rh,
                            child: PixelImage(bg, scale: k),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Общая раскладка ниже сцены: пол продолжается вниз — нижние
              // ряды фона зеркально (без пустой полосы, 29.09).
              if (slots.interest != null && top + rh < h - 0.5)
                Positioned(
                  key: const ValueKey<String>('room:floor:more'),
                  left: left,
                  top: top + rh,
                  width: rw,
                  height: h - top - rh,
                  child: IgnorePointer(
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: rh,
                        maxHeight: rh,
                        child: Transform.flip(
                            flipY: true, child: PixelImage(bg, scale: k)),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: left,
                top: top,
                width: rw,
                height: rh,
                child: PixelImage(
                  bg,
                  scale: k,
                  fallback: const _RoomStub(),
                ),
              ),
              // Раскладка: мебель в глубине (дверь, тумба с копилкой, место
              // питомца) и холодильник с едой недели — за Финни.
              if (drawFurniture)
                for (final String id in <String>[
                  'door',
                  'bedside_cabinet',
                  'piggy',
                  'pet_corner'
                ])
                  if (sprite(id) case final String path)
                    _furniture(id, path, onScreen(slots.furniture[id]!)),
              if (lay != null && slots.furniture['fridge'] != null)
                if (reg?.roomObject(lay.furniture['fridge'] ?? 'fridge')
                    case final RoomObjectArt f)
                  _layoutFridge(onScreen(slots.furniture['fridge']!), f,
                      shelves: <Rect>[
                        for (final RoomSlots r in art!.byRoom.values)
                          ...?r.objects['fridge']?.shelves,
                      ].take(4).toList(),
                      stock: fridge,
                      food: fridge.foodId == null
                          ? null
                          : reg?.item(fridge.foodId!),
                      snack: reg?.item('snack')),
              if (placed.containsKey('door'))
                thing('door', 'room:door', 'Дверь — в город', onDoorTap),
              if (placed.containsKey('dresser'))
                thing('dresser', piggyOnDresser ? 'room:piggy' : 'room:dresser',
                    'Копилка', onPiggyTap),
              // Передний план: кровать, коробки, картина — поверх двери и
              // комода, когда узкий экран вдвинул их в комнату.
              if (behindFront) finniLayer,
              // Раскладка: передний план у краёв кадра — поверх Финни за ним.
              if (drawFurniture)
                for (final String id in <String>['bed', 'desk_chair'])
                  if (sprite(id) case final String path)
                    _furniture(id, path, onScreen(slots.furniture[id]!)),
              if (front != null && placed.isNotEmpty)
                Positioned(
                  key: const ValueKey<String>('room:front'),
                  left: left,
                  top: top,
                  width: rw,
                  height: rh,
                  child: IgnorePointer(child: PixelImage(front, scale: k)),
                ),
              // Холодильник — поверх переднего плана: коробки деревни не
              // закрывают полки; под декором, питомцем и Финни.
              if (behindFridge && !behindFront) finniLayer,
              if (placed.containsKey('fridge'))
                Positioned.fromRect(
                  rect: onScreen(placed['fridge']!),
                  child: _RoomTap(
                    key: const ValueKey<String>('room:fridge'),
                    label: fridgeLabel(fridge),
                    onTap: onFridgeTap,
                    child: _Fridge(
                      sprite: things['fridge']!.path,
                      k: k,
                      shelves: slots.objects['fridge']!.shelves,
                      stock: fridge,
                      food: fridge.foodId == null
                          ? null
                          : reg?.item(fridge.foodId!),
                      snack: reg?.item('snack'),
                    ),
                  ),
                ),
              for (final String id in decorIds)
                _decor(id, slots, k, at, reg?.item(id), onScreen),
              // Раскладка: каждый предмет с действием — зона касания; порядок
              // слотов — от младшего к старшему (копилка поверх тумбы).
              if (lay != null) ...<Widget>[
                for (final String id in slots.taps.keys)
                  if (layoutTap(id) case (final String label, final String key))
                    zone(
                        id,
                        key,
                        id == 'fridge'
                            ? fridgeLabel(fridge)
                            : id == 'piggy' && piggySaved != null
                                ? 'Копилка: $piggySaved монет'
                                : label,
                        switch (slots.actions[id]) {
                          'city' => onDoorTap,
                          'sleep' => onBedTap,
                          'jobs' => onDeskTap,
                          'food' => onFridgeTap,
                          'piggy' => onPiggyTap,
                          _ => null,
                        }),
              ] else ...<Widget>[
                if (slots.taps.containsKey('bed'))
                  zone('bed', 'room:bed', 'Кровать — лечь спать', onBedTap),
                if (slots.taps.containsKey('piggy'))
                  zone('piggy', 'room:piggy', 'Копилка', onPiggyTap),
              ],
              // Сумма копилки — над копилкой, всегда видна (Денис 29.09:
              // «сколько в копилке лучше показать над копилкой»).
              if (lay != null &&
                  piggySaved != null &&
                  slots.furniture['piggy'] != null)
                Positioned(
                  left: onScreen(slots.furniture['piggy']!).center.dx - 60,
                  width: 120,
                  bottom: h - onScreen(slots.furniture['piggy']!).top + 2,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Center(
                        child: _PiggyAmount(
                            key: const ValueKey<String>('room:piggy:amount'),
                            amount: piggySaved!),
                      ),
                    ),
                  ),
                ),
              if (petId != null)
                at(
                  petAwake ? 'pet_floor' : 'pet_bed',
                  GestureDetector(
                    key: ValueKey<String>('room:pet:$petId'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onPetTap,
                    child: pet == null
                        ? _SpriteStub(label: '🐾', size: 24.0 * k)
                        : SpriteAnim(
                            sprite: pet,
                            tag: petAwake ? 'wake' : 'sleep',
                            scale: pk,
                            semanticLabel: 'Питомец',
                          ),
                  ),
                ),
              if (focusRect != null)
                Positioned.fromRect(
                  // Рамка целиком в кадре: дверь выше сцены не режет её край.
                  rect: onScreen(focusRect)
                      .inflate(4)
                      .intersect((Offset.zero & Size(w, h)).deflate(2)),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: ValueKey<String>('room:focus:$focus'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.chip),
                        border: Border.all(color: WorldColors.gold, width: 3),
                      ),
                    ),
                  ),
                ),
              if (!behindFront && !behindFridge) finniLayer,
              // Имя, которое выбрал ребёнок (ТЗ 2.5.2.2), — табличка в углу
              // комнаты. TalkBack его не читает второй раз: имя уже в
              // подписи самого Финни.
              if (showName && !camera) namePlate,
            ],
          ),
        ),
      );
      if (!camera) return world;
      final CameraSpec cam = art?.layout?.camera ?? CameraSpec.standard;
      return ClipRect(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _FollowCamera(
                viewport: vw,
                world: rw,
                target: feet.dx * k,
                focus: nearRect == null ? null : onScreen(nearRect),
                deadZone: cam.deadZone,
                ease: context.motion(cam.ease),
                // Геометрия для кнопки у предмета — в px экрана: со
                // сдвигом камеры.
                onMoved: onGeometry == null
                    ? null
                    : (double x) => onGeometry!(RoomGeometry(
                          walk: geometry.walk,
                          objects: geometry.objects,
                          feet: geometry.feet,
                          unit: geometry.unit,
                          k: geometry.k,
                          origin: geometry.origin.translate(x, 0),
                        )),
                child: SizedBox(width: rw, height: h, child: world),
              ),
            ),
            if (showName) namePlate,
          ],
        ),
      );
    });
  }
}

/// Сдвигает [r] внутрь [box], если помещается: зона, выросшая до пальца у
/// края сцены, уходит в видимую часть, а не полоской за край.
Rect _inside(Rect r, Rect box) => r.shift(Offset(
      r.width > box.width
          ? 0
          : (r.left < box.left
              ? box.left - r.left
              : math.min(0, box.right - r.right)),
      r.height > box.height
          ? 0
          : (r.top < box.top
              ? box.top - r.top
              : math.min(0, box.bottom - r.bottom)),
    ));

/// Зона не меньше пальца: растёт от центра до [min] по каждой стороне.
Rect _atLeast(Rect r, double min) => Rect.fromCenter(
    center: r.center,
    width: math.max(r.width, min),
    height: math.max(r.height, min));

/// Предмет комнаты, который можно нажать: кнопка для TalkBack и короткий
/// отклик под пальцем — предмет чуть проседает, зона в арте подсвечивается.
class _RoomTap extends StatefulWidget {
  const _RoomTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.highlight = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  /// Зона поверх арта фона: подсветка вместо проседания.
  final bool highlight;

  @override
  State<_RoomTap> createState() => _RoomTapState();
}

class _RoomTapState extends State<_RoomTap> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // Без действия (знакомство рисует ту же комнату) — просто картинка:
    // кнопка TalkBack, которая ничего не делает, хуже её отсутствия.
    if (widget.onTap == null) return ExcludeSemantics(child: widget.child);
    final Duration d = MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : const Duration(milliseconds: 90);
    // Пустая подпись — зона только для пальца (тумба под копилкой):
    // TalkBack слышит одну «Копилку», а не две.
    return Semantics(
      button: widget.label.isNotEmpty,
      label: widget.label.isEmpty ? null : widget.label,
      excludeSemantics: true,
      onTap: widget.label.isEmpty ? null : widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: widget.highlight
            ? AnimatedContainer(
                duration: d,
                decoration: BoxDecoration(
                  color:
                      _down ? const Color(0x33FFFFFF) : const Color(0x00FFFFFF),
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: widget.child,
              )
            : AnimatedScale(
                duration: d,
                scale: _down ? 0.96 : 1,
                alignment: Alignment.bottomCenter,
                child: widget.child,
              ),
      ),
    );
  }
}

/// Открытый холодильник с едой недели на полках ([fridgeSpots]): сначала
/// еда недели ([food]), за ней перекусы ([snack]). Картинки — только вид:
/// число порций TalkBack слышит в подписи кнопки.
class _Fridge extends StatelessWidget {
  const _Fridge({
    required this.sprite,
    required this.k,
    required this.shelves,
    required this.stock,
    this.food,
    this.snack,
  });

  final String sprite;
  final double k;
  final List<Rect> shelves;
  final FridgeStock stock;
  final String? food;
  final String? snack;

  @override
  Widget build(BuildContext context) {
    final List<Rect> spots = fridgeSpots(shelves, stock.portions);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        PixelImage(sprite, scale: k),
        for (int i = 0; i < spots.length; i++)
          if ((i < stock.food ? food : snack) case final String path)
            Positioned(
              left: spots[i].left * k,
              top: spots[i].top * k,
              width: spots[i].width * k,
              height: spots[i].height * k,
              child: IgnorePointer(
                child: Image.asset(
                  path,
                  key: ValueKey<String>('room:fridge:portion:$i'),
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
      ],
    );
  }
}

/// Табличка с именем Финни: имя целиком, одной строкой (до 16 символов).
class _NamePlate extends StatelessWidget {
  const _NamePlate({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WorldColors.panel,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: WorldColors.line, width: 1.5),
        ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: WorldColors.text),
          ),
        ),
      );
}

/// Вещь на своём месте: картинка в коробке по долям высоты фона.
Widget _decor(String id, RoomSlots slots, double k,
    Widget Function(String slot, Widget child) at, String? path,
    [Rect Function(Rect)? onScreen]) {
  final DecorPlace place = decorPlace(id);
  // Общая раскладка: у места своя коробка — картинка вписана в неё.
  final Rect? box = slots.boxes[place.slot];
  if (box != null && path != null && onScreen != null) {
    return Positioned.fromRect(
      key: ValueKey<String>('room:decor:$id'),
      rect: onScreen(box),
      child: ExcludeSemantics(
        child: Image.asset(
          path,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
  final String slot =
      slots.points.containsKey(place.slot) ? place.slot : 'item_sill';
  final Key key = ValueKey<String>('room:decor:$id');
  if (path == null) return at('item_sill', _DecorStub(key: key, k: k));
  final double h = slots.size.height * k;
  return at(
    slot,
    ExcludeSemantics(
      key: key,
      child: SizedBox(
        width: place.width * h,
        height: place.height * h,
        child: Image.asset(
          path,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

class _RoomStub extends StatelessWidget {
  const _RoomStub();

  @override
  Widget build(BuildContext context) => const Column(
        children: <Widget>[
          Expanded(flex: 3, child: ColoredBox(color: SceneColors.wall)),
          Expanded(child: ColoredBox(color: SceneColors.floor)),
        ],
      );
}

class _SpriteStub extends StatelessWidget {
  const _SpriteStub({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child:
            Center(child: Text(label, style: TextStyle(fontSize: size * 0.6))),
      );
}

/// Купленная вещь без арта в реестре — значок-заглушка на подоконнике.
class _DecorStub extends StatelessWidget {
  const _DecorStub({super.key, required this.k});

  final double k;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: 14.0 * k,
          child: FittedBox(
              child: Text('🪴', style: TextStyle(fontSize: 12.0 * k))),
        ),
      );
}

/// Подпись TalkBack и ключ зоны предмета общей раскладки; у предмета без
/// действия в сцене — null.
(String, String)? layoutTap(String id) => switch (id) {
      'door' => ('Дверь — в город', 'room:door'),
      'bed' => ('Кровать — лечь спать', 'room:bed'),
      'desk' => ('Стол — работа', 'room:desk'),
      'fridge' => ('Холодильник', 'room:fridge'),
      'piggy' => ('Копилка', 'room:piggy'),
      'cabinet' => ('', 'room:cabinet'),
      _ => null,
    };

/// Мебель общей раскладки: картинка вписана в место, низом по центру.
/// Касание — у зоны предмета поверх, картинка его не ловит.
Widget _furniture(String id, String path, Rect rect) => Positioned.fromRect(
      key: ValueKey<String>('room:furniture:$id'),
      rect: rect,
      child: IgnorePointer(
        child: Image.asset(
          path,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );

/// Холодильник общей раскладки: спрайт вписан в место низом по центру, еда
/// недели на его полках (полки — в px спрайта, как у прежней комнаты).
Widget _layoutFridge(Rect slot, RoomObjectArt f,
    {required List<Rect> shelves,
    required FridgeStock stock,
    String? food,
    String? snack}) {
  final double s = math.min(slot.width / f.width, slot.height / f.height);
  final Rect r = Rect.fromLTWH(slot.center.dx - f.width * s / 2,
      slot.bottom - f.height * s, f.width * s, f.height * s);
  return Positioned.fromRect(
    key: const ValueKey<String>('room:furniture:fridge'),
    rect: r,
    child: IgnorePointer(
      child: _Fridge(
          sprite: f.path,
          k: s,
          shelves: shelves,
          stock: stock,
          food: food,
          snack: snack),
    ),
  );
}

/// Камера комнаты за Финни, как в Paper Mario (Денис 29.09): мир шириной
/// [world] за окном шириной [viewport]; пока Финни в средней полосе
/// [deadZone] экрана — камера стоит, вышел — догоняет за [ease] (выключены
/// «Анимации» — сразу). Только по горизонтали, в пределах комнаты. [focus] —
/// предмет действия (px мира): камера доводит его до экрана.
class _FollowCamera extends StatefulWidget {
  const _FollowCamera({
    required this.viewport,
    required this.world,
    required this.target,
    required this.deadZone,
    required this.ease,
    required this.child,
    this.focus,
    this.onMoved,
  });

  /// Куда встала камера (сдвиг, px экрана) — после кадра.
  final ValueChanged<double>? onMoved;

  final double viewport;
  final double world;
  final double target;
  final Rect? focus;
  final double deadZone;
  final Duration ease;
  final Widget child;

  @override
  State<_FollowCamera> createState() => _FollowCameraState();
}

class _FollowCameraState extends State<_FollowCamera> {
  late double _x = _next(null);

  void _report() {
    final ValueChanged<double>? f = widget.onMoved;
    if (f == null) return;
    final double x = _x;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) f(x);
    });
  }

  @override
  void initState() {
    super.initState();
    _report();
  }

  double _next(double? prev) => followCameraX(
      prev: prev,
      viewport: widget.viewport,
      world: widget.world,
      target: widget.target,
      deadZone: widget.deadZone,
      focus: widget.focus);

  @override
  void didUpdateWidget(_FollowCamera old) {
    super.didUpdateWidget(old);
    _x = _next(_x);
    _report();
  }

  @override
  Widget build(BuildContext context) => OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: widget.world,
        maxWidth: widget.world,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _x),
          duration: widget.ease,
          curve: Curves.easeOut,
          child: widget.child,
          builder: (BuildContext context, double x, Widget? child) =>
              Transform.translate(
                  key: const ValueKey<String>('room:camera'),
                  offset: Offset(x, 0),
                  child: child),
        ),
      );
}

/// Сдвиг камеры (px экрана, ≤ 0): от прежнего [prev] (null — первый кадр:
/// центр комнаты). Финни ([target], px мира) в мёртвой зоне — камера
/// стоит, вышел — сдвиг ровно до края зоны; предмет действия [focus]
/// доводится до экрана; мир не уходит с экрана.
double followCameraX({
  required double? prev,
  required double viewport,
  required double world,
  required double target,
  required double deadZone,
  Rect? focus,
}) {
  // Первый кадр — центр комнаты (покой, после знакомства); дальше —
  // мёртвая зона за Финни.
  double x = prev ?? (viewport - world) / 2;
  final double lo = viewport * (0.5 - deadZone / 2);
  final double hi = viewport * (0.5 + deadZone / 2);
  final double at = target + x;
  if (at < lo) x += lo - at;
  if (at > hi) x -= at - hi;
  if (focus != null) {
    if (focus.left + x < 0) x = -focus.left;
    if (focus.right + x > viewport) x = viewport - focus.right;
  }
  return x.clamp(math.min(0.0, viewport - world), 0.0).toDouble();
}

/// Табличка суммы над копилкой: крупно, на тёмной подложке — читается на
/// любом фоне при 360 dp.
class _PiggyAmount extends StatelessWidget {
  const _PiggyAmount({super.key, required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WorldColors.night.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: WorldColors.needs, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text('$amount',
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WorldColors.text)),
        ),
      );
}
