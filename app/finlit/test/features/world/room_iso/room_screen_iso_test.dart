import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/room_iso/iso_room_scene.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_world.dart';
import '../../../support/world_harness.dart';

/// The room screen as shipped (`room.view: "iso"`, Денис 20.10).
///
/// Protects: the shipped room screen draws the iso room (not the front one);
/// its furniture does what the front room's did — bed asks «Лечь спать?»,
/// piggy opens the piggy bank, the door the city, the fridge the shop on
/// «Еда», the desk the job board — at every stage and on a phone held either
/// way; «Расставить вещи» is in the menu although `room.customize` is off;
/// leaving the room does not throw (a lazy controller first created in
/// `dispose` did, 20.10).
/// Would fail on: the flag not reaching `RoomScreen`, a callback of the front
/// scene not wired into the iso one, a thing drawn but not reachable by a
/// finger, the arrange item gated on `room.customize` only.
/// Not covered elsewhere: `iso_room_scene_test` pumps the scene alone with
/// its own callbacks; `room_objects_test` runs the front room (rollback).

/// Mid-week at [stage]: the week runs, sleep is allowed.
World _livingAt(WorldStage stage) {
  final World w = FakeWorld(
      config: WorldConfig(stageByRent: false, stageMinPoints: <int>[
    for (final WorldStage s in WorldStage.values)
      s.index <= stage.index ? 0 : 1000,
  ]));
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  expect(w.snapshot.stage, stage, reason: 'настройка теста');
  expect(w.room.iso, isTrue, reason: 'сборка — iso');
  return w;
}

const Map<String, Size> _sizes = <String, Size>{
  ...bothOrientations,
  'альбомная 800×360': Size(800, 360),
  'портрет 360×800': Size(360, 800),
};

/// The room, shown whole ([showWholeRoom]: it opens close to Finni);
/// [whole] false — the first frame.
Future<void> _pumpRoom(WidgetTester tester, World w, Size size,
    {bool whole = true}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    await pumpWorldScreen(tester, const RoomScreen(), world: w, size: size);
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
  if (whole) await showWholeRoom(tester);
}

/// Finni walks to the thing first, then the screen or the dialog opens.
Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(RoomScene.roomWalk + const Duration(milliseconds: 150));
  await tester.pump();
}

/// Mid-week, the fish bought (a goal reached): it lives in the room.
World _withFish(WorldStage stage) {
  final World w = FakeWorld(
      config: WorldConfig(stageByRent: false, stageMinPoints: <int>[
    for (final WorldStage s in WorldStage.values)
      s.index <= stage.index ? 0 : 1000,
  ]));
  ok(w.chooseGoal('pet_fish'));
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
  for (int i = 0; i < 6 && w.snapshot.goal < 400; i++) {
    w.completeJob('consultant', score: 1);
    if (w.snapshot.free > 0) {
      ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
    }
  }
  ok(w.buy('pet_fish'));
  expect(w.snapshot.activePetId, 'pet_fish', reason: 'настройка');
  return w;
}

void main() {
  // Питомец — кнопка под палец (проверка Саши 20.10: во фронтальной комнате
  // зона питомца меньше 48 dp). Would fail on: the pet zone sized by its
  // picture, no button role, no label.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    for (final double font in <double>[1.0, 1.3]) {
      testWidgets(
          'питомец · ${o.key} · шрифт ×$font: зона ≥ 48 dp, кнопка '
          '«Питомец»', (WidgetTester tester) async {
        final SemanticsHandle sem = tester.ensureSemantics();
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await pumpWorldScreen(tester, const RoomScreen(),
              world: _withFish(WorldStage.village),
              size: o.value,
              textScale: font);
          for (int i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            await tester.pump();
          }
        });
        final Finder pet =
            find.byKey(const ValueKey<String>('room:pet:pet_fish'));
        expect(pet, findsOneWidget);
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

  // Джойстик (в 0.1.3 Финни в комнате водили пальцем по полу; в iso его не
  // было — регресс, finni 20.10). Would fail on: no joystick in the iso
  // room, the finger on the floor panning the camera instead of walking,
  // no thing button when Finni stops by the bed, a pad smaller than a finger.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets(
        'джойстик · ${o.key} · шрифт ×1,3: палец по полу ведёт '
        'Финни, у вещи — её кнопка', (WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: _livingAt(WorldStage.village),
            size: o.value,
            textScale: 1.3);
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      final Finder rest =
          find.byKey(const ValueKey<String>('room:iso:joystick'));
      expect(rest, findsOneWidget, reason: 'джойстик в покое виден');
      expect(tester.getSize(rest).shortestSide, greaterThanOrEqualTo(48));
      const ValueKey<String> spot = ValueKey<String>('room:finni:spot');
      // Against the door: the camera follows Finni (the room opens close to
      // him), so on screen he stays near the middle while the room moves.
      Offset finni() =>
          tester.getCenter(find.byKey(spot)) -
          tester.getCenter(find.byKey(const ValueKey<String>('room:door')));
      final Offset before = finni();
      final TestGesture g = await tester.startGesture(tester.getCenter(rest));
      // Up on the screen — into the room, toward the bed.
      for (int i = 1; i <= 6; i++) {
        await g.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey<String>('room:iso:pad')), findsOneWidget,
          reason: 'под пальцем — джойстик');
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final Offset after = finni();
      expect(after.dy, lessThan(before.dy - 20),
          reason: 'Финни ушёл вглубь комнаты: $before → $after');
      await g.up();
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('room:iso:pad')), findsNothing);
      final Offset stopped = finni();
      await tester.pump(const Duration(seconds: 1));
      expect(finni(), stopped,
          reason: 'отпустил — стоит');
      final Finder near = find.byKey(const ValueKey<String>('room:near'));
      expect(near, findsOneWidget, reason: 'Финни у вещи — её кнопка');
      expect(tester.getSize(near).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  }

  // Телефон на боку (800×360): комната, вписанная по высоте, выходила
  // мелкой — Финни ~45 dp (кадры 20.10). Would fail on: the room fitted
  // with the empty wall tops again, a thing pushed out of the frame.
  for (final double font in <double>[1.0, 1.3]) {
    testWidgets('800×360 · шрифт ×$font: Финни крупнее 56 dp, все вещи в кадре',
        (WidgetTester tester) async {
      await _pumpRoom(tester, _livingAt(WorldStage.town), const Size(800, 360),
          whole: false);
      if (font != 1.0) {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await pumpWorldScreen(tester, const RoomScreen(),
              world: _livingAt(WorldStage.town),
              size: const Size(800, 360),
              textScale: font);
          for (int i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            await tester.pump();
          }
        });
      }
      final Size finni = tester.getSize(find
          .descendant(
              of: find.byKey(const ValueKey<String>('room:finni')),
              matching: find.byType(SizedBox))
          .first);
      expect(finni.height, greaterThanOrEqualTo(56), reason: '$finni');
      // The first frame is close to Finni; «Вся комната» shows every thing.
      await showWholeRoom(tester);
      final Rect view = Offset.zero & const Size(800, 360);
      for (final String k in <String>[
        'room:bed',
        'room:piggy',
        'room:door',
        'room:fridge',
        'room:desk',
      ]) {
        final Rect r = tester.getRect(find.byKey(ValueKey<String>(k)));
        expect(view.intersect(r).height, greaterThan(r.height * 0.6),
            reason: '$k в кадре: $r');
        pointOn(tester, k);
      }
    });
  }

  test('сборка: комната в изометрии', () {
    expect(shippedDayContent.room.iso, isTrue);
    expect(contentConfig.room.iso, isTrue);
  });

  for (final WorldStage stage in WorldStage.values) {
    for (final MapEntry<String, Size> o in _sizes.entries) {
      testWidgets(
          '${stage.name} · ${o.key}: iso-комната; кровать, копилка, дверь, '
          'холодильник, стол — каждый ведёт на свой экран',
          (WidgetTester tester) async {
        Future<void> tapThing(String key) async {
          await _pumpRoom(tester, _livingAt(stage), o.value);
          expect(find.byType(IsoRoomScene), findsOneWidget);
          expect(find.byType(RoomScene), findsNothing);
          await tester.tapAt(pointOn(tester, key));
          await _step(tester);
        }

        await tapThing('room:bed');
        expect(find.text('Лечь спать?'), findsOneWidget);

        await tapThing('room:piggy');
        expect(find.byType(PiggyScreen), findsOneWidget);

        await tapThing('room:door');
        expect(find.byType(CityScreen), findsOneWidget);

        await tapThing('room:fridge');
        expect(find.byType(WorldShopScreen), findsOneWidget);
        expect(
            DefaultTabController.of(tester.element(find.byType(TabBar))).index,
            0,
            reason: 'холодильник открывает «Еду»');

        await tapThing('room:desk');
        expect(find.byType(JobBoardScreen), findsOneWidget);

        // Leaving the room (the screen above replaced it) threw no error.
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      });
    }
  }

  // «Расставить вещи» — как в 0.1.3: только при `room.customize` (finni
  // 20.10). Would fail on: the item shown with the flag off (the V2 branch
  // showed it for iso always), or missing with the flag on.
  for (final bool customize in <bool>[false, true]) {
    testWidgets(
        '«Расставить вещи» ${customize ? 'есть' : 'нет'} при room.customize '
        '${customize ? 'вкл' : 'выкл'}', (WidgetTester tester) async {
      final World w = customize
          ? FakeWorld(
              config: const WorldConfig(room: RoomCatalog(enabled: true)))
          : _livingAt(WorldStage.village);
      if (customize) {
        ok(w.startWeek());
        ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      }
      expect(w.room.iso, isTrue, reason: 'настройка');
      expect(w.room.enabled, customize, reason: 'настройка');
      await _pumpRoom(tester, w, portrait);
      await tester.tap(find.byKey(const ValueKey<String>('room:menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          find.byKey(const ValueKey<String>('room:settings')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('room:arrange')),
          customize ? findsOneWidget : findsNothing);
      if (!customize) return;
      await tester.tap(find.byKey(const ValueKey<String>('room:arrange')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<IsoRoomScene>(find.byType(IsoRoomScene)).arrange,
          isTrue);
    });
  }
}
