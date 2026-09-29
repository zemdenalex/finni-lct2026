import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// ТЗ 2.5.8.5 «Демо: все профессии» — [World.demoUnlockAllJobs].
///
/// Всё, что меняет запись: замки работ. Деньги, ⚡, 😊, владение, фаза и
/// цены работ — те же, что до неё; иначе демо подменяет экономику, которую
/// эксперт проверяет.
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
    (s.owned.toList()..sort()).join(','),
    s.activeGoalId,
    s.activePetId,
    // Цены работ: транспорт дал бы скидку ⚡, собака — перк оплаты.
    for (final JobOffer o in w.jobBoard) '${o.pay}/${o.energyCost}',
  ].join(' | ');
}

List<String> _lockedJobs(World w) => <String>[
      for (final JobOffer o in w.jobBoard)
        if (o.locked) '${o.jobId}/${o.variant}',
    ];

void main() {
  // Защищает: кнопка эксперта открывает курьера и выгульщика и ничего больше.
  // Уронит: открытие через покупку/владение (поменяются owned, ⚡ и оплата),
  // запись с монетами, повтор, который пишет вторую запись или меняет
  // числа, смена открытой работы, которая всё равно отказывает.
  forEachWorld((WorldKind kind) {
    test('все профессии открыты без покупок; повтор — без эффекта', () {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 0, goal: 0));
      expect(_lockedJobs(w), isNotEmpty, reason: 'до демо курьер закрыт');
      expect(w.offer('dog_walker')!.locked, isTrue);
      final String before = _resources(w);

      ok(w.demoUnlockAllJobs());
      expect(_lockedJobs(w), isEmpty);
      expect(w.allJobsUnlocked, isTrue);
      expect(_resources(w), before);
      final int? length = w is WorldGame ? w.journal.length : null;

      final WorldResult again = w.demoUnlockAllJobs();
      expect(again.ok, isFalse);
      expect(again.reasonCode, 'demo.jobs.done');
      expect(_resources(w), before);
      if (w is WorldGame) expect(w.journal.length, length);

      ok(w.completeJob('dog_walker', score: 0.5));
      ok(w.completeJob('courier', variant: 'near', score: 0.5));
    });
  });

  // Защищает: эффект живёт в журнале — переживает перезапуск (ТЗ 2.5.13.1)
  // и стирается сбросом. Уронит: вид записи не читается обратно (запись
  // пропущена как «нечитаемая», профессии снова закрыты), флаг держится
  // вне журнала и переживает сброс.
  test('запись demo.* переживает сохранение и стирается сбросом', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('finlit_demo_jobs_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<String> read(String path) => File(path).readAsString();

    final SavedWorld first =
        await openSavedWorld(read: read, storage: FileStorage(dir));
    ok(first.world.demoUnlockAllJobs());
    expect(WorldEntry.kindToString(first.world.journal.last.kind),
        'demo.unlockAllJobs');
    await first.flush();
    expect(first.lastSaveError, isNull);

    final SavedWorld again =
        await openSavedWorld(read: read, storage: FileStorage(dir));
    expect(again.restored, WorldRestore.restored);
    expect(again.world.unreadable, 0);
    expect(again.world.allJobsUnlocked, isTrue);
    expect(_lockedJobs(again.world), isEmpty);
    expect(_resources(again.world), _resources(first.world));

    // Сброс — как у WorldState.persistent: новый мир + стереть сохранённое.
    final WorldGame fresh = again.freshWorld();
    await again.forget();
    expect(fresh.allJobsUnlocked, isFalse);
    expect(fresh.offer('dog_walker')!.locked, isTrue);
    final SavedWorld third =
        await openSavedWorld(read: read, storage: FileStorage(dir));
    expect(third.world.allJobsUnlocked, isFalse);
    expect(third.world.offer('dog_walker')!.locked, isTrue);
  });
}
