import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// DEN-27, вариант A на экране взрослого (S14): флаг `adult.weekly_bonus`
/// включён — правило и кнопка про монеты, нажатие — +N в кошелёк, кнопка
/// гаснет до следующей недели. Тексты — заглушки, поэтому
/// проверяются ключи и числа, а не формулировки. Уронит: экран не узнал о
/// варианте (показывает «дополнительную смену» с отказом `parent.no_limit`)
/// или кнопка не зовёт мир. Почему не ловят прежние: `adult_demo_test`
/// гоняет бонус только в варианте «+1 смена».
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldGame _coinsWorld() {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  e['adult'] = <String, Object?>{
    ...(e['adult']! as Map<String, Object?>),
    'weekly_bonus': true,
  };
  return WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(e),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
    roomItems: _read('room_items.json'),
  )));
}

Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  if (f.evaluate().isEmpty) {
    final Finder list = find.byType(Scrollable).last;
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await _step(tester);
    await tester.scrollUntilVisible(f, 200, scrollable: list);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _step(tester);
}

void main() {
  testWidgets('флаг включён: кнопка даёт монеты раз в неделю',
      (WidgetTester tester) async {
    final WorldGame w = _coinsWorld();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    expect(w.parentBonusCoins, 20);
    final int before = w.snapshot.free;
    final WorldState ws = await pumpWorldScreen(
        tester, WorldAdultScreen(random: Random(6)),
        world: w);
    final String q =
        tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
    await tester.enterText(find.byKey(WorldAdultScreen.answerKey),
        '${WorldAdultScreen.answerOf(q)}');
    await _tap(tester, 'adult:enter');

    final Finder button = find.byKey(const ValueKey<String>('adult:bonus'));
    await tester.scrollUntilVisible(button, 200,
        scrollable: find.byType(Scrollable).last);
    VoidCallback? pressed() =>
        tester.widget<ButtonStyleButton>(button).onPressed;
    expect(
        tester
            .widget<PicText>(
                find.byKey(const ValueKey<String>('adult:bonus:rule')))
            .text,
        contains('20'));
    expect(pressed(), isNotNull, reason: 'кнопка включена');
    expect(find.byKey(const ValueKey<String>('adult:bonus:why')), findsNothing);

    await _tap(tester, 'adult:bonus');
    expect(ws.world.snapshot.free, before + 20);
    expect(pressed(), isNull, reason: 'второй раз за неделю — нельзя');
    expect(
        find.byKey(const ValueKey<String>('adult:bonus:why')), findsOneWidget);

    // BG-02 (баг-прогон 18.10): справка и неделя в «Прогрессе» звали
    // бонус монетами «дополнительной сменой».
    await _tap(tester, 'adult:help');
    expect(find.textContaining('дополнительная смена'), findsNothing,
        reason: 'справка взрослого: бонус — монеты');
    expect(
        find.textContaining('бонус — 20 монеток раз в неделю'), findsOneWidget);
    await pumpWorldScreen(tester, const HistoryScreen(), state: ws);
    expect(
        find.textContaining('от взрослого: дополнительная смена',
            findRichText: true),
        findsNothing);
    expect(find.textContaining('от взрослого: +20', findRichText: true),
        findsOneWidget);
  });
}
