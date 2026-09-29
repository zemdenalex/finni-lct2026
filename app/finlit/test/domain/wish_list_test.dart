import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Список ожидания — единственная механика продукта, которой нет в ТЗ.
/// Она держится на трёх обещаниях, и каждое здесь проверяется:
/// купить сейчас можно всегда, пауза длится ровно неделю, а передумать
/// ничего не стоит.
void main() {
  late GameContent content;

  CatalogItem expensiveWant(GameContent c) => c.catalog
      .where((CatalogItem i) => !i.isNeed)
      .reduce((CatalogItem a, CatalogItem b) => a.price > b.price ? a : b);

  CatalogItem cheapWant(GameContent c) => c.catalog
      .where((CatalogItem i) => !i.isNeed)
      .reduce((CatalogItem a, CatalogItem b) => a.price < b.price ? a : b);

  Game fresh() {
    final Game g = Game(
      content: content,
      profile: GameProfile.fresh(isDemo: true),
    );
    g.startPeriod();
    final int income = g.snapshot.wallet.unallocated;
    g.confirmPlan(Allocation(needs: 0, wants: income, savings: 0));
    return g;
  }

  setUpAll(() async {
    content = await loadRealContent();
  });

  test('ожидание предлагается только на дорогом и только на необязательном', () {
    final Game g = fresh();
    expect(g.canWait(expensiveWant(content)), isTrue);
    expect(g.canWait(cheapWant(content)), isFalse,
        reason: 'на самой дешёвой вещи пауза унизительна, и правило бросают');
    expect(g.canWait(content.catalog.firstWhere((CatalogItem i) => i.isNeed)),
        isFalse,
        reason: 'еду нельзя откладывать «до следующей недели»');
  });

  test('🔴 подождать — предложение, а не запрет: купить сейчас можно всегда',
      () {
    final Game g = fresh();
    final CatalogItem item = expensiveWant(content);
    expect(g.canWait(item), isTrue);
    expect(g.canBuy(item).allowed, isTrue,
        reason: 'наличие паузы не должно закрывать обычную покупку');
  });

  test('пауза длится ровно неделю', () {
    final Game g = fresh();
    final CatalogItem item = expensiveWant(content);
    g.addToWishList(item);

    expect(g.ripeWishes, isEmpty, reason: 'на этой же неделе спрашивать рано');
    expect(g.freshWishes.single.id, item.id);
    expect(g.canWait(item), isFalse, reason: 'дважды отложить нельзя');

    g.closePeriod();
    g.startPeriod();

    expect(g.ripeWishes.single.id, item.id);
    expect(g.freshWishes, isEmpty);
  });

  test('отложить и передумать не стоит ни монетки', () {
    final Game g = fresh();
    final CatalogItem item = expensiveWant(content);
    final int before = g.snapshot.wallet.envelopes.byEnvelope(Envelope.wants);

    g.addToWishList(item);
    expect(g.snapshot.wallet.envelopes.byEnvelope(Envelope.wants), before);

    g.closePeriod();
    g.startPeriod();
    g.dropWish(item);
    expect(g.snapshot.wallet.envelopes.byEnvelope(Envelope.wants), before,
        reason: 'передумать — бесплатно, иначе это наказание за честность');
  });

  test('счётчик считает и «дождался», и «передумал»', () {
    final Game g = fresh();
    final List<CatalogItem> wants = content.catalog
        .where((CatalogItem i) =>
            !i.isNeed && i.price >= content.economy.wishThreshold)
        .toList();
    expect(wants.length, greaterThanOrEqualTo(2),
        reason: 'в каталоге должно быть чем воспользоваться');

    g.addToWishList(wants[0]);
    g.addToWishList(wants[1]);
    g.closePeriod();
    g.startPeriod();

    g.keepWish(wants[0]);
    g.dropWish(wants[1]);

    expect(g.wishTally, (1, 1));
    expect(g.ripeWishes, isEmpty);
  });

  test('подтверждённое желание можно купить как обычно', () {
    final Game g = fresh();
    final CatalogItem item = expensiveWant(content);
    g.addToWishList(item);
    g.closePeriod();
    g.startPeriod();
    final int income = g.snapshot.wallet.unallocated;
    g.confirmPlan(Allocation(needs: 0, wants: income, savings: 0));

    g.keepWish(item);
    expect(g.canBuy(item).allowed, isTrue);
    g.buy(item);
    expect(
        g.ledger.where((LedgerEntry e) => e.kind == LedgerKind.purchase).length,
        1);
  });

  test('каждое решение попадает в журнал с причиной', () {
    final Game g = fresh();
    final CatalogItem item = expensiveWant(content);
    g.addToWishList(item);
    g.closePeriod();
    g.startPeriod();
    g.dropWish(item);

    final List<LedgerKind> kinds =
        g.ledger.map((LedgerEntry e) => e.kind).toList();
    expect(kinds, contains(LedgerKind.wishAdded));
    expect(kinds, contains(LedgerKind.wishDropped));

    for (final LedgerEntry e in g.ledger.where((LedgerEntry e) =>
        e.kind == LedgerKind.wishAdded || e.kind == LedgerKind.wishDropped)) {
      final String text = content.say(e.reasonCode, e.args);
      expect(text.contains('{'), isFalse);
      expect(text, contains(item.title));
    }
  });

  test('список ожидания переживает сохранение и загрузку', () {
    final Game g = fresh();
    final CatalogItem item = expensiveWant(content);
    g.addToWishList(item);
    g.closePeriod();
    g.startPeriod();
    g.keepWish(item);
    g.addToWishList(item);

    final Game restored = Game.fromJson(g.toJson(), content);
    expect(restored.freshWishes.single.id, item.id);
    expect(restored.wishTally, (1, 0));
  });
}
