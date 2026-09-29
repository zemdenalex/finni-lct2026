import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/features/world/jobs/board/job_offer_card.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/world_harness.dart';

/// Ловит: экран показывает не те числа, что в `world.jobBoard` (оплата
/// пересчитана на экране, ступень «×1.25» с точкой), закрытую смену можно
/// начать, причина отказа не та, что у мира (`offer.blockReason`),
/// «Взяться» уводит не в ту смену, до плана недели смена стартует, доска
/// не влезает в 360 × 640 при шрифте 1,3.
///
/// Маршрут смены — зонд, который запоминает аргументы: сама мини-игра в
/// отдельной задаче.
void main() {
  forEachWorld((WorldKind kind) {
    late List<RouteSettings> pushed;

    World livingWorld() {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 0, goal: 0));
      return w;
    }

    Future<WorldState> pump(WidgetTester tester, World world,
        {double textScale = 1, Size size = portrait}) async {
      pushed = <RouteSettings>[];
      final WorldState ws = WorldState(world);
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
          home: const JobBoardScreen(),
          onGenerateRoute: (RouteSettings s) {
            pushed.add(s);
            return MaterialPageRoute<void>(
                settings: s,
                builder: (_) => Scaffold(body: Text('route ${s.name}')));
          },
        ),
      ));
      await tester.pump();
      return ws;
    }

    /// Строка под ключом: у фактов карточки — исходная строка [PicText]
    /// (значки ⚡ 😊 рисуются вектором), у остальных — текст [Text].
    String textOf(WidgetTester tester, String key) {
      final Finder of = find.byKey(ValueKey<String>(key));
      final Finder pic =
          find.descendant(of: of, matching: find.byType(PicText));
      if (pic.evaluate().isNotEmpty) {
        return tester.widget<PicText>(pic.first).text;
      }
      return tester
          .widget<Text>(
              find.descendant(of: of, matching: find.byType(Text)).first)
          .data!;
    }

    testWidgets('числа каждой карточки — ровно из world.jobBoard',
        (WidgetTester tester) async {
      final World w = livingWorld();
      // Настроение и опыт не нулевые: оплата не совпадает с базой.
      ok(w.leisure('park'));
      ok(w.completeJob('gardener', score: 1));
      await pump(tester, w);
      final List<JobOffer> board = w.jobBoard;
      expect(board.any((JobOffer o) => o.pay != o.basePay), isTrue);
      for (final JobOffer o in board) {
        final String k = offerKey(o);
        expect(find.byKey(ValueKey<String>('jobs:card:$k')), findsOneWidget,
            reason: k);
        expect(
            tester
                .widget<Text>(find.byKey(ValueKey<String>('jobs:pay:$k')))
                .data,
            'Заплатят ${o.pay}',
            reason: k);
        expect(textOf(tester, 'jobs:energy:$k'),
            'энергия ${energyShown(o.energyCost)}',
            reason: k);
        expect(textOf(tester, 'jobs:exp:$k'), 'опыт +${o.experiencePercent} %',
            reason: k);
        final String good = textOf(tester, 'jobs:bonus:$k');
        expect(good, contains('до +${o.efficiencyBonusMax}'), reason: k);
        expect(good, contains('⚡ ${energyShown(o.goodEnergyExtra)}'),
            reason: k);
        expect(find.byKey(ValueKey<String>('jobs:step:$k')), findsNothing,
            reason: 'ступень ×1 не показывается');
        expect(
            textOf(tester, 'jobs:left:$k'), 'смен на неделе: ${o.shiftsLeft}',
            reason: k);
      }
      expect(energyCostText(2.9), '2,9');
      expect(energyCostText(3), '3');
    });

    testWidgets('курьер без транспорта: причина и никакого перехода',
        (WidgetTester tester) async {
      final World w = livingWorld();
      await pump(tester, w);
      final JobOffer courier = w.offer('courier', variant: 'near')!;
      expect(courier.locked, isTrue);
      const String k = 'courier/near';
      expect(find.byKey(const ValueKey<String>('jobs:take:$k')), findsNothing);
      final Finder blocked =
          find.byKey(const ValueKey<String>('jobs:blocked:$k'));
      expect(
          textOf(tester, 'jobs:blocked:$k'),
          allOf(startsWith(courier.blockReason!.text),
              contains(courier.lockedReason)));
      await tester.ensureVisible(blocked);
      await tester.tap(blocked);
      await tester.pumpAndSettle();
      expect(pushed, isEmpty);
    });

    testWidgets('«Взяться» открывает смену с нужной работой и уровнем',
        (WidgetTester tester) async {
      // Уровни — у программиста; он закрыт ноутбуком, замки снимает демо
      // (сами замки — в job_unlocks_test).
      final World w = livingWorld();
      ok(w.demoUnlockAllJobs());
      await pump(tester, w);
      for (final (String job, String? variant) in <(String, String?)>[
        ('consultant', null),
        ('accountant', null),
        ('programmer', 'medium'),
      ]) {
        pushed.clear();
        final String k = variant == null ? job : '$job/$variant';
        final Finder take = find.byKey(ValueKey<String>('jobs:take:$k'));
        await tester.ensureVisible(take);
        await tester.pumpAndSettle();
        expect(tester.getSize(take).height, greaterThanOrEqualTo(48));
        await tester.tap(take);
        await tester.pumpAndSettle();
        expect(pushed.single.name, WorldRoutes.job);
        final JobPlayArgs args = pushed.single.arguments! as JobPlayArgs;
        expect(args.jobId, job);
        expect(args.variant, variant);
        Navigator.of(tester.element(find.text('route ${WorldRoutes.job}')))
            .pop();
        await tester.pumpAndSettle();
      }
    });

    // Ловит: доска не говорит, что смена — мини-игра (дизайнер 28.09 не
    // нашла игры), или строка пропадает, когда наверху баннер фазы.
    for (final bool planned in <bool>[true, false]) {
      testWidgets(
          'первая строка: каждая смена — мини-игра '
          '(${planned ? 'неделя идёт' : 'до плана, с баннером'})',
          (WidgetTester tester) async {
        final World w = kind.make();
        ok(w.startWeek());
        if (planned) ok(w.plan(needs: 250, wants: 0, goal: 0));
        await pump(tester, w);
        expect(find.byKey(const ValueKey<String>('jobs:banner')),
            planned ? findsNothing : findsOneWidget);
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey<String>('jobs:intro')))
                .data,
            contains('мини-игра'));
      });
    }

    testWidgets('до плана недели смену не взять, и сказано почему',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      expect(w.phase, WeekPhase.planning);
      await pump(tester, w);
      expect(find.byKey(const ValueKey<String>('jobs:banner')), findsOneWidget);
      expect(find.byWidgetPredicate((Widget x) {
        final Key? key = x.key;
        return key is ValueKey<String> && key.value.startsWith('jobs:take:');
      }), findsNothing);
      expect(textOf(tester, 'jobs:blocked:consultant'),
          startsWith(w.offer('consultant')!.blockReason!.text));
    });

    // Ловит: доска держит свою копию правил и расходится с миром — пишет
    // свою причину или гасит не ту карточку.
    testWidgets('причина и ступень — из карточки мира: «×1,25», blockReason',
        (WidgetTester tester) async {
      final _BoardWorld w = _BoardWorld(livingWorld());
      await pump(tester, w);
      expect(textOf(tester, 'jobs:step:cashier'), 'ставка ×1,25');
      expect(textOf(tester, 'jobs:blocked:cashier'),
          'Не хватает ⚡: нужно 3, есть 1. Отдохни или перекуси.');
      expect(find.byKey(const ValueKey<String>('jobs:take:cashier')),
          findsNothing);
      // Мир карточку не гасит — доска тоже, даже если ⚡ на вид мало.
      expect(find.byKey(const ValueKey<String>('jobs:take:consultant')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('jobs:step:consultant')),
          findsNothing);
      expect(stageStepText(1.5), '×1,5');
    });

    testWidgets('влезает в 360 × 640 при шрифте 1,3',
        (WidgetTester tester) async {
      final World w = livingWorld();
      await pump(tester, w, textScale: 1.3);
      expect(tester.takeException(), isNull);
      final Finder scroll = find.byType(Scrollable).last;
      for (final JobOffer o in w.jobBoard) {
        final Finder card =
            find.byKey(ValueKey<String>('jobs:card:${offerKey(o)}'));
        await tester.scrollUntilVisible(card, 200, scrollable: scroll);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(card).right, lessThanOrEqualTo(360));
      }
      expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('jobs:back')))
              .height,
          greaterThanOrEqualTo(48));
      expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('jobs:help')))
              .height,
          greaterThanOrEqualTo(48));
    });

    // Ловит: в альбомной доска — растянутый портретный столбик (одна карточка
    // на экран) или уровни одной работы разъехались по разным рядам.
    testWidgets('альбомная 640 × 360 при 1,3: две колонки, уровни рядом',
        (WidgetTester tester) async {
      final World w = livingWorld();
      await pump(tester, w, textScale: 1.3, size: landscape);
      expect(tester.takeException(), isNull);
      final Finder scroll = find.byType(Scrollable).last;
      Rect rect(String k) =>
          tester.getRect(find.byKey(ValueKey<String>('jobs:card:$k')));
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('jobs:card:programmer/easy')), 200,
          scrollable: scroll);
      // Уровни программиста: лёгкий и средний — в одном ряду, рядом.
      expect(rect('programmer/easy').top, rect('programmer/medium').top);
      expect(rect('programmer/easy').right,
          lessThan(rect('programmer/medium').left));
      for (final JobOffer o in w.jobBoard) {
        final Finder card =
            find.byKey(ValueKey<String>('jobs:card:${offerKey(o)}'));
        await tester.scrollUntilVisible(card, 200, scrollable: scroll);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(card).right, lessThanOrEqualTo(640));
        expect(tester.getRect(card).width, lessThan(320));
      }
      final Finder take =
          find.byKey(const ValueKey<String>('jobs:take:cashier'));
      await tester.scrollUntilVisible(take, -200, scrollable: scroll);
      expect(tester.getSize(take).height, greaterThanOrEqualTo(48));
    });
  });
}

/// Мир с подменённой доской: ступень ×1,25 и отказ «мало ⚡» у кассира —
/// числа и причины придумывает мир, а не экран.
class _BoardWorld extends FakeWorld {
  _BoardWorld(this.base);

  final World base;

  @override
  List<JobOffer> get jobBoard => <JobOffer>[
        for (final JobOffer o in base.jobBoard)
          if (o.jobId == 'cashier' || o.jobId == 'consultant')
            JobOffer(
              jobId: o.jobId,
              title: o.title,
              basePay: o.basePay,
              experiencePercent: o.experiencePercent,
              stageStep: o.jobId == 'cashier' ? 1.25 : 1,
              pay: o.pay,
              efficiencyBonusMax: o.efficiencyBonusMax,
              energyCost: 99,
              shiftsLeft: o.shiftsLeft,
              goodScoreMin: o.goodScoreMin,
              goodEnergyExtra: o.goodEnergyExtra,
              goodHappiness: o.goodHappiness,
              blockReason: o.jobId == 'cashier'
                  ? const BlockReason(
                      'job.energy', 'Не хватает ⚡: нужно 3, есть 1.',
                      nextStep: 'Отдохни или перекуси.')
                  : null,
            ),
      ];
}
