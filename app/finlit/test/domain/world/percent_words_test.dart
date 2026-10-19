import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_world.dart';
import '../../support/world_harness.dart';

/// Т6 А (Настя 19.10, решение pm вместо DEN-37 C): процентов на детских
/// экранах нет — доля с суммой монетами («640 из 1000»), без суммы словами
/// («на десятую часть»). В событиях доли тоже словами.
///
/// Уронит: «%» или «процент» вернулись в перк, итог недели или событие. Еда в итогах (`foodTakeaway`) и копилка проверены на своих
/// границах: `meals_test`, `shop_piggy_test`.
void main() {
  test('события сборки: ни одного процента в ситуациях и вариантах', () {
    for (final WorldEventSpec e in contentDayConfig.events) {
      final List<String> texts = <String>[
        e.title,
        e.situation,
        for (final WorldEventOptionSpec o in e.options) ...<String>[
          o.label,
          o.finni,
        ],
      ];
      for (final String t in texts) {
        expect(t, isNot(matches(RegExp(r'%|процент'))), reason: '${e.id}: $t');
      }
    }
  });

  test('перк питомца «+10 % к оплате» — словами, без процента', () {
    final WorldGame w = WorldGame(config: contentConfig);
    final String pet = contentConfig.payPerks.keys.first;
    final String perk = w.catalogItem(pet)!.perk!;
    expect(perk, contains('оплата больше на десятую часть'));
    expect(perk, isNot(matches(RegExp(r'%|процент'))));
  });

  for (final (String name, World Function() make)
      in <(String, World Function())>[
    ('FakeWorld', () => FakeWorld(config: contentConfig)),
    ('WorldGame', contentWorld),
  ]) {
    test('$name: очко «отложено регулярно» в итогах — без процента', () {
      final World w = make();
      ok(w.startWeek());
      ok(w.plan(needs: 400, wants: 0, goal: 0));
      ok(w.chooseGoal('pet_fish'));
      ok(w.completeJob('consultant', score: 0.5));
      ok(w.depositToGoal(w.snapshot.free));
      ok(w.sleep());
      final WorldResult r = ok(w.payBills());
      expect(r.reason, contains('отложено не меньше десятой части дохода'));
      expect(r.reason, isNot(matches(RegExp(r'%|процент'))));
    });
  }
}
