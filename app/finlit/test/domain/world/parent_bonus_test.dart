import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// ТЗ 2.5.12.3 «Бонус взрослого» — [World.parentExtraShift] (К4, решение
/// Дениса 28.09: «взрослый открывает дополнительное задание», не монеты).
///
/// Всё, что меняет бонус: лимит смен этой недели (+1 к общему и +1 к лимиту
/// каждой работы). Деньги, ⚡, 😊, фаза и цены работ — те же, что до него.
String _resources(World w) {
  final ResourceSnapshot s = w.snapshot;
  return <Object?>[
    w.phase,
    s.weekNo,
    s.need,
    s.want,
    s.goal,
    s.free,
    s.unallocated,
    s.energy,
    s.happiness,
    s.growthPoints,
    s.experience,
    s.shiftsThisWeek,
    (s.owned.toList()..sort()).join(','),
    for (final JobOffer o in w.jobBoard) '${o.pay}/${o.energyCost}',
  ].join(' | ');
}

World _week1(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 250, wants: 0, goal: 0));
  return w;
}

int? _journalLength(World w) => w is WorldGame ? w.journal.length : null;

/// Две открытые работы с разными id (у уровней одной работы лимит общий).
(JobOffer, JobOffer) _twoJobs(World w) {
  final List<JobOffer> open =
      w.jobBoard.where((JobOffer o) => !o.blocked).toList();
  final JobOffer a = open.first;
  final JobOffer b = open.firstWhere((JobOffer o) => o.jobId != a.jobId,
      orElse: () => fail('нужны две открытые работы'));
  return (a, b);
}

int _left(World w, JobOffer o) =>
    w.offer(o.jobId, variant: o.variant)!.shiftsLeft;

void main() {
  // Защищает: кнопка взрослого пишет одну запись `parentBonus` с причиной и
  // даёт ровно +1 смену на эту неделю — монет, ⚡ и 😊 не даёт; второй раз
  // за неделю — отказ без записи. Уронит: бонус монетами (как в старом
  // плейсхолдере), запись без причины, повтор, который пишет вторую запись.
  forEachWorld((WorldKind kind) {
    test('бонус: запись с причиной, лимит +1, ресурсы те же, раз в неделю', () {
      final World w = _week1(kind);
      final int base = w.shiftsLimitThisWeek;
      expect(w.parentBonusThisWeek, isFalse);
      expect(w.canDo(WorldAction.parentBonus), isNull);
      final String before = _resources(w);
      final int? length = _journalLength(w);

      final WorldResult r = ok(w.parentExtraShift());
      expect(r.reasonCode, parentBonusCode);
      expect(r.reason, contains(parentBonusReason));
      expect((r.coins, r.goal, r.energy, r.happiness), (0, 0, 0.0, 0));
      expect(w.shiftsLimitThisWeek, base + 1);
      expect(w.parentBonusThisWeek, isTrue);
      expect(_resources(w), before);
      if (w is WorldGame) {
        expect(w.journal.length, length! + 1);
        final WorldEntry e = w.journal.last;
        expect(e.kind, WorldLedgerKind.parentBonus);
        expect(WorldEntry.kindToString(e.kind), 'world.parentBonus');
        expect(e.args['reason'], parentBonusReason);
        expect(<num>[
          e.need,
          e.want,
          e.goal,
          e.free,
          e.unallocated,
          e.energy,
          e.happiness
        ], everyElement(0));
      }

      final WorldResult again = w.parentExtraShift();
      expect(again.ok, isFalse);
      expect(again.reasonCode, 'parent.bonus.done');
      expect(w.canDo(WorldAction.parentBonus)?.code, 'parent.bonus.done');
      expect(w.shiftsLimitThisWeek, base + 1);
      expect(_resources(w), before);
      if (w is WorldGame) expect(w.journal.length, length! + 1);
      expect(w.weekHistory.last.parentBonus, isTrue);
    });

    // Защищает: дополнительная смена годится на любую работу — и на ту,
    // где свой лимит уже выбран. Уронит: бонус поднимает только общий
    // лимит (работа A остаётся на нуле) или только лимит работы.
    test('бонус: +1 и к общему лимиту, и к лимиту каждой работы', () {
      final World w = _week1(kind);
      final (JobOffer a, JobOffer b) = _twoJobs(w);
      final int perJob = _left(w, a);
      // Обычная смена (оценка 0) — без лишней ⚡ за «хорошо».
      for (int i = 0; i < perJob; i++) {
        ok(w.completeJob(a.jobId, variant: a.variant, score: 0));
      }
      expect(w.phase, WeekPhase.living, reason: '⚡ хватило на смены');
      expect(_left(w, a), 0);
      final int bBefore = _left(w, b);
      expect(bBefore, w.shiftsLimitThisWeek - perJob);

      ok(w.parentExtraShift());
      expect(_left(w, a), 1);
      expect(_left(w, b), bBefore + 1);
    });

    // Защищает: бонус живёт одну неделю и доступен только пока неделя идёт.
    // Уронит: флаг не сбрасывается началом недели (лимит 4 навсегда),
    // бонус пишется до плана или после «Спать».
    test('бонус: только пока неделя идёт; со следующей недели лимит прежний',
        () {
      final World w = kind.make();
      ok(w.startWeek());
      final int? planningLength = _journalLength(w);
      final WorldResult planning = w.parentExtraShift();
      expect(planning.reasonCode, 'phase.parentBonus');
      expect(planning.reason, isNotEmpty);
      expect(_journalLength(w), planningLength);

      ok(w.plan(needs: 250, wants: 0, goal: 0));
      final int base = w.shiftsLimitThisWeek;
      ok(w.parentExtraShift());
      ok(w.sleep());
      expect(w.parentExtraShift().reasonCode, 'phase.parentBonus');
      ok(w.payBills());
      ok(w.startWeek());
      ok(w.plan(needs: 0, wants: 0, goal: 0));

      expect(w.shiftsLimitThisWeek, base);
      expect(w.parentBonusThisWeek, isFalse);
      expect(w.weekHistory.map((WeekPlanFact f) => f.parentBonus).toList(),
          <bool>[true, false]);
      ok(w.parentExtraShift());
      expect(w.shiftsLimitThisWeek, base + 1);
    });
  });

  // Защищает: бонус — запись журнала, а не поле в памяти: переживает
  // перезапуск (ТЗ 2.5.13.1) и свёртку заново. Уронит: вид записи не
  // читается обратно (запись «нечитаемая», лимит снова 3), свёртка его
  // пропускает.
  test('parentBonus переживает сохранение и восстановление', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('finlit_parent_bonus_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<String> read(String path) => File(path).readAsString();

    final SavedWorld first =
        await openSavedWorld(read: read, storage: FileStorage(dir));
    final WorldGame w = first.world;
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 0, goal: 0));
    final int base = w.shiftsLimitThisWeek;
    ok(w.parentExtraShift());
    await first.flush();
    expect(first.lastSaveError, isNull);

    final SavedWorld again =
        await openSavedWorld(read: read, storage: FileStorage(dir));
    expect(again.restored, WorldRestore.restored);
    expect(again.world.unreadable, 0);
    expect(again.world.parentBonusThisWeek, isTrue);
    expect(again.world.shiftsLimitThisWeek, base + 1);
    expect(again.world.parentExtraShift().reasonCode, 'parent.bonus.done');
    expect(_resources(again.world), _resources(w));
    expect(again.world.weekHistory.last.parentBonus, isTrue);
  });
}
