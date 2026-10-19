import '../../../domain/world/contract.dart';
import '../../../domain/world/world_config.dart';
import '../../../domain/world/world_game.dart';

/// Числа ежедневных дел (контракт `docs/final/day-energy-contract.md` §4).
///
/// 🔴 Флаг один и живёт в домене: `economy.json → day_cycle.daily_activities`.
/// Включил его — карточка «Сегодня» появилась в комнате; экран своего флага
/// не держит. В контракте [World] настроек нет, поэтому числа берутся у
/// [WorldGame]; у любого другого мира (фейк в тестах экранов) дел нет.
class DailyRules {
  const DailyRules({
    required this.shopEnergy,
    required this.restEnergy,
    required this.restHappiness,
  });

  /// Дела включены в этом мире — или null, если выключены.
  static DailyRules? of(World w) {
    if (w is! WorldGame) return null;
    final DayCycle dc = w.config.dayCycle;
    if (!dc.enabled || !dc.dailyActivities) return null;
    return DailyRules(
      shopEnergy: dc.shopEnergy,
      restEnergy: dc.restEnergy,
      restHappiness: dc.restHappiness,
    );
  }

  /// ⚡ за поход в магазин (наполнить холодильник).
  final double shopEnergy;

  /// ⚡ за отдых дома.
  final double restEnergy;

  /// 😊 за отдых дома.
  final int restHappiness;
}

/// Сколько ещё дел хватит сил сделать сегодня: ⚡ ÷ самое дешёвое дело.
int actsLeftToday(World w) {
  final double cheapest = w.cheapestActionEnergy;
  if (cheapest <= 0) return 0;
  return (w.snapshot.energy / cheapest + 1e-9).floor();
}

/// Сил не осталось ни на одно дело — вечер (в домене отдельного вечера нет:
/// утро наступает сразу после «Спать»).
bool isEvening(World w) => actsLeftToday(w) == 0;

/// Порций в холодильнике всего.
int fridgePortions(ResourceSnapshot s) =>
    s.fridge.values.fold<int>(0, (int a, int b) => a + b);

/// Сколько дней недели впереди, считая сегодня, — столько порций разумно
/// положить в холодильник.
int daysLeftInWeek(ResourceSnapshot s) =>
    (s.daysPerWeek - s.dayInWeek + 1).clamp(1, s.daysPerWeek);
