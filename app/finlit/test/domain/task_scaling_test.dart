import 'package:finlit/data/content_loader.dart';
import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Задания в режиме «числа покрупнее» (§2.5.8.4).
///
/// 🔴 Тест существует из-за настоящего дефекта: у задания умножалась только
/// награда. При масштабе 5 «Что сначала?» давало бюджет 6 на каталог, где
/// каша стоит 10, — первая же покупка была дороже всего бюджета, и задание
/// заканчивалось словами «Купить не получилось ничего». А «Сколько недель
/// копить?» уверяло, что зоопарк стоит 20, когда цель стоила 100.
///
/// Поэтому проверяются две вещи и обе — в обоих масштабах: задание остаётся
/// проходимым, и текст задания не противоречит его собственным числам.
void main() {
  late GameContent base;
  late GameContent big;

  setUpAll(() async {
    base = await loadRealContent();
    big = await loadRealContent(scale: 5);
  });

  int money(GameTask t, String key) => t.params[key]! as int;

  /// Каждое задание во всех недельных вариантах: вариант проверяется
  /// теми же правилами, что и основное задание.
  List<GameTask> every(GameContent c) =>
      c.tasks.expand((GameTask t) => t.allVariants).toList();

  List<CatalogItem> itemsOf(GameContent c, GameTask t) =>
      ((t.params['items']! as List<Object?>).cast<String>())
          .map(c.item)
          .toList();

  /// Все числа, которые задание имеет право называть в тексте.
  Set<int> knownNumbers(GameTask t) => <int>{
        t.reward,
        for (final Object? v in t.params.values)
          if (v is int) v,
        for (final Object? v in t.params.values)
          if (v is Map<Object?, Object?>)
            ...v.values.whereType<int>(),
      };

  List<String> textsOf(GameTask t) => <String>[
        t.prompt,
        t.explainAny,
        t.explainBest,
        ...t.params.values.whereType<String>(),
      ];

  for (final MapEntry<String, int> mode
      in <String, int>{'обычные числа': 1, 'числа покрупнее': 5}.entries) {
    final String label = mode.key;
    final int scale = mode.value;
    GameContent content() => scale == 1 ? base : big;

    test('$label: контент цел', () {
      final List<String> problems = ContentValidation.problems(content());
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('$label: каждое задание проходимо', () {
      for (final GameTask t in every(content())) {
        expect(t.reward, greaterThan(0), reason: t.id);

        switch (t.kind) {
          case TaskKind.orderAndBuy:
            final int budget = money(t, 'budget');
            final List<CatalogItem> items = itemsOf(content(), t);
            final int cheapest = items
                .map((CatalogItem i) => i.price)
                .reduce((int a, int b) => a < b ? a : b);
            final int all = items.fold<int>(
                0, (int a, CatalogItem i) => a + i.price);
            expect(budget, greaterThanOrEqualTo(cheapest),
                reason: '${t.id}: бюджет $budget меньше самой дешёвой покупки '
                    '($cheapest) — «Купить не получилось ничего»');
            expect(budget, lessThan(all),
                reason: '${t.id}: монеток хватает на всё, и порядок покупок '
                    'перестаёт что-либо решать');

          case TaskKind.allocate:
            final int amount = money(t, 'amount');
            expect(amount, greaterThan(0), reason: t.id);

            final Map<Object?, Object?>? must =
                t.params['mustCover'] as Map<Object?, Object?>?;
            if (must != null) {
              final int required = must.values
                  .whereType<int>()
                  .fold<int>(0, (int a, int b) => a + b);
              expect(required, lessThanOrEqualTo(amount),
                  reason: '${t.id}: минимум $required нельзя покрыть '
                      'суммой $amount');
            }

            final Map<Object?, Object?>? proposal =
                t.params['finniProposal'] as Map<Object?, Object?>?;
            if (proposal != null) {
              final int total = proposal.values
                  .whereType<int>()
                  .fold<int>(0, (int a, int b) => a + b);
              expect(total, amount,
                  reason: '${t.id}: раскладка Финни не сходится с суммой — '
                      'экран потребует разложить то, чего нет');
            }

            // Подсказанные покупки должны стоить ровно столько, сколько
            // требует минимум по «Нужному»: иначе подсказка врёт.
            final List<Object?>? hints = t.params['hintItems'] as List<Object?>?;
            if (hints != null && must != null) {
              final int hinted = hints
                  .cast<String>()
                  .map(content().item)
                  .fold<int>(0, (int a, CatalogItem i) => a + i.price);
              expect(hinted, must['needs'],
                  reason: '${t.id}: подсказка называет покупки на $hinted, '
                      'а требуется ${must['needs']}');
            }

          case TaskKind.numericInput:
            final int answer = money(t, 'answer');
            expect(answer, greaterThan(0), reason: t.id);
        }
      }
    });

    test('$label: числа в тексте — это числа задания', () {
      final RegExp digits = RegExp(r'\d+');
      for (final GameTask t in every(content())) {
        final Set<int> known = knownNumbers(t);
        for (final String text in textsOf(t)) {
          expect(text.contains('{'), isFalse,
              reason: '${t.id}: незаполненная подстановка в «$text»');
          for (final RegExpMatch m in digits.allMatches(text)) {
            final int n = int.parse(m.group(0)!);
            expect(known, contains(n),
                reason: '${t.id}: текст называет число $n, которого нет '
                    'в параметрах задания:\n«$text»');
          }
        }
      }
    });

    test('$label: разбор вычисления сходится во всех вариантах', () {
      final GameContent c = content();
      final GameContent plain = base;
      for (int v = 0; v < c.task('b1_how_many_weeks').allVariants.length; v++) {
        final GameTask weeks = c.task('b1_how_many_weeks').allVariants[v];
        expect(money(weeks, 'price') - money(weeks, 'saved'),
            money(weeks, 'rest'));
        expect(money(weeks, 'rest') % money(weeks, 'perWeek'), 0,
            reason: 'вариант $v: срок должен делиться нацело');
        expect(money(weeks, 'rest') ~/ money(weeks, 'perWeek'),
            money(weeks, 'answer'));
        expect(money(weeks, 'answer'),
            money(plain.task('b1_how_many_weeks').allVariants[v], 'answer'),
            reason: 'срок в неделях от масштаба монеток не зависит');
        expect(money(weeks, 'price'), c.goal('zoo')!.price,
            reason: 'задание называет цену зоопарка — она должна совпадать '
                'с настоящей целью в любом масштабе');
      }

      for (final GameTask change in c.task('c1_change').allVariants) {
        expect(money(change, 'given') - money(change, 'spent'),
            money(change, 'answer'));
      }

      for (final GameTask cheaper in c.task('c2_which_cheaper').allVariants) {
        expect(money(cheaper, 'bigPrice') % money(cheaper, 'weeks'), 0);
        expect(money(cheaper, 'bigPrice') ~/ money(cheaper, 'weeks'),
            money(cheaper, 'answer'));
        expect(money(cheaper, 'smallPrice'),
            greaterThan(money(cheaper, 'answer')),
            reason: 'иначе вывод «большая выгоднее» перестаёт быть верным');
      }
    });
  }

  test('денежные параметры умножаются, а остальные — нет', () {
    for (int i = 0; i < base.tasks.length; i++) {
      final GameTask b = base.tasks[i];
      final GameTask g = big.tasks[i];
      expect(g.id, b.id);
      expect(g.reward, b.reward * 5, reason: b.id);
      for (final String key in b.moneyParams) {
        final Object? was = b.params[key];
        final Object? now = g.params[key];
        if (was is int) {
          expect(now, was * 5, reason: '${b.id}.$key');
        } else if (was is Map<Object?, Object?>) {
          was.forEach((Object? k, Object? v) {
            expect((now! as Map<Object?, Object?>)[k], (v! as int) * 5,
                reason: '${b.id}.$key.$k');
          });
        }
      }
      for (final String key in b.plainParams) {
        expect(g.params[key], b.params[key], reason: '${b.id}.$key');
      }
    }
  });
}
