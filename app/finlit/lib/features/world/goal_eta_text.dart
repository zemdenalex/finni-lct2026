import '../../domain/phrases.dart';
import '../../domain/world/goal_eta.dart';

/// Срок до цели одной короткой строкой — для списка целей при выборе
/// (путь ребёнка 16.10, дефект 11: «Собака 3200» выглядела так же близкой,
/// как «Рыбка 400»). Расчёт — [goalEta] (ТЗ 2.5.7.4, `06-formuly.md` §5.1),
/// здесь только слова.
///
/// null — срока пока нет: под списком тогда одна строка [goalEtaGapText], а
/// не одно и то же у каждой цели.
String? goalEtaShort(GoalEta? e) {
  if (e == null) return 'накоплено уже хватает';
  final int? weeks = e.weeks;
  if (weeks == null) return null;
  return 'примерно $weeks ${Phrases.weekWord(weeks)}';
}

/// Почему срока нет — пока не было ни одного взноса.
const String goalEtaNoDeposit =
    'Сколько ждать, станет ясно, когда ты в первый раз отложишь '
    'монеты.';

/// Взнос уже есть, но первая неделя с ним ещё идёт: срок считается только по
/// законченным неделям (`goalEta`, [GoalEtaGap.weekNotOver]).
const String goalEtaWeekNotOver =
    'Срок посчитаем в конце первой недели — по тому, сколько получится '
    'отложить.';

/// Почему срока нет — словами для ребёнка.
String goalEtaGapText(GoalEtaGap gap) => switch (gap) {
      GoalEtaGap.noDeposit => goalEtaNoDeposit,
      GoalEtaGap.weekNotOver => goalEtaWeekNotOver,
    };
