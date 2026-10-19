import 'dart:convert';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/demo/world_demo_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// «Режим проверки» (pm 18.10, ТЗ 2.5.12–13): цена города 5000 остаётся, а
/// жюри доходит до города демо-кнопкой. Защищает: «Открыть город» переводит
/// Финни в город без монет (жильё, очки, стадия — тем же правилом, что
/// покупка), второй раз — отказ; «Дать 1000 / 5000 монет» добавляет
/// свободные монеты; обе записи в журнале переживают перезапуск. Уронит:
/// стадия не меняется (жильё без очков или очки без жилья), монеты не
/// доходят до свёртки, демо-кнопки нет. Почему не ловят прежние: до 18.10
/// таких действий не было.
Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  if (f.evaluate().isEmpty) {
    final Finder list = find.byType(Scrollable).last;
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(f, 200, scrollable: list);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

WorldGame _living() {
  final WorldGame w = contentDayWorld();
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return w;
}

WorldGame _restored(WorldGame w) =>
    WorldGame.fromJson(jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);

void main() {
  test('«Открыть город»: стадия город без монет, повтор — отказ', () {
    final WorldGame w = _living();
    expect(w.snapshot.stage, WorldStage.village);
    final int coins = w.snapshot.available;
    final int goal = w.snapshot.goal;
    final WorldResult r = w.demoOpenCity();
    expect(r.ok, isTrue, reason: r.reason);
    expect(w.snapshot.stage, WorldStage.town);
    expect(w.snapshot.available, coins, reason: 'без монет');
    expect(w.snapshot.goal, goal);
    expect(w.journal.any((WorldEntry e) => e.kind == WorldDemoKind.openCity),
        isTrue);
    expect(
        w.journal.any((WorldEntry e) => e.kind == WorldLedgerKind.stageChanged),
        isTrue);
    expect(w.demoOpenCity().reasonCode, 'demo.city.done');
    expect(_restored(w).snapshot.stage, WorldStage.town, reason: 'перезапуск');
  });

  test('«Дать монеты»: +1000 и +5000 свободных, переживает перезапуск', () {
    final WorldGame w = _living();
    final int before = w.snapshot.free;
    ok(w.demoGiveCoins(1000));
    ok(w.demoGiveCoins(5000));
    expect(w.snapshot.free, before + 6000);
    expect(_restored(w).snapshot.free, w.snapshot.free);
    expect(w.demoGiveCoins(0).ok, isFalse);
  });

  testWidgets('экран демо: «Открыть город» и «Дать 5000 монет»',
      (WidgetTester tester) async {
    final WorldGame w = _living();
    final WorldState ws =
        await pumpWorldScreen(tester, const WorldDemoScreen(), world: w);
    final int free = ws.snapshot.free;
    await _tap(tester, 'demo:coins5000');
    expect(ws.snapshot.free, free + 5000);
    await _tap(tester, 'demo:city');
    expect(ws.snapshot.stage, WorldStage.town);
    expect(
        tester
            .widget<ButtonStyleButton>(
                find.byKey(const ValueKey<String>('demo:city')))
            .onPressed,
        isNull,
        reason: 'второй раз нажать нечего');
  });
}
