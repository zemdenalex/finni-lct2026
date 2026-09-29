import 'dart:io';

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/core/art/sprite_sheet.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/world_harness.dart' show contentWorld;

/// Ловит: реестр в `assets/art/` разошёлся с файлами (забыли
/// `tools/sync_app_art.py` после правки арта) — в сборке была бы дыра на
/// месте здания или питомца; спрайт-лист с тегом за пределами кадров.
void main() {
  final AssetRegistry reg =
      AssetRegistry.parse(File('assets/art/registry.json').readAsStringSync());

  test('каждый файл из реестра лежит в assets/art/', () {
    final List<String> missing = <String>[
      for (final String p in reg.allPaths)
        if (!File(p).existsSync()) p,
    ];
    expect(missing, isEmpty);
  });

  test('копия реестра в сборке совпадает с assets/registry.json', () {
    expect(File('assets/art/registry.json').readAsStringSync(),
        File('../../assets/registry.json').readAsStringSync(),
        reason: 'запусти python tools/sync_app_art.py');
  }, skip: !File('../../assets/registry.json').existsSync());

  test('все спрайт-листы читаются, теги Финни и питомцев на месте', () {
    for (final String species in reg.ids('finni')) {
      final SpriteSheet s =
          SpriteSheet.parse(File(reg.finni(species)!.data).readAsStringSync());
      expect(s.tags.keys, contains('idle-1'), reason: species);
    }
    for (final String id in reg.ids('pets')) {
      final SpriteSheet s =
          SpriteSheet.parse(File(reg.pet(id)!.data).readAsStringSync());
      expect(s.tags.keys, containsAll(<String>['sleep', 'wake']), reason: id);
    }
  });

  test('семь зданий города есть в реестре', () {
    for (final String id in <String>[
      'home',
      'grocery',
      'job-centre',
      'pet-shop',
      'park',
      'cinema',
      'piggy-bank',
    ]) {
      expect(reg.building(id), isNotNull, reason: id);
    }
    expect(reg.building('nope'), isNull);
  });

  test('у каждой вещи магазина и декора есть картинка', () {
    // Новая вещь в каталоге без арта — карточка без картинки, комната без
    // вещи: ловим расхождение каталога мира и реестра здесь.
    const Set<WorldCatalogCategory> shop = <WorldCatalogCategory>{
      WorldCatalogCategory.food,
      WorldCatalogCategory.snack,
      WorldCatalogCategory.clothes,
      WorldCatalogCategory.decor,
    };
    final List<String> ids = <String>[
      for (final WorldCatalogItem i in contentWorld().catalog)
        if (shop.contains(i.category)) i.id,
    ];
    expect(ids, hasLength(greaterThan(10)));
    expect(<String>[
      for (final String id in ids)
        if (reg.item(id) == null) id
    ], isEmpty);
    expect(reg.item('nope'), isNull);
  });

  // Ловит: дверь, комод с копилкой или передний план комнаты не доехали
  // до сборки (забыли sync_app_art.py) — предмет молча пропадает из комнаты,
  // и нажать на него нечем; слот холодильника этапа 4 потерян.
  test('предметы комнаты: дверь, комод, передний план и слоты', () {
    for (final String id in <String>['door', 'dresser']) {
      final RoomObjectArt? o = reg.roomObject(id);
      expect(o, isNotNull, reason: id);
      expect(File(o!.path).existsSync(), isTrue, reason: o.path);
      expect(o.width, greaterThan(0), reason: id);
    }
    // Дверь ≈ 1,1 роста Финни (~114 px), комод с копилкой — с кровать.
    expect(reg.roomObject('door')!.height, inInclusiveRange(115, 135));
    expect(reg.roomObject('dresser')!.height, inInclusiveRange(50, 75));
    expect(reg.roomObject('nope'), isNull);
    for (final String stage in <String>['village', 'town', 'moscow']) {
      expect(File(reg.roomFront(stage)!).existsSync(), isTrue, reason: stage);
      final RoomSlots s =
          RoomSlots.parse(File(reg.roomSlots(id: stage)!).readAsStringSync());
      expect(s.taps.keys, contains('bed'), reason: stage);
      expect(s.objects.keys, containsAll(<String>['door', 'fridge']),
          reason: stage);
      // Копилка: в арте города и Москвы — зона, в деревне — комод.
      expect(s.taps.containsKey('piggy') || s.objects.containsKey('dresser'),
          isTrue,
          reason: stage);
      // Зоны не попали в точки слотов (у них тоже есть x и y).
      expect(s.points.keys, isNot(contains('bed')), reason: stage);
    }
  });

  test('pingpong не повторяет крайние кадры', () {
    final SpriteSheet s = SpriteSheet.parse('''
{"frames":[
 {"frame":{"x":0,"y":0,"w":4,"h":4},"duration":100},
 {"frame":{"x":4,"y":0,"w":4,"h":4},"duration":100},
 {"frame":{"x":8,"y":0,"w":4,"h":4},"duration":100},
 {"frame":{"x":12,"y":0,"w":4,"h":4},"duration":100}],
 "meta":{"frameTags":[
  {"name":"a","from":0,"to":2,"direction":"pingpong"},
  {"name":"b","from":1,"to":3,"direction":"reverse"}]}}''');
    expect(s.sequence('a'), <int>[0, 1, 2, 1]);
    expect(s.sequence('b'), <int>[3, 2, 1]);
    expect(s.sequence('missing'), <int>[0, 1, 2, 3]);
  });

  test('тег вне кадров — понятная ошибка', () {
    expect(
      () => SpriteSheet.parse('{"frames":[{"frame":{"x":0,"y":0,"w":1,"h":1}}],'
          '"meta":{"frameTags":[{"name":"x","from":0,"to":5}]}}'),
      throwsA(isA<FormatException>()
          .having((FormatException e) => e.message, 'message', contains('x'))),
    );
  });
}
