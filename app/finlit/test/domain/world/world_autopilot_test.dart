import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import '../../support/world_game_loader.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart' show LedgerKind;
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import '../../support/world_harness.dart' show weekMode;
import 'package:flutter_test/flutter_test.dart';

/// Мир из настоящих файлов контента — те же байты, что едут в assets.
/// Режим «неделя» (флаг `days_per_week: 1`) — как сдано.
Future<WorldGame> _world() => openWorldGame(
    read: (String p) async {
      final String s = await File(p).readAsString();
      return p.endsWith('economy.json') ? weekMode(s) : s;
    },
    storage: MemoryStorage());

/// Тот же мир, но с днями по энергии — как в сборке по умолчанию.
Future<WorldGame> _dayWorld() => openWorldGame(
    read: (String p) => File(p).readAsString(), storage: MemoryStorage());

void main() {
  // Защищает: демо-автопилот работает и в модели дней — каждый шаг принят
  // миром, недели идут, в неделе больше одного утра. Уронит: автопилот ждёт,
  // что «Спать» кончает неделю, и зацикливается или стоит на месте.
  // Защищает: кнопка демо «Дойти до 3-й стадии» (S16) работает и в модели
  // дней — Москва без отказов, не позже 14-й недели (цены переездов 5000 /
  // 12000 с 18.10, сначала питомец: замер — 12-я; при 1200 / 2000 была 5-я).
  // Уронит:
  // автопилот тратит ⚡ дня на дешёвую работу или ест всю неделю за утро.
  test('демо «Дойти до 3-й стадии» в модели дней: Москва к 14-й неделе',
      () async {
    final WorldGame w = await _dayWorld();
    final List<AutopilotStep> steps =
        WorldAutopilot(w).playToStage(WorldStage.moscow);
    expect(steps.every((AutopilotStep s) => s.result.ok), isTrue);
    expect(w.snapshot.stage, WorldStage.moscow);
    final WorldEntry moscow = w.journal.firstWhere((WorldEntry e) =>
        e.kind == WorldLedgerKind.stageChanged &&
        e.args['stage'] == WorldStage.moscow.name);
    expect(moscow.weekNo, lessThanOrEqualTo(14));
  });

  // Режим «неделя» (не сборка): кнопка демо всё равно доходит до Москвы в
  // пределах [WorldAutopilot.playToStage] — замер 21-я неделя.
  test('демо «Дойти до 3-й стадии» в режиме «неделя»: Москва в пределе',
      () async {
    final WorldGame w = await _world();
    WorldAutopilot(w).playToStage(WorldStage.moscow);
    expect(w.snapshot.stage, WorldStage.moscow);
  });

  test('автопилот в модели дней: 3 недели без отказов, дни внутри недели',
      () async {
    final WorldGame w = await _dayWorld();
    expect(w.config.daysPerWeek, greaterThan(1));
    final List<AutopilotStep> steps = WorldAutopilot(w).playWeeks(3);
    for (final AutopilotStep s in steps) {
      expect(s.result.ok, isTrue, reason: '$s');
    }
    expect(w.snapshot.weekNo, greaterThanOrEqualTo(3));
    expect(
        w.journal.where((WorldEntry e) => e.kind == WorldLedgerKind.dayEnded),
        isNotEmpty,
        reason: 'неделя прожита по дням');
  });

  // A8 — в обоих режимах: недели (флаг) и дни по энергии (сборка по умолчанию).
  for (final (String mode, Future<WorldGame> Function() make)
      in <(String, Future<WorldGame> Function())>[
    ('неделя', _world),
    ('дни', _dayWorld),
  ]) {
    // Защищает: 5 недель автопилота показывают все системы (ТЗ 2.5.13.2), в
    // режиме дней — с питомцем (1-я неделя) и переездом в город (замер: 5-я
    // неделя при цене 5000).
    // Москва — отдельными тестами «Дойти до 3-й стадии» выше (цены 18.10).
    // Уронит: автопилот не закрывает счёт своими деньгами (семья → нет очка),
    // съедает ⚡ до «Спать», не откладывает; или очки появились мимо журнала —
    // тогда восстановление из JSON даст другую стадию.
    test('A8: автопилот на мире из content/ — все системы за 5 недель · $mode',
        () async {
      final WorldGame w = await make();
      final List<AutopilotStep> steps = WorldAutopilot(w).playWeeks(5);

      for (final AutopilotStep s in steps) {
        expect(s.result.ok, isTrue, reason: '$s');
      }
      final List<WorldEntry> j = w.journal;
      if (mode == 'дни') {
        expect(
            w.snapshot.stage.index, greaterThanOrEqualTo(WorldStage.town.index),
            reason: 'переезд в город за 5 недель');
      }

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
              e.kind == WorldLedgerKind.jobPayout &&
              e.reasonCode == 'job.payout')
          .toList();
      expect(own.length, greaterThanOrEqualTo(2));
      expect(own.every((WorldEntry e) => e.args['good'] == true), isTrue,
          reason: 'смены автопилота — хорошие');

      final WorldGame restored = WorldGame.fromJson(
          jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
          config: w.config);
      expect(restored.unreadable, 0);
      expect(restored.snapshot.growthPoints, w.snapshot.growthPoints);
      expect(restored.snapshot.stage, w.snapshot.stage);
    });

    // Защищает: баланс не меняется без объяснения и в демо (ТЗ 2.5.4.3) —
    // у каждой записи автопилота есть код причины, у каждого шага — фраза.
    // Уронит: действие мира, которое пишет запись без reasonCode или
    // возвращает пустую причину.
    // Защищает: автопилот демо ест посреди недели (Денис 938: еда даёт ⚡
    // сразу) — каждую неделю все приёмы, домашним меню, и еда идёт в факт
    // НУЖНО. Уронит: убрали ветку «поесть» из автопилота — тогда приёмов 0 и
    // вся еда уходит в счёт недели.
    test('A8: автопилот ест все приёмы недели, еда — в факте НУЖНО · $mode',
        () async {
      final WorldGame w = await make();
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

    test('A8: у каждой записи, созданной автопилотом, есть причина · $mode',
        () async {
      final WorldGame w = await make();
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
    test(
        'A8: step() по одному действию даёт тот же журнал, что playWeeks · $mode',
        () async {
      final WorldGame byWeeks = await make();
      WorldAutopilot(byWeeks).playWeeks(5);

      final WorldGame bySteps = await make();
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
}
