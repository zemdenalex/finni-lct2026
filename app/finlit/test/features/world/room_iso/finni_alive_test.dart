import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/world_harness.dart';
import '../../../support/world_screens.dart';

/// Финни в iso-комнате живой (Денис 20.10: «в комнате у Финни нет анимации»).
///
/// Защищает: под джойстиком Финни идёт кадрами ходьбы и смотрит, куда идёт;
/// стоя — дышит (два кадра покоя почти одинаковые); на касание — подпрыгивает.
/// «Анимации» выключены — ни дыхания, ни прыжка.
/// Уронит: джойстик снова двигает Финни стоячей картинкой (ходьба только по
/// пути к вещи), нет поворота, дыхание без проверки «Анимаций», прыжок на
/// касание при выключенных анимациях.
/// Почему не ловят другие: `room_screen_iso_test` проверяет, что джойстик
/// двигает Финни, но не чем он нарисован; кадры спрайта — `sprite_anim`.

Future<void> _pumpRoom(WidgetTester tester, {World? world}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    await pumpWorldScreen(tester, const RoomScreen(),
        world: world ?? livingWorld(worldKinds.last));
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  await tester.pump();
}

final Finder _finni = find.byKey(const ValueKey<String>('room:finni'));

/// Финни нарисован: на экране есть кадр его спрайта (а не пустое место,
/// пока лист ходьбы грузится). Настя 20.10: «при движении Финни моделька
/// пропадает вообще, остаётся только надпись рядом с ним».
bool _drawn(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
        find.descendant(of: _finni, matching: find.byType(CustomPaint)))
    .any((CustomPaint c) => c.painter != null);

/// Мир с фронтальной комнатой (откат флагом `room.view`).
World _frontLiving() {
  final World w = contentFrontWorld();
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return w;
}

/// Видна ли картинка ходьбы.
bool _walking(WidgetTester tester) => tester
    .widget<Visibility>(find
        .ancestor(
            of: find.byKey(const ValueKey<String>('room:finni:walk'),
                skipOffstage: false),
            matching: find.byType(Visibility, skipOffstage: false))
        .first)
    .visible;

List<Matrix4> _transforms(WidgetTester tester) => <Matrix4>[
      for (final Transform t in tester.widgetList<Transform>(
          find.descendant(of: _finni, matching: find.byType(Transform))))
        t.transform,
    ];

bool _facesLeft(WidgetTester tester) =>
    _transforms(tester).any((Matrix4 m) => m.storage[0] < 0);

double _lift(WidgetTester tester) => _transforms(tester)
    .map((Matrix4 m) => -m.storage[13])
    .fold(0, (double a, double b) => a > b ? a : b);

Future<void> _drag(WidgetTester tester, TestGesture g, Offset step) async {
  for (int i = 0; i < 6; i++) {
    await g.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(rootBundle.clear);

  testWidgets('джойстик: кадры ходьбы и поворот по ходу', (tester) async {
    await _pumpRoom(tester);
    expect(_walking(tester), isFalse, reason: 'стоит — кадры покоя');
    final Finder rest = find.byKey(const ValueKey<String>('room:iso:joystick'));
    final TestGesture g = await tester.startGesture(tester.getCenter(rest));
    await g.moveBy(const Offset(-10, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_drawn(tester), isTrue, reason: 'первый шаг — Финни виден');
    await _drag(tester, g, const Offset(-10, 0));
    expect(_walking(tester), isTrue, reason: 'идёт под джойстиком — ходьба');
    expect(_drawn(tester), isTrue, reason: 'идёт — Финни виден');
    expect(_facesLeft(tester), isTrue, reason: 'идёт влево — смотрит влево');
    await _drag(tester, g, const Offset(20, 0));
    expect(_facesLeft(tester), isFalse, reason: 'повернул вправо');
    await g.up();
    await tester.pump();
    expect(_walking(tester), isFalse, reason: 'отпустил — снова стоит');
    expect(tester.takeException(), isNull);
  });

  testWidgets('касание — прыжок; «Анимации» выкл. — без прыжка',
      (tester) async {
    await _pumpRoom(tester);
    await tester.tap(_finni);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_lift(tester), greaterThan(4), reason: 'в середине прыжка выше');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_lift(tester), lessThan(0.5), reason: 'приземлился');

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpRoom(tester);
    await tester.tap(_finni);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_lift(tester), lessThan(0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('стоит — дышит; «Анимации» выкл. — неподвижен', (tester) async {
    late final SpriteRef poses;
    await tester.runAsync(() async {
      poses = (await RoomArt.load()).registry.finniPoses('finni-a1')!;
    });
    // Одна поза (один кадр): движение только от дыхания.
    Future<bool> moves({required bool breathe, required bool reduce}) async {
      final GlobalKey key = GlobalKey();
      bool differ = false;
      await tester.runAsync(() async {
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 120,
                height: 140,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SpriteAnim(
                      sprite: poses,
                      tag: 'joy-1',
                      breathe: breathe,
                      height: 100),
                ),
              ),
            ),
          ),
        ));
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump(const Duration(milliseconds: 1));
        }
        Future<Uint8List> shot() async {
          final ui.Image img = await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          return (await img.toByteData())!.buffer.asUint8List();
        }

        final Uint8List a = await shot();
        // Половина вдоха — вершина.
        await tester.pump(SpriteAnim.breathPeriod ~/ 2);
        final Uint8List b = await shot();
        expect(a.length, b.length);
        for (int i = 0; i < a.length; i++) {
          if (a[i] != b[i]) {
            differ = true;
            break;
          }
        }
        await tester.pumpWidget(const SizedBox());
      });
      return differ;
    }

    expect(await moves(breathe: true, reduce: false), isTrue,
        reason: 'дышит — картинка меняется');
    expect(await moves(breathe: false, reduce: false), isFalse,
        reason: 'без дыхания один кадр стоит');
    expect(await moves(breathe: true, reduce: true), isFalse,
        reason: '«Анимации» выкл. — не дышит');
  });

  for (final (String, World Function()?) room in <(String, World Function()?)>[
    ('iso', null),
    ('фронтальная', _frontLiving),
  ]) {
    testWidgets('${room.$1}: идёт к кровати — Финни виден на каждом кадре',
        (tester) async {
      await _pumpRoom(tester, world: room.$2?.call());
      expect(_drawn(tester), isTrue, reason: 'стоит — виден');
      await tester.tap(find.byKey(const ValueKey<String>('room:bed')));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(_drawn(tester), isTrue, reason: 'кадр ${i + 1} пути — виден');
      }
      // Дошёл: открылся вопрос кровати — закрыть экран и таймеры.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  }
}
