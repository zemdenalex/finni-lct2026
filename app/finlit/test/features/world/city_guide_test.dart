import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/world_harness.dart';

/// Город понятен ребёнку 7–8 лет (`docs/final/gorod-audit.md`):
/// строка «Куда идти» с причиной, подписи зданий на карте, причина
/// закрытого здания в «Все места», TalkBack со смыслом здания, «?» в три
/// предложения. Всё это — флаг `city.guide` (по умолчанию включён).
///
/// Ловит: город снова встречает общим «Нажми на здание» и спорит с
/// «Сейчас: …» комнаты; здание без названия; закрытое здание без причины;
/// подписи налезают друг на друга при шрифте 1,3.
void main() {
  // Фейк, движок на числах «неделя» и движок как в сборке — с днями.
  for (final (String name, World Function() makeWorld)
      in <(String, World Function())>[
    for (final WorldKind k in worldKinds) (k.name, () => k.make()),
    ('WorldGame · дни (сборка)', contentDayWorld),
  ]) {
    group(name, () => cases(makeWorld));
  }
}

void cases(World Function() makeWorld) {
  {
    late List<RouteSettings> pushed;

    Future<void> pumpCity(WidgetTester tester, WorldState state,
        {double textScale = 1,
        Size size = const Size(360, 640),
        bool guide = true}) async {
      pushed = <RouteSettings>[];
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(ChangeNotifierProvider<WorldState>.value(
          value: state,
          child: MaterialApp(
            key: UniqueKey(),
            theme: buildAppTheme(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: CityScreen(guide: guide),
            onGenerateRoute: (RouteSettings s) {
              pushed.add(s);
              return MaterialPageRoute<void>(
                settings: s,
                builder: (_) => Scaffold(body: Text('route ${s.name}')),
              );
            },
          ),
        ));
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();
    }

    /// Неделя 1: план ещё не составлен.
    World planning() => makeWorld()..startWeek();

    /// План составлен так, что на счета не хватает: всё — в копилку.
    World short() {
      final World w = makeWorld()..startWeek();
      ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
      return w;
    }

    /// Всё в «Нужное»: на счета хватает, ждёт событие недели.
    World enough() {
      final World w = makeWorld()..startWeek();
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      return w;
    }

    /// Смены до упора: сил на дела не осталось (или неделя кончилась).
    /// Сначала самая дорогая по ⚡ смена: от порядка доски (садовник первым,
    /// NAS-4) не зависит, сколько сил останется в конце.
    World tired() {
      final World w = enough();
      for (int i = 0; i < 40; i++) {
        JobOffer? open;
        for (final JobOffer o in w.jobBoard) {
          if (o.blocked) continue;
          if (open == null || o.energyCost > open.energyCost) open = o;
        }
        if (open == null) break;
        w.completeJob(open.jobId, variant: open.variant, score: 1);
      }
      return w;
    }

    int money(World w) => w.snapshot.need + w.snapshot.want + w.snapshot.free;

    // Одна таблица: состояние → куда ведёт «Куда идти» и о чём говорит.
    for (final (String name, World Function() make, String target, Pattern says)
        in <(String, World Function(), String, Pattern)>[
      ('до плана недели', planning, 'home', 'план'),
      ('на счета не хватает', short, 'job-centre', 'не хватает'),
      (
        'сил не осталось',
        tired,
        'home',
        RegExp('спать|итоги', caseSensitive: false)
      ),
    ]) {
      testWidgets('«Куда идти»: $name → $target', (WidgetTester tester) async {
        final World w = make();
        if (target == 'job-centre') {
          expect(money(w), lessThan(w.snapshot.weeklyBill),
              reason: 'настройка теста');
        }
        await pumpCity(tester, WorldState(w));
        final Finder guide = find.byKey(ValueKey<String>('city:guide:$target'));
        expect(guide, findsOneWidget);
        expect(find.descendant(of: guide, matching: find.textContaining(says)),
            findsOneWidget);
        // Касание строки: Финни идёт туда сам, потом экран здания.
        await tester.tap(guide);
        await tester.pumpAndSettle();
        final String route =
            cityBuildings.firstWhere((CityBuilding b) => b.id == target).route;
        expect(pushed.map((RouteSettings s) => s.name), <String>[route]);
      });
    }

    testWidgets('«Куда идти»: хватает на счета — к зданию с «!»',
        (WidgetTester tester) async {
      // Смена-другая: заработанного хватает на счета, событие ждёт.
      final World w = enough();
      for (int i = 0; i < 6 && money(w) < w.snapshot.weeklyBill; i++) {
        final JobOffer open = w.jobBoard.firstWhere((JobOffer o) => !o.blocked);
        ok(w.completeJob(open.jobId, variant: open.variant, score: 1));
      }
      expect(money(w), greaterThanOrEqualTo(w.snapshot.weeklyBill),
          reason: 'настройка теста');
      final String? ev = w.eventBuildingId;
      expect(ev, isNotNull, reason: 'настройка теста: событие недели');
      await pumpCity(tester, WorldState(w));
      final Finder guide = find.byKey(ValueKey<String>('city:guide:$ev'));
      expect(guide, findsOneWidget);
      // Касание — Финни идёт к зданию, потом событие (не экран здания).
      await tester.tap(guide);
      await tester.pumpAndSettle();
      expect(
          pushed.map((RouteSettings s) => s.name), <String>[WorldRoutes.event]);
    });

    for (final Size size in <Size>[
      const Size(360, 640),
      const Size(640, 360)
    ]) {
      testWidgets(
          'у каждого здания на карте подпись; подписи не налезают · $size',
          (WidgetTester tester) async {
        await pumpCity(tester, WorldState(enough()),
            textScale: 1.3, size: size);
        final Map<String, Rect> labels = <String, Rect>{};
        for (final CityBuilding b in cityBuildings) {
          final Finder l = find.byKey(ValueKey<String>('city:label:${b.id}'));
          expect(l, findsOneWidget, reason: b.id);
          expect(find.descendant(of: l, matching: find.text(b.name)),
              findsOneWidget,
              reason: b.id);
          labels[b.id] = tester.getRect(l);
        }
        final List<Rect> others = <Rect>[
          for (final Element e in find
              .byWidgetPredicate((Widget w) =>
                  w.key is ValueKey<String> &&
                  RegExp(r'^city:(icon|event):')
                      .hasMatch((w.key! as ValueKey<String>).value))
              .evaluate())
            tester.getRect(find.byElementPredicate((Element x) => x == e)),
        ];
        final List<String> ids = labels.keys.toList();
        for (int i = 0; i < ids.length; i++) {
          final Rect a = labels[ids[i]]!;
          for (int j = i + 1; j < ids.length; j++) {
            expect(a.overlaps(labels[ids[j]]!), isFalse,
                reason: '${ids[i]} налезает на ${ids[j]}');
          }
          for (final Rect o in others) {
            expect(a.overlaps(o), isFalse,
                reason: 'подпись ${ids[i]} на значке $o');
          }
        }
      });
    }

    testWidgets('касание подписи ведёт в её здание',
        (WidgetTester tester) async {
      for (final CityBuilding b in cityBuildings) {
        await pumpCity(tester, WorldState(enough()));
        final Finder l = find.byKey(ValueKey<String>('city:label:${b.id}'));
        await tester.ensureVisible(l);
        await tester.pumpAndSettle();
        await tester.tap(l);
        await tester.pumpAndSettle();
        expect(pushed.map((RouteSettings s) => s.name), <String>[b.route],
            reason: b.id);
      }
    });

    testWidgets('«Все места»: зачем туда, а закрытое — почему',
        (WidgetTester tester) async {
      Finder line(String id, Pattern text) => find.descendant(
          of: find.byKey(ValueKey<String>('city:button:$id')),
          matching: find.textContaining(text));

      await pumpCity(tester, WorldState(planning()));
      await openCityPlaces(tester);
      expect(line('job-centre', 'после плана'), findsOneWidget);
      expect(line('home', 'Финни'), findsOneWidget);

      await pumpCity(tester, WorldState(enough()));
      await openCityPlaces(tester);
      expect(line('job-centre', RegExp('смены', caseSensitive: false)),
          findsOneWidget);
    });

    testWidgets('TalkBack: здание — с тем, зачем туда; стрелка — «Домой»',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await pumpCity(tester, WorldState(enough()));
      expect(
          find.bySemanticsLabel(RegExp('^Дом работы: смены')), findsOneWidget);
      expect(find.byTooltip('Домой'), findsOneWidget);
      h.dispose();
    });

    testWidgets('флаг city.guide выключен — город как раньше',
        (WidgetTester tester) async {
      await pumpCity(tester, WorldState(short()), guide: false);
      expect(
          find.byWidgetPredicate((Widget w) =>
              w.key is ValueKey<String> &&
              RegExp(r'^city:(guide|label):')
                  .hasMatch((w.key! as ValueKey<String>).value)),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('city:hint')), findsOneWidget);
      expect(find.byTooltip('Назад'), findsOneWidget);
    });

    testWidgets('«Что здесь?» — не больше трёх предложений, без значков',
        (WidgetTester tester) async {
      await pumpCity(tester, WorldState(enough()));
      await tester.tap(find.byKey(const ValueKey<String>('city:help')));
      await tester.pumpAndSettle();
      final Text t = tester.widget<Text>(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Это город')));
      final String s = t.data ?? t.textSpan!.toPlainText();
      expect(RegExp(r'[.!?…](\s|$)').allMatches(s).length, lessThanOrEqualTo(3),
          reason: s);
      expect(s, isNot(contains('￼')), reason: 'значок посреди текста');
    });
  }
}
