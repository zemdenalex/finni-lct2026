import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/economy/economy_config.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Решение команды 19.09 («вариант 4»): база недели — бюджет от родителей,
/// задания — ограниченная подработка, и с каждой стадией доля родителей
/// падает, а доля заработанного растёт.
void main() {
  late GameContent content;
  setUpAll(() async => content = await loadRealContent());

  test('продвинуться никогда не невыгодно: максимум недели не убывает', () {
    int previous = 0;
    for (final PetStage st in PetStage.values) {
      final TrustLevel t = content.economy.trustFor(st);
      expect(t.weeklyMax, greaterThanOrEqualTo(previous),
          reason: 'на стадии «${st.title}» максимум недели меньше, чем раньше');
      previous = t.weeklyMax;
    }
  });

  test('доля самостоятельности растёт со стадией', () {
    double previous = -1;
    for (final PetStage st in PetStage.values) {
      final TrustLevel t = content.economy.trustFor(st);
      final double share = t.earnCap / t.weeklyMax;
      expect(share, greaterThan(previous),
          reason: 'на стадии «${st.title}» ребёнок зарабатывает не большую долю');
      previous = share;
    }
  });

  test('🔴 родители всегда дают достаточно, чтобы Финни был сыт и чист', () {
    // §3.5: забота о питомце не должна зависеть от того, выполнил ли ребёнок
    // задания. Считаем самый дешёвый набор «нужного», который за неделю
    // покрывает затухание сытости и чистоты.
    final int fullnessLoss = -content.economy.decay.fullness;
    final int cleanLoss = -content.economy.decay.cleanliness;
    int cheapest(Meter m, int need) {
      final List<CatalogItem> needs = content.catalog
          .where((CatalogItem i) => i.isNeed && i.effect.byMeter(m) > 0)
          .toList();
      int best = 1 << 30;
      for (final CatalogItem i in needs) {
        final int times = (need / i.effect.byMeter(m)).ceil();
        final int cost = times * i.price;
        if (cost < best) best = cost;
      }
      return best;
    }

    final int weeklyNeeds =
        cheapest(Meter.fullness, fullnessLoss) + cheapest(Meter.cleanliness, cleanLoss);
    for (final PetStage st in PetStage.values) {
      expect(content.economy.trustFor(st).fromParents,
          greaterThanOrEqualTo(weeklyNeeds),
          reason: 'на стадии «${st.title}» без заданий Финни не прокормить');
    }
  });

  test('первая стадия совпадает с карманными из контента', () {
    expect(content.economy.trustFor(PetStage.novice).fromParents,
        content.economy.pocketMoney);
  });

  Game fresh() =>
      Game(content: content, profile: GameProfile.fresh(isDemo: true))
        ..startPeriod();

  test('бесконечно фармить нельзя: за неделю не заработать больше лимита', () {
    final Game g = fresh();
    final int base = g.snapshot.wallet.unallocated;
    for (int round = 0; round < 5; round++) {
      for (final GameTask t in content.tasks) {
        g.completeTask(t, best: true);
      }
    }
    expect(g.snapshot.wallet.unallocated, base + g.earnCap);
    expect(g.earnCapReached, isTrue);
  });

  test('задание сверх лимита засчитывается, хотя монеток не приносит', () {
    // Учёба не должна зависеть от того, осталась ли подработка.
    final Game g = fresh();
    for (final GameTask t in content.tasks) {
      g.completeTask(t, best: true);
    }
    final int before = g.profile.completedTaskIds.length;
    final int coins = g.snapshot.wallet.unallocated;
    final ActionResult r = g.completeTask(content.tasks.first, best: true);
    expect(g.profile.completedTaskIds.length, before + 1);
    expect(g.snapshot.wallet.unallocated, coins);
    expect(r.text, contains('засчитано'));
    expect(r.text.contains('{'), isFalse);
  });

  test('взрослый не дарит монетки, а расширяет подработку', () {
    final Game g = fresh();
    final int coins = g.snapshot.wallet.unallocated;
    final int cap = g.earnCap;
    g.parentUnlockTask();
    expect(g.snapshot.wallet.unallocated, coins, reason: '§2.1: ресурсы ограничены');
    expect(g.earnCap, cap + content.economy.parentBonusCap);
  });

  test('лимит — на неделю: со следующей недели подработка снова открыта', () {
    final Game g = fresh();
    for (final GameTask t in content.tasks) {
      g.completeTask(t, best: true);
    }
    expect(g.earnCapReached, isTrue);
    g.closePeriod();
    g.startPeriod();
    expect(g.earnedThisPeriod, 0);
    expect(g.earnCapReached, isFalse);
  });

  test('каждая запись о подработке объясняется без сырых шаблонов', () {
    final Game g = fresh();
    for (final GameTask t in content.tasks) {
      g.completeTask(t, best: true);
    }
    for (final LedgerEntry e in g.ledger
        .where((LedgerEntry e) => e.kind == LedgerKind.taskReward)) {
      final String text = content.say(e.reasonCode, e.args);
      expect(text.contains('{'), isFalse, reason: text);
    }
  });
}
