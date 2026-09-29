import 'package:finlit/domain/world/contract.dart';
import 'package:flutter_test/flutter_test.dart';

/// Пример Насти (v13, слайд 17) «неделя 1: ЦЕЛЬ, рыбка и парк» — на границе
/// [World], чтобы тот же сценарий прогнать и на фейке, и на домене (A2–A3).
///
/// Ловит: «на жизнь» не добавили к цене действия (конец недели 6 ⚡ вместо 2),
/// покупка списала ⚡, неделя закрылась по ⚡ на границе «осталось 2 — самое
/// дешёвое стоит 2», сон не перенёс +1 ⚡ на неделю 2, три невыбранных
/// приёма пищи не съедены дома (+3 × 0,5 ⚡ каши на неделю 2).
///
/// Порядок действий важен: рыбка покупается после парка — +10 😊 от цели
/// удешевляет следующее действие по ⚡ (парк стоил бы 1,95).
///
/// Смены — **обычные** (оценка ниже порога «хорошо», P1 пересмотр 27.09):
/// пример Насти написан до деления на хорошие и обычные смены. Хорошая смена
/// стоит сверх карточки +0,5 ⚡ и −1 😊 — это проверяет тест оплаты в
/// `world_game_test.dart`.
void weekOneEnergyScenario(World Function() newWorld) {
  test(
      'неделя 1: 10 − 2×(2+1) за консультанта − (1+1) за парк = 2 ⚡, '
      'неделя 2 начинается с 12,5', () {
    final World w = newWorld();
    expect(w.phase, WeekPhase.onboarding);

    expect(w.startWeek().ok, isTrue);
    expect(w.phase, WeekPhase.planning);
    expect(w.snapshot.energy, closeTo(10, 1e-9));

    final WorldResult planned = w.plan(needs: 400, wants: 0, goal: 0);
    expect(planned.ok, isTrue, reason: planned.reason);
    expect(w.phase, WeekPhase.living);

    for (int i = 0; i < 2; i++) {
      final WorldResult shift = w.completeJob('consultant', score: 0.5);
      expect(shift.ok, isTrue, reason: shift.reason);
    }
    expect(w.snapshot.energy, closeTo(4, 1e-9));

    final WorldResult park = w.leisure('park');
    expect(park.ok, isTrue, reason: park.reason);
    expect(w.snapshot.energy, closeTo(2, 1e-9));
    expect(w.phase, WeekPhase.living,
        reason: '2 ⚡ хватает на парк или садовника — неделя не кончилась');

    final int toGoal = 400 - w.snapshot.goal;
    expect(w.depositToGoal(toGoal).ok, isTrue);
    final WorldResult fish = w.buy('pet_fish');
    expect(fish.ok, isTrue, reason: fish.reason);
    expect(w.snapshot.energy, closeTo(2, 1e-9), reason: 'покупка не тратит ⚡');

    expect(w.sleep().ok, isTrue);
    expect(w.phase, WeekPhase.review);
    expect(w.snapshot.endedBy, WeekEnd.sleep);

    final WorldResult bills = w.payBills();
    expect(bills.ok, isTrue, reason: bills.reason);
    expect(w.snapshot.available, greaterThanOrEqualTo(0));

    expect(w.startWeek().ok, isTrue);
    expect(w.snapshot.weekNo, 2);
    expect(w.snapshot.energy, closeTo(12.5, 1e-9),
        reason: 'ранний сон с ⚡ ≥ 1 переносит +1 на следующую неделю, три '
            'каши дома в итогах — ещё 3 × 0,5');
  });
}
