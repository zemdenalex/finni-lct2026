import '../../domain/content.dart';
import '../../domain/models/catalog_item.dart';
import '../../domain/models/envelope.dart';

/// Сколько стоит самый дешёвый набор «поесть и попить» по каталогу.
///
/// Число не пишется в коде: §3.2 требует держать учебный контент отдельно от
/// интерфейса, а §2.5.14 — чтобы новая позиция каталога не заставляла править
/// логику. Поэтому цена считается по самому каталогу: самая дешёвая позиция
/// «Нужного», которая кормит, плюс самая дешёвая, которая даёт чистоту.
///
/// Нужно ровно для одной подсказки на экране плана. Подсказка мягкая и ничего
/// не запрещает: §2.2 требует безопасной ошибки, а не запрета положить
/// в «Нужное» меньше, чем стоит еда.
int cheapestNeedsBasket(GameContent content) {
  final int? food =
      _cheapest(content, (CatalogItem i) => i.effect.fullness > 0);
  final int? water =
      _cheapest(content, (CatalogItem i) => i.effect.cleanliness > 0);
  if (food == null || water == null) return 0;
  return food + water;
}

int? _cheapest(GameContent content, bool Function(CatalogItem) suits) {
  int? best;
  for (final CatalogItem i in content.catalog) {
    if (i.envelope != Envelope.needs || !suits(i)) continue;
    if (best == null || i.price < best) best = i.price;
  }
  return best;
}
