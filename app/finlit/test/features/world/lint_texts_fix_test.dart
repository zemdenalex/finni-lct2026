import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Правила детских текстов Насти, нарушения из линта по RC 3a1d5f6:
/// 1А — не «конверт», а «часть»; 5А — без обращения с родом («закончил ты
/// сам»); режим дней — «он сыт» при недельном лимите еды неправда (сытость
/// — шкала дня). Запасной режим «неделя» сохраняет прежние слова.
///
/// Уронит: строку вернули к старой или перевернули условие режима.

/// Съесть все приёмы недели: в днях — по одному в день, между ними сон.
/// Мир дней, где приёмы недели кончаются до её конца: 3 на неделю. На 7
/// днях и 1 приёме в день обеды кончаются лишь вечером 7-го дня — сообщение
/// «еда кончилась» иначе не увидеть (CI на trial/rc-7d, 17.10). На 3 днях
/// ключа `day_cycle.meals_per_week` нет — он ничего не меняет.
WorldGame _dayWorldMeals3() {
  String read(String f) =>
      File('${WorldContentLoader.base}/$f').readAsStringSync();
  final Map<String, Object?> eco =
      jsonDecode(read('economy.json')) as Map<String, Object?>;
  eco['day_cycle'] = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
    'meals_per_week': 3,
  };
  return WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
          economy: jsonEncode(eco),
          jobs: read('jobs.json'),
          events: read('events.json'))));
}

void _eatAllMeals(WorldGame w) {
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  final String food = w.config.foods.first.id;
  while (w.snapshot.mealsLeft > 0) {
    if (w.canDo(WorldAction.eat, id: food) == null) {
      ok(w.eat(food));
    } else {
      ok(w.sleep());
    }
  }
}

void main() {
  setUp(rootBundle.clear);

  test('еда недели кончилась, режим дней: без «он сыт»', () {
    final WorldGame w = _dayWorldMeals3();
    _eatAllMeals(w);
    final BlockReason? b =
        w.canDo(WorldAction.eat, id: w.config.foods.first.id);
    expect(b?.code, 'eat.limit');
    expect(b!.text, startsWith('Еда на эту неделю кончилась'));
    expect(b.text, isNot(contains('он сыт')));
  });

  test('еда недели кончилась, режим «неделя»: прежние слова', () {
    final WorldGame w = contentWorld();
    _eatAllMeals(w);
    final BlockReason? b =
        w.canDo(WorldAction.eat, id: w.config.foods.first.id);
    expect(b?.code, 'eat.limit');
    expect(b!.text, contains('— он сыт'));
  });

  test('copy.json: ни одного «конверт» (правило 1А)', () {
    final Map<String, Object?> copy =
        jsonDecode(File('assets/content/copy.json').readAsStringSync())
            as Map<String, Object?>;
    final List<String> bad = <String>[
      for (final MapEntry<String, Object?> e in copy.entries)
        if (e.value is String &&
            (e.value! as String).toLowerCase().contains('конверт'))
          e.key,
    ];
    expect(bad, isEmpty);
  });

  testWidgets('итоги после «Спать»: без «закончил ты сам» (правило 5А)', (
    WidgetTester tester,
  ) async {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    ok(sleepWeek(w));
    expect(w.phase, WeekPhase.review);
    await pumpWorldScreen(tester, const WeekReviewScreen(), world: w);
    final Finder box = find.byKey(const ValueKey<String>('review:ended'));
    expect(box, findsOneWidget);
    expect(
      find.descendant(
        of: box,
        matching: find.textContaining('Неделя закончилась', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('закончил ты сам', findRichText: true),
        findsNothing);
  });
}
