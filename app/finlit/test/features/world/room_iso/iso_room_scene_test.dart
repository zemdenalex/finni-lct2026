import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_skins.dart';
import 'package:finlit/features/world/room_iso/iso_painter.dart';
import 'package:finlit/features/world/room_iso/iso_room.dart';
import 'package:finlit/features/world/room_iso/iso_room_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/world_harness.dart';

/// Iso room scene (V2) on the game's real data and pictures.
///
/// Protects: every bought decor id and every furniture skin of the catalog
/// is drawn in the iso room on its slot with its own picture; Finni is drawn
/// in front of or behind furniture by the §6 order; the camera zooms to
/// Finni and back and pinch stays in [1, maxZoom]; a placed thing can be
/// dragged and the rules of the room still refuse a bad place.
/// Would fail on: a catalog id whose slot is missing from
/// `room_layout_iso.json` (it silently disappears), a skin keyed by its
/// object (`desk`) instead of the slot (`desk_chair`), a reversed draw order
/// in the scene, a zoom without limits, a drop that skips the rules.

IsoRoomSpec _spec() => IsoRoomSpec.parse(
    File('assets/content/world/room_layout_iso.json').readAsStringSync());

/// The 8 decor places of the front room (`decorPlace`), written out: a place
/// lost from the code must fail here, not shrink the list.
const Set<String> decorSlots = <String>{
  'decor_wall',
  'decor_floor',
  'decor_ceiling',
  'item_sill',
  'decor_books',
  'decor_globe',
  'decor_bear',
  'decor_rug',
};

IsoRoomSpec _withFinni(IsoRoomSpec s, int x, int y) => IsoRoomSpec(
      grid: s.grid,
      slots: s.slots,
      door: s.door,
      window: s.window,
      finniX: x,
      finniY: y,
      finniH: s.finniH,
      finniR: s.finniR,
      petH: s.petH,
      bandBottom: s.bandBottom,
      bandTop: s.bandTop,
      highBottom: s.highBottom,
      highTop: s.highTop,
    );

void main() {
  final IsoRoomSpec spec = _spec();
  final WorldGame world = contentWorld();
  final List<String> catalog = <String>[
    for (final WorldCatalogItem i in world.catalog) i.id,
  ];
  late RoomArt art;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    art = await RoomArt.load();
  });

  /// One bought id per decor place, from the catalog.
  List<String> onePerDecorPlace() {
    final Map<String, String> bySlot = <String, String>{};
    for (final String id in catalog.where(isDecorId)) {
      bySlot.putIfAbsent(decorPlace(id).slot, () => id);
    }
    return bySlot.values.toList();
  }

  /// One skin per piece of furniture, by slot (`bed` → `skin_bed__…`).
  Map<String, String> oneSkinEach() => furnitureSkins(equippedSkins(
      catalog.where((String id) => id.startsWith('skin_')).toList(),
      const <String, String>{}));

  test('каждый декор каталога встаёт на место iso-раскладки', () {
    final List<String> decor = catalog.where(isDecorId).toList();
    expect(decor, isNotEmpty);
    expect(<String>{
      for (final String id in decor) decorPlace(id).slot
    }, decorSlots, reason: 'каталог покрывает все 8 мест декора');
    for (final String id in decor) {
      expect(spec.slots.containsKey(decorPlace(id).slot), isTrue,
          reason: '$id → ${decorPlace(id).slot}');
    }
  });

  test('скины мебели — по именам слотов iso: bed, desk_chair, bedside_cabinet',
      () {
    final Map<String, String> skins = oneSkinEach();
    expect(
        skins.keys.toSet(), <String>{'bed', 'desk_chair', 'bedside_cabinet'});
    for (final String slot in skins.keys) {
      expect(spec.slots[slot]?.layer, IsoLayer.floor, reason: slot);
    }
  });

  Future<void> pump(WidgetTester tester, Widget scene,
      {Size size = const Size(360, 640)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: true),
      child: MaterialApp(home: Material(child: scene)),
    ));
    await tester.pump();
  }

  IsoRoomScene scene({
    IsoRoomSpec? s,
    WorldStage stage = WorldStage.town,
    List<String> decor = const <String>[],
    Map<String, String> skins = const <String, String>{},
    Map<String, RoomIsoSpot> saved = const <String, RoomIsoSpot>{},
    bool arrange = false,
    ValueChanged<String>? onSelect,
    void Function(String, RoomIsoSpot)? onPlace,
    ValueChanged<String>? onRefuse,
  }) =>
      IsoRoomScene(
        art: art,
        stage: stage,
        species: 'finni-a2',
        idleTag: 'idle-1',
        finniName: 'Финни',
        happiness: 60,
        spec: s ?? spec,
        decorIds: decor,
        furnitureSkins: skins,
        saved: saved,
        arrange: arrange,
        onSelect: onSelect,
        onPlace: onPlace,
        onRefuse: onRefuse,
      );

  Set<String> assetsIn(WidgetTester tester, String slot) => <String>{
        for (final Image i in tester.widgetList<Image>(find.descendant(
            of: find.byKey(ValueKey<String>('room:iso:slot:$slot')),
            matching: find.byType(Image))))
          if (i.image case final AssetImage a) a.assetName,
      };

  testWidgets('8 мест декора и 3 скина — в сцене, каждое со своей картинкой',
      (WidgetTester tester) async {
    final AssetRegistry reg = art.registry;
    final List<String> decor = onePerDecorPlace();
    final Map<String, String> skins = oneSkinEach();
    expect(decor, hasLength(8));
    await pump(tester, scene(decor: decor, skins: skins));
    for (final String id in decor) {
      final String slot = decorPlace(id).slot;
      expect(
          find.byKey(ValueKey<String>('room:iso:slot:$slot')), findsOneWidget,
          reason: slot);
      final String? want = reg.item(id);
      expect(want, isNotNull, reason: 'нет картинки у $id');
      expect(assetsIn(tester, slot), contains(want), reason: '$slot ← $id');
    }
    for (final MapEntry<String, String> e in skins.entries) {
      final Set<String> got = assetsIn(tester, e.key);
      expect(got, contains(reg.item(e.value)), reason: '${e.key} ← ${e.value}');
      final String? def =
          spec.slots[e.key]!.sprite?.replaceAll('{stage}', 'town');
      final String? defPath =
          def == null ? null : (reg.item(def) ?? reg.roomObject(def)?.path);
      expect(got, isNot(contains(defPath)),
          reason: '${e.key}: видна мебель по умолчанию, а не скин');
    }
  });

  // Per stage and per place (финал 20.10): the room of each stage has its
  // own default furniture, and a place lost at one stage must fail by name.
  for (final WorldStage stage in WorldStage.values) {
    group('стадия ${stage.name}', () {
      for (final String slot in decorSlots) {
        testWidgets('декор «$slot» — на своём месте, своя картинка',
            (WidgetTester tester) async {
          final String id = onePerDecorPlace()
              .firstWhere((String d) => decorPlace(d).slot == slot);
          await pump(tester, scene(stage: stage, decor: onePerDecorPlace()));
          // The room opens close to Finni: «Вся комната» shows every place.
          await tester.tap(find.byKey(const ValueKey<String>('room:iso:camera')));
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey<String>('room:iso:slot:$slot')),
              findsOneWidget);
          expect(assetsIn(tester, slot), contains(art.registry.item(id)),
              reason: '$slot ← $id');
          expect(
              tester
                  .getRect(find.byKey(ValueKey<String>('room:iso:slot:$slot')))
                  .overlaps(Offset.zero & const Size(360, 640)),
              isTrue,
              reason: '$slot в кадре');
        });
      }
      for (final String slot in <String>[
        'bed',
        'desk_chair',
        'bedside_cabinet'
      ]) {
        testWidgets('скин «$slot» — вместо мебели по умолчанию',
            (WidgetTester tester) async {
          final Map<String, String> skins = oneSkinEach();
          await pump(tester, scene(stage: stage, skins: skins));
          final Set<String> got = assetsIn(tester, slot);
          expect(got, contains(art.registry.item(skins[slot]!)),
              reason: '$slot ← ${skins[slot]}');
          final String? def =
              spec.slots[slot]!.sprite?.replaceAll('{stage}', stage.name);
          final String? defPath = def == null
              ? null
              : (art.registry.item(def) ?? art.registry.roomObject(def)?.path);
          expect(defPath, isNotNull, reason: '$slot: у стадии есть мебель');
          expect(got, isNot(contains(defPath)));
          // Without the skin the stage's own furniture is drawn.
          await pump(tester, Container());
          await pump(tester, scene(stage: stage));
          expect(assetsIn(tester, slot), contains(defPath),
              reason: '$slot: мебель стадии ${stage.name}');
        });
      }
    });
  }

  // Every pet of the game, on a phone held either way: its zone is a finger
  // and TalkBack reads a button «Питомец» (the front room's pet was smaller
  // than 48 dp, проверка Саши 20.10).
  for (final String petId in <String>[
    'pet_fish',
    'pet_hamster',
    'pet_frog',
    'pet_turtle',
    'pet_kitten',
    'pet_snake',
    'pet_axolotl',
    'pet_dog',
  ]) {
    for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
      testWidgets(
          '$petId · ${size.width.toInt()}×${size.height.toInt()}: '
          'зона ≥ 48 dp, кнопка «Питомец»', (WidgetTester tester) async {
        final SemanticsHandle sem = tester.ensureSemantics();
        await pump(
            tester,
            IsoRoomScene(
              art: art,
              stage: WorldStage.village,
              species: 'finni-a2',
              idleTag: 'idle-1',
              finniName: 'Финни',
              happiness: 60,
              spec: spec,
              topInset: 108,
              petId: petId,
              onPetTap: () {},
            ),
            size: size);
        final Finder pet = find.byKey(ValueKey<String>('room:pet:$petId'));
        expect(art.registry.pet(petId), isNotNull, reason: 'картинка $petId');
        final Size s = tester.getSize(pet);
        expect(s.width, greaterThanOrEqualTo(48), reason: '$s');
        expect(s.height, greaterThanOrEqualTo(48), reason: '$s');
        expect(
            tester.getSemantics(pet),
            matchesSemantics(
                label: 'Питомец', isButton: true, hasTapAction: true));
        sem.dispose();
      });
    }
  }

  // Высокий экран (1440×3120 → 411×891 dp): над и под комнатой оставалась
  // голая полоса фона (кадры 20.10); в 0.1.3 комната заполняла высокие
  // экраны. Would fail on: nothing painted around the room.
  test('высокий экран: над комнатой стена, под ней пол — не пусто', () async {
    const Size view = Size(411, 891);
    final double k = 411 * 0.96 / spec.grid.contentSize.width;
    final Offset off = Offset(
        (view.width - spec.grid.contentSize.width * k) / 2,
        (view.height - spec.grid.contentSize.height * k) / 2);
    final ui.PictureRecorder rec = ui.PictureRecorder();
    IsoShellPainter(spec: spec, k: k, offset: off).paint(Canvas(rec), view);
    final ui.Image img = await rec
        .endRecording()
        .toImage(view.width.toInt(), view.height.toInt());
    final ByteData bytes = (await img.toByteData())!;
    int alpha(double x, double y) =>
        bytes.getUint8(((y.toInt() * view.width.toInt()) + x.toInt()) * 4 + 3);
    final double roomTop = off.dy,
        roomBottom = off.dy + spec.grid.contentSize.height * k;
    expect(roomTop, greaterThan(150), reason: 'настройка: место над комнатой');
    // Off the centre line: walls and tiles meet there (anti-aliased seam).
    expect(alpha(view.width / 2 + 13, roomTop / 2), 255,
        reason: 'над комнатой');
    expect(alpha(view.width / 2 + 13, (roomBottom + view.height) / 2), 255,
        reason: 'под комнатой');
  });

  // Утро: Финни подошёл к кровати и закрывал её середину — касание по
  // кровати гладило Финни (day_mode_screens_test, 20.10). Would fail on:
  // Finni standing right at the bed's side again.
  for (final WorldStage stage in WorldStage.values) {
    for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
      testWidgets(
          '${stage.name} · ${size.width.toInt()}×${size.height.toInt()}: '
          'Финни у кровати — середина кровати нажимается',
          (WidgetTester tester) async {
        int bed = 0, finni = 0;
        IsoRoomScene at(String? near) => IsoRoomScene(
              art: art,
              stage: stage,
              species: 'finni-a2',
              idleTag: 'idle-1',
              finniName: 'Финни',
              happiness: 60,
              spec: spec,
              topInset: 108,
              finniNear: near,
              onBedTap: () => bed++,
              onFinniTap: () => finni++,
            );
        await pump(tester, at(null), size: size);
        await pump(tester, at('bed'), size: size);
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.byKey(const ValueKey<String>('room:bed')));
        await tester.pump();
        expect((bed, finni), (1, 0), reason: 'касание середины кровати');
      });
    }
  }

  testWidgets('Финни перед кроватью и за ней — по порядку §6',
      (WidgetTester tester) async {
    // Bed moved to (2,3)–(4,4); Finni at (2,4) is in front, at (2,2) behind.
    const Map<String, RoomIsoSpot> bed = <String, RoomIsoSpot>{
      'bed': (plane: 'floor', x: 2, y: 3),
    };
    int index(String key) {
      final Finder f = find.byKey(const ValueKey<String>('room:finni:spot'));
      final Stack s = tester.widget<Stack>(
          find.ancestor(of: f, matching: find.byType(Stack)).first);
      return s.children
          .indexWhere((Widget w) => w.key == ValueKey<String>(key));
    }

    await pump(tester, scene(s: _withFinni(spec, 2, 4), saved: bed));
    expect(index('room:finni:spot'), greaterThan(index('room:iso:slot:bed')),
        reason: 'Финни перед кроватью рисуется после неё');
    await pump(tester, Container());
    await pump(tester, scene(s: _withFinni(spec, 2, 2), saved: bed));
    expect(index('room:finni:spot'), lessThan(index('room:iso:slot:bed')),
        reason: 'Финни за кроватью рисуется до неё');
  });

  group('камера', () {
    const ValueKey<String> spot = ValueKey<String>('room:finni:spot');
    double finniH(WidgetTester t) => t.getSize(find.byKey(spot)).height;

    testWidgets('«Вся комната» отдаляет, «К Финни» — снова к нему',
        (WidgetTester tester) async {
      // The room opens close to Finni (n6-room2).
      await pump(tester, scene());
      final double close = finniH(tester);
      expect(find.text('Вся комната'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('room:iso:camera')));
      await tester.pumpAndSettle();
      final double h0 = finniH(tester);
      expect(close / h0, greaterThan(1.15));
      expect(close / h0, lessThanOrEqualTo(IsoRoomScene.finniZoom + 0.01));
      expect(find.text('К Финни'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('room:iso:camera')));
      await tester.pumpAndSettle();
      expect(finniH(tester), closeTo(close, 0.01));
      final Rect f = tester.getRect(find.byKey(spot));
      expect((f.center.dx - 180).abs(), lessThan(360 * 0.2),
          reason: 'Финни у середины экрана: ${f.center}');
      expect(find.text('Вся комната'), findsOneWidget);
    });

    testWidgets('щипок: не больше maxZoom и не меньше всей комнаты',
        (WidgetTester tester) async {
      await pump(tester, scene());
      // From the whole room (the room opens close to Finni).
      await tester.tap(find.byKey(const ValueKey<String>('room:iso:camera')));
      await tester.pumpAndSettle();
      final double h0 = finniH(tester);
      const Offset c = Offset(180, 330);
      Future<void> pinch(double from, double to) async {
        final TestGesture a =
            await tester.startGesture(c - Offset(from, 0), pointer: 1);
        final TestGesture b =
            await tester.startGesture(c + Offset(from, 0), pointer: 2);
        for (int i = 1; i <= 10; i++) {
          final double d = (to - from) / 10;
          await a.moveBy(Offset(-d, 0));
          await b.moveBy(Offset(d, 0));
          await tester.pump();
        }
        await a.up();
        await b.up();
        await tester.pumpAndSettle();
      }

      await pinch(20, 170); // ×8.5 asked
      expect(finniH(tester) / h0, closeTo(IsoRoomScene.maxZoom, 0.01));
      await pinch(170, 5); // ×0.03 asked
      expect(finniH(tester), closeTo(h0, 0.01));
    });

    testWidgets('от края назад комната едет сразу, без мёртвой зоны',
        (WidgetTester tester) async {
      // The room opens close to Finni: zoomed, so it pans.
      await pump(tester, scene());
      // Far past the right edge of the room, then 60 px back.
      final TestGesture g = await tester.startGesture(const Offset(100, 400));
      for (int i = 0; i < 10; i++) {
        await g.moveBy(const Offset(-80, 0));
        await tester.pump();
      }
      final double atEdge = tester.getCenter(find.byKey(spot)).dx;
      for (int i = 0; i < 3; i++) {
        await g.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byKey(spot)).dx - atEdge, closeTo(60, 0.5));
    });

    test('центр камеры держит комнату в кадре', () {
      const Size content = Size(384, 304), view = Size(360, 560);
      // Zoomed ×3 from fit 0.9: the room is wider than the view.
      final Offset c =
          isoClampCentre(const Offset(-500, 9000), content, view, 2.7);
      expect(c.dx, closeTo(180 / 2.7, 1e-9));
      expect(c.dy, closeTo(content.height - 280 / 2.7, 1e-9));
      // At fit the room is smaller than the view: centred.
      expect(isoClampCentre(Offset.zero, content, view, 0.9),
          Offset(content.width / 2, content.height / 2));
    });
  });

  group('перетаскивание в «Расставить»', () {
    Offset cellCentre(WidgetTester t, int x, int y) =>
        t.getCenter(find.byKey(ValueKey<String>('room:iso:cell:$x:$y')));

    testWidgets('кровать тащится на свободное место — onPlace с клеткой',
        (WidgetTester tester) async {
      final List<(String, RoomIsoSpot)> placed = <(String, RoomIsoSpot)>[];
      final List<String> refused = <String>[], selected = <String>[];
      await pump(
          tester,
          scene(
            arrange: true,
            onSelect: selected.add,
            onPlace: (String s, RoomIsoSpot p) => placed.add((s, p)),
            onRefuse: refused.add,
          ));
      final Offset d = cellCentre(tester, 2, 3) - cellCentre(tester, 0, 0);
      // Grab the bed by its right half: the fridge stands before the left.
      await tester.dragFrom(cellCentre(tester, 1, 0), d);
      await tester.pumpAndSettle();
      expect(selected, <String>['bed']);
      expect(refused, isEmpty);
      expect(placed, <(String, RoomIsoSpot)>[
        ('bed', (plane: 'floor', x: 2, y: 3)),
      ]);
    });

    testWidgets('на занятое место и на Финни — отказ словами, без записи',
        (WidgetTester tester) async {
      final List<(String, RoomIsoSpot)> placed = <(String, RoomIsoSpot)>[];
      final List<String> refused = <String>[];
      await pump(
          tester,
          scene(
            arrange: true,
            decor: const <String>['decor_globe'],
            onPlace: (String s, RoomIsoSpot p) => placed.add((s, p)),
            onRefuse: refused.add,
          ));
      // Bed (0,0)–(2,1) two cells along x: onto the cabinet at (2,0).
      await tester.dragFrom(cellCentre(tester, 1, 0),
          cellCentre(tester, 2, 0) - cellCentre(tester, 0, 0));
      await tester.pumpAndSettle();
      // Globe (5,1) onto Finni's cell.
      final IsoSlotSpec globe = spec.slots['decor_globe']!;
      await tester.dragFrom(
          tester.getCenter(
              find.byKey(const ValueKey<String>('room:iso:slot:decor_globe'))),
          cellCentre(tester, spec.finniX, spec.finniY) -
              cellCentre(tester, globe.x, globe.y));
      await tester.pumpAndSettle();
      expect(placed, isEmpty);
      expect(refused, <String>[
        'Здесь уже стоит другая вещь. Выбери свободное место.',
        'Здесь стоит Финни.',
      ]);
    });

    testWidgets('отменённое касание и второй палец — вещь остаётся на месте',
        (WidgetTester tester) async {
      final List<(String, RoomIsoSpot)> placed = <(String, RoomIsoSpot)>[];
      final List<String> refused = <String>[], selected = <String>[];
      await pump(
          tester,
          scene(
            arrange: true,
            onSelect: selected.add,
            onPlace: (String s, RoomIsoSpot p) => placed.add((s, p)),
            onRefuse: refused.add,
          ));
      final Offset bed = cellCentre(tester, 1, 0);
      final Offset step =
          (cellCentre(tester, 2, 3) - cellCentre(tester, 0, 0)) / 4;
      // 1. The OS cancels a drag over a free cell (back swipe, shade).
      final TestGesture a = await tester.startGesture(bed);
      for (int i = 0; i < 4; i++) {
        await a.moveBy(step);
        await tester.pump();
      }
      await a.cancel();
      await tester.pumpAndSettle();
      expect(placed, isEmpty, reason: 'отмена не ставит вещь');
      // 2. A pinch whose second finger lands on the bed, then the first
      // finger lifts and the second moves on: no drag of the bed.
      selected.clear();
      final TestGesture p1 =
          await tester.startGesture(cellCentre(tester, 3, 4), pointer: 7);
      final TestGesture p2 = await tester.startGesture(bed, pointer: 8);
      for (int i = 0; i < 4; i++) {
        await p1.moveBy(const Offset(0, 15));
        await p2.moveBy(const Offset(0, -15));
        await tester.pump();
      }
      await p1.up();
      await tester.pump();
      for (int i = 0; i < 4; i++) {
        await p2.moveBy(step);
        await tester.pump();
      }
      await p2.up();
      await tester.pumpAndSettle();
      expect(placed, isEmpty);
      expect(refused, isEmpty);
      expect(selected, isEmpty, reason: 'щипок не выбирает вещь');
    });

    testWidgets('постер переезжает с левой стены на правую',
        (WidgetTester tester) async {
      final List<(String, RoomIsoSpot)> placed = <(String, RoomIsoSpot)>[];
      await pump(
          tester,
          scene(
            arrange: true,
            decor: const <String>['poster_space'],
            onPlace: (String s, RoomIsoSpot p) => placed.add((s, p)),
          ));
      Offset wall(String side, int u) => tester
          .getCenter(find.byKey(ValueKey<String>('room:iso:wall:$side:$u')));
      // The poster spans left 1–2, high over the fridge (n6-room 20.10:
      // the fridge stands before the wall there). Grabbed by its top, moved
      // so that its centre lands between right slots 0 and 1.
      final Rect poster = tester.getRect(
          find.byKey(const ValueKey<String>('room:iso:slot:decor_wall')));
      final Offset to = (wall('right', 0) + wall('right', 1)) / 2;
      await tester.dragFrom(
          Offset(poster.center.dx, poster.top + poster.height * 0.2),
          to - poster.center);
      await tester.pumpAndSettle();
      expect(placed, <(String, RoomIsoSpot)>[
        ('decor_wall', (plane: 'right', x: 0, y: 0)),
      ]);
    });
  });
}
