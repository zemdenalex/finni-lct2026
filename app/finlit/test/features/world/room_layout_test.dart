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
    expect(x, lessThan(home), reason: 'камера сдвинулась вправо');
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
      for (final String id in <String>['bed', 'desk_chair']) {
        final Rect r =
            tester.getRect(find.byKey(ValueKey<String>('room:furniture:$id')));
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
    final Rect bg = tester.getRect(find.byWidgetPredicate((Widget w) =>
        w is PixelImage && (w.path ?? '').contains('shell-town')));
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
}
