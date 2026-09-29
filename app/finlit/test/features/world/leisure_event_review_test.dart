import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/event/event_screen.dart';
import 'package:finlit/features/world/home/world_hud.dart';
import 'package:finlit/features/world/leisure/leisure_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/world_harness.dart';

/// Ловит (B8): досуг показывает не те числа, что вернул мир, или HUD не
/// обновился; отказ досуга что-то списал или молчит о причине; итоги недели
/// не доводят до новой недели, уводят баланс в минус или не влезают в
/// 360 × 640 при шрифте 1,3; выбор в событии меняет мир не так, как
/// обещало превью, не снимает «!» или погашенный вариант выбирается.
void main() {
  forEachWorld((WorldKind kind) {
    /// Неделя идёт: 400 карманных, 250 в НУЖНО, ХОЧУ пусто, 150 в заработке.
    World livingWorld() {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 0, goal: 0));
      return w;
    }

    String textIn(WidgetTester tester, String key) => tester
        .widget<Text>(find
            .descendant(
                of: find.byKey(ValueKey<String>(key)),
                matching: find.byType(Text))
            .last)
        .data!;

    Future<void> tap(WidgetTester tester, String key) async {
      final Finder f = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
    }

    group('S8 досуг', () {
      testWidgets('парк: ⚡ и 😊 меняются как говорит мир, HUD обновлён',
          (WidgetTester tester) async {
        final World w = livingWorld();
        final ResourceSnapshot before = w.snapshot;
        await pumpWorldScreen(tester, const LeisureScreen(place: 'park'),
            world: w);

        await tap(tester, 'leisure:go:park');

        final ResourceSnapshot after = w.snapshot;
        expect(after.energy, lessThan(before.energy));
        expect(after.happiness, greaterThan(before.happiness));
        expect(after.available, before.available, reason: 'парк бесплатный');
        expect(find.byKey(const ValueKey<String>('leisure:result')),
            findsOneWidget);
        final String delta = tester
            .widget<PicText>(
                find.byKey(const ValueKey<String>('leisure:delta')))
            .text;
        expect(delta, contains('😊 +${after.happiness - before.happiness}'));
        expect(textIn(tester, 'hud:energy'), WorldHud.energyText(after.energy));
        expect(textIn(tester, 'hud:happiness'), '${after.happiness}');
      });

      testWidgets('кино без денег: кнопка погашена, причина мира на карточке',
          (WidgetTester tester) async {
        // Все карманные — в НУЖНО: на кино (ХОЧУ и заработок) денег нет.
        final World w = kind.make();
        ok(w.startWeek());
        ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
        final ResourceSnapshot before = w.snapshot;
        await pumpWorldScreen(tester, const LeisureScreen(place: 'cinema'),
            world: w, textScale: 1.3);

        final BlockReason block = w.canDo(WorldAction.leisure, id: 'cinema')!;
        expect(block.text, contains('Не хватает'));
        final Finder go =
            find.byKey(const ValueKey<String>('leisure:go:cinema'));
        expect(tester.widget<FilledButton>(go).onPressed, isNull);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey<String>('leisure:block:cinema')),
                matching: find.text(block.text)),
            findsOneWidget);

        await tester.ensureVisible(go);
        await tester.tap(go, warnIfMissed: false);
        await tester.pump();

        final ResourceSnapshot after = w.snapshot;
        expect(after.available, before.available);
        expect(after.energy, before.energy);
        expect(after.happiness, before.happiness);
        expect(
            find.byKey(const ValueKey<String>('leisure:delta')), findsNothing);
      });

      // Ловит: цена ⚡ на карточке примерная или не та, что спишет мир, и не
      // обновляется, когда 😊 изменилось (каталог живой).
      testWidgets(
          '⚡ и 😊 на карточке — из каталога мира, после действия заново',
          (WidgetTester tester) async {
        final World w = livingWorld();
        await pumpWorldScreen(tester, const LeisureScreen(place: 'park'),
            world: w);
        expect(find.textContaining('≈'), findsNothing);

        void expectCard(String id) {
          final WorldCatalogItem i = w.catalogItem(id)!;
          expect(
              tester
                  .widget<Text>(
                      find.byKey(ValueKey<String>('leisure:energy:$id')))
                  .data,
              WorldHud.energyText(-i.energy));
          expect(
              tester
                  .widget<Text>(
                      find.byKey(ValueKey<String>('leisure:happiness:$id')))
                  .data,
              '+${i.happiness}');
        }

        expectCard('park');
        final double parkCost = -w.catalogItem('park')!.energy;
        final double before = w.snapshot.energy;
        await tap(tester, 'leisure:go:park');
        // Спишется ровно то, что было на карточке.
        expect(before - w.snapshot.energy, closeTo(parkCost, 1e-9));
        expectCard('park');
        expectCard('cafe');
      });

      // Ловит: в альбомной (основной) варианты не видны разом, итог прячется
      // под карточками или экран переполняется при шрифте 1,3.
      testWidgets('альбомная 640 × 360, шрифт 1,3: парк, итог сбоку',
          (WidgetTester tester) async {
        final World w = livingWorld();
        final ResourceSnapshot before = w.snapshot;
        await pumpWorldScreen(tester, const LeisureScreen(place: 'park'),
            world: w, size: landscape, textScale: 1.3);
        expect(tester.takeException(), isNull);
        // Варианты — сеткой: вторая карточка справа от первой, в одном ряду.
        for (final String k in <String>['park', 'cafe', 'cinema']) {
          expect(
              find.byKey(ValueKey<String>('leisure:card:$k')), findsOneWidget);
        }
        final Rect park = tester
            .getRect(find.byKey(const ValueKey<String>('leisure:card:park')));
        final Rect cafe = tester
            .getRect(find.byKey(const ValueKey<String>('leisure:card:cafe')));
        expect(cafe.left, greaterThan(park.right));
        expect(cafe.top, park.top);

        await tap(tester, 'leisure:go:park');

        final ResourceSnapshot after = w.snapshot;
        expect(after.energy, lessThan(before.energy));
        expect(after.happiness, greaterThan(before.happiness));
        expect(tester.takeException(), isNull);
        final Finder result =
            find.byKey(const ValueKey<String>('leisure:result'));
        expect(result.hitTestable(), findsOneWidget);
        // Итог — справа от карточек, а не над ними.
        expect(
            tester.getTopLeft(result).dx,
            greaterThan(tester
                .getTopRight(
                    find.byKey(const ValueKey<String>('leisure:card:park')))
                .dx));
        expect(textIn(tester, 'hud:energy'), WorldHud.energyText(after.energy));
      });

      testWidgets('игра с питомцем — только если питомец есть',
          (WidgetTester tester) async {
        await pumpWorldScreen(tester, const LeisureScreen(place: 'park'),
            world: livingWorld());
        expect(find.byKey(const ValueKey<String>('leisure:card:pet_play')),
            findsNothing);
        expect(find.byKey(const ValueKey<String>('leisure:card:park')),
            findsOneWidget);
      });
    });

    group('S11 итоги', () {
      Future<WorldState> pumpReview(WidgetTester tester, World w,
          {double textScale = 1, Size size = portrait}) async {
        final WorldState ws = WorldState(w);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ChangeNotifierProvider<WorldState>.value(
          value: ws,
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            // Комната со спрайтами — зонд: проверяем только переход.
            routes: <String, WidgetBuilder>{
              WorldRoutes.room: (_) => const Scaffold(body: Text('room probe')),
            },
            home: const WeekReviewScreen(),
          ),
        ));
        await tester.pump();
        return ws;
      }

      void expectNotNegative(ResourceSnapshot s) {
        expect(s.need, greaterThanOrEqualTo(0));
        expect(s.want, greaterThanOrEqualTo(0));
        expect(s.free, greaterThanOrEqualTo(0));
        expect(s.goal, greaterThanOrEqualTo(0));
      }

      testWidgets('спать → счета → новая неделя: неделя +1 и план',
          (WidgetTester tester) async {
        final World w = livingWorld();
        ok(w.sleep());
        expect(w.phase, WeekPhase.review);
        final int week = w.snapshot.weekNo;
        await pumpReview(tester, w);
        expect(
            find.byKey(const ValueKey<String>('review:ended')), findsOneWidget);

        // Счёт 550 при 400 своих — нехватка, «как есть» — поможет семья.
        await tap(tester, 'review:pay');
        expectNotNegative(w.snapshot);
        expect(find.byKey(const ValueKey<String>('review:bills_result')),
            findsOneWidget);
        expect(find.byKey(const ValueKey<String>('review:growth')),
            findsOneWidget);

        await tap(tester, 'review:new_week');
        await tester.pump();
        expect(w.snapshot.weekNo, week + 1);
        expect(w.phase, WeekPhase.planning);
        expect(find.text('room probe'), findsOneWidget);
      });

      // Ловит (ТЗ 2.5.5.3): итоги показывают «было / стало» вместо плана
      // против факта, или числа не те, что ребёнок разложил и что вышло.
      testWidgets('после счетов: план против факта по НУЖНО / ХОЧУ / ЦЕЛЬ',
          (WidgetTester tester) async {
        final World w = livingWorld(); // план: 250 / 0 / 0
        ok(w.sleep());
        await pumpReview(tester, w);
        await tap(tester, 'review:pay');

        String row(String env) {
          final Finder f = find.byKey(ValueKey<String>('review:planfact:$env'));
          expect(f, findsOneWidget, reason: env);
          return tester
              .widget<Text>(find.descendant(of: f, matching: find.byType(Text)))
              .textSpan!
              .toPlainText()
              .replaceAll(' ', ' ');
        }

        final WeekPlanFact fact = w.weekHistory.last;
        expect(fact.need.actual, greaterThan(250), reason: 'счёт больше плана');
        expect(
            row('need'),
            allOf(contains('НУЖНО'), contains('план 250'),
                contains('счета ${fact.need.actual}')));
        expect(row('want'), allOf(contains('ХОЧУ'), contains('план 0')));
        expect(row('goal'), allOf(contains('ЦЕЛЬ'), contains('план 0')));
        expect(find.byKey(const ValueKey<String>('review:takeaway')),
            findsOneWidget);
      });

      // Ловит: итоги, открытые второй раз, снова предлагают оплатить счета
      // (флага «оплачено» раньше не было) и не показывают план и факт.
      testWidgets('открыты после оплаты — сразу итог, без кнопок оплаты',
          (WidgetTester tester) async {
        final World w = livingWorld();
        ok(w.sleep());
        ok(w.payBills());
        await pumpReview(tester, w);
        expect(find.byKey(const ValueKey<String>('review:pay')), findsNothing);
        expect(find.byKey(const ValueKey<String>('review:bills_result')),
            findsOneWidget);
        expect(find.byKey(const ValueKey<String>('review:planfact:need')),
            findsOneWidget);
        expect(find.byKey(const ValueKey<String>('review:new_week')),
            findsOneWidget);
      });

      testWidgets('из копилки — с подтверждением, баланс не в минусе',
          (WidgetTester tester) async {
        final World w = livingWorld();
        ok(w.sleep());
        final int saved = w.snapshot.goal;
        expect(saved, greaterThan(0));
        await pumpReview(tester, w);

        await tap(tester, 'review:pay_goal');
        await tap(tester, 'review:goal:yes');
        await tester.pump();
        expect(w.snapshot.goal, lessThan(saved));
        expectNotNegative(w.snapshot);
        // Ловит: строка ЦЕЛЬ в плане против факта говорит «отложили −N»,
        // когда из копилки взяли больше, чем положили.
        final int took = -w.weekHistory.last.goal.actual;
        expect(took, greaterThan(0), reason: 'за неделю копилка уменьшилась');
        final String goalRow = tester
            .widget<Text>(find.descendant(
                of: find.byKey(const ValueKey<String>('review:planfact:goal')),
                matching: find.byType(Text)))
            .textSpan!
            .toPlainText()
            .replaceAll(' ', ' ');
        expect(goalRow, contains('взяли из копилки $took'));
        expect(goalRow, isNot(contains('отложили')));
        expect(goalRow, isNot(contains('-$took')));
        expect(goalRow, isNot(contains('−$took')));
        expect(find.byKey(const ValueKey<String>('review:new_week')),
            findsOneWidget);
      });

      // Ловит: в альбомной (основной) раскладке итоги не доходят до новой
      // недели или «Новая неделя» уезжает с прокруткой.
      testWidgets(
          'альбомная 640 × 360, шрифт 1,3: спать → счета → новая неделя',
          (WidgetTester tester) async {
        final World w = livingWorld();
        ok(w.sleep());
        final int week = w.snapshot.weekNo;
        await pumpReview(tester, w, size: landscape, textScale: 1.3);
        expect(tester.takeException(), isNull);
        // Кнопки оплаты прибиты — нажимаются без прокрутки; счёт начинается
        // на экране, «почему кончилась» — справа от него.
        for (final String k in <String>['review:pay', 'review:pay_goal']) {
          expect(find.byKey(ValueKey<String>(k)).hitTestable(), findsOneWidget,
              reason: k);
        }
        final Rect bills =
            tester.getRect(find.byKey(const ValueKey<String>('review:bills')));
        expect(bills.top, lessThan(landscape.height / 2));
        expect(
            tester
                .getRect(find.byKey(const ValueKey<String>('review:ended')))
                .left,
            greaterThan(bills.right));
        expect(
            find.byKey(const ValueKey<String>('review:new_week')), findsNothing,
            reason: 'до оплаты новой недели нет');

        await tap(tester, 'review:pay');
        expectNotNegative(w.snapshot);
        expect(tester.takeException(), isNull);
        // Две колонки: итог оплаты слева, рост справа — рядом.
        final Offset paid = tester.getCenter(
            find.byKey(const ValueKey<String>('review:bills_result')));
        final Offset growth = tester
            .getCenter(find.byKey(const ValueKey<String>('review:growth')));
        expect(growth.dx, greaterThan(paid.dx));
        // «Новая неделя» прибита — нажимается без прокрутки.
        final Finder next =
            find.byKey(const ValueKey<String>('review:new_week'));
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        await tester.pump();
        await tester.pump();
        expect(w.snapshot.weekNo, week + 1);
        expect(w.phase, WeekPhase.planning);
        expect(find.text('room probe'), findsOneWidget);
      });

      testWidgets('влезает в 360 × 640 при шрифте 1,3',
          (WidgetTester tester) async {
        final World w = livingWorld();
        ok(w.sleep());
        await pumpReview(tester, w, textScale: 1.3);
        await tap(tester, 'review:pay');
        await tester.ensureVisible(
            find.byKey(const ValueKey<String>('review:new_week')));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    group('S10 событие', () {
      String own(WidgetTester tester, String key) =>
          tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

      /// Неделя, когда сломался рюкзак, а в копилке меньше, чем стоит
      /// хороший рюкзак, — вариант «из копилки» погашен (как в
      /// contract_c2_test). Неделя берётся у мира, а не из расписания
      /// фейка: всё отложенное по пути тратится, события закрываются
      /// вариантом, который меньше всех кладёт в копилку.
      World backpackWorld() {
        final World w = kind.make();
        ok(w.startWeek());
        ok(w.plan(needs: 400, wants: 0, goal: 0));
        for (int week = 0;
            week < 12 && w.pendingEvent?.id != 'backpack_broke';
            week++) {
          final PendingEvent? e = w.pendingEvent;
          if (e != null) {
            final List<PendingEventChoice> open = e.choices
                .where((PendingEventChoice c) => c.available)
                .toList()
              ..sort((PendingEventChoice x, PendingEventChoice y) =>
                  x.preview.goal.compareTo(y.preview.goal));
            ok(w.resolveEvent(open.first.id));
          }
          if (w.phase == WeekPhase.living) ok(w.sleep());
          w.payBills();
          ok(w.startWeek());
          ok(w.plan(
              needs: 450.clamp(0, w.snapshot.unallocated), wants: 0, goal: 0));
        }
        expect(w.pendingEvent?.id, 'backpack_broke',
            reason: 'за 12 недель рюкзак так и не сломался');
        return w;
      }

      // Ловит: число на кнопке и то, что случилось, расходятся; выбор не
      // идёт в мир; «!» не снимается.
      testWidgets('превью видно до выбора, выбор меняет мир как обещано',
          (WidgetTester tester) async {
        final WorldState ws = WorldState(livingWorld());
        final PendingEvent e = ws.world.pendingEvent!;
        final PendingEventChoice park = e.choices
            .firstWhere((PendingEventChoice c) => c.id == 'just_play_park');
        expect(park.preview.isEmpty, isFalse);
        final ResourceSnapshot before = ws.snapshot;
        await pumpWorldScreen(tester, const EventScreen(),
            state: ws, textScale: 1.3);
        expect(find.text(e.title), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final PendingEventChoice c in e.choices) {
          expect(
              tester
                  .widget<PicText>(
                      find.byKey(ValueKey<String>('event:preview:${c.id}')))
                  .text,
              c.preview.text);
        }

        await tap(tester, 'event:choice:just_play_park');

        final ResourceSnapshot after = ws.snapshot;
        expect(ws.lastResult!.ok, isTrue);
        expect(after.available - before.available, park.preview.coins);
        expect(
            after.energy - before.energy, closeTo(park.preview.energy, 1e-9));
        expect(after.happiness - before.happiness, park.preview.happiness);
        expect(ws.world.pendingEvent, isNull);
        expect(ws.eventBuildingId, isNull);
        expect(
            find.byKey(const ValueKey<String>('event:finni')), findsOneWidget);
        expect(own(tester, 'event:finni'), contains(ws.lastResult!.reason));
        expect(own(tester, 'event:changes'), contains(park.preview.text));
      });

      testWidgets('недоступный вариант погашен, подписан и не выбирается',
          (WidgetTester tester) async {
        final World w = backpackWorld();
        final PendingEventChoice good = w.pendingEvent!.choices
            .firstWhere((PendingEventChoice c) => c.id == 'good_from_savings');
        expect(good.available, isFalse);
        final ResourceSnapshot before = w.snapshot;
        await pumpWorldScreen(tester, const EventScreen(), world: w);

        final Finder btn = find
            .byKey(const ValueKey<String>('event:choice:good_from_savings'));
        expect(tester.widget<OutlinedButton>(btn).onPressed, isNull);
        expect(own(tester, 'event:blocked:good_from_savings'),
            contains(good.blockReason!.text));
        await tester.ensureVisible(btn);
        await tester.tap(btn, warnIfMissed: false);
        await tester.pump();

        expect(w.pendingEvent, isNotNull);
        expect(w.snapshot.goal, before.goal);
        expect(
            find.byKey(const ValueKey<String>('event:outcome')), findsNothing);
      });

      testWidgets('события нет — спокойная заглушка и дорога назад',
          (WidgetTester tester) async {
        await pumpWorldScreen(tester, const EventScreen(), world: kind.make());
        expect(
            find.byKey(const ValueKey<String>('event:empty')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('event:title')), findsNothing);
        expect(find.byKey(const ValueKey<String>('event:empty:back')),
            findsOneWidget);
      });

      // Ловит: в альбомной выбор уезжает под текст ситуации, а последствие —
      // под сгиб экрана.
      testWidgets(
          'альбомная 640 × 360, шрифт 1,3: ситуация слева, выбор справа',
          (WidgetTester tester) async {
        final WorldState ws = WorldState(livingWorld());
        await pumpWorldScreen(tester, const EventScreen(),
            state: ws, size: landscape, textScale: 1.3);
        expect(tester.takeException(), isNull);
        final double titleX = tester
            .getCenter(find.byKey(const ValueKey<String>('event:title')))
            .dx;
        final Finder choice =
            find.byKey(const ValueKey<String>('event:choice:simulate'));
        expect(choice.hitTestable(), findsOneWidget);
        expect(tester.getCenter(choice).dx, greaterThan(titleX));

        await tester.tap(choice);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final Finder outcome =
            find.byKey(const ValueKey<String>('event:outcome'));
        expect(outcome, findsOneWidget);
        expect(tester.getTopLeft(outcome).dx, greaterThan(titleX));
        expect(ws.eventBuildingId, isNull);
      });
    });
  });
}
