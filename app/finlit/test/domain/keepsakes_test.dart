import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Комната Финни — вещи, которые остаются после покупки. Выводится из
/// журнала, как баланс: в комнате не может оказаться вещь, за которую
/// не платили.
void main() {
  late GameContent content;
  setUpAll(() async => content = await loadRealContent());

  Game ready() {
    final Game g = Game(content: content, profile: GameProfile.fresh(isDemo: true));
    g.startPeriod();
    g.confirmPlan(Allocation(needs: 3, wants: g.snapshot.wallet.unallocated - 3, savings: 0));
    return g;
  }

  test('купленная игрушка остаётся в комнате, съеденная каша — нет', () {
    final Game g = ready();
    g.buy(content.item('ball'));
    g.buy(content.item('porridge'));
    final List<String> ids =
        g.keepsakes.map(((CatalogItem, int) k) => k.$1.id).toList();
    expect(ids, <String>['ball']);
  });

  test('повторная покупка увеличивает число, а не дублирует вещь', () {
    final Game g = ready();
    g.buy(content.item('stickers'));
    g.buy(content.item('stickers'));
    expect(g.keepsakes.single.$2, 2);
  });

  test('отказ от покупки ничего в комнату не кладёт', () {
    final Game g = ready();
    g.declinePurchase(content.item('hat'));
    expect(g.keepsakes, isEmpty);
  });

  test('комната переживает сохранение и загрузку', () {
    final Game g = ready()..buy(content.item('book'));
    final Game restored = Game.fromJson(g.toJson(), content);
    expect(restored.keepsakes.single.$1.id, 'book');
  });

  test('в каталоге есть вещи, которые остаются, и вещи, которые тратятся', () {
    expect(content.catalog.where((CatalogItem i) => i.keeps), isNotEmpty);
    expect(content.catalog.where((CatalogItem i) => i.isNeed && i.keeps), isEmpty,
        reason: 'еда и уборка не могут «оставаться в комнате»');
  });
}
