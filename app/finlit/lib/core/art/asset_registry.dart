import 'dart:convert';

import 'package:flutter/services.dart';

/// Реестр арта: id → файл (`assets/registry.json`, копия в `assets/art/`).
///
/// 🔴 Код знает только id. Денис подменяет картинку — правится реестр и
/// перекладывается `tools/sync_app_art.py`, код не трогается
/// (`docs/game/ui-sound-style.md`, «Реестр ассетов»).
///
/// Нет id в реестре — `null`, и экран рисует заглушку: логика не ждёт арта
/// (`docs/plan-sborki-29-09.md`, «Арт: минимум для демо»).
class AssetRegistry {
  AssetRegistry._(this._root);

  /// Разбор уже прочитанного `registry.json` — для тестов и [load].
  factory AssetRegistry.parse(String json) {
    final Object? root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('registry.json: корень не объект');
    }
    return AssetRegistry._(root);
  }

  /// Каталог копии арта внутри сборки.
  static const String base = 'assets/art/';

  /// Реестр из бандла приложения. Строку кеширует сам `rootBundle`, поэтому
  /// своего статического кеша нет: будущее, созданное в зоне одного теста,
  /// не должно оставаться «вечно ждущим» для следующего (комната без арта).
  static Future<AssetRegistry> load() =>
      rootBundle.loadString('${base}registry.json').then(AssetRegistry.parse);

  final Map<String, Object?> _root;

  Map<String, Object?>? _entry(String group, String id) {
    final Object? g = _root[group];
    if (g is! Map<String, Object?>) return null;
    final Object? e = g[id];
    return e is Map<String, Object?> ? e : null;
  }

  static String? _path(Object? rel) => rel is String ? '$base$rel' : null;

  /// id в группе (`buildings`, `pets`, `finni`, `room`, `items`,
  /// `room_objects`).
  List<String> ids(String group) {
    final Object? g = _root[group];
    if (g is! Map<String, Object?>) return const <String>[];
    return g.keys.where((String k) => !k.startsWith('_')).toList();
  }

  /// Здание города: `home`, `grocery`, `job-centre`, `pet-shop`, `park`,
  /// `cinema`, `piggy-bank`. [variant] — `d045` / `d072`, иначе выбранное.
  String? building(String id, {String? variant}) {
    final Map<String, Object?>? e = _entry('buildings', id);
    if (e == null) return null;
    final Object? variants = e['variants'];
    if (variant != null && variants is Map<String, Object?>) {
      final String? v = _path(variants[variant]);
      if (v != null) return v;
    }
    return _path(e['default']);
  }

  /// Питомец по id из `economy.json` (`pet_kitten`, `pet_fish`, …).
  /// Теги: `sleep`, `wake`.
  SpriteRef? pet(String id) => _sprite('pets', id);

  /// Картинка вещи каталога по id из `economy.json` (`snack`, `cloth_cap`,
  /// `poster_city`, …) — hi-res, плотность в имени файла. Нет арта — null.
  /// Сначала `items`, потом `night_items` — заготовки трека арта для
  /// новых блюд и декора (29.09): оживают, когда id есть в `economy.json`.
  String? item(String id) =>
      _path((_entry('items', id) ?? _entry('night_items', id))?['image']);

  /// Пиксельный значок верхней плашки (`hud_coin`, `hud_bolt`, `hud_smile`).
  String? hudIcon(String id) => _path(_entry('hud_icons', id)?['image']);

  /// Картинка работы на доске смен по id работы (`cashier`, `courier`, …):
  /// группа `job_pictures` называет предмет, картинка — как у [item].
  String? jobPicture(String jobId) {
    final Object? id = _root['job_pictures'] is Map<String, Object?>
        ? (_root['job_pictures']! as Map<String, Object?>)[jobId]
        : null;
    return id is String ? item(id) : null;
  }

  /// Финни по виду (`finni-a1`, `finni-a2`, `finni-a3`).
  /// Теги: `idle-1`…`idle-4` (облик), у a1 ещё `walk`.
  SpriteRef? finni(String species) => _sprite('finni', species);

  /// Кадры ходьбы вида Финни для всех обликов (`finni_walk`, теги
  /// `walk-1`…`walk-4` по номеру облика) — ветка арта 29.09. Нет группы в
  /// реестре — null, и Финни идёт прежними кадрами или покачиваясь.
  SpriteRef? finniWalk(String species) => _sprite('finni_walk', species);

  /// Есть ли у вида Финни тег анимации ([tag]: `walk`, `wave`, …) — по
  /// списку `tags` реестра.
  bool finniHasTag(String species, String tag) {
    final Object? tags = _entry('finni', species)?['tags'];
    return tags is List<Object?> && tags.contains(tag);
  }

  /// Статичные облики Финни — для выбора в онбординге.
  List<String> finniLooks(String species) {
    final Object? looks = _entry('finni', species)?['looks'];
    if (looks is! List<Object?>) return const <String>[];
    return <String>[
      for (final Object? l in looks)
        if (_path(l) case final String p) p,
    ];
  }

  /// Фон комнаты. [variant] — `s7`, `s11`, `s23`, `s42`, иначе выбранный.
  String? room({String id = 'home', String? variant}) {
    final Map<String, Object?>? e = _entry('room', id);
    if (e == null) return null;
    final Object? variants = e['variants'];
    if (variant != null && variants is Map<String, Object?>) {
      final String? v = _path(variants[variant]);
      if (v != null) return v;
    }
    return _path(e['default']);
  }

  /// Файл со слотами комнаты (Финни, питомец, предмет) в пикселях фона.
  /// Размер фона комнаты [id] в логических px (`size_px`): мир общей
  /// раскладки комнаты. Нет — null.
  Size? roomSize(String id) {
    final Object? v = _entry('room', id)?['size_px'];
    if (v is! List<Object?> || v.length != 2 || v[0] is! num || v[1] is! num) {
      return null;
    }
    return Size((v[0]! as num).toDouble(), (v[1]! as num).toDouble());
  }

  String? roomSlots({String id = 'home'}) =>
      _path(_entry('room', id)?['slots']);

  /// Передний план комнаты стадии (кровать, коробки, картина): тот же фон,
  /// всё прочее прозрачно. Рисуется поверх двери и комода — они стоят за
  /// мебелью, когда узкий экран вдвигает их в комнату.
  String? roomFront(String id) => _path(_entry('room', id)?['front']);

  /// Предмет комнаты, который можно нажать (`door`, `dresser`, `fridge`):
  /// картинка и размер в логических px. Нет арта — null, предмета нет.
  RoomObjectArt? roomObject(String id) {
    final Map<String, Object?>? e = _entry('room_objects', id);
    final String? path = _path(e?['image']);
    final Object? size = e?['size_px'];
    if (path == null ||
        size is! List<Object?> ||
        size.length != 2 ||
        size[0] is! num ||
        size[1] is! num) {
      return null;
    }
    return (
      path: path,
      width: (size[0]! as num).toDouble(),
      height: (size[1]! as num).toDouble(),
    );
  }

  /// Все пути к файлам, на которые ссылается реестр, — для теста «копия
  /// арта в сборке полная».
  Iterable<String> get allPaths sync* {
    Iterable<String> walk(Object? node) sync* {
      if (node is Map<String, Object?>) {
        for (final MapEntry<String, Object?> e in node.entries) {
          if (e.key == 'source') continue; // исходники вне сборки
          yield* walk(e.value);
        }
      } else if (node is List<Object?>) {
        for (final Object? v in node) {
          yield* walk(v);
        }
      } else if (node is String &&
          (node.endsWith('.png') || node.endsWith('.json')) &&
          !node.startsWith('gen-test')) {
        yield '$base$node';
      }
    }

    for (final MapEntry<String, Object?> g in _root.entries) {
      if (g.key.startsWith('_')) continue;
      yield* walk(g.value);
    }
  }

  SpriteRef? _sprite(String group, String id) {
    final Map<String, Object?>? e = _entry(group, id);
    if (e == null) return null;
    final String? sheet = _path(e['sheet']);
    final String? data = _path(e['data']);
    if (sheet == null || data == null) return null;
    return SpriteRef(sheet: sheet, data: data);
  }
}

/// Картинка предмета комнаты и его размер в логических px.
typedef RoomObjectArt = ({String path, double width, double height});

/// Спрайт-лист: картинка-лента и её `.json` с кадрами и тегами.
class SpriteRef {
  const SpriteRef({required this.sheet, required this.data});

  final String sheet;
  final String data;

  @override
  bool operator ==(Object other) =>
      other is SpriteRef && other.sheet == sheet && other.data == data;

  @override
  int get hashCode => Object.hash(sheet, data);
}
