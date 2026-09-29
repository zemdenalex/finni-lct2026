import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart';
import 'package:finlit/domain/ledger/ledger_fold.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/goal.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Мечта исполняется и остаётся в мире Финни. Центральная петля из анализа
/// игровых референсов команды: накопил → вещь появляется → новое желание.
void main() {
  late GameContent content;
  setUpAll(() async => content = await loadRealContent());

  /// Копилка с заданной суммой: переводом через журнал, как в игре.
  Game withSavings(String goalId, int amount) {
    final Game g = Game(content: content, profile: GameProfile.fresh(isDemo: true))
      ..chooseGoal(goalId);
    while (g.snapshot.wallet.savings < amount) {
      g.startPeriod();
      final int free = g.snapshot.wallet.unallocated;
      final int need = amount - g.snapshot.wallet.savings;
      g.confirmPlan(Allocation(needs: 0, wants: 0, savings: free < need ? free : need));
      g.allocate(Envelope.savings, g.snapshot.wallet.unallocated);
      g.closePeriod();
    }
    return g;
  }

  test('пока не набрано, исполнить мечту нельзя и копилка не трогается', () {
    final Game g = withSavings('zoo', 5);
    final int before = g.snapshot.wallet.savings;
    g.fulfillGoal();
    expect(g.snapshot.wallet.savings, before);
    expect(g.fulfilledGoals, isEmpty);
  });

  test('исполнение снимает из копилки ровно цену и оставляет мечту в мире', () {
    final Game g = withSavings('zoo', content.goal('zoo')!.price + 3);
    final int before = g.snapshot.wallet.savings;
    expect(g.goalReached, isTrue);

    g.fulfillGoal();

    expect(g.snapshot.wallet.savings, before - content.goal('zoo')!.price);
    expect(g.fulfilledGoals.single.id, 'zoo');
    expect(g.profile.goalId, isNull, reason: 'можно выбрать следующую мечту');
  });

  test('🔴 исполненная мечта не исчезает, когда выбрана следующая', () {
    final Game g = withSavings('zoo', content.goal('zoo')!.price);
    g.fulfillGoal();
    g.chooseGoal('house');
    expect(g.fulfilledGoals.map((Goal x) => x.id), <String>['zoo']);
  });

  test('исполнение мечты — не отклонение от плана недели', () {
    final Game g = withSavings('zoo', content.goal('zoo')!.price);
    g.startPeriod();
    g.confirmPlan(Allocation(needs: 0, wants: 0, savings: g.snapshot.wallet.unallocated));
    g.fulfillGoal();
    final Allocation fact = LedgerFold.factOfPeriod(g.ledger, g.periodNo);
    expect(fact.savings, greaterThanOrEqualTo(0),
        reason: 'достигнутая цель не должна считаться тратой мимо плана');
  });

  test('запись об исполнении объясняется словами и переживает перезапуск', () {
    final Game g = withSavings('zoo', content.goal('zoo')!.price);
    g.fulfillGoal();
    final LedgerEntry e =
        g.ledger.lastWhere((LedgerEntry e) => e.kind == LedgerKind.goalFulfilled);
    final String text = content.say(e.reasonCode, e.args);
    expect(text.contains('{'), isFalse, reason: text);
    expect(text, contains(content.goal('zoo')!.title));

    final Game restored = Game.fromJson(g.toJson(), content);
    expect(restored.fulfilledGoals.single.id, 'zoo');
  });
}
