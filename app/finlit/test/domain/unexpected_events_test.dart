import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/economy/economy_config.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Непредвиденные расходы приходят по кругу, каждый раз свои.
///
/// 🔴 До 23.09 событие было одно — плед на третьей неделе, — и после него
/// мир ничего не приносил.
void main() {
  late GameContent content;
  setUpAll(() async => content = await loadRealContent());

  test('первое на третьей неделе, дальше каждые три — и все разные', () {
    final EconomyConfig e = content.economy;
    expect(e.unexpectedEvents.length, greaterThanOrEqualTo(3));
    expect(e.unexpectedEvents.map((UnexpectedEvent x) => x.id).toSet().length,
        e.unexpectedEvents.length);

    final List<String?> byWeek = <String?>[
      for (int w = 1; w <= 15; w++) e.unexpectedFor(w)?.id,
    ];
    expect(byWeek.whereType<String>().length, 5);
    expect(byWeek[2], e.unexpectedEvents[0].id, reason: 'неделя 3');
    expect(byWeek[3], isNull, reason: 'неделя 4 — без события');
    expect(byWeek[5], e.unexpectedEvents[1].id, reason: 'неделя 6');
    expect(byWeek[8], e.unexpectedEvents[2].id, reason: 'неделя 9');
  });

  test('у каждого события есть цена и выход «обойтись»', () {
    for (final UnexpectedEvent x in content.economy.unexpectedEvents) {
      expect(x.cost, greaterThan(0), reason: x.id);
      expect(x.cost, lessThanOrEqualTo(content.economy.pocketMoney ~/ 2),
          reason: '${x.id}: событие не должно съедать полнедели');
      for (final String t in <String>[
        x.title, x.chip, x.need, x.deferLabel, x.paidTitle, x.paid, x.deferred
      ]) {
        expect(t.trim(), isNotEmpty, reason: x.id);
        expect(t.toLowerCase(), isNot(contains('болеет')), reason: x.id);
      }
    }
  });

  test('заплатить дважды или без события нельзя', () {
    final Game g =
        Game(content: content, profile: GameProfile.fresh(isDemo: false));
    g.startPeriod();
    final int before = g.ledger.length;
    g.payUnexpected(Envelope.savings);
    g.deferUnexpected();
    expect(g.ledger.length, before, reason: 'неделя 1 — события нет');

    while (g.periodNo < content.economy.unexpectedPeriod) {
      g.confirmPlan(Allocation(needs: g.snapshot.wallet.unallocated));
      g.closePeriod();
      g.startPeriod();
    }
    g.confirmPlan(Allocation(savings: g.snapshot.wallet.unallocated));
    expect(g.unexpectedPending, isTrue);
    g.payUnexpected(Envelope.savings);
    final int afterPay = g.ledger.length;
    g.payUnexpected(Envelope.savings);
    g.deferUnexpected();
    expect(g.ledger.length, afterPay, reason: 'второе решение не пишется');
  });
}
