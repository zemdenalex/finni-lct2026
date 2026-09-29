import 'dart:math' as math;

import '../models/goal.dart';

/// Прогноз срока до цели.
class GoalForecast {
  const GoalForecast({
    required this.remaining,
    required this.weeks,
    required this.averageDeposit,
    required this.reason,
  });

  final int remaining;

  /// null — срок показать нельзя, и [reason] объясняет почему.
  final int? weeks;
  final int averageDeposit;

  /// Почему срока нет. Показывается вместо числа: §2.5.7.4 требует, чтобы
  /// расчёт был **понятным**, а придуманный из воздуха срок понятным не бывает.
  final String? reason;

  bool get reached => remaining <= 0;
}

/// Что произойдёт при снятии с копилки — показывается **до** подтверждения
/// (§2.5.7.5).
class WithdrawPreview {
  const WithdrawPreview({
    required this.savingsBefore,
    required this.savingsAfter,
    required this.before,
    required this.after,
  });

  final int savingsBefore;
  final int savingsAfter;
  final GoalForecast before;
  final GoalForecast after;
}

class SavingsRules {
  const SavingsRules._();

  /// Сколько недель осталось до цели.
  ///
  /// §2.5.7.4 ТЗ: «расчёт должен быть понятным и основанным на **средней сумме
  /// регулярного пополнения**». Считаем по последним [window] неделям, в которых
  /// взнос был больше нуля, — недели без взносов не должны раздувать срок
  /// до бесконечности, но и не должны молча исчезать из знаменателя, если
  /// взносов не было вовсе.
  static GoalForecast forecast({
    required Goal goal,
    required int savings,
    required List<int> depositHistory,
    int window = 3,
  }) {
    final int remaining = goal.price - savings;

    if (remaining <= 0) {
      return GoalForecast(
        remaining: remaining,
        weeks: 0,
        averageDeposit: 0,
        reason: null,
      );
    }

    final List<int> positive =
        depositHistory.where((int d) => d > 0).toList();
    final List<int> recent = positive.length <= window
        ? positive
        : positive.sublist(positive.length - window);

    if (recent.isEmpty) {
      return GoalForecast(
        remaining: remaining,
        weeks: null,
        averageDeposit: 0,
        reason: 'Срок появится, когда ты первый раз отложишь монетки в копилку.',
      );
    }

    final int sum = recent.reduce((int a, int b) => a + b);
    final int average = (sum / recent.length).round();

    if (average <= 0) {
      return GoalForecast(
        remaining: remaining,
        weeks: null,
        averageDeposit: 0,
        reason: 'Пока откладывается слишком мало, чтобы посчитать срок.',
      );
    }

    return GoalForecast(
      remaining: remaining,
      weeks: (remaining / average).ceil(),
      averageDeposit: average,
      reason: null,
    );
  }

  /// Сколько максимум можно снять.
  static int maxWithdraw(int savings) => math.max(0, savings);

  static WithdrawPreview previewWithdraw({
    required Goal goal,
    required int savings,
    required int amount,
    required List<int> depositHistory,
  }) {
    final int clamped = amount.clamp(0, maxWithdraw(savings));
    return WithdrawPreview(
      savingsBefore: savings,
      savingsAfter: savings - clamped,
      before: forecast(
          goal: goal, savings: savings, depositHistory: depositHistory),
      after: forecast(
          goal: goal,
          savings: savings - clamped,
          depositHistory: depositHistory),
    );
  }
}
