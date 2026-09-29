import 'package:finlit/domain/economy/finni_habits.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Финни сам раскладывает монетки» — обещание стадии «Хранитель копилки».
/// Финни не знает правильного ответа: он повторяет привычку ребёнка.
void main() {
  FinniProposal? propose(Map<int, Allocation> plans,
          {int periodNo = 5, int available = 16}) =>
      FinniHabits.propose(
          plans: plans, periodNo: periodNo, available: available);

  test('без истории Финни не предлагает ничего', () {
    expect(propose(<int, Allocation>{}), isNull);
    expect(
        propose(<int, Allocation>{1: const Allocation()}), isNull,
        reason: 'пустой план — не привычка');
  });

  test('раскладка всегда сходится с тем, что есть', () {
    const List<Allocation> habits = <Allocation>[
      Allocation(needs: 3, wants: 4, savings: 3),
      Allocation(needs: 1, wants: 1, savings: 1),
      Allocation(needs: 5, wants: 0, savings: 9),
      Allocation(needs: 0, wants: 10, savings: 0),
    ];
    for (final Allocation h in habits) {
      for (int available = 1; available <= 50; available++) {
        final FinniProposal p =
            propose(<int, Allocation>{4: h}, available: available)!;
        expect(p.plan.total, available, reason: '$h на $available');
      }
    }
  });

  test('повторяет доли ребёнка — с точностью до монетки', () {
    // Ребёнок раскладывал 10 как 3/2/5, а теперь у Финни 16.
    final FinniProposal p = propose(<int, Allocation>{
      4: const Allocation(needs: 3, wants: 2, savings: 5),
    })!;
    expect(p.plan.needs, inInclusiveRange(4, 5));
    expect(p.plan.wants, inInclusiveRange(3, 4));
    expect(p.plan.savings, 8);
  });

  test('помнит три последние недели, а не всю игру и не будущее', () {
    final FinniProposal p = propose(<int, Allocation>{
      1: const Allocation(wants: 10), // давно — забыто
      2: const Allocation(needs: 4, savings: 6),
      3: const Allocation(needs: 4, savings: 6),
      4: const Allocation(needs: 4, savings: 6),
      5: const Allocation(wants: 10), // текущая неделя — ещё не привычка
    }, available: 10)!;
    expect(p.plan, isA<Allocation>());
    expect(p.plan.wants, 0);
    expect(p.plan.needs, 4);
    expect(p.plan.savings, 6);
  });

  test('называет привычку, но не оценивает её', () {
    final String saver = propose(<int, Allocation>{
      4: const Allocation(needs: 3, wants: 1, savings: 6),
    })!.says;
    expect(saver, contains('откладываешь'));

    final String spender = propose(<int, Allocation>{
      4: const Allocation(needs: 3, wants: 7),
    })!.says;
    expect(spender, contains('«Хочу»'));

    final String noNeeds = propose(<int, Allocation>{
      4: const Allocation(wants: 5, savings: 5),
    })!.says;
    expect(noNeeds, contains('«Нужное»'));

    for (final String s in <String>[saver, spender, noNeeds]) {
      for (final String word in <String>['молодец', 'зря', 'плохо', 'неправильно']) {
        expect(s.toLowerCase(), isNot(contains(word)), reason: s);
      }
    }
  });
}
