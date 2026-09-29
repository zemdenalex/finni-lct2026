import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// ТЗ 2.5.8.5 «Демо: все события» — [World.demoShowEvent].
///
/// Запись только делает событие событием недели: деньги, ⚡, 😊 и фаза — те
/// же, что до неё. Меняет их уже выбор, обычным путём [World.resolveEvent].
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
    (s.owned.toList()..sort()).join(','),
  ].join(' | ');
}

World _week1(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 250, wants: 0, goal: 0));
  return w;
}

void main() {
  // Защищает: эксперт открывает любое событие мира в неделе 1 и проходит его
  // выбор. Уронит: список захардкожен или короче конфига, запись меняет
  // монеты/⚡/😊 или пишется вне недели, событие не становится ждущим (S10 пустой), выбор после
  // демо-показа отказывает или не пишет `eventChoice` с причиной.
  forEachWorld((WorldKind kind) {
    test('любое событие из списка становится событием недели и выбирается', () {
      final List<({String id, String title})> all = kind.make().demoEvents;
      if (kind.name == 'WorldGame') {
        expect(all.map((e) => e.id).toList(),
            contentConfig.events.map((WorldEventSpec e) => e.id).toList());
        expect(all, hasLength(21));
      }
      expect(all, isNotEmpty);

      // Вне недели и с чужим id — отказ без записи.
      final World idle = kind.make();
      ok(idle.startWeek());
      final int? idleLength = idle is WorldGame ? idle.journal.length : null;
      final WorldResult planning = idle.demoShowEvent(all.first.id);
      expect(planning.reasonCode, 'phase.event');
      expect(planning.reason, isNotEmpty);
      expect(idle.demoShowEvent('no_such_event').reasonCode, 'phase.event');
      if (idle is WorldGame) expect(idle.journal.length, idleLength);
      for (final ({String id, String title}) ev in all) {
        final World w = _week1(kind);
        final String before = _resources(w);
        final WorldResult r = w.demoShowEvent(ev.id);
        if (r.ok) {
          expect(r.reasonCode, 'demo.event');
        } else {
          // Расписание уже показало это событие — повторять нечего.
          expect(r.reasonCode, 'demo.event.pending', reason: ev.id);
        }
        expect(_resources(w), before, reason: ev.id);
        final PendingEvent? p = w.pendingEvent;
        expect(p?.id, ev.id);
        expect(p!.title, ev.title);
        final PendingEventChoice c = p.choices.firstWhere(
            (PendingEventChoice c) => c.available,
            orElse: () => fail('${ev.id}: ни одного доступного варианта'));
        final int length = w is WorldGame ? w.journal.length : 0;
        ok(w.resolveEvent(c.id));
        expect(w.pendingEvent?.id, isNot(ev.id), reason: ev.id);
        // Уже отвеченное показывается снова — так же открывается и событие,
        // пришедшее по расписанию.
        ok(w.demoShowEvent(ev.id));
        expect(w.pendingEvent?.id, ev.id);
        if (w is WorldGame) {
          final WorldEntry choice = w.journal.skip(length).firstWhere(
              (WorldEntry e) => e.kind == WorldLedgerKind.eventChoice);
          expect(choice.args['eventId'], ev.id);
          expect(choice.args['reason'], isA<String>());
        }
      }
    });
  });

  // Защищает: показанное событие живёт в журнале — после перезапуска оно
  // всё ещё ждёт выбора, и выбор проходит. Уронит: вид записи не читается
  // обратно (запись «нечитаемая», события нет) или свёртка его теряет.
  test('demo.showEvent переживает сохранение, выбор после перезапуска',
      () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('finlit_demo_event_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<String> read(String path) => File(path).readAsString();

    final SavedWorld first =
        await openSavedWorld(read: read, storage: FileStorage(dir));
    final World w = first.world;
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 0, goal: 0));
    // Не то, что пришло по расписанию: у бабушки min_week 2.
    expect(w.pendingEvent?.id, isNot('grandma_gift'));
    ok(w.demoShowEvent('grandma_gift'));
    expect(WorldEntry.kindToString(first.world.journal.last.kind),
        'demo.showEvent');
    await first.flush();
    expect(first.lastSaveError, isNull);

    final SavedWorld again =
        await openSavedWorld(read: read, storage: FileStorage(dir));
    expect(again.restored, WorldRestore.restored);
    expect(again.world.unreadable, 0);
    expect(again.world.pendingEvent?.id, 'grandma_gift');
    expect(_resources(again.world), _resources(first.world));
    ok(again.world.resolveEvent('all_to_goal'));
    expect(again.world.pendingEvent?.id, isNot('grandma_gift'));
    // Выбор сохраняется в фоне — дождаться, иначе папку не удалить.
    await again.flush();
  });
}
