import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/history/parent_share.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/bank_world.dart';
import '../../support/world_harness.dart';

/// Перевод монет между частями (ТЗ Насти «Начальное обучение» 18.10,
/// экран 11; флаг `bank.transfer`).
///
/// Защищает обязательную бизнес-логику ТЗ: перевод меняет ровно две части
/// на одну сумму одной записью; больше остатка и в ту же часть — отказ без
/// изменений; повтор операции и перезапуск не списывают второй раз; перевод
/// не доход и не расход — план-факт, итоги недели и текст для родителя его
/// не видят. Уронит: две записи вместо одной, забытая половина, перевод в
/// статистике трат, флаг включён в сборке.
int _total(ResourceSnapshot s) => s.need + s.want + s.goal;

({int need, int want, int goal}) _parts(ResourceSnapshot s) =>
    (need: s.need, want: s.want, goal: s.goal);

WorldGame _restart(WorldGame w) =>
    WorldGame.fromJson(w.toJson(), config: w.config, onboarding: w.onboarding);

void main() {
  group('флаг', () {
    test('сборка: bank.transfer = false в обеих копиях economy.json', () {
      for (final String f in <String>[
        '${WorldContentLoader.base}/economy.json',
        '../../content/economy.json',
      ]) {
        final Map<String, Object?> e =
            jsonDecode(File(f).readAsStringSync()) as Map<String, Object?>;
        expect((e['bank']! as Map<String, Object?>)['transfer'], isFalse,
            reason: f);
      }
      expect(bankConfig().bankTransfer, isFalse);
    });

    test('в коде по умолчанию false: нет ключа — перевода нет', () {
      expect(const WorldConfig().bankTransfer, isFalse);
      final Map<String, Object?> e = jsonDecode(
          File('${WorldContentLoader.base}/economy.json')
              .readAsStringSync()) as Map<String, Object?>
        ..remove('bank');
      String read(String f) =>
          File('${WorldContentLoader.base}/$f').readAsStringSync();
      final WorldContent c = WorldContent.parse(
        economy: jsonEncode(e),
        jobs: read('jobs.json'),
        events: read('events.json'),
        roomItems: read('room_items.json'),
      );
      expect(c.economy.bankTransfer, isFalse);
    });

    test('флаг выключен — отказ feature.off, журнал не пополнен', () {
      final WorldGame w = bankWorld(on: false);
      final int n = w.journal.length;
      final WorldResult r =
          w.transfer(from: MoneyPart.want, to: MoneyPart.goal, amount: 30);
      expect(r.ok, isFalse);
      expect(r.reasonCode, 'feature.off');
      expect(w.journal.length, n);
      expect(w.canDo(WorldAction.transfer)?.code, 'feature.off');
    });
  });

  group('перевод', () {
    // (откуда, куда, сколько) — каждая пара частей в обе стороны.
    const List<(MoneyPart, MoneyPart, int)> table =
        <(MoneyPart, MoneyPart, int)>[
      (MoneyPart.want, MoneyPart.goal, 30),
      (MoneyPart.goal, MoneyPart.want, 50),
      (MoneyPart.need, MoneyPart.goal, 10),
      (MoneyPart.goal, MoneyPart.need, 100),
      (MoneyPart.need, MoneyPart.want, 70),
      (MoneyPart.want, MoneyPart.need, 80),
    ];
    for (final (MoneyPart from, MoneyPart to, int n) in table) {
      test(
          '${from.title} → ${to.title}, $n: две части, сумма та же, '
          'одна запись', () {
        final WorldGame w = bankWorld();
        final ResourceSnapshot b = w.snapshot;
        final int len = w.journal.length;
        final WorldResult r = ok(w.transfer(from: from, to: to, amount: n));
        final ResourceSnapshot a = w.snapshot;
        expect(from.of(a), from.of(b) - n);
        expect(to.of(a), to.of(b) + n);
        final MoneyPart other =
            MoneyPart.values.firstWhere((MoneyPart p) => p != from && p != to);
        expect(other.of(a), other.of(b));
        expect(a.free, b.free);
        expect(a.unallocated, b.unallocated);
        expect(_total(a), _total(b));
        expect(w.journal.length, len + 1, reason: 'одна запись на перевод');
        final WorldEntry e = w.journal.last;
        expect(e.kind, WorldLedgerKind.envelopeTransfer);
        expect(e.need + e.want + e.goal, 0);
        expect(e.args, containsPair('from', from.name));
        expect(e.args, containsPair('to', to.name));
        expect(e.args, containsPair('amount', n));
        expect(r.reason,
            'Готово! Мы перевели $n монет из части «${from.title}» в «${to.title}».');
      });
    }

    test('весь остаток можно; на одну монету больше — отказ ТЗ, ничего', () {
      final WorldGame w = bankWorld();
      final int want = w.snapshot.want;
      final ({int need, int want, int goal}) before = _parts(w.snapshot);
      final int len = w.journal.length;
      final WorldResult r = w.transfer(
          from: MoneyPart.want, to: MoneyPart.goal, amount: want + 1);
      expect(r.ok, isFalse);
      expect(r.reasonCode, 'transfer.too_much');
      expect(r.reason, 'В этой части не хватает монет. Выбери сумму поменьше.');
      expect(_parts(w.snapshot), before);
      expect(w.journal.length, len);
      ok(w.transfer(from: MoneyPart.want, to: MoneyPart.goal, amount: want));
      expect(w.snapshot.want, 0);
    });

    test('та же часть — отказ ТЗ; ноль и минус — отказ; ничего не меняется',
        () {
      final WorldGame w = bankWorld();
      final ({int need, int want, int goal}) before = _parts(w.snapshot);
      final int len = w.journal.length;
      for (final MoneyPart p in MoneyPart.values) {
        final WorldResult r = w.transfer(from: p, to: p, amount: 10);
        expect(r.reasonCode, 'transfer.same');
        expect(r.reason, 'Выбери другую часть для перевода.');
      }
      for (final int n in <int>[0, -10]) {
        expect(
            w
                .transfer(from: MoneyPart.want, to: MoneyPart.goal, amount: n)
                .reasonCode,
            'transfer.zero');
      }
      expect(_parts(w.snapshot), before);
      expect(w.journal.length, len);
    });

    test('двойное подтверждение (тот же opId) — второй раз не списывает', () {
      final WorldGame w = bankWorld();
      final ResourceSnapshot b = w.snapshot;
      ok(w.transfer(
          from: MoneyPart.want, to: MoneyPart.goal, amount: 30, opId: 'op-1'));
      final WorldResult again = w.transfer(
          from: MoneyPart.want, to: MoneyPart.goal, amount: 30, opId: 'op-1');
      expect(again.ok, isFalse);
      expect(again.reasonCode, 'transfer.repeat');
      expect(w.snapshot.want, b.want - 30);
      expect(w.snapshot.goal, b.goal + 30);
      // Новый ключ — новый законный перевод.
      ok(w.transfer(
          from: MoneyPart.want, to: MoneyPart.goal, amount: 30, opId: 'op-2'));
      expect(w.snapshot.want, b.want - 60);
    });

    test('перезапуск: те же остатки, ключ операции помнится', () {
      final WorldGame w = bankWorld();
      ok(w.transfer(
          from: MoneyPart.want, to: MoneyPart.goal, amount: 30, opId: 'op-1'));
      ok(w.transfer(from: MoneyPart.need, to: MoneyPart.want, amount: 20));
      final WorldGame back = _restart(w);
      expect(back.unreadable, 0);
      expect(_parts(back.snapshot), _parts(w.snapshot));
      expect(back.snapshot.free, w.snapshot.free);
      expect(back.weekHistory.last.transfers, w.weekHistory.last.transfers);
      final WorldResult again = back.transfer(
          from: MoneyPart.want, to: MoneyPart.goal, amount: 30, opId: 'op-1');
      expect(again.reasonCode, 'transfer.repeat');
      expect(_parts(back.snapshot), _parts(w.snapshot));
    });

    test('только пока неделя идёт: до плана и в итогах — отказ фазы', () {
      final WorldGame w = WorldGame(
          config: bankConfig(on: true),
          onboarding:
              const OnboardingProgress(step: OnboardingProgress.stepDone));
      ok(w.startWeek());
      expect(
          w
              .transfer(from: MoneyPart.goal, to: MoneyPart.want, amount: 10)
              .reasonCode,
          'phase.transfer');
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      expect(w.canDo(WorldAction.transfer), isNull);
      sleepWeek(w);
      expect(w.phase, WeekPhase.review);
      expect(
          w
              .transfer(from: MoneyPart.goal, to: MoneyPart.need, amount: 10)
              .reasonCode,
          'phase.transfer');
    });
  });

  group('перевод — не доход и не расход', () {
    test('план-факт, итоги недели и текст родителю не меняются', () {
      final WorldGame w = bankWorld();
      final WeekPlanFact before = w.weekHistory.last;
      final String parentBefore = parentShareText(before, petName: 'Финни');
      ok(w.transfer(from: MoneyPart.want, to: MoneyPart.goal, amount: 30));
      ok(w.transfer(from: MoneyPart.need, to: MoneyPart.want, amount: 40));
      ok(w.transfer(from: MoneyPart.goal, to: MoneyPart.need, amount: 30));
      final WeekPlanFact after = w.weekHistory.last;
      for (final (String name, EnvelopePlanFact b, EnvelopePlanFact a)
          in <(String, EnvelopePlanFact, EnvelopePlanFact)>[
        ('Нужно', before.need, after.need),
        ('Хочу', before.want, after.want),
        ('Копилка', before.goal, after.goal),
      ]) {
        expect(a.planned, b.planned, reason: '$name: план');
        expect(a.actual, b.actual, reason: '$name: факт');
      }
      expect(after.purchases, isEmpty);
      expect(after.events, before.events);
      expect(after.food, before.food);
      // Копилка: +30 и −30 — остаток тот же, иначе строка «В копилке» для
      // родителя честно сдвинулась бы (это остаток, а не «отложили»).
      expect(after.savedAtEnd, before.savedAtEnd);
      expect(after.transfers, <String>[
        'Перевод: Хочу → Копилка, 30 монет',
        'Перевод: Нужно → Хочу, 40 монет',
        'Перевод: Копилка → Нужно, 30 монет',
      ]);
      expect(parentShareText(after, petName: 'Финни'), parentBefore);
    });

    test('неделя с переводом закрывается так же, как без него', () {
      // Двойники на одних числах. В «Нужном» ровно на счета и без перевода,
      // поэтому счета, траты и отложенное недели обязаны совпасть; 30 монет
      // просто лежат в копилке, а не в «Хочу».
      final WorldGame a = bankWorld();
      final WorldGame b = bankWorld();
      final int depBefore = a.state.depositsThisWeek;
      ok(a.transfer(from: MoneyPart.want, to: MoneyPart.need, amount: 50));
      ok(a.transfer(from: MoneyPart.want, to: MoneyPart.goal, amount: 30));
      expect(a.state.depositsThisWeek, depBefore,
          reason: 'В5: перевод в копилку не «отложили»');
      for (final WorldGame w in <WorldGame>[a, b]) {
        sleepWeek(w);
        ok(w.payBills());
      }
      final WeekPlanFact fa = a.weekHistory.first;
      final WeekPlanFact fb = b.weekHistory.first;
      expect(fa.need.actual, fb.need.actual, reason: 'счета недели');
      expect(fa.want.actual, fb.want.actual, reason: 'траты «Хочу»');
      expect(fa.goal.actual, fb.goal.actual, reason: 'отложено');
      expect(fa.savedAtEnd, fb.savedAtEnd + 30);
      expect(a.snapshot.growthPoints, b.snapshot.growthPoints);
      ResourceSnapshot s(WorldGame w) => w.snapshot;
      int all(ResourceSnapshot x) => x.need + x.want + x.free + x.goal;
      expect(all(s(a)), all(s(b)), reason: 'монет всего — столько же');
    });
  });
}
