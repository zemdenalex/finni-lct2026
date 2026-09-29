import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_game_loader.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart' show LedgerKind;
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Мир из настоящих файлов контента — те же байты, что едут в assets.
Future<WorldGame> _world() => openWorldGame(
    read: (String p) => File(p).readAsString(), storage: MemoryStorage());

void main() {
  // Защищает: «Дойти до 3-й стадии» в демо — настоящей игрой за 5 недель
  // (ТЗ 2.6 «рост ≥ 3», 2.5.13.2), и неделя показывает все системы.
  // Уронит: автопилот не закрывает счёт своими деньгами (семья → нет очка),
  // съедает ⚡ до «Спать», не откладывает; или очки появились мимо журнала —
  // тогда восстановление из JSON даст другую стадию.
  test('A8: автопилот на мире из content/ доходит до 3-й стадии к 5-й неделе',
      () async {
    final WorldGame w = await _world();
    final List<AutopilotStep> steps = WorldAutopilot(w).playWeeks(5);

    for (final AutopilotStep s in steps) {
      expect(s.result.ok, isTrue, reason: '$s');
    }
    final List<WorldEntry> j = w.journal;
    final WorldEntry moscow = j.firstWhere(
        (WorldEntry e) =>
            e.kind == WorldLedgerKind.stageChanged &&
            e.args['stage'] == WorldStage.moscow.name,
        orElse: () => fail('3-й стадии нет'));
    expect(moscow.weekNo, lessThanOrEqualTo(5));

    bool has(Enum kind, [String? code]) => j.any((WorldEntry e) =>
        e.kind == kind && (code == null || e.reasonCode == code));
    expect(has(LedgerKind.planConfirmed), isTrue, reason: 'план');
    expect(has(WorldLedgerKind.billPaid), isTrue, reason: 'счета');
    expect(has(WorldLedgerKind.petBought, 'buy.goal'), isTrue,
        reason: 'покупка цели');
    expect(has(WorldLedgerKind.leisure, 'leisure.done'), isTrue,
        reason: 'досуг');
    expect(has(WorldLedgerKind.sleep, 'sleep.bonus'), isTrue, reason: 'сон');
    expect(has(WorldLedgerKind.familyHelp), isFalse,
        reason: 'счета — своими деньгами');
    final List<WorldEntry> own = j
        .where((WorldEntry e) =>
            e.kind == WorldLedgerKind.jobPayout && e.reasonCode == 'job.payout')
        .toList();
    expect(own.length, greaterThanOrEqualTo(2));
    expect(own.every((WorldEntry e) => e.args['good'] == true), isTrue,
        reason: 'смены автопилота — хорошие');

    final WorldGame restored = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(restored.unreadable, 0);
    expect(restored.snapshot.growthPoints, w.snapshot.growthPoints);
    expect(restored.snapshot.stage, WorldStage.moscow);
  });

  // Защищает: баланс не меняется без объяснения и в демо (ТЗ 2.5.4.3) —
  // у каждой записи автопилота есть код причины, у каждого шага — фраза.
  // Уронит: действие мира, которое пишет запись без reasonCode или
  // возвращает пустую причину.
  // Защищает: автопилот демо ест посреди недели (Денис 938: еда даёт ⚡
  // сразу) — каждую неделю все приёмы, домашним меню, и еда идёт в факт
  // НУЖНО. Уронит: убрали ветку «поесть» из автопилота — тогда приёмов 0 и
  // вся еда уходит в счёт недели.
  test('A8: автопилот ест все приёмы недели, еда — в факте НУЖНО', () async {
    final WorldGame w = await _world();
    WorldAutopilot(w).playWeeks(5);
    final int meals = w.snapshot.mealsPerWeek;
    expect(meals, greaterThan(0));
    for (int week = 1; week <= 5; week++) {
      final Iterable<WorldEntry> eaten = w.journal.where((WorldEntry e) =>
          e.weekNo == week && e.kind == WorldLedgerKind.mealEaten);
      expect(eaten, hasLength(meals), reason: 'неделя $week');
      expect(eaten.map((WorldEntry e) => e.args['foodId']).toSet(),
          <Object?>{'food_simple'},
          reason: 'домашнее меню по умолчанию — деньги как в счёте');
    }
    final WeekPlanFact first = w.weekHistory.first;
    expect(first.food, meals * w.catalogItem('food_simple')!.price);
    expect(first.treats, 0);
  });

  test('A8: у каждой записи, созданной автопилотом, есть причина', () async {
    final WorldGame w = await _world();
    final int from = w.journal.length;
    final List<AutopilotStep> steps = WorldAutopilot(w).playWeeks(5);

    final List<WorldEntry> made = w.journal.sublist(from);
    expect(made, isNotEmpty);
    for (final WorldEntry e in made) {
      expect(e.reasonCode.trim(), isNotEmpty, reason: '$e');
    }
    for (final AutopilotStep s in steps) {
      expect(s.result.reason.trim(), isNotEmpty, reason: '$s');
    }
  });

  // Защищает: пошаговый режим (одно действие за нажатие) и «N недель»
  // играют одну и ту же игру, и игра детерминирована. Уронит: шаг делает
  // больше одного действия или выбор зависит от чего-то кроме состояния.
  test('A8: step() по одному действию даёт тот же журнал, что playWeeks',
      () async {
    final WorldGame byWeeks = await _world();
    WorldAutopilot(byWeeks).playWeeks(5);

    final WorldGame bySteps = await _world();
    final WorldAutopilot a = WorldAutopilot(bySteps);
    int closed = 0;
    int guard = 500;
    while (closed < 5 && guard-- > 0) {
      final int before = bySteps.journal.length;
      final AutopilotStep s = a.step();
      expect(bySteps.journal.length, greaterThan(before), reason: '$s');
      if (s.action == AutopilotAction.payBills) closed++;
    }
    a.step(); // playWeeks открывает следующую неделю
    expect(jsonEncode(bySteps.toJson()), jsonEncode(byWeeks.toJson()));
  });
}
