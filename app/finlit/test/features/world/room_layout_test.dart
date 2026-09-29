import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_layout.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Общая раскладка комнаты (`content/room_layout.json`, Денис 29.09):
/// комната — главное меню, предметы на одних местах во всех стадиях.
void main() {
  late RoomArt art;
  late RoomLayout layout;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    art = await RoomArt.load();
    layout = art.layout!;
  });

  test('копия в сборке совпадает с content/room_layout.json', () {
    expect(File('assets/content/world/room_layout.json').readAsStringSync(),
        File('../../content/room_layout.json').readAsStringSync());
  });

  test('каждый слот с действием ведёт к своему экрану и есть в сцене', () {
    const Map<String, String> actionOf = <String, String>{
      'door': 'city',
      'bed': 'sleep',
      'desk_chair': 'jobs',
      'piggy': 'piggy',
      'bedside_cabinet': 'piggy',
      'fridge': 'food',
    };
    final Map<String, String?> got = <String, String?>{
      for (final MapEntry<String, LayoutSlot> e in layout.tappable)
        e.key: e.value.action,
    };
    expect(got, actionOf);
    for (final String slot in got.keys) {
      expect(layoutTap(RoomLayout.objectOf(slot)), isNotNull, reason: slot);
    }
  });

  test('места с касанием не перекрываются, кроме заявленных пар', () {
    final List<MapEntry<String, LayoutSlot>> t = layout.tappable;
    for (int i = 0; i < t.length; i++) {
      for (int j = i + 1; j < t.length; j++) {
        final Rect a = t[i].value.rect, b = t[j].value.rect;
        final Rect x = a.intersect(b);
        final bool overlap = x.width > 1e-9 && x.height > 1e-9;
        final bool declared = t[i].value.overlaps.contains(t[j].key) ||
            t[j].value.overlaps.contains(t[i].key);
        expect(overlap && !declared, isFalse,
            reason: '${t[i].key} × ${t[j].key}');
      }
    }
  });

  test('копилка на тумбе ложится в сцене поверх тумбы', () {
    final List<String> order = RoomSlots.fromLayout(
            layout, layout.stages['town']!, const Size(368, 368))
        .taps
        .keys
        .toList();
    expect(order.indexOf('piggy'), greaterThan(order.indexOf('cabinet')),
        reason: 'в стеке сцены копилка ложится поверх тумбы: $order');
  });

  test('перспектива и зона ходьбы — из файла', () {
    final Map<String, Object?> raw = jsonDecode(
            File('assets/content/world/room_layout.json').readAsStringSync())
        as Map<String, Object?>;
    final Map<String, Object?> d = raw['depth_scale']! as Map<String, Object?>;
    final Map<String, Object?> w = raw['walk']! as Map<String, Object?>;
    expect(layout.depth.at(layout.walk.top),
        lessThan(layout.depth.at(layout.walk.bottom)));
    expect(layout.depth.at(0), d['scale_back']);
    expect(layout.depth.at(1), d['scale_front']);
    final RoomSlots s = RoomSlots.fromLayout(
        layout, layout.stages['village']!, const Size(400, 300));
    expect(
        s.walk,
        Rect.fromLTRB((w['x0']! as num) * 400, (w['y0']! as num) * 300,
            (w['x1']! as num) * 400, (w['y1']! as num) * 300));
  });

  test('камера: мёртвая зона, край комнаты, предмет действия на экране', () {
    // Финни в мёртвой зоне — камера стоит.
    expect(
        followCameraX(
            prev: -100, viewport: 360, world: 560, target: 280, deadZone: 0.3),
        -100);
    // Ушёл вправо до края мира — камера у края, не дальше.
    expect(
        followCameraX(
            prev: -100, viewport: 360, world: 560, target: 555, deadZone: 0.3),
        -200);
    // Предмет у правого края — целиком на экране.
    final double x = followCameraX(
        prev: 0,
        viewport: 360,
        world: 560,
        target: 200,
        deadZone: 0.3,
        focus: const Rect.fromLTWH(420, 50, 60, 100));
    expect(420 + x, greaterThanOrEqualTo(0));
    expect(480 + x, lessThanOrEqualTo(360));
  });

  test('HUD сверху: комната встаёт под полосу, масштаб по оставшейся высоте',
      () {
    final RoomSlots s = RoomSlots.fromLayout(
        layout, layout.stages['town']!, const Size(368, 368));
    final RoomFrame f =
        roomFrame(s, box: const Size(640, 560), hires: true, topInset: 120);
    expect(f.top, 120);
    expect(f.k * 368, closeTo(440, 1e-6));
    // Длинный портрет: масштаб ограничен (кровать и стол на ¾), но комната
    // по центру под HUD — без пустой полосы с одной стороны.
    final RoomFrame tall =
        roomFrame(s, box: const Size(360, 700), hires: true, topInset: 100);
    final double rh = tall.k * 368;
    expect(tall.top, closeTo(100 + (700 - 100 - rh) / 2, 1e-6),
        reason: 'по центру под HUD — поровну потолка и пола');
    expect(tall.k * 368, lessThan(600), reason: 'масштаб ограничен');
  });

  Future<void> pumpRoom(WidgetTester tester, Widget room,
      {bool noMotion = false}) async {
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(
          size: const Size(360, 560), disableAnimations: noMotion),
      child: MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 360, height: 560, child: room),
        ),
      ),
    ));
    await tester.pump();
  }

  RoomScene scene({String? near, List<String> decor = const <String>[]}) =>
      RoomScene(
        art: art,
        stage: WorldStage.town,
        species: 'finni-a2',
        idleTag: 'idle-1',
        finniName: 'Финни',
        happiness: 60,
        finniNear: near,
        decorIds: decor,
        onFridgeTap: () {},
      );

  double cameraX(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const ValueKey<String>('room:camera')))
      .transform
      .getTranslation()
      .x;

  testWidgets(
      'портрет: Финни у холодильника — камера у края, холодильник виден',
      (WidgetTester tester) async {
    await pumpRoom(tester, scene(), noMotion: true);
    final double home = cameraX(tester);
    await pumpRoom(tester, scene(near: 'fridge'), noMotion: true);
    // «Анимации» выключены — камера на месте в том же кадре, без догона.
    final double x = cameraX(tester);
    // Готовый фон почти целиком в кадре: камера могла уже стоять у края.
    expect(x, lessThanOrEqualTo(home), reason: 'камера не ушла влево');
    final Rect fridge =
        tester.getRect(find.byKey(const ValueKey<String>('room:fridge')));
    expect(fridge.left, greaterThanOrEqualTo(0));
    expect(fridge.right, lessThanOrEqualTo(360.5));
    final double rw =
        tester.getSize(find.byKey(const ValueKey<String>('room:camera'))).width;
    expect(x, greaterThanOrEqualTo(360 - rw - 1e-6), reason: 'не дальше края');
  });

  testWidgets('касание каждого предмета зовёт действие из файла',
      (WidgetTester tester) async {
    final List<String> fired = <String>[];
    await pumpRoom(
        tester,
        RoomScene(
          art: art,
          stage: WorldStage.village,
          species: 'finni-a2',
          idleTag: 'idle-1',
          finniName: 'Финни',
          happiness: 60,
          onDoorTap: () => fired.add('city'),
          onBedTap: () => fired.add('sleep'),
          onDeskTap: () => fired.add('jobs'),
          onPiggyTap: () => fired.add('piggy'),
          onFridgeTap: () => fired.add('food'),
        ),
        noMotion: true);
    for (final MapEntry<String, LayoutSlot> e in layout.tappable) {
      final String id = RoomLayout.objectOf(e.key);
      final Finder f = find.byKey(ValueKey<String>('room:$id'));
      // Касание — в видимую часть зоны (у краёв кадра предмет срезан).
      final Rect r =
          tester.getRect(f).intersect(const Rect.fromLTWH(0, 0, 360, 560));
      fired.clear();
      await tester.tapAt(r.center);
      await tester.pump();
      expect(fired, <String>[e.value.action!], reason: e.key);
    }
  });

  // Ловит (ревью 29.09): `else` прежних зон прилип к внутреннему `if`, и
  // без раскладки у комнаты пропадали кровать и копилка.
  testWidgets('без файла раскладки — прежние зоны кровати и копилки',
      (WidgetTester tester) async {
    await pumpRoom(
        tester,
        RoomScene(
          art: RoomArt(art.registry, art.slots, byRoom: art.byRoom),
          stage: WorldStage.town,
          species: 'finni-a2',
          idleTag: 'idle-1',
          finniName: 'Финни',
          happiness: 60,
          onBedTap: () {},
          onPiggyTap: () {},
        ),
        noMotion: true);
    expect(find.byKey(const ValueKey<String>('room:bed')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('room:piggy')), findsOneWidget);
  });

  testWidgets('с камерой геометрия сцены — в px экрана',
      (WidgetTester tester) async {
    RoomGeometry? g;
    await pumpRoom(
        tester,
        RoomScene(
          art: art,
          stage: WorldStage.town,
          species: 'finni-a2',
          idleTag: 'idle-1',
          finniName: 'Финни',
          happiness: 60,
          finniNear: 'fridge',
          onGeometry: (RoomGeometry x) => g = x,
        ),
        noMotion: true);
    await tester.pump();
    // Ноги Финни на экране — центр его места (FinniWalker) по x.
    final double onScreen = tester
        .getCenter(find.byKey(const ValueKey<String>('room:finni:spot')))
        .dx;
    final Rect byGeo = g!.finniOnScreen(g!.feet);
    expect((byGeo.center.dx - onScreen).abs(), lessThan(8),
        reason: 'без сдвига камеры геометрия уезжала на весь сдвиг');
  });

  // Ловит: в высоком портрете кровать у края срезана наполовину (Денис:
  // передний план — чуть срезан кадром, не наполовину).
  for (final double sceneH in <double>[420, 560, 700]) {
    testWidgets('в покое кровать и стол видны на ¾ · сцена 360×$sceneH',
        (WidgetTester tester) async {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(360, sceneH), disableAnimations: true),
        child: MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 360, height: sceneH, child: scene()),
          ),
        ),
      ));
      await tester.pump();
      final double want = layout.camera.foregroundShown;
      expect(want, greaterThan(0), reason: 'значение — из файла');
      // Кровать и стол нарисованы в фоне: их место на экране — место
      // слота стадии на картинке фона.
      final Rect bg = tester.getRect(find
          .byWidgetPredicate((Widget w) =>
              w is PixelImage && (w.path ?? '').contains('gen-town'))
          .last);
      final RoomLayout town = layout.forStage(layout.stages['town']!);
      for (final String id in <String>['bed', 'desk_chair']) {
        final Rect f = town.slots[id]!.rect;
        final Rect r = Rect.fromLTWH(
            bg.left + f.left * bg.width,
            bg.top + f.top * bg.height,
            f.width * bg.width,
            f.height * bg.height);
        final Rect seen = r.intersect(Rect.fromLTWH(0, 0, 360, sceneH));
        expect(seen.width / r.width, greaterThanOrEqualTo(want - 0.01),
            reason: '$id: видно ${seen.width} из ${r.width}');
      }
    });
  }

  testWidgets('купленный глобус стоит на своём месте раскладки',
      (WidgetTester tester) async {
    await pumpRoom(tester, scene(decor: <String>['decor_globe']),
        noMotion: true);
    final Finder g =
        find.byKey(const ValueKey<String>('room:decor:decor_globe'));
    expect(g, findsOneWidget);
    final Rect box = layout.decor['decor_globe']!;
    // Фон комнаты на экране (с учётом сдвига камеры).
    final Rect bg = tester.getRect(find
        .byWidgetPredicate((Widget w) =>
            w is PixelImage && (w.path ?? '').contains('gen-town'))
        .last);
    final Rect r = tester.getRect(g);
    expect((r.left - (bg.left + box.left * bg.width)).abs(), lessThan(1));
    expect((r.top - (bg.top + box.top * bg.height)).abs(), lessThan(1));
  });

  test('у каждой работы и вещи группы «Вещи» есть картинка в сборке', () async {
    final AssetRegistry reg = art.registry;
    final Map<String, Object?> eco =
        jsonDecode(File('assets/content/world/economy.json').readAsStringSync())
            as Map<String, Object?>;
    final List<String> jobs = <String>[
      for (final String k in (eco['jobs']! as Map<String, Object?>).keys)
        if (!k.startsWith('_')) k,
    ];
    final List<String> things = <String>[
      for (final Object? i
          in (eco['decor']! as Map<String, Object?>)['items']! as List<Object?>)
        if ((i! as Map<String, Object?>)['group'] == 'things')
          (i as Map<String, Object?>)['id']! as String,
    ];
    expect(things, isNotEmpty);
    for (final String p in <String>[
      for (final String j in jobs) reg.jobPicture(j) ?? 'нет: $j',
      for (final String t in things) reg.item(t) ?? 'нет: $t',
      for (final LayoutStage s in layout.stages.values)
        for (final String id in s.furniture.values)
          reg.item(id) ?? reg.roomObject(id)?.path ?? 'нет: $id',
    ]) {
      await rootBundle.load(p); // бросит, если файла нет в сборке
    }
  });

  // Готовые фоны команды (мебель нарисована в фоне): рамки предметов,
  // замеренные по картинкам assets/hires/room/gen-*@3x.png (доли кадра,
  // x0, y0, x1, y1) — независимо от чисел в room_layout.json.
  const Map<String, Map<String, List<double>>> drawn =
      <String, Map<String, List<double>>>{
    'village': <String, List<double>>{
      'door': <double>[0.095, 0.085, 0.275, 0.45],
      'cabinet': <double>[0.29, 0.345, 0.44, 0.475],
      'piggy': <double>[0.345, 0.265, 0.435, 0.345],
      'fridge': <double>[0.835, 0.15, 0.995, 0.495],
      'bed': <double>[0.0, 0.51, 0.355, 1.0],
      'desk': <double>[0.84, 0.47, 1.0, 0.9],
    },
    'town': <String, List<double>>{
      'door': <double>[0.05, 0.05, 0.245, 0.47],
      'cabinet': <double>[0.24, 0.335, 0.385, 0.495],
      'piggy': <double>[0.26, 0.25, 0.36, 0.35],
      'fridge': <double>[0.8, 0.175, 0.995, 0.5],
      'bed': <double>[0.0, 0.54, 0.305, 1.0],
      'desk': <double>[0.8, 0.52, 1.0, 0.93],
    },
    'moscow': <String, List<double>>{
      'door': <double>[0.04, 0.05, 0.245, 0.52],
      'cabinet': <double>[0.25, 0.36, 0.37, 0.53],
      'piggy': <double>[0.28, 0.31, 0.35, 0.375],
      'fridge': <double>[0.855, 0.115, 1.0, 0.54],
      'bed': <double>[0.0, 0.49, 0.35, 0.87],
      'desk': <double>[0.81, 0.53, 1.0, 0.95],
    },
  };

  for (final String st in drawn.keys) {
    test(
        '$st: фон с мебелью, каждая зона касания лежит на нарисованном предмете',
        () {
      final LayoutStage s = layout.stages[st]!;
      expect(s.backgroundHasFurniture, isTrue);
      expect(art.registry.room(id: s.background), contains('gen-$st'));
      const Size size = Size(1, 1);
      final Map<String, Rect> taps = RoomSlots.fromLayout(layout, s, size).taps;
      expect(taps.keys.toSet(), drawn[st]!.keys.toSet());
      for (final MapEntry<String, List<double>> e in drawn[st]!.entries) {
        final List<double> b = e.value;
        final Rect obj = Rect.fromLTRB(b[0], b[1], b[2], b[3]);
        final Rect zone = taps[e.key]!;
        final Rect x = zone.intersect(obj);
        expect(x.width > 0 && x.height > 0, isTrue, reason: '$st ${e.key}');
        // Зона почти целиком на предмете, центр зоны — на предмете.
        expect(
            x.width * x.height / (zone.width * zone.height), greaterThan(0.6),
            reason: '$st ${e.key}: $zone vs $obj');
        expect(obj.contains(zone.center), isTrue, reason: '$st ${e.key}');
      }
      // Места с касанием стадии не перекрываются, кроме заявленных пар.
      final List<MapEntry<String, LayoutSlot>> t = layout.forStage(s).tappable;
      for (int i = 0; i < t.length; i++) {
        for (int j = i + 1; j < t.length; j++) {
          final Rect x = t[i].value.rect.intersect(t[j].value.rect);
          final bool declared = t[i].value.overlaps.contains(t[j].key) ||
              t[j].value.overlaps.contains(t[i].key);
          expect(x.width > 1e-9 && x.height > 1e-9 && !declared, isFalse,
              reason: '$st: ${t[i].key} × ${t[j].key}');
        }
      }
    });
  }
}
