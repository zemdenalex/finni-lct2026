import 'package:finlit/domain/economy/savings_rules.dart';
import 'package:finlit/domain/models/goal.dart';
import 'package:flutter_test/flutter_test.dart';

const Goal zoo = Goal(
    id: 'zoo', title: 'Зоопарк', price: 20, isExperience: true, icon: 'zoo');

void main() {
  group('§2.5.7.4 срок до цели — краевые случаи', () {
    test('взносов не было: срок не выдумывается', () {
      final GoalForecast f = SavingsRules.forecast(
          goal: zoo, savings: 0, depositHistory: const <int>[]);
      expect(f.weeks, isNull);
      expect(f.reason, isNotNull);
    });

    test('были взносы, потом три пустые недели — деления на ноль нет', () {
      final GoalForecast f = SavingsRules.forecast(
          goal: zoo, savings: 5, depositHistory: const <int>[5, 0, 0, 0]);
      expect(f.weeks, isNotNull);
      expect(f.averageDeposit, 5);
      expect(f.weeks, 3, reason: '(20 − 5) / 5 = 3');
    });

    test('цель уже набрана: срок ноль, а не отрицательное число', () {
      final GoalForecast f = SavingsRules.forecast(
          goal: zoo, savings: 25, depositHistory: const <int>[5, 5, 5]);
      expect(f.reached, isTrue);
      expect(f.weeks, 0);
    });

    test('перелёт через цель не даёт отрицательных недель', () {
      final GoalForecast f = SavingsRules.forecast(
          goal: zoo, savings: 100, depositHistory: const <int>[50]);
      expect(f.weeks, 0);
      expect(f.weeks! >= 0, isTrue);
    });

    test('среднее берётся по последним трём непустым неделям', () {
      final GoalForecast f = SavingsRules.forecast(
        goal: zoo,
        savings: 2,
        depositHistory: const <int>[100, 0, 3, 3, 3],
      );
      expect(f.averageDeposit, 3,
          reason: 'старый крупный взнос не должен занижать срок');
      expect(f.weeks, 6, reason: '(20 − 2) / 3 = 6');
    });
  });

  group('§2.5.7.5 снятие показывается до подтверждения', () {
    test('видно и новую сумму копилки, и новый срок', () {
      final WithdrawPreview p = SavingsRules.previewWithdraw(
        goal: zoo,
        savings: 12,
        amount: 4,
        depositHistory: const <int>[4, 4, 4],
      );
      expect(p.savingsBefore, 12);
      expect(p.savingsAfter, 8);
      expect(p.before.weeks, 2, reason: '(20 − 12) / 4 = 2');
      expect(p.after.weeks, 3, reason: '(20 − 8) / 4 = 3');
    });

    test('снять больше, чем есть, невозможно', () {
      final WithdrawPreview p = SavingsRules.previewWithdraw(
        goal: zoo,
        savings: 5,
        amount: 50,
        depositHistory: const <int>[5],
      );
      expect(p.savingsAfter, 0);
    });
  });
}
