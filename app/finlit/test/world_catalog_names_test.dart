import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/world_game_loader.dart';

/// C10 (17.10): в магазине две карточки «Глобус» стояли с разными ценами
/// (450 и 80) — ребёнок видел одно название за две цены. Защищает: у позиций
/// каталога с одним названием одна цена (одинаковые названия допустимы
/// только у цветов одного вида — они стоят одинаково). Уронит: новый вид
/// вещи назвали так же, как другой, но с другой ценой. Почему не ловят
/// прежние: `world_catalog_from_content_test` сверяет цену каждой позиции с
/// файлом, а не названия между собой.
void main() {
  test('одно название — одна цена', () async {
    final WorldGame w = await openWorldGame(
        read: (String p) => File(p).readAsString(), storage: MemoryStorage());
    final Map<String, Set<int>> prices = <String, Set<int>>{};
    for (final WorldCatalogItem i in w.catalog) {
      (prices[i.title] ??= <int>{}).add(i.price);
    }
    final Map<String, Set<int>> clash = <String, Set<int>>{
      for (final MapEntry<String, Set<int>> e in prices.entries)
        if (e.value.length > 1) e.key: e.value,
    };
    expect(clash, isEmpty, reason: '$clash');
  });
}
