import 'game.dart';
import 'models/catalog_item.dart';
import 'models/envelope.dart';
import 'models/pet.dart';

/// Промотка тестового профиля до стадии питомца — только для демо-режима
/// (§2.5.13: эксперт должен увидеть все стадии, не играя три недели).
///
/// Здесь нет ни одной формулы очков: неделя проигрывается теми же
/// действиями, что делает ребёнок на экранах, — план, покупки, закрытие.
/// Стадия получается из журнала так же, как в игре.
///
/// 🔴 Раскладка автопилота — самая дешёвая еда и вода, остальное в копилку.
/// Это не «правильный ответ», а минимум, при котором неделя приносит все
/// три очка заботы. Панель демо-режима говорит об этом прямо.
class DemoAutopilot {
  const DemoAutopilot._();

  /// Сколько недель проигрывать максимум: зависший цикл в демонстрации
  /// выглядит хуже недомотанной игры.
  static const int guard = 12;

  /// Проигрывает недели, пока питомец не дойдёт до [target], и открывает
  /// следующую неделю — с карманными, но без плана.
  static int playTo(Game g, PetStage target) {
    if (!g.profile.isDemo) {
      throw StateError('Автопилот работает только на тестовом профиле');
    }
    int weeks = 0;
    while (g.snapshot.stage.index < target.index && weeks < guard) {
      _goodWeek(g);
      g.closePeriod();
      weeks++;
    }
    if (g.phase == PeriodPhase.closing) g.startPeriod();
    return weeks;
  }

  static void _goodWeek(Game g) {
    if (g.phase == PeriodPhase.closing) g.startPeriod();
    final CatalogItem food = _cheapest(g, (CatalogItem i) => i.effect.fullness > 0);
    final CatalogItem water =
        _cheapest(g, (CatalogItem i) => i.effect.cleanliness > 0);
    if (g.phase == PeriodPhase.planning) {
      final int available = g.snapshot.wallet.unallocated;
      final int needs = food.price + water.price;
      g.confirmPlan(Allocation(needs: needs, savings: available - needs));
    }
    g.buy(food);
    g.buy(water);
  }

  static CatalogItem _cheapest(Game g, bool Function(CatalogItem) suits) =>
      g.content.catalog
          .where((CatalogItem i) => i.envelope == Envelope.needs && suits(i))
          .reduce((CatalogItem a, CatalogItem b) => b.price < a.price ? b : a);
}
