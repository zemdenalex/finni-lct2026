import 'dart:convert';
import 'dart:math' as math;

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/fridge_stock.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/room_layout.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Мир посреди недели на стадии [stage]: неделя идёт, «Спать» доступно.
World _livingAt(WorldStage stage) {
  final World w = FakeWorld(
      config: WorldConfig(
          // Стадия по очкам: тест про экран стадии, а не про переезд.
          stageByRent: false,
          stageMinPoints: <int>[
        for (final WorldStage s in WorldStage.values)
          s.index <= stage.index ? 0 : 1000,
      ]));
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  expect(w.snapshot.stage, stage, reason: 'настройка теста');
  expect(w.phase, WeekPhase.living, reason: 'настройка теста');
  return w;
}

const Map<String, Size> _sizes = <String, Size>{
  ...bothOrientations,
  'альбомная 800×360': Size(800, 360),
  'портрет 360×800': Size(360, 800),
};

/// Зоны предметов комнаты (фидбек дизайнера 28.09, п. 4; холодильник —
/// этап 4, п. 7).
const List<String> _zones = <String>[
  'room:bed',
  'room:piggy',
  'room:door',
  'room:fridge',
];

/// Магазин открыт на вкладке «Еда»: касание холодильника ведёт к еде.
void _expectShopOnFood(WidgetTester tester) {
  expect(find.byType(WorldShopScreen), findsOneWidget);
  final TabController tabs =
      DefaultTabController.of(tester.element(find.byType(TabBar)));
  expect(tabs.index, 0, reason: 'вкладка «Еда» — первая');
  expect(
      find.byKey(const ValueKey<String>('card:food_simple')), findsOneWidget);
}

/// Самая большая рамка спрайта в группе реестра (frame_px), в px фона.
Size _largestFrame(Map<String, Object?> registry, String group) {
  double w = 0, h = 0;
  for (final MapEntry<String, Object?> e
      in (registry[group]! as Map<String, Object?>).entries) {
    if (e.value case {'frame_px': [final num fw, final num fh]}) {
      w = math.max(w, fw.toDouble());
      h = math.max(h, fh.toDouble());
    }
  }
  return Size(w, h);
}

/// [inner] целиком внутри [outer] (с допуском на округление, 0,5 px).
bool _within(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

/// Коробка «низ по центру» в точке [p].
Rect _standing(Offset p, Size s) =>
    Rect.fromLTWH(p.dx - s.width / 2, p.dy - s.height, s.width, s.height);

Future<void> _pumpRoom(WidgetTester tester, World w, Size size) async {
  // Новое дерево, а не обновление прежнего: иначе Navigator с открытым
  // диалогом или экраном переживает перезапуск.
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    await pumpWorldScreen(tester, const RoomScreen(), world: w, size: size);
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
}

/// Спрайты анимируются бесконечно — pumpAndSettle не дождётся покоя.
///
/// Касание предмета: Финни сперва идёт к нему ([RoomScene.roomWalk]), потом
/// действие — экран или диалог строится кадром позже.
Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(RoomScene.roomWalk + const Duration(milliseconds: 150));
  await tester.pump();
}

List<HitTestEntry> _hits(WidgetTester tester, Offset p) {
  final HitTestResult r = HitTestResult();
  tester.binding.hitTestInView(r, p, tester.view.viewId);
  return r.path.toList();
}

bool _reaches(WidgetTester tester, Offset p, String key) {
  final RenderObject target =
      tester.renderObject(find.byKey(ValueKey<String>(key)));
  return _hits(tester, p).any((HitTestEntry e) => identical(e.target, target));
}

/// Точка на экране, где палец попадает в [key]: внутри сцены и не под
/// Финни или питомцем. Нет такой — null.
Offset? _tapPoint(WidgetTester tester, String key, Rect scene) {
  final Rect r =
      tester.getRect(find.byKey(ValueKey<String>(key))).intersect(scene);
  if (r.width <= 0 || r.height <= 0) return null;
  const List<double> f = <double>[0.5, 0.3, 0.7, 0.15, 0.85];
  for (final double fy in f) {
    for (final double fx in f) {
      final Offset p = Offset(r.left + r.width * fx, r.top + r.height * fy);
      if (_reaches(tester, p, key)) return p;
    }
  }
  return null;
}

void main() {
  for (final WorldStage stage in WorldStage.values) {
    for (final MapEntry<String, Size> o in _sizes.entries) {
      // Ловит: кровать, копилка и дверь в комнате — просто картинка
      // (дизайнер 28.09 искала их пальцем), зона не на своём предмете или
      // накрыта Финни, питомцем или краем сцены.
      testWidgets(
          '${stage.name} · ${o.key}: кровать → «Лечь спать?», '
          'копилка → S9, дверь → город', (WidgetTester tester) async {
        Future<Offset> pointFor(String key) async {
          await _pumpRoom(tester, _livingAt(stage), o.value);
          final Rect scene = tester.getRect(find.byType(RoomScene));
          final Offset? p = _tapPoint(tester, key, scene);
          expect(p, isNotNull, reason: '$key: не попасть пальцем');
          return p!;
        }

        await tester.tapAt(await pointFor('room:bed'));
        await _step(tester);
        expect(find.text('Лечь спать?'), findsOneWidget);

        await tester.tapAt(await pointFor('room:piggy'));
        await _step(tester);
        expect(find.byType(PiggyScreen), findsOneWidget);

        await tester.tapAt(await pointFor('room:door'));
        await _step(tester);
        expect(find.byType(CityScreen), findsOneWidget);

        await tester.tapAt(await pointFor('room:fridge'));
        await _step(tester);
        _expectShopOnFood(tester);
      });

      // Ловит: холодильник не на экране или срезан краем, полки показывают
      // не запас недели (приём пищи не забрал порцию, перекус не лёг на
      // полку).
      testWidgets(
          '${stage.name} · ${o.key}: холодильник виден, на полках — '
          'запас недели', (WidgetTester tester) async {
        final World w = _livingAt(stage);
        ok(w.eat('food_simple'));
        ok(w.eat('food_soup'));
        await _pumpRoom(tester, w, o.value);
        final FridgeStock stock = fridgeOf(w.snapshot);
        expect(stock.portions, w.snapshot.mealsPerWeek - 2,
            reason: 'настройка');
        expect(stock.portions, greaterThan(0), reason: 'настройка');
        final Rect scene = tester.getRect(find.byType(RoomScene));
        final Rect fridge =
            tester.getRect(find.byKey(const ValueKey<String>('room:fridge')));
        expect(_within(fridge, scene), isTrue, reason: 'срезан: $fridge');
        final Finder portions = find.byWidgetPredicate((Widget x) =>
            x.key is ValueKey<String> &&
            (x.key! as ValueKey<String>)
                .value
                .startsWith('room:fridge:portion'));
        // Готовый фон с мебелью: холодильник нарисован в фоне, второй
        // (с полками) поверх не рисуется — еда открывается касанием.
        late final RoomArt art;
        await tester.runAsync(() async => art = await RoomArt.load());
        if (art.layout?.stages[roomIdByStage[stage]]?.backgroundHasFurniture ??
            false) {
          expect(portions, findsNothing);
          return;
        }
        expect(portions, findsNWidgets(stock.portions));
        for (final Element e in portions.evaluate()) {
          final Rect r = tester.getRect(find.byWidget(e.widget));
          expect(_within(r, fridge), isTrue, reason: 'порция вне холодильника');
        }
      });

      // Ловит: холодильник встал на Финни, питомца, декор, дверь, комод или
      // зону касания из арта. Проверка по слотам: питомец и декор — на всех
      // своих местах с самой большой картинкой, даже если их ещё нет.
      testWidgets('${stage.name} · ${o.key}: холодильник ничего не накрывает',
          (WidgetTester tester) async {
        await _pumpRoom(tester, _livingAt(stage), o.value);
        final Size box = tester.getSize(find.byType(RoomScene));
        late final RoomArt art;
        late final Map<String, Object?> json;
        await tester.runAsync(() async {
          art = await RoomArt.load();
          json = jsonDecode(await rootBundle.loadString(
              '${AssetRegistry.base}registry.json')) as Map<String, Object?>;
        });
        // Проверка — про прежние слоты стадии. Когда сцена рисует общую
        // раскладку (её фон есть в реестре), этих слотов на экране нет:
        // холодильник раскладки проверяет «холодильник виден» по экрану.
        final LayoutStage? ls = art.layout?.stages[roomIdByStage[stage]];
        if (ls != null && art.registry.room(id: ls.background) != null) {
          return;
        }
        final RoomSlots slots = art.slotsFor(roomIdByStage[stage]);
        final Map<String, Size> sizes = <String, Size>{
          for (final String id in slots.objects.keys)
            if (art.registry.roomObject(id) case final RoomObjectArt a)
              id: Size(a.width, a.height),
        };
        expect(sizes.keys, contains('fridge'));
        final Size finni = _largestFrame(json, 'finni');
        final Size pet = _largestFrame(json, 'pets');
        final double sh = slots.size.height;
        Rect decor(String id) {
          final DecorPlace d = decorPlace(id);
          return _standing(
              slots.slot(
                  slots.points.containsKey(d.slot) ? d.slot : 'item_sill'),
              Size(d.width * sh, d.height * sh));
        }

        for (final (bool hasPet, bool awake) in <(bool, bool)>[
          (false, false),
          (true, false),
          (true, true),
        ]) {
          final RoomFrame f = roomFrame(slots,
              box: box, hires: true, hasPet: hasPet, petAwake: awake);
          final Map<String, Rect> placed = placeRoomObjects(slots, sizes,
              sceneLeft: -f.left / f.k, sceneRight: (box.width - f.left) / f.k);
          final Rect fridge = placed['fridge']!;
          final Map<String, Rect> others = <String, Rect>{
            'Финни': _standing(slots.slot('finni'), finni),
            'питомец на лежанке': _standing(slots.slot('pet_bed'), pet),
            'питомец на полу': _standing(slots.slot('pet_floor'), pet),
            for (final String id in <String>[
              'poster_city',
              'plant_floor',
              'plant_cactus',
              'light_bulb',
              'light_garland_long',
            ])
              'декор $id': decor(id),
            for (final MapEntry<String, Rect> e in placed.entries)
              if (e.key != 'fridge') e.key: e.value,
            for (final MapEntry<String, Rect> e in slots.taps.entries)
              'зона ${e.key}': e.value,
          };
          for (final MapEntry<String, Rect> e in others.entries) {
            final Rect cross = fridge.intersect(e.value);
            expect(cross.width <= 0.5 || cross.height <= 0.5, isTrue,
                reason: 'питомец $hasPet/$awake: холодильник $fridge '
                    'накрывает ${e.key} ${e.value}');
          }
          // Весь на экране: полки видны целиком.
          final Rect seen = Rect.fromLTWH(
              -f.left / f.k, -f.top / f.k, box.width / f.k, box.height / f.k);
          expect(_within(fridge, seen), isTrue,
              reason: 'питомец $hasPet/$awake: холодильник $fridge, '
                  'видно $seen');
        }
      });

      // Ловит: зона предмета перехватила касание Финни или HUD, стала
      // меньше пальца (48 dp) или вылезла из сцены на панель и кнопки.
      testWidgets(
          '${stage.name} · ${o.key}: зоны не накрывают Финни и HUD, '
          'не меньше 48 dp', (WidgetTester tester) async {
        await _pumpRoom(tester, _livingAt(stage), o.value);
        final Rect scene = tester.getRect(find.byType(RoomScene));
        final List<RenderObject> zones = <RenderObject>[
          for (final String k in _zones)
            tester.renderObject(find.byKey(ValueKey<String>(k))),
        ];
        bool anyZone(Offset p) => _hits(tester, p).any((HitTestEntry e) =>
            zones.any((RenderObject z) => identical(e.target, z)));

        final Offset finni =
            tester.getCenter(find.byKey(const ValueKey<String>('room:finni')));
        expect(_reaches(tester, finni, 'room:finni'), isTrue);
        expect(anyZone(finni), isFalse, reason: 'зона под центром Финни');
        for (final String hud in <String>[
          'hud:coins',
          'hud:energy',
          'hud:happiness',
          'room:goal',
          'room:now',
          'room:menu',
          'room:help',
        ]) {
          final Offset c = tester.getCenter(find.byKey(ValueKey<String>(hud)));
          expect(anyZone(c), isFalse, reason: 'зона над $hud');
        }
        for (final String k in _zones) {
          final Rect r = tester.getRect(find.byKey(ValueKey<String>(k)));
          expect(r.width, greaterThanOrEqualTo(48), reason: '$k $r');
          expect(r.height, greaterThanOrEqualTo(48), reason: '$k $r');
          // Видимая часть — тоже с палец: зона, выросшая до 48 dp полоской
          // у края сцены над срезанным предметом, не считается.
          final Rect seen = r.intersect(scene);
          expect(seen.width, greaterThanOrEqualTo(48),
              reason: '$k виден $seen');
          expect(seen.height, greaterThanOrEqualTo(48),
              reason: '$k виден $seen');
        }
      });
    }
  }

  // Ловит: TalkBack видит кровать, дверь и копилку надписью без действия
  // «нажать» (`Semantics(excludeSemantics: true)` без `onTap`).
  for (final WorldStage stage in WorldStage.values) {
    testWidgets('${stage.name}: предметы — кнопки TalkBack с действием',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      for (final (String label, Type screen) in <(String, Type)>[
        ('Дверь — в город', CityScreen),
        ('Копилка', PiggyScreen),
      ]) {
        await _pumpRoom(tester, _livingAt(stage), landscape);
        // «Копилка» есть и в нижней панели — берём ту, что в комнате; у
        // копилки в подписи ещё сумма («Копилка: 200 монет»).
        final Finder f = find.descendant(
            of: find.byType(RoomScene),
            matching:
                find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')));
        expect(f, findsOneWidget, reason: label);
        final SemanticsNode n = tester.getSemantics(f);
        expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
            reason: label);
        n.owner!.performAction(n.id, SemanticsAction.tap);
        await _step(tester);
        expect(find.byType(screen), findsOneWidget, reason: label);
      }
      // Холодильник: число порций — в подписи, касание — магазин с едой.
      await _pumpRoom(tester, _livingAt(stage), landscape);
      final Finder fridge =
          find.bySemanticsLabel('Холодильник, приёмов пищи осталось: 3');
      expect(fridge, findsOneWidget);
      final SemanticsNode fn = tester.getSemantics(fridge);
      expect(fn.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      fn.owner!.performAction(fn.id, SemanticsAction.tap);
      await _step(tester);
      _expectShopOnFood(tester);

      await _pumpRoom(tester, _livingAt(stage), landscape);
      final SemanticsNode bed =
          tester.getSemantics(find.bySemanticsLabel('Кровать — лечь спать'));
      bed.owner!.performAction(bed.id, SemanticsAction.tap);
      await _step(tester);
      expect(find.text('Лечь спать?'), findsOneWidget);
      h.dispose();
    });
  }
}
