import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/home/hud_chips.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/world_help.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

World _living(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 250, wants: 100, goal: 50));
  return w;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
}

// Денис, 29.09 (вариант В): «нужно чтобы суммарно интерфейс по вертикали
// занимал процентов 20-30 максимум»; показатели — поверх комнаты, а не
// отдельной полосой. Ловит: непрозрачные полосы интерфейса снова отъели
// экран у комнаты — нижняя панель выше 30 % высоты в портрете, боковой
// столбец шире 30 % в альбомной, показатели снова полосой над сценой.
// Настоящий шрифт: подстановочный вдвое шире и раздул бы панель.
void main() {
  setUpAll(loadAppFonts);

  // Ловит: самые широкие числа (4 знака денег, «10,5» сил, «100»
  // настроения) переносят ряд фишек во второй на 360 dp — рендер 29.09 с
  // «760 · 200 · 6,5 · 48» уже переносил, а комната в тесте выше этого не
  // видела (у неё числа уже).
  for (final double scale in <double>[1.0, 1.3]) {
    testWidgets('фишки: самые широкие числа — один ряд на 360 dp ×$scale',
        (WidgetTester tester) async {
      tester.view.physicalSize = portrait;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const ResourceSnapshot wide = ResourceSnapshot(
        weekNo: 9,
        need: 9999,
        want: 0,
        goal: 9999,
        free: 0,
        unallocated: 0,
        energy: 10.5,
        happiness: 100,
        growthPoints: 0,
        stage: WorldStage.moscow,
        experience: 0,
        shiftsThisWeek: 0,
        weeklyBill: 0,
        owned: <String>{},
      );
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          // Масштаб — как его отдаёт app.dart: зажат снизу единицей (CI
          // 36551226483: повторный зажим до [1, 1] падал на проверке).
          data: MediaQueryData(
              size: portrait,
              textScaler: TextScaler.linear(scale)
                  .clamp(minScaleFactor: 1.0, maxScaleFactor: 2.0)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              child: HudChips(snapshot: wide, trailing: <Widget>[
                HelpButton(onPressed: () {}),
                IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_vert_rounded, size: 28)),
              ]),
            ),
          ),
        ),
      ));
      final double top =
          tester.getRect(find.byKey(const ValueKey<String>('hud:coins'))).top;
      for (final String k in <String>['hud:energy', 'hud:happiness']) {
        expect(tester.getRect(find.byKey(ValueKey<String>(k))).top,
            closeTo(top, 0.5),
            reason: '$k в одном ряду с монетами');
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final double scale in <double>[1.0, 1.3]) {
    testWidgets('портрет 360×640 ×$scale: панель ≤ 30 %, сцена под HUD',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: _living(worldKinds.last), textScale: scale);
      });
      await _settle(tester);
      final Rect dock =
          tester.getRect(find.byKey(const ValueKey<String>('room:dock')));
      final Rect scene = tester.getRect(find.byType(RoomScene));
      final Rect goal =
          tester.getRect(find.byKey(const ValueKey<String>('room:goal')));
      // Весь интерфейс по вертикали (ревью В2, 29.09): фишки и строка цели
      // сверху — от края до низа строки цели, плюс нижняя панель. ≤ 30 %.
      final double ui = goal.bottom + dock.height;
      expect(ui / portrait.height, lessThanOrEqualTo(0.30),
          reason: 'сверху ${goal.bottom}, снизу ${dock.height}');
      // Сверху полосы нет: сцена начинается у верхнего края, показатели
      // лежат на ней.
      expect(scene.top, lessThanOrEqualTo(0.5));
      expect(scene.bottom, closeTo(dock.top, 0.5));
      for (final String k in <String>[
        'hud:coins',
        'hud:energy',
        'hud:happiness',
        'room:help',
        'room:menu',
      ]) {
        final Rect r = tester.getRect(find.byKey(ValueKey<String>(k)));
        expect(scene.contains(r.center), isTrue, reason: '$k поверх сцены');
        expect(r.height, greaterThanOrEqualTo(48), reason: k);
        // Один ряд (ревью В2): фишки и «?», ⋮ на одной высоте — ряд не
        // переносится во второй.
        expect(
            r.top,
            closeTo(
                tester
                    .getRect(find.byKey(const ValueKey<String>('hud:coins')))
                    .top,
                0.5),
            reason: '$k в одном ряду с монетами');
      }
      // Ловит: комната (общая раскладка) снова уходит под показатели —
      // фишки и строка цели закрывают дверь или копилку (topInset сцены не
      // передан или меньше высоты HUD).
      final List<Rect> hud = <Rect>[
        goal,
        for (final String k in <String>[
          'hud:coins',
          'hud:energy',
          'hud:happiness',
          'room:help',
          'room:menu',
        ])
          tester.getRect(find.byKey(ValueKey<String>(k))),
      ];
      for (final String o in <String>['room:door', 'room:piggy']) {
        final Rect r = tester.getRect(find.byKey(ValueKey<String>(o)));
        for (final Rect h in hud) {
          expect(h.intersect(r).height <= 0.5 || h.intersect(r).width <= 0.5,
              isTrue,
              reason: '$o $r под показателями $h');
        }
      }
      expect(tester.takeException(), isNull);
    });

    // Ловит: полосы города (сверху «Назад», показатели, «?»; снизу «Все
    // места») снова выше ~21 % экрана — показатели ушли во второй ряд или
    // подсказка — в отдельную полосу (координатор, 29.09).
    testWidgets('город 360×640 ×$scale: полосы ≤ 21 %, один ряд сверху',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const CityScreen(),
            world: _living(worldKinds.last), textScale: scale);
      });
      await _settle(tester);
      final Rect top =
          tester.getRect(find.byKey(const ValueKey<String>('city:top')));
      final Rect bar =
          tester.getRect(find.byKey(const ValueKey<String>('city:bar')));
      expect(
          (top.height + bar.height) / portrait.height, lessThanOrEqualTo(0.21),
          reason: 'сверху ${top.height}, снизу ${bar.height}');
      final double row = tester
          .getRect(find.byKey(const ValueKey<String>('city:back')))
          .center
          .dy;
      for (final String k in <String>[
        'hud:coins',
        'hud:energy',
        'hud:happiness',
        'city:help',
      ]) {
        final Rect r = tester.getRect(find.byKey(ValueKey<String>(k)));
        expect(r.center.dy, closeTo(row, 1), reason: '$k в ряду с «Назад»');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('альбомная 640×360 ×$scale: боковой столбец ≤ 30 %',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: _living(worldKinds.last), textScale: scale, size: landscape);
      });
      await _settle(tester);
      final Rect side =
          tester.getRect(find.byKey(const ValueKey<String>('room:side')));
      expect(side.width / landscape.width, lessThanOrEqualTo(0.30));
      final Rect scene = tester.getRect(find.byType(RoomScene));
      expect(scene.top, lessThanOrEqualTo(0.5), reason: 'без полосы сверху');
      expect(
          scene.contains(tester
              .getRect(find.byKey(const ValueKey<String>('hud:coins')))
              .center),
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
