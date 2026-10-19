import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_content.dart';
import 'package:finlit/features/world/jobs/games/cashier_game.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:finlit/features/world/jobs/games/gardener_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// C3 (план контента 17.10, эксперт 16.10 [01:37–02:16] «постепенное
/// нарастание сложности»): больше наборов заданий — консультант 8,
/// бухгалтер 6, кассир 20 покупок, садовник 3 поля. Защищает: число наборов,
/// решаемость каждого (лучший вариант в бюджете, бюджет назван в реплике),
/// суммы кассы, нарастание трудности внутри купюры, отсутствие дублей.
/// Уронит: набор добавили без лучшего варианта или с бюджетом меньше его
/// цены, сдача в файле не сходится с ценой, «трудная» сдача стоит перед
/// лёгкой, два одинаковых набора. Почему не ловят прежние:
/// `tasks_logic_test` проверяет лесенку двух наборов и порядок купюр, но не
/// число, суммы и решаемость всех.
Map<String, Object?> _job(String id) => ((jsonDecode(
            File('${WorldContentLoader.base}/jobs.json').readAsStringSync())
        as Map<String, Object?>)['jobs']! as Map<String, Object?>)[id]!
    as Map<String, Object?>;

/// Сколько монет нужно на сдачу, если отдавать самыми крупными (1, 2, 5, 10
/// — жадный размен для этого набора минимален).
int coinsFor(int change, List<int> coins) {
  int left = change, n = 0;
  for (final int c in <int>[...coins]..sort((int a, int b) => b - a)) {
    n += left ~/ c;
    left %= c;
  }
  expect(left, 0, reason: 'сдачу $change не собрать из $coins');
  return n;
}

void main() {
  for (final (String job, ConsultantContent c, int want)
      in <(String, ConsultantContent, int)>[
    ('consultant', contentJobGames.consultant, 8),
    ('accountant', contentJobGames.accountant, 6),
  ]) {
    test('$job: $want наборов, каждый решается, без дублей', () {
      expect(c.sets, hasLength(want));
      expect(c.sets.map((ConsultantSet s) => s.id).toSet(), hasLength(want));
      expect(
          c.sets.map((ConsultantSet s) => s.category).toSet(), hasLength(want));
      final List<Object?> raw = _job(job)['sets']! as List<Object?>;
      final Set<String> itemIds = <String>{};
      for (final Object? o in raw) {
        final Map<String, Object?> s = o! as Map<String, Object?>;
        final String id = s['id']! as String;
        final List<Map<String, Object?>> items = <Map<String, Object?>>[
          for (final Object? i in s['items']! as List<Object?>)
            i! as Map<String, Object?>,
        ];
        expect(items, hasLength(3), reason: '$id: три товара');
        for (final Map<String, Object?> i in items) {
          expect(itemIds.add(i['id']! as String), isTrue,
              reason: '$id: id ${i['id']} повторяется');
          expect((i['why'] as String? ?? '').isNotEmpty, isTrue,
              reason: '$id/${i['id']}: «почему такая цена»');
        }
        final Set<int> prices = <int>{
          for (final Map<String, Object?> i in items) i['price']! as int,
        };
        expect(prices, hasLength(3), reason: '$id: цены разные — полки');
        final Map<String, Object?> cu = s['customer']! as Map<String, Object?>;
        final int budget = cu['budget']! as int;
        final Map<String, Object?> best = items.firstWhere(
            (Map<String, Object?> i) => i['id'] == cu['best_fit'],
            orElse: () => fail('$id: best_fit не из товаров набора'));
        expect(best['price']! as int, lessThanOrEqualTo(budget),
            reason: '$id: лучший вариант в бюджете');
        expect(cu['line']! as String, contains('$budget монет'),
            reason: '$id: бюджет назван покупателем');
        for (final String k in <String>[
          'feedback_fit',
          'feedback_cheaper',
          'feedback_pricier'
        ]) {
          expect((cu[k] as String? ?? '').isNotEmpty, isTrue, reason: '$id.$k');
        }
      }
    });
  }

  test('кассир: 20 покупок, суммы сходятся, сдачу можно собрать', () {
    final Map<String, Object?> j = _job('cashier');
    final List<int> coins = <int>[
      for (final Object? c in j['coins']! as List<Object?>) c! as int,
    ];
    final List<Object?> raw = j['purchases']! as List<Object?>;
    expect(raw, hasLength(20));
    final Set<String> ids = <String>{};
    final Set<String> pairs = <String>{};
    for (final Object? o in raw) {
      final Map<String, Object?> p = o! as Map<String, Object?>;
      final int price = p['price']! as int, paid = p['paid_with']! as int;
      expect(ids.add(p['id']! as String), isTrue, reason: 'id ${p['id']}');
      expect(pairs.add('$price/$paid'), isTrue,
          reason: 'дубль $price из $paid');
      expect(price, inExclusiveRange(0, paid), reason: '${p['item']}');
      expect(<int>[10, 50, 100], contains(paid), reason: '${p['item']}');
      expect(p['change'], paid - price, reason: '${p['item']}: поле change');
      coinsFor(paid - price, coins);
    }
  });

  test(
      'кассир: купюры по возрастанию, внутри купюры сдача не труднее '
      'следующей (меньше монет — проще)', () {
    final CashierContent c = contentJobGames.cashier;
    final List<int> coins = <int>[1, 2, 5, 10];
    for (int k = 1; k < c.purchases.length; k++) {
      final CashierPurchase a = c.purchases[k - 1], b = c.purchases[k];
      expect(b.paidWith, greaterThanOrEqualTo(a.paidWith),
          reason: '${b.item} после ${a.item}');
      if (a.paidWith != b.paidWith) continue;
      final int da = coinsFor(a.change, coins), db = coinsFor(b.change, coins);
      expect(db, greaterThanOrEqualTo(da),
          reason: '${a.paidWith}−${a.price} ($da мон.) перед '
              '${b.paidWith}−${b.price} ($db мон.)');
    }
  });

  test('садовник: 3 поля, грядки ложатся в сетку', () {
    final List<Object?> fields = _job('gardener')['fields']! as List<Object?>;
    expect(fields, hasLength(3));
    final Set<String> ids = <String>{};
    for (final Object? o in fields) {
      final Map<String, Object?> f = o! as Map<String, Object?>;
      expect(ids.add(f['id']! as String), isTrue);
      final List<Object?> grid = f['grid']! as List<Object?>;
      expect((grid[0]! as int) * (grid[1]! as int), f['beds'],
          reason: '${f['id']}: колонки × ряды = грядки');
    }
  });

  // Игра берёт поле смены по номеру: грядок столько, сколько в fields[r],
  // и ничего не вылезает за экран при шрифте 1,3 в обеих ориентациях.
  for (int r = 0; r < 3; r++) {
    for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
      testWidgets(
          'садовник: смена $r — своё поле, ${size.width.toInt()}×'
          '${size.height.toInt()}', (WidgetTester tester) async {
        final Map<String, Object?> f = (_job('gardener')['fields']!
            as List<Object?>)[r]! as Map<String, Object?>;
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
                  content: contentJobGames.gardener,
                  round: r,
                  onDone: (double _) {}),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final int beds = find
            .byWidgetPredicate((Widget w) =>
                w.key is ValueKey<String> &&
                RegExp(r'^gardener:bed:\d+$')
                    .hasMatch((w.key! as ValueKey<String>).value))
            .evaluate()
            .length;
        expect(beds, f['beds']);
      });
    }
  }
}
