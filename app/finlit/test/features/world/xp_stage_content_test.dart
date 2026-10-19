import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/games/cashier_game.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:finlit/features/world/jobs/games/gardener_game.dart';
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart';

/// C2: содержание ступеней сложности (`jobs.json → jobs.<работа>.stages`) и
/// экран смены. Защищает: у кассира, консультанта, бухгалтера и садовника
/// по 3 ступени; ступень 1 — базовое содержание без изменений; дальше
/// труднее (кассир — больше покупателей и сдача из большего числа монет,
/// садовник — больше грядок и сохнет больше разом); каждая ступень решается
/// и влезает на экран; карточка смены показывает ступень только с флагом, а
/// игра получает содержание своей ступени. Уронит: ступень 1 разошлась с
/// базой, ступень «труднее» на деле легче, набор ступени без решения, экран
/// не передал ступень в игру. Почему не ловят прежние: `job_sets_test`
/// проверяет только базовое содержание.
Map<String, Object?> _jobs() =>
    (jsonDecode(File('${WorldContentLoader.base}/jobs.json').readAsStringSync())
        as Map<String, Object?>)['jobs']! as Map<String, Object?>;

List<Map<String, Object?>> _stages(String job) => <Map<String, Object?>>[
      for (final Object? s in (_jobs()[job]! as Map<String, Object?>)['stages']!
          as List<Object?>)
        s! as Map<String, Object?>,
    ];

int _coins(int change) {
  int left = change, n = 0;
  for (final int c in const <int>[10, 5, 2, 1]) {
    n += left ~/ c;
    left %= c;
  }
  return n;
}

double _avgCoins(CashierContent c) =>
    c.purchases
        .map((CashierPurchase p) => _coins(p.change))
        .reduce((int a, int b) => a + b) /
    c.purchases.length;

void main() {
  const List<String> staged = <String>[
    'cashier',
    'consultant',
    'accountant',
    'gardener'
  ];

  test('по 3 ступени; ступень 1 — базовое содержание, без своих полей', () {
    for (final String job in staged) {
      final List<Map<String, Object?>> s = _stages(job);
      expect(s, hasLength(3), reason: job);
      expect(s.first.keys.where((String k) => !k.startsWith('_')), isEmpty,
          reason: '$job: ступень 1 ничего не переопределяет');
    }
    expect(identical(contentJobGames.forStage(1), contentJobGames), isTrue);
    expect(identical(contentJobGames.forStage(null), contentJobGames), isTrue);
  });

  test('кассир: с каждой ступенью покупателей не меньше и сдача труднее', () {
    CashierContent? prev;
    for (int st = 1; st <= 3; st++) {
      final CashierContent c = contentJobGames.forStage(st).cashier;
      for (final CashierPurchase p in c.purchases) {
        expect(p.change, greaterThan(0), reason: p.item);
        expect(<int>[10, 50, 100], contains(p.paidWith));
      }
      for (int k = 1; k < c.purchases.length; k++) {
        final CashierPurchase a = c.purchases[k - 1], b = c.purchases[k];
        expect(b.paidWith, greaterThanOrEqualTo(a.paidWith),
            reason: 'ступень $st: ${b.item}');
        if (a.paidWith == b.paidWith) {
          expect(_coins(b.change), greaterThanOrEqualTo(_coins(a.change)),
              reason: 'ступень $st: ${a.item} → ${b.item}');
        }
      }
      if (prev != null) {
        expect(c.customersPerShift, greaterThan(prev.customersPerShift),
            reason: 'ступень $st: покупателей больше');
        expect(_avgCoins(c), greaterThan(_avgCoins(prev)),
            reason: 'ступень $st: сдача из большего числа монет');
      }
      prev = c;
    }
  });

  test('кассир: поле change в файле = цена до купюры на каждой ступени', () {
    for (final Map<String, Object?> s in _stages('cashier').skip(1)) {
      for (final Object? o in s['purchases']! as List<Object?>) {
        final Map<String, Object?> p = o! as Map<String, Object?>;
        expect(p['change'], (p['paid_with']! as int) - (p['price']! as int),
            reason: '${p['item']}');
      }
    }
  });

  test('консультант и бухгалтер: каждая ступень решается, id не повторяются',
      () {
    for (final String job in <String>['consultant', 'accountant']) {
      final Set<String> ids = <String>{};
      for (int st = 1; st <= 3; st++) {
        final JobGames g = contentJobGames.forStage(st);
        final ConsultantContent c =
            job == 'consultant' ? g.consultant : g.accountant;
        expect(c.sets.length, greaterThanOrEqualTo(2), reason: '$job/$st');
        for (final ConsultantSet s in c.sets) {
          if (st > 1) {
            expect(ids.add(s.id), isTrue, reason: '$job: ${s.id} повторяется');
          }
          final ConsultantItem best = s.items
              .firstWhere((ConsultantItem i) => i.id == s.customer.bestFit);
          expect(best.price, lessThanOrEqualTo(s.customer.budget),
              reason: '$job/$st/${s.id}');
          expect(s.customer.line, contains('${s.customer.budget} монет'),
              reason: '$job/$st/${s.id}');
          expect(
              s.items.map((ConsultantItem i) => i.price).toSet(), hasLength(3));
        }
        if (st == 1) {
          ids.addAll(c.sets.map((ConsultantSet s) => s.id));
        }
      }
    }
  });

  test('садовник: с каждой ступенью грядок больше и сохнет больше разом', () {
    double avgBeds(GardenerContent g) =>
        <int>[for (int r = 0; r < 6; r++) g.forRound(r).beds]
            .reduce((int a, int b) => a + b) /
        6;
    GardenerContent? prev;
    for (int st = 1; st <= 3; st++) {
      final GardenerContent g = contentJobGames.forStage(st).gardener;
      if (prev != null) {
        expect(avgBeds(g), greaterThan(avgBeds(prev)), reason: 'ступень $st');
        expect(g.maxDryAtOnce, greaterThanOrEqualTo(prev.maxDryAtOnce));
      }
      prev = g;
    }
  });

  for (int st = 2; st <= 3; st++) {
    for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
      testWidgets(
          'садовник, ступень $st: каждое поле влезает · '
          '${size.width.toInt()}×${size.height.toInt()}',
          (WidgetTester tester) async {
        final GardenerContent g = contentJobGames.forStage(st).gardener;
        for (int r = 0; r < g.fields.length; r++) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GardenerGame(
                    key: ValueKey<int>(r),
                    content: g,
                    round: r,
                    onDone: (double _) {}),
              ),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'поле $r');
        }
      });
    }
  }

  /// Мир с флагом и порогами 0/1/2: две хорошие смены — ступень 3.
  Future<WorldGame> stagedWorld({bool on = true, int good = 2}) async {
    final WorldGame w = await openWorldGame(
        read: (String p) async {
          final String s = await File(p).readAsString();
          if (!p.endsWith('economy.json')) return s;
          final Map<String, Object?> e = jsonDecode(s) as Map<String, Object?>;
          e['day_cycle'] = <String, Object?>{
            ...(e['day_cycle']! as Map<String, Object?>),
            'xp_stages': on,
            'xp_stage_min': <int>[0, 1, 2],
          };
          return jsonEncode(e);
        },
        storage: MemoryStorage());
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    for (int i = 0; i < good; i++) {
      ok(w.completeJob('cashier', score: 1));
      ok(w.sleep());
    }
    return w;
  }

  testWidgets('карточка смены: «Ступень 3», игра — покупки ступени 3',
      (WidgetTester tester) async {
    final WorldGame w = await tester.runAsync(stagedWorld) as WorldGame;
    expect(w.xpStage('cashier'), 3);
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
        world: w);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('job:offer:stage')))
            .data,
        startsWith('Ступень 3'));
    // Карточка: «Начать смену» или вопрос смены (вариант и есть старт).
    Finder start = find.byKey(const ValueKey<String>('job:start'));
    if (start.evaluate().isEmpty) {
      start = find
          .byWidgetPredicate((Widget w) =>
              w.key is ValueKey<String> &&
              RegExp(r'^job:choice:(?!question|hint|effects)[a-z_]+$')
                  .hasMatch((w.key! as ValueKey<String>).value))
          .first;
    }
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final CashierContent s3 = contentJobGames.forStage(3).cashier;
    final String first = s3
        .purchasesFor(JobPlayScreen.roundFor(w.snapshot, 'cashier'))
        .first
        .item;
    expect(find.textContaining(first), findsWidgets,
        reason: 'игра показывает покупку ступени 3 «$first»');
  });

  // BG-10 (баг-прогон 18.10): на базовой ступени (опыт 0) карточка писала
  // «Ступень 1: задания сложнее» — сложнее ещё ничего не стало.
  for (final (String name, bool on, int good, int? stage)
      in <(String, bool, int, int?)>[
    ('флаг выключен', false, 2, null),
    ('ступень 1 (опыт 0)', true, 0, 1),
  ]) {
    testWidgets('$name: строки ступени нет', (WidgetTester tester) async {
      final WorldGame w = await tester
          .runAsync(() => stagedWorld(on: on, good: good)) as WorldGame;
      expect(w.xpStage('cashier'), stage);
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: w);
      expect(
          find.byKey(const ValueKey<String>('job:offer:stage')), findsNothing);
    });
  }
}
