import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Пул событий режима дней (Денис: «событий побольше», 14 новых,
/// 17.10): утро без события — пустой день на карте.
///
/// Защищает:
/// - в сборке 52 события с уникальными id (45 + 3 о мошенниках + 4 по темам, 18.10), 14 новых на месте;
/// - пул не истощается: 4 недели × 7 утр у ребёнка без питомца (самый узкий
///   пул) — каждое утро есть событие, даже если ни на одно не ответить
///   (показанное, но не отвеченное, тоже занимает окно повтора 4 недели);
/// - каждое новое событие хоть раз выпадает за 8 недель у ребёнка с
///   питомцем.
/// Уронит: событие пропало из файла или его условия нельзя выполнить; пул
/// снова меньше 28 событий на окно повтора (на старых 31 событии без
/// питомца утра 4-й недели пустые).
void main() {
  const List<String> added = <String>[
    'school_trip_fee',
    'subscription_auto',
    'found_wallet',
    'snack_every_day',
    'broken_phone_screen',
    'pocket_money_early',
    'bulk_pack',
    'friend_sells_toy',
    'cashback_card',
    'sick_day',
    'goal_price_up',
    'share_lunch',
    'piggy_count',
    'pet_vet',
  ];

  final WorldConfig c = contentDayConfig;

  test('в сборке 52 события, id уникальны, 14 новых на месте', () {
    final List<String> ids = c.events.map((WorldEventSpec e) => e.id).toList();
    expect(ids, hasLength(52));
    expect(ids.toSet(), hasLength(52));
    expect(ids, containsAll(added));
  });

  /// Сыграть [weeks] недель, не отвечая на события; вернуть id событий по
  /// утрам (null — утро без события). [pet] — купить питомца в неделе 1.
  List<String?> mornings(int weeks, {String? pet}) {
    final WorldGame w = WorldGame(config: c);
    final List<String?> seen = <String?>[];
    for (int week = 1; week <= weeks; week++) {
      ok(w.startWeek());
      final int have = w.snapshot.unallocated;
      // Питомец — цель: оплата из копилки.
      ok(w.plan(needs: 0, wants: 0, goal: pet != null && week == 1 ? have : 0));
      if (pet != null && week == 1) ok(w.buy(pet));
      seen.add(w.pendingEvent?.id);
      for (int d = 1; d < c.daysPerWeek; d++) {
        expect(w.sleep().reasonCode, 'day.next');
        seen.add(w.pendingEvent?.id);
      }
      ok(w.sleep());
      ok(w.payBills());
    }
    return seen;
  }

  test('пул не истощается: 4 недели × 7 утр без питомца — событие каждое утро',
      () {
    final List<String?> seen = mornings(4);
    expect(seen, hasLength(4 * c.daysPerWeek));
    final List<int> empty = <int>[
      for (int i = 0; i < seen.length; i++)
        if (seen[i] == null) i,
    ];
    expect(empty, isEmpty, reason: 'пустые утра (индекс дня): $empty; $seen');
  });

  test('каждое новое событие выпадает за 8 недель (с питомцем)', () {
    final WorldPet cheapest = (c.pets.toList()
          ..sort((WorldPet a, WorldPet b) => a.price.compareTo(b.price)))
        .first;
    final List<String?> seen = mornings(8, pet: cheapest.id);
    final Set<String> shown = seen.whereType<String>().toSet();
    expect(added.where((String id) => !shown.contains(id)).toList(), isEmpty,
        reason: 'показано: $shown');
  });
}
