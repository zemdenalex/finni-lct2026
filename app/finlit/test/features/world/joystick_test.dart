import 'dart:io';

import 'package:finlit/app_state.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Джойстик и простое 2.5D в комнате (Денис, 1001: «разработка хождения и
/// джойстика, простого 2.5d»).
///
/// Ловит: джойстик не двигает Финни или выводит его за пол, Финни не уходит
/// за кровать, когда стоит глубже её, у предмета нет кнопки действия, а
/// при выключенных «Анимациях» джойстик остаётся (ТЗ 3.6.7: без хода).
void main() {
  setUp(rootBundle.clear);

  Future<void> pump(WidgetTester tester,
      {Size size = portrait, bool animations = true, World? world}) async {
    await tester.runAsync(() async {
      AppState? app;
      if (!animations) {
        app = AppState(MemoryStorage());
        await app.boot();
        await app.updateProfile(app.game.profile
            .copyWith(settings: const GameSettings(animationsOn: false)));
      }
      await pumpWorldScreen(tester, const RoomScreen(),
          world: world ?? livingWorld(worldKinds.last), size: size, app: app);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  final Finder stick = find.byKey(const ValueKey<String>('room:joystick'));
  Offset feet(WidgetTester tester) => tester
      .getRect(find.byKey(const ValueKey<String>('room:finni:spot')))
      .topLeft;

  /// Где Финни в комнате, а не на экране: камера (общая раскладка) ведёт
  /// комнату за ним, и на экране он почти стоит — считать от двери.
  Offset inRoom(WidgetTester tester) =>
      feet(tester) -
      tester.getRect(find.byKey(const ValueKey<String>('room:door'))).topLeft;

  /// Держит ручку отведённой в [dir] (доля радиуса) [ms] миллисекунд.
  Future<TestGesture> hold(WidgetTester tester, Offset dir, int ms) async {
    final Offset c = tester.getCenter(stick);
    final TestGesture g = await tester.startGesture(c);
    await g.moveBy(dir * 20);
    await g.moveBy(dir * 28);
    for (int t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return g;
  }

  /// Порядок слоёв сцены: Финни раньше переднего плана — он за кроватью.
  bool behindFront(WidgetTester tester) {
    // Стек сцены — тот, где стоит Финни (у камеры снаружи есть свой).
    final Stack stack = tester
        .widgetList<Stack>(find.descendant(
            of: find.byType(RoomScene), matching: find.byType(Stack)))
        .firstWhere((Stack s) => s.children.any((Widget c) =>
            c.key is ValueKey<String> &&
            (c.key! as ValueKey<String>).value.startsWith('finni:frame:')));
    int finni = -1, front = -1;
    for (int i = 0; i < stack.children.length; i++) {
      final Key? k = stack.children[i].key;
      // Передний план: прежний слой `front` или кровать общей раскладки.
      if (k == const ValueKey<String>('room:front') ||
          k == const ValueKey<String>('room:furniture:bed')) {
        front = i;
      }
      if (k is ValueKey<String> && k.value.startsWith('finni:frame:')) {
        finni = i;
      }
    }
    expect(front, isNot(-1), reason: 'передний план в сцене');
    expect(finni, isNot(-1), reason: 'Финни в сцене');
    return finni < front;
  }

  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('${o.key}: джойстик вправо — Финни идёт, отпустил — стоит',
        (WidgetTester tester) async {
      await pump(tester, size: o.value);
      expect(stick, findsOneWidget);
      final Offset start = inRoom(tester);
      final TestGesture g = await hold(tester, const Offset(1, 0), 500);
      final Offset moved = inRoom(tester);
      expect(moved.dx, greaterThan(start.dx + 10),
          reason: 'Финни пошёл вправо');
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      final Offset stopped = inRoom(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(inRoom(tester), stopped, reason: 'ручку отпустили — стоит');
    });

    testWidgets('${o.key}: джойстик долго влево — Финни не уходит за пол',
        (WidgetTester tester) async {
      await pump(tester, size: o.value);
      final Rect scene = tester.getRect(find.byType(RoomScene));
      final TestGesture g = await hold(tester, const Offset(-1, 1), 4000);
      final Offset at = feet(tester);
      expect(at.dx, greaterThanOrEqualTo(scene.left));
      expect(at.dy, lessThanOrEqualTo(scene.bottom));
      await g.up();
      await tester.pump();
    });
  }

  // 2.5D: глубже линии кровати — Финни за передним планом, ближе — перед.
  testWidgets('глубина: у стены Финни за кроватью, у края — перед ней',
      (WidgetTester tester) async {
    await pump(tester, size: landscape);
    // Кровать общей раскладки — у левого края кадра (Денис 1050): к стене
    // Финни идёт вверх-влево, к кровати, а не вверх посреди комнаты.
    TestGesture g = await hold(tester, const Offset(-1, -1), 3000);
    await g.up();
    await tester.pump();
    expect(behindFront(tester), isTrue, reason: 'у стены — за кроватью');
    g = await hold(tester, const Offset(0, 1), 3000);
    await g.up();
    await tester.pump();
    expect(behindFront(tester), isFalse, reason: 'у края — перед кроватью');
  });

  // Ловит: у двери Финни нарисован поверх кровати (смоук 29.09, портрет):
  // дверь стоит на линии пола за кроватью, а место Финни у неё было на
  // переднем ряду, и глубина считалась только для джойстика.
  for (final WorldStage stage in WorldStage.values) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      testWidgets('${o.key} · ${stage.name}: у двери Финни за кроватью',
          (WidgetTester tester) async {
        await pump(tester, size: o.value, world: _livingAt(stage));
        expect(behindFront(tester), isFalse, reason: 'дома — перед кроватью');
        await tester.tapAt(pointOn(tester, 'room:door'));
        await tester.pump(); // кадр, с которого идёт ход
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(CityScreen), findsNothing, reason: 'ещё идёт');
        expect(behindFront(tester), isTrue,
            reason: 'у двери — в глубине, за кроватью');
        await tester.pump(RoomScene.roomWalk);
        await tester.pump();
      });
    }
  }

  testWidgets('у холодильника — кнопка его действия, она открывает еду',
      (WidgetTester tester) async {
    await pump(tester);
    final Finder near = find.byKey(const ValueKey<String>('room:near'));
    expect(near, findsNothing, reason: 'Финни ни у чего не стоит');
    final Rect fridge =
        tester.getRect(find.byKey(const ValueKey<String>('room:fridge')));
    // Ведём Финни к холодильнику, пока кнопка не назовёт его.
    final Finder label =
        find.descendant(of: near, matching: find.textContaining('Холодильник'));
    for (int i = 0; i < 40 && label.evaluate().isEmpty; i++) {
      final Offset d = fridge.centerLeft - feet(tester);
      if (d.distance < 1) break;
      final TestGesture g = await hold(tester, d / d.distance, 100);
      await g.up();
      await tester.pump();
    }
    expect(near, findsOneWidget);
    expect(
        find.descendant(of: near, matching: find.textContaining('Холодильник')),
        findsOneWidget);
    expect(tester.getSize(near).height, greaterThanOrEqualTo(48));
    await tester.tap(near);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorldShopScreen), findsOneWidget);
  });

  // Ловит (Денис 29.09: «снизу слишком много кнопок»): джойстик снова
  // виден всегда — он показывается, только пока палец ведёт по полу.
  testWidgets('джойстик не виден, пока палец не ведёт по полу',
      (WidgetTester tester) async {
    await pump(tester);
    final Finder pad = find.byKey(const ValueKey<String>('room:pad'));
    expect(pad, findsNothing, reason: 'без касания джойстика не видно');
    final Offset start = feet(tester);
    final TestGesture g = await hold(tester, const Offset(1, 0), 300);
    expect(pad, findsOneWidget, reason: 'палец ведёт — джойстик под ним');
    expect(feet(tester).dx, greaterThan(start.dx), reason: 'Финни идёт');
    await g.up();
    await tester.pump();
    expect(pad, findsNothing, reason: 'палец поднят — джойстик пропал');
  });

  testWidgets('«Анимации» выкл. — джойстика нет, ходьбы нет',
      (WidgetTester tester) async {
    await pump(tester, animations: false);
    expect(stick, findsNothing);
  });

  // ───────────────────────────── город ─────────────────────────────

  Future<void> pumpCity(WidgetTester tester,
      {Size size = portrait, bool animations = true}) async {
    await tester.runAsync(() async {
      AppState? app;
      if (!animations) {
        app = AppState(MemoryStorage());
        await app.boot();
        await app.updateProfile(app.game.profile
            .copyWith(settings: const GameSettings(animationsOn: false)));
      }
      await pumpWorldScreen(tester, const CityScreen(),
          world: livingWorld(worldKinds.last), size: size, app: app);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  final Finder cityStick = find.byKey(const ValueKey<String>('city:joystick'));
  Offset cityFeet(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('city:finni'))).topLeft;

  Future<void> holdCity(WidgetTester tester, Offset dir, int ms) async {
    final TestGesture g =
        await tester.startGesture(tester.getCenter(cityStick));
    await g.moveBy(dir * 20);
    await g.moveBy(dir * 28);
    for (int t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await g.up();
    await tester.pump();
  }

  /// Порядок слоёв карты: Финни раньше здания [id] — оно стоит перед ним.
  bool cityBehind(WidgetTester tester, String id) {
    final Stack stack = tester.widget<Stack>(find
        .descendant(
            of: find.byKey(const ValueKey<String>('city:map')),
            matching: find.byType(Stack))
        .first);
    int finni = -1, house = -1;
    for (int i = 0; i < stack.children.length; i++) {
      final Key? k = stack.children[i].key;
      if (k == ValueKey<String>('city:layer:$id')) house = i;
      if (k is ValueKey<String> && k.value.startsWith('city:finni:frame:')) {
        finni = i;
      }
    }
    expect(house, isNot(-1));
    expect(finni, isNot(-1));
    return finni < house;
  }

  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('город · ${o.key}: джойстик ведёт Финни по земле, не за край',
        (WidgetTester tester) async {
      await pumpCity(tester, size: o.value);
      expect(cityStick, findsOneWidget);
      final Offset start = cityFeet(tester);
      await holdCity(tester, const Offset(-1, 0), 400);
      expect((cityFeet(tester) - start).distance, greaterThan(10),
          reason: 'Финни пошёл');
      await holdCity(tester, const Offset(-1, 0), 5000);
      final Rect map =
          tester.getRect(find.byKey(const ValueKey<String>('city:map')));
      final Offset at = cityFeet(tester);
      expect(at.dx, greaterThanOrEqualTo(map.left - 1),
          reason: 'не ушёл за край земли');
      expect(at.dx, lessThanOrEqualTo(map.right + 1));
    });
  }

  // 2.5D в городе: выше по карте (дальше от зрителя) — Финни за Домом,
  // ниже — перед ним.
  testWidgets('город: глубина — выше Дома Финни за ним, ниже — перед ним',
      (WidgetTester tester) async {
    await pumpCity(tester, size: landscape);
    expect(cityBehind(tester, 'home'), isFalse, reason: 'стоит перед Домом');
    await holdCity(tester, const Offset(0, -1), 1500);
    expect(cityBehind(tester, 'home'), isTrue, reason: 'ушёл за Дом');
  });

  testWidgets('город: у Магазина — кнопка «войти», она открывает магазин',
      (WidgetTester tester) async {
    await pumpCity(tester, size: landscape);
    final Finder near = find.byKey(const ValueKey<String>('city:near'));
    final Finder label =
        find.descendant(of: near, matching: find.text('Магазин'));
    // Камера едет за Финни — место Магазина на экране меняется по пути.
    Rect shop() => tester
        .getRect(find.byKey(const ValueKey<String>('city:building:grocery')));
    for (int i = 0; i < 60 && label.evaluate().isEmpty; i++) {
      final Offset d = shop().bottomCenter - cityFeet(tester);
      if (d.distance < 1) break;
      await holdCity(tester, d / d.distance, 100);
    }
    expect(label, findsOneWidget);
    expect(tester.getSize(near).height, greaterThanOrEqualTo(48));
    await tester.tap(near);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorldShopScreen), findsOneWidget);
  });

  testWidgets('город: «Анимации» выкл. — джойстика нет',
      (WidgetTester tester) async {
    await pumpCity(tester, animations: false);
    expect(cityStick, findsNothing);
  });

  // Ревью 29.09: Финни уходил наполовину за край и прятался под джойстиком.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    // Джойстик теперь плавающий (рисуется под пальцем, пока ведёшь) —
    // «не под джойстиком» больше не про место на экране.
    testWidgets('${o.key}: Финни целиком в кадре', (WidgetTester tester) async {
      await pump(tester, size: o.value);
      final Rect scene = tester.getRect(find.byType(RoomScene));
      for (final Offset dir in <Offset>[
        const Offset(1, 0),
        const Offset(-1, 1),
        const Offset(-1, 0),
      ]) {
        final TestGesture g = await hold(tester, dir, 3000);
        await g.up();
        await tester.pump();
        final Offset f = feet(tester);
        final RoomGeometry geo = RoomGeometry(
            walk: Rect.zero,
            objects: const <String, Rect>{},
            feet: Offset.zero,
            unit: 1);
        expect(geo, isNotNull);
        final Rect finni =
            tester.getRect(find.byKey(const ValueKey<String>('room:finni')));
        final Rect body =
            finni.isEmpty ? Rect.fromLTWH(f.dx - 1, f.dy - 1, 2, 2) : finni;
        expect(body.left, greaterThanOrEqualTo(scene.left - 1), reason: '$dir');
        expect(body.right, lessThanOrEqualTo(scene.right + 1), reason: '$dir');
      }
    });

    // Портрет: джойстик поверх карты (полупрозрачный, справа внизу) —
    // координатор 29.09 по ревью «пустая полоса „Все места“»; альбомная —
    // своя полоса под списком. В обоих — не на кнопках, и Финни камера
    // держит в середине окна, не под джойстиком.
    testWidgets('город · ${o.key}: джойстик не на кнопках и не на Финни',
        (WidgetTester tester) async {
      await pumpCity(tester, size: o.value);
      final Rect pad = tester.getRect(cityStick);
      bool covers(Rect r) => r.width > 0 && r.height > 0 && r.overlaps(pad);
      final Rect finni =
          tester.getRect(find.byKey(const ValueKey<String>('city:finni')));
      expect(covers(finni), isFalse, reason: 'Финни $finni, джойстик $pad');
      for (final String k in <String>[
        'city:places',
        'city:back',
        'city:help'
      ]) {
        final Finder f = find.byKey(ValueKey<String>(k));
        if (f.evaluate().isEmpty) continue;
        expect(covers(tester.getRect(f)), isFalse, reason: k);
      }
      for (final CityBuilding b in cityBuildings) {
        final Finder f = find.byKey(ValueKey<String>('city:button:${b.id}'));
        if (f.evaluate().isEmpty) continue; // портрет: список — листом
        final Rect r = tester.getRect(f).intersect(
            tester.getRect(find.byKey(const ValueKey<String>('city:list'))));
        expect(covers(r), isFalse, reason: '${b.id} $r');
      }
    });
  }

  test('onboarding.json без «−» (U+2212): в шрифте Onest его нет', () {
    expect(
        File(OnboardingScript.path).readAsStringSync().contains('−'), isFalse);
  });

  // Ревью 29.09: у копилки на полке уши Финни срезались верхом кадра, а
  // кнопка «Копилка» ложилась ему на лицо.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets(
        '${o.key}: Финни целиком в кадре у каждого предмета, '
        'кнопка не на нём', (WidgetTester tester) async {
      await pump(tester, size: o.value);
      final Rect scene = tester.getRect(find.byType(RoomScene));
      final Finder near = find.byKey(const ValueKey<String>('room:near'));
      for (final (String key, String word) in <(String, String)>[
        ('room:piggy', 'Копилка'),
        ('room:fridge', 'Холодильник'),
        ('room:door', 'Дверь'),
        ('room:bed', 'Кровать'),
      ]) {
        final Finder label =
            find.descendant(of: near, matching: find.textContaining(word));
        final Rect thing = tester.getRect(find.byKey(ValueKey<String>(key)));
        for (int i = 0; i < 60 && label.evaluate().isEmpty; i++) {
          // К месту у предмета — низ по центру, там и стоят.
          final Offset d = thing.bottomCenter - feet(tester);
          if (d.distance < 1) break;
          final TestGesture g = await hold(tester, d / d.distance, 100);
          await g.up();
          await tester.pump();
        }
        expect(label, findsOneWidget,
            reason: '$key: Финни дошёл; ноги ${feet(tester)}, '
                'свободно ${tester.widget<RoomScene>(find.byType(RoomScene)).finniFree}, '
                'предмет $thing, джойстик ${tester.getRect(stick)}');
        final Rect finni =
            tester.getRect(find.byKey(const ValueKey<String>('room:finni')));
        expect(finni.top, greaterThanOrEqualTo(scene.top - 1), reason: key);
        expect(finni.left, greaterThanOrEqualTo(scene.left - 1), reason: key);
        expect(finni.right, lessThanOrEqualTo(scene.right + 1), reason: key);
        expect(tester.getRect(near).overlaps(finni.deflate(4)), isFalse,
            reason: '$key: кнопка ${tester.getRect(near)} на Финни $finni');
      }
    });
  }
}

/// Комната стадии [stage] посреди недели — как стенд `tool/render_world_screens_test.dart`.
World _livingAt(WorldStage stage) {
  final WorldGame w = contentWorld();
  WorldAutopilot(w).playToStage(stage);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}
