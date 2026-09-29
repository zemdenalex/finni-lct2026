import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/world_harness.dart';

/// Ловит: здание на карте или кнопка запасного списка ведёт не туда, «!»
/// стоит не над тем зданием или не следует за `world.eventBuildingId`,
/// экран не влезает в 360 × 640 при шрифте 1,3; башни Москва-Сити не на
/// своей стадии, вылезают за карту или перехватывают тап по зданию.
///
/// Маршруты — заглушки с записью имени: проверяется сам переход, а не
/// чужие экраны, которые ещё в работе.
void main() {
  forEachWorld((WorldKind kind) {
    late List<RouteSettings> pushed;

    /// Неделя 1 после плана: событие «автомат» ждёт в парке.
    World eventWorld() {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 400, wants: 0, goal: 0));
      return w;
    }

    Future<void> pumpCity(WidgetTester tester,
        {WorldState? state,
        double textScale = 1,
        Size size = const Size(360, 640),
        CityVariant variant = cityVariant}) async {
      pushed = <RouteSettings>[];
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(ChangeNotifierProvider<WorldState>.value(
          value: state ?? WorldState(kind.make()),
          child: MaterialApp(
            key: UniqueKey(),
            theme: buildAppTheme(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: CityScreen(variant: variant),
            onGenerateRoute: (RouteSettings s) {
              pushed.add(s);
              return MaterialPageRoute<void>(
                settings: s,
                builder: (_) => Scaffold(body: Text('route ${s.name}')),
              );
            },
          ),
        ));
        // Реестр, картинки и альфа спрайтов читаются из бандла.
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();
    }

    /// Мир на стадии [stage]. Движок доходит туда своей игрой (автопилот
    /// демо); у фейка автопилота нет — его пороги стадий опущены так, что
    /// он стоит на [stage] с первой недели.
    World stageWorld(WorldStage stage) {
      final World made = kind.make();
      final World w;
      if (made is WorldGame) {
        WorldAutopilot(made).playToStage(stage);
        w = made;
      } else {
        w = FakeWorld(
            config: WorldConfig(
                // Стадия по очкам: тест про экран стадии, а не про переезд.
                stageByRent: false,
                stageMinPoints: <int>[
              for (final WorldStage s in WorldStage.values)
                s.index <= stage.index ? 0 : 1000,
            ]));
        ok(w.startWeek());
        ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      }
      expect(w.snapshot.stage, stage, reason: 'настройка теста');
      return w;
    }

    for (final CityVariant v in CityVariant.values) {
      for (final WorldStage stage in WorldStage.values) {
        for (final Size size in <Size>[
          const Size(360, 640),
          const Size(640, 360)
        ]) {
          testWidgets(
              'тап по каждому зданию на карте ведёт в его экран · '
              '${v.name} · ${stage.name} · $size', (WidgetTester tester) async {
            final WorldState ws = WorldState(stageWorld(stage));
            await pumpCity(tester, state: ws, size: size, variant: v);
            // Спрайт прочитан: зона касания — размер картинки, а не коробка-заглушка.
            // Парк стадии (@4x, 96 в ширину): деревня 96 × 59, город 96 × 74,25,
            // Москва 96 × 73,5.
            // Масштаб карты: целый, а в альбомной, где карта при 1× выше
            // экрана, — дробный по высоте.
            final double k = tester
                    .getSize(find.byKey(const ValueKey<String>('city:map')))
                    .width /
                CityScreen.mapBaseFor(v).width;
            final Size park = tester.getSize(
                find.byKey(const ValueKey<String>('city:building:park')));
            final double parkH = switch (stage) {
              WorldStage.village => 59,
              WorldStage.town => 74.25,
              WorldStage.moscow => 73.5,
            };
            expect(park.width, closeTo(96 * k, 0.5));
            expect(park.height, closeTo(parkH * k, 0.5));
            // Башни Москва-Сити — только в Москве и целиком внутри карты.
            final Finder towers = find.byWidgetPredicate((Widget w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('city:skyline:'));
            expect(towers,
                stage == WorldStage.moscow ? findsNWidgets(2) : findsNothing);
            final Rect map =
                tester.getRect(find.byKey(const ValueKey<String>('city:map')));
            for (final Element t in towers.evaluate()) {
              final Rect r = tester.getRect(
                  find.byElementPredicate((Element e) => identical(e, t)));
              expect(map.intersect(r), r, reason: 'башня за картой: $r');
            }
            for (final CityBuilding b in cityBuildings) {
              await pumpCity(tester, state: ws, size: size, variant: v);
              // Карта в портрете выше экрана — ребёнок докручивает до здания.
              await tester.ensureVisible(
                  find.byKey(ValueKey<String>('city:building:${b.id}')));
              await tester.pump();
              final Rect r = tester.getRect(
                  find.byKey(ValueKey<String>('city:building:${b.id}')));
              // Тело здания, а не угол коробки: там силуэт непрозрачен.
              await tester.tapAt(Offset(r.center.dx, r.top + r.height * 0.6));
              await tester.pumpAndSettle();
              expect(pushed.map((RouteSettings s) => s.name), <String>[b.route],
                  reason: b.id);
              if (b.id != 'home') expect(pushed.single.arguments, b.id);
            }
          });
        }
      }
    }

    for (final CityVariant v in CityVariant.values) {
      for (final Size size in <Size>[
        const Size(360, 640),
        const Size(640, 360)
      ]) {
        testWidgets(
            'каждая кнопка запасного списка ведёт в экран здания · '
            '${v.name} · $size', (WidgetTester tester) async {
          for (final CityBuilding b in cityBuildings) {
            await pumpCity(tester, size: size, variant: v);
            final Finder btn =
                find.byKey(ValueKey<String>('city:button:${b.id}'));
            await openCityPlaces(tester);
            await tester.ensureVisible(btn);
            await tester.pumpAndSettle();
            expect(tester.getSize(btn).height, greaterThanOrEqualTo(48));
            await tester.tap(btn);
            await tester.pumpAndSettle();
            expect(pushed.map((RouteSettings s) => s.name), <String>[b.route],
                reason: b.id);
          }
        });
      }
    }

    testWidgets('«!» — над зданием из world.eventBuildingId и ведёт в событие',
        (WidgetTester tester) async {
      await pumpCity(tester);
      expect(find.byWidgetPredicate(_eventKey), findsNothing,
          reason: 'до плана недели событий нет');

      final WorldState ws = WorldState(eventWorld());
      final String id = ws.world.eventBuildingId!;
      await pumpCity(tester, state: ws);
      expect(find.byWidgetPredicate(_eventKey), findsNWidgets(2));
      expect(find.byKey(ValueKey<String>('city:event:$id')), findsOneWidget);
      expect(find.byKey(ValueKey<String>('city:button-event:$id')),
          findsOneWidget);

      final Rect marker =
          tester.getRect(find.byKey(ValueKey<String>('city:event:$id')));
      final Rect house =
          tester.getRect(find.byKey(ValueKey<String>('city:building:$id')));
      expect(marker.width, closeTo(48, 1e-6));
      expect(marker.height, closeTo(48, 1e-6));
      expect(marker.center.dx, closeTo(house.center.dx, 1));
      expect(marker.bottom, lessThanOrEqualTo(house.top + 8));

      // Камера стоит на Финни — до «!» ребёнок докручивает карту.
      await tester
          .ensureVisible(find.byKey(ValueKey<String>('city:event:$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('city:event:$id')));
      await tester.pumpAndSettle();
      expect(pushed.single.name, WorldRoutes.event);
      expect(pushed.single.arguments, id);
    });

    // Ловит: «!» живёт своей жизнью, а не мира — не пропадает после выбора.
    testWidgets('выбор в событии снимает «!» в городе',
        (WidgetTester tester) async {
      final WorldState ws = WorldState(eventWorld());
      await pumpCity(tester, state: ws);
      expect(find.byWidgetPredicate(_eventKey), findsNWidgets(2));
      final PendingEvent e = ws.world.pendingEvent!;
      final PendingEventChoice free =
          e.choices.firstWhere((PendingEventChoice c) => c.available);
      ws.act((World w) => w.resolveEvent(free.id));
      await tester.pump();
      expect(ws.world.eventBuildingId, isNull);
      expect(find.byWidgetPredicate(_eventKey), findsNothing);
    });

    for (final CityVariant v in CityVariant.values) {
      testWidgets(
          '360 × 640, шрифт 1,3: без переполнений, цели ≥ 48 dp · ${v.name}',
          (WidgetTester tester) async {
        final SemanticsHandle sem = tester.ensureSemantics();
        await pumpCity(tester,
            state: WorldState(eventWorld()), textScale: 1.3, variant: v);
        expect(tester.takeException(), isNull);
        // Окно камеры — в экране; карта крупнее окна (камера нужна).
        final Rect map =
            tester.getRect(find.byKey(const ValueKey<String>('city:map')));
        final Rect cam =
            tester.getRect(find.byKey(const ValueKey<String>('city:cam-x')));
        expect(cam.left, greaterThanOrEqualTo(0));
        expect(cam.right, lessThanOrEqualTo(360));
        expect(map.width > cam.width || map.height > cam.height, isTrue);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        sem.dispose();
      });

      // Ловит: на карте есть что нажать мельче 48 dp. Значок роли над
      // зданием нажимается, но TalkBack его не видит (ExcludeSemantics) —
      // проверка по семантике выше его пропускает.
      for (final Size size in <Size>[
        const Size(360, 640),
        const Size(640, 360)
      ]) {
        testWidgets('на карте всё нажимаемое ≥ 48 dp · ${v.name} · $size',
            (WidgetTester tester) async {
          await pumpCity(tester,
              state: WorldState(eventWorld()), size: size, variant: v);
          final List<Element> taps = find
              .descendant(
                  of: find.byKey(const ValueKey<String>('city:map')),
                  matching: find.byWidgetPredicate((Widget w) =>
                      (w is GestureDetector && w.onTap != null) ||
                      (w is InkResponse && w.onTap != null)))
              .evaluate()
              .toList();
          expect(taps.length, greaterThanOrEqualTo(cityBuildings.length));
          for (final Element e in taps) {
            final Size s = (e.renderObject! as RenderBox).size;
            expect(s.width, greaterThanOrEqualTo(48), reason: '${e.widget}');
            expect(s.height, greaterThanOrEqualTo(48), reason: '${e.widget}');
          }
        });
      }
    }

    // Ловит: камера уезжает за край карты (видно пустоту за городом) — и
    // не доезжает до крайнего здания, выбранного списком (Денис, 29.09:
    // «экран должен следовать за финни»).
    for (final CityVariant v in CityVariant.values) {
      for (final Size size in <Size>[
        const Size(360, 640),
        const Size(640, 360)
      ]) {
        testWidgets('камера упирается в края карты · ${v.name} · $size',
            (WidgetTester tester) async {
          await pumpCity(tester, size: size, variant: v);
          final Finder camX = find.byKey(const ValueKey<String>('city:cam-x'),
              skipOffstage: false);
          final Finder camY = find.byKey(const ValueKey<String>('city:cam-y'),
              skipOffstage: false);
          // Самые левое и правое здания раскладки.
          // Дом не берём: его кнопка заменяет город комнатой.
          final List<CityBuilding> byX = cityBuildings
              .where((CityBuilding b) => b.id != 'home')
              .toList()
            ..sort((CityBuilding a, CityBuilding b) => tester
                .getRect(find.byKey(ValueKey<String>('city:building:${a.id}')))
                .center
                .dx
                .compareTo(tester
                    .getRect(
                        find.byKey(ValueKey<String>('city:building:${b.id}')))
                    .center
                    .dx));
          for (final CityBuilding b in <CityBuilding>[byX.first, byX.last]) {
            final Finder btn =
                find.byKey(ValueKey<String>('city:button:${b.id}'));
            await openCityPlaces(tester);
            await tester.ensureVisible(btn);
            await tester.pumpAndSettle();
            await tester.tap(btn);
            await tester.pumpAndSettle();
            expect(pushed.last.name, b.route);
            tester.state<NavigatorState>(find.byType(Navigator)).pop();
            await tester.pumpAndSettle();
            for (final Finder f in <Finder>[camX, camY]) {
              final ScrollPosition p = tester
                  .state<ScrollableState>(find
                      .descendant(of: f, matching: find.byType(Scrollable))
                      .first)
                  .position;
              expect(p.pixels,
                  inInclusiveRange(p.minScrollExtent, p.maxScrollExtent),
                  reason: b.id);
            }
            final Rect view = tester.getRect(camY);
            final Rect map = tester.getRect(find.byKey(
                const ValueKey<String>('city:map'),
                skipOffstage: false));
            // Карта закрывает окно целиком (или стоит по центру, если меньше).
            if (map.width >= view.width) {
              expect(map.left, lessThanOrEqualTo(view.left + 0.5),
                  reason: b.id);
              expect(map.right, greaterThanOrEqualTo(view.right - 0.5),
                  reason: b.id);
            }
            final Rect house = tester.getRect(find.byKey(
                ValueKey<String>('city:building:${b.id}'),
                skipOffstage: false));
            expect(view.overlaps(house), isTrue,
                reason: 'камера доехала до ${b.id}');
          }
        });
      }
    }

    // Ловит: здание, которое камерой не показать целиком (с значком над
    // ним), и старт, на котором «!» события за кадром (ревью 29.09: «зоо-
    // магазин справа и „!“ парка сверху обрезаны»).
    for (final CityVariant v in CityVariant.values) {
      for (final Size size in <Size>[
        const Size(360, 640),
        const Size(640, 360)
      ]) {
        testWidgets(
            'каждое здание камерой видно целиком, «!» — с первого кадра · '
            '${v.name} · $size', (WidgetTester tester) async {
          final WorldState ws = WorldState(eventWorld());
          final String ev = ws.world.eventBuildingId!;
          await pumpCity(tester, state: ws, size: size, variant: v);
          final Rect view =
              tester.getRect(find.byKey(const ValueKey<String>('city:cam-y')));
          final Rect marker =
              tester.getRect(find.byKey(ValueKey<String>('city:event:$ev')));
          expect(view.intersect(marker), marker,
              reason: '«!» над $ev виден сразу: $marker в окне $view');
          for (final CityBuilding b in cityBuildings) {
            final Finder house =
                find.byKey(ValueKey<String>('city:building:${b.id}'));
            await Scrollable.ensureVisible(tester.element(house),
                alignment: 0.5);
            await tester.pumpAndSettle();
            final Rect r = tester.getRect(house).expandToInclude(tester
                .getRect(find.byKey(ValueKey<String>('city:icon:${b.id}'))));
            expect(view.intersect(r), r, reason: '${b.id} $r в окне $view');
          }
        });
      }
    }

    // Ловит: в альбомной окно камеры не во всю высоту или список мест
    // оказывается под картой.
    for (final CityVariant v in CityVariant.values) {
      for (final double scale in <double>[1, 1.3]) {
        testWidgets(
            '640 × 360, шрифт $scale: окно карты, список справа · ${v.name}',
            (WidgetTester tester) async {
          await pumpCity(tester,
              state: WorldState(eventWorld()),
              textScale: scale,
              size: const Size(640, 360),
              variant: v);
          expect(tester.takeException(), isNull);
          final Rect cam =
              tester.getRect(find.byKey(const ValueKey<String>('city:cam-y')));
          expect(cam.top, greaterThanOrEqualTo(0));
          expect(cam.bottom, lessThanOrEqualTo(360));
          expect(cam.left, greaterThanOrEqualTo(0));
          expect(cam.height, greaterThan(360 - 3 * 8), reason: 'во всю высоту');
          final Rect list =
              tester.getRect(find.byKey(const ValueKey<String>('city:list')));
          expect(list.left, greaterThanOrEqualTo(cam.right));
          expect(list.right, lessThanOrEqualTo(640));
          final Rect back =
              tester.getRect(find.byKey(const ValueKey<String>('city:back')));
          expect(back.topLeft, const Offset(0, 0));
          expect(
              find.byKey(const ValueKey<String>('city:help')), findsOneWidget);
        });
      }
    }
  });
}

bool _eventKey(Widget w) {
  final Key? k = w.key;
  return k is ValueKey<String> &&
      (k.value.startsWith('city:event:') ||
          k.value.startsWith('city:button-event:'));
}
