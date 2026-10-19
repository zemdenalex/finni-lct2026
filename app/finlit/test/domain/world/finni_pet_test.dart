import 'dart:convert';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_world.dart';
import '../../support/world_harness.dart';

/// Погладить Финни в комнате (решение Дениса 16.10): +1 😊, не чаще раза в
/// игровой день.
///
/// Защищает: +1 😊 за первое касание игрового дня, повтор в тот же день —
/// реакция без 😊; новый игровой день — снова +1; перезапуск (мир из журнала)
/// не даёт второго +1 в тот же день; монеты и копилка не меняются.
/// Уронит: счётчик дня держится в памяти, а не в журнале (перезапуск даёт
/// второй +1), или повтор тоже начисляет — «фарм» радости касаниями.
void main() {
  // Мир с прошедшим знакомством, неделя идёт: касание доступно в комнате.
  World started(World w) {
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    return w;
  }

  final List<(String, World Function())> worlds = <(String, World Function())>[
    ('FakeWorld', () => started(FakeWorld())),
    ('WorldGame', () => started(contentWorld())),
  ];

  for (final (String name, World Function() make) in worlds) {
    group(name, () {
      test('первое касание за игровой день: +1 😊, без монет', () {
        final World w = make();
        final ResourceSnapshot before = w.snapshot;
        final WorldResult r = w.petFinni();
        expect(r.ok, isTrue);
        expect(r.reasonCode, 'finni.pet');
        expect(r.happiness, 1);
        expect(w.snapshot.happiness, before.happiness + 1);
        expect(w.snapshot.free, before.free, reason: 'касание не даёт монет');
        expect(w.snapshot.goal, before.goal, reason: 'и не трогает копилку');
        expect(w.snapshot.energy, before.energy, reason: 'и не тратит ⚡');
      });

      test('повтор в тот же день: реакция есть, 😊 не растёт', () {
        final World w = make();
        ok(w.petFinni());
        final int after1 = w.snapshot.happiness;
        for (int i = 0; i < 5; i++) {
          final WorldResult r = w.petFinni();
          expect(r.ok, isTrue, reason: 'Финни всегда реагирует');
          expect(r.reasonCode, 'finni.pet_again');
          expect(r.happiness, 0);
          expect(r.reason, isNotEmpty);
        }
        expect(w.snapshot.happiness, after1);
      });

      test('новый игровой день — снова +1', () {
        final World w = make();
        ok(w.petFinni());
        // Досуг в парке — игровой день (тратит ⚡), как смена.
        ok(w.leisure('park'));
        final int before = w.snapshot.happiness;
        final WorldResult r = w.petFinni();
        expect(r.reasonCode, 'finni.pet');
        expect(w.snapshot.happiness, before + 1);
      });
    });
  }

  test('WorldGame: перезапуск из журнала не даёт второй +1 в тот же день', () {
    final WorldGame w = started(contentWorld()) as WorldGame;
    ok(w.petFinni());
    final WorldGame restored = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(restored.unreadable, 0);
    expect(restored.snapshot.happiness, w.snapshot.happiness);
    final WorldResult again = restored.petFinni();
    expect(again.reasonCode, 'finni.pet_again');
    expect(restored.snapshot.happiness, w.snapshot.happiness);
    // Запись с причиной — 2.5.4.3: 😊 не меняется без объяснения.
    expect(
        w.journal.where((WorldEntry e) =>
            e.kind == WorldLedgerKind.finniPetted &&
            e.reasonCode == 'finni.pet'),
        hasLength(1));
  });
}
