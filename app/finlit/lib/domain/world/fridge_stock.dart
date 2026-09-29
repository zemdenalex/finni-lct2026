/// Холодильник в комнате — видимый запас еды недели (фидбек дизайнера
/// 28.09, п. 7, этап 4; решение Дениса 28.09; с 29.09 — приёмы пищи,
/// Денис, 938: «кушаем не так часто по игре»).
///
/// 🔴 Не показатель: нового числа в сохранении нет, штрафа и «голода» нет.
/// Запас **выводится** из того, что журнал уже знает: номер недели,
/// домашнее меню, сколько раз Финни поел и сколько перекусов куплено.
/// Пустой холодильник — просто пустой: невыбранные приёмы Финни всё равно
/// съест дома в итогах недели.
library;

import 'contract.dart';

/// Что сейчас в холодильнике.
class FridgeStock {
  const FridgeStock({this.foodId, this.food = 0, this.snacks = 0});

  static const FridgeStock empty = FridgeStock();

  /// Домашнее меню — какую картинку класть на полки.
  final String? foodId;

  /// Приёмов пищи до конца недели.
  final int food;

  /// Перекусов из магазина, купленных на этой неделе.
  final int snacks;

  /// Всего порций на полках.
  int get portions => food + snacks;

  @override
  bool operator ==(Object other) =>
      other is FridgeStock &&
      other.foodId == foodId &&
      other.food == food &&
      other.snacks == snacks;

  @override
  int get hashCode => Object.hash(foodId, food, snacks);

  @override
  String toString() => 'FridgeStock($foodId: food $food, snacks $snacks)';
}

/// Запас по правилу (`docs/sdacha/06-formuly.md`, «Холодильник»):
///
/// * до первой недели ([weekNo] 0) — пусто;
/// * с начала недели — [mealsPerWeek] порций домашнего меню [foodId];
///   смена меню посреди недели меняет только картинку, не число;
/// * каждый приём пищи ([mealsEaten], кнопка «Съесть») — минус порция;
///   игровые дни еду больше не едят;
/// * перекус из магазина ([snacksThisWeek]) — +1 порция на полке до конца
///   недели;
/// * меньше нуля не бывает; новая неделя — снова полный.
FridgeStock fridgeStock({
  required int weekNo,
  required String? foodId,
  required int mealsPerWeek,
  required int mealsEaten,
  required int snacksThisWeek,
}) {
  if (weekNo <= 0) return FridgeStock.empty;
  final int food = mealsPerWeek - (mealsEaten < 0 ? 0 : mealsEaten);
  return FridgeStock(
    foodId: foodId,
    food: food < 0 ? 0 : food,
    snacks: snacksThisWeek < 0 ? 0 : snacksThisWeek,
  );
}

/// Запас из снимка мира.
FridgeStock fridgeOf(ResourceSnapshot s) => fridgeStock(
      weekNo: s.weekNo,
      foodId: s.foodId,
      mealsPerWeek: s.mealsPerWeek,
      mealsEaten: s.mealsThisWeek,
      snacksThisWeek: s.snacksThisWeek,
    );
