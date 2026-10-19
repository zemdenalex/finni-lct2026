import 'contract.dart';

/// Примерный срок до цели по среднему пополнению копилки (ТЗ 2.5.7.4).
///
/// Правило (решение владельца 17.10, вариант A; `docs/sdacha/06-formuly.md`
/// §5.1): **остаток / средний взнос за последние 3 законченные недели с
/// взносом, включая ползунок; до первой такой недели — объяснение вместо
/// срока.**
///
/// - Неделя «с взносом» — та, где чистое отложенное [WeekPlanFact.goal].actual
///   (взносы в ЦЕЛЬ по плану и ползунком минус снятое) больше нуля.
/// - Неделя «законченная» — итоги подведены ([WeekPlanFact.billsPaid]; запись
///   `periodClosed`, в режиме дней — после сна последнего дня). Идущая неделя
///   в среднее не входит: в ней ещё копят ползунком, и один взнос по плану
///   выдал бы срок как будто это вся неделя.
/// - Недели без взноса или со снятием в среднее не входят: срок показывает
///   темп, когда ребёнок копит, а не штрафует за пропуск.
/// - Недели = ⌈осталось ÷ среднее⌉ целочисленно:
///   `(remaining·n + sum − 1) ~/ sum`.
///
/// Считается из [World.weekHistory], без изменения контракта.
class GoalEta {
  const GoalEta._({this.perWeek, this.weeks, this.reason});

  /// Среднее пополнение за неделю, округлённое для показа (не меньше 1).
  final int? perWeek;

  /// Сколько недель до цели при таком темпе.
  final int? weeks;

  /// Почему срока нет; null, когда срок есть.
  final GoalEtaGap? reason;

  bool get hasEstimate => weeks != null;
}

/// Почему срок не посчитать.
enum GoalEtaGap {
  /// Ни одной недели с взносом в копилку.
  noDeposit,

  /// Взнос есть, но только в идущей неделе: ни одна неделя с взносом ещё не
  /// закончилась, среднего пополнения пока нет.
  weekNotOver,
}

/// Сколько последних законченных недель с взносом усредняется.
const int goalEtaWindow = 3;

/// Срок до цели: [remaining] — сколько ещё не хватает (цена − копилка).
/// При [remaining] ≤ 0 — null: цель уже можно купить, срок не нужен.
GoalEta? goalEta(List<WeekPlanFact> history, int remaining) {
  if (remaining <= 0) return null;
  final List<WeekPlanFact> withDeposit = history
      .where((WeekPlanFact w) => w.billsPaid && w.goal.actual > 0)
      .toList();
  if (withDeposit.isEmpty) {
    final bool depositThisWeek =
        history.any((WeekPlanFact w) => !w.billsPaid && w.goal.actual > 0);
    return GoalEta._(
        reason:
            depositThisWeek ? GoalEtaGap.weekNotOver : GoalEtaGap.noDeposit);
  }
  final List<WeekPlanFact> last = withDeposit.length <= goalEtaWindow
      ? withDeposit
      : withDeposit.sublist(withDeposit.length - goalEtaWindow);
  final int n = last.length;
  final int sum =
      last.fold<int>(0, (int s, WeekPlanFact w) => s + w.goal.actual);
  return GoalEta._(
    // Среднее меньше половины монеты всё равно больше нуля.
    perWeek: (sum / n).round() < 1 ? 1 : (sum / n).round(),
    weeks: (remaining * n + sum - 1) ~/ sum,
  );
}
