import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// День по энергии в комнате: «Спать» не в последний день недели — новое утро
/// в той же комнате, без итогов недели.
///
/// Защищает: экран не уводит в итоги, пока неделя идёт (модель дней включена
/// в сборке по умолчанию). Уронит: «Спать» по-старому всегда ведёт в итоги.
void main() {
  String read(String f) =>
      File('${WorldContentLoader.base}/$f').readAsStringSync();

  testWidgets('«Спать» в первый день недели — утро, комната остаётся',
      (WidgetTester tester) async {
    final WorldGame world = WorldGame(
        config: worldConfigFromContent(WorldContent.parse(
            economy: read('economy.json'),
            jobs: read('jobs.json'),
            events: read('events.json'))));
    expect(world.config.daysPerWeek, greaterThan(1));
    ok(world.startWeek());
    ok(world.plan(needs: 250, wants: 100, goal: 50));
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(), world: world);
    });
    await tester.runAsync(() async {
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await tester.tap(find.byKey(const ValueKey<String>('room:bed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('День закончится'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('sleep:confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(world.phase, WeekPhase.living);
    expect(world.snapshot.dayInWeek, 2);
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.byType(WeekReviewScreen), findsNothing);
    expect(find.byKey(const ValueKey<String>('sleep:next')), findsNothing,
        reason: 'кнопки «К итогам» нет — неделя идёт');
  });
}
