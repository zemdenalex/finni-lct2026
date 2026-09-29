import '../../domain/models/catalog_item.dart';
import '../../domain/models/envelope.dart';

/// Чем закончился проход по списку покупок в порядке, который составил
/// ребёнок.
class OrderRun {
  const OrderRun({
    required this.bought,
    required this.stoppedAt,
    required this.left,
  });

  final List<CatalogItem> bought;

  /// Первая позиция, на которую не хватило монеток. null — хватило на все.
  final CatalogItem? stoppedAt;

  /// Сколько монеток осталось.
  final int left;
}

/// Расчёты заданий. Чистый Dart, без Flutter.
///
/// 🔴 Это не дубль игровой экономики: задания — учебные сценарии, они не
/// трогают кошелёк ребёнка (иначе одно и то же действие меняло бы и историю
/// покупок, и журнал недели). Поэтому «покупка» внутри задания считается
/// здесь, а не в [PurchaseRules], — но всё равно не в виджете.
abstract final class TaskScoring {
  /// Идём по списку сверху вниз и покупаем, пока хватает бюджета.
  ///
  /// На первой позиции, которая не влезает, останавливаемся и показываем её:
  /// «монетки закончились вот здесь» — это и есть последствие порядка.
  /// Пропускать дорогую позицию и брать следующую нельзя: тогда порядок,
  /// который составил ребёнок, перестал бы значить хоть что-нибудь.
  static OrderRun run(List<CatalogItem> ordered, int budget) {
    final List<CatalogItem> bought = <CatalogItem>[];
    int left = budget;
    for (final CatalogItem item in ordered) {
      if (item.price > left) {
        return OrderRun(bought: bought, stoppedAt: item, left: left);
      }
      bought.add(item);
      left -= item.price;
    }
    return OrderRun(bought: bought, stoppedAt: null, left: left);
  }

  /// Лучший исход для порядка покупок: все обязательные позиции оказались
  /// выше всех необязательных.
  static bool needsFirst(List<CatalogItem> ordered) {
    bool seenWant = false;
    for (final CatalogItem item in ordered) {
      if (item.isNeed && seenWant) return false;
      if (!item.isNeed) seenWant = true;
    }
    return true;
  }

  /// Лучший исход для распределения: в каждом конверте не меньше минимума
  /// из `params['mustCover']`.
  static bool covers(Allocation a, Map<Envelope, int> mustCover) {
    for (final MapEntry<Envelope, int> e in mustCover.entries) {
      if (a.byEnvelope(e.key) < e.value) return false;
    }
    return true;
  }

  /// Верхняя граница счётчика в числовом задании.
  ///
  /// Вдвое больше ответа, но не меньше двадцати: ребёнок должен иметь
  /// возможность и ошибиться, и не крутить кнопку бесконечно. В контенте
  /// этой границы нет намеренно — это свойство органа управления,
  /// а не самого задания.
  static int numericMax(int answer) => answer * 2 < 20 ? 20 : answer * 2;
}
