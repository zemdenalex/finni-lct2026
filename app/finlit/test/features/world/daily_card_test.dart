import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/daily/daily_layer.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Числа сборки с днями; [daily] — флаг ежедневных дел.
WorldConfig _config({required bool daily}) {
  final Map<String, Object?> eco = jsonDecode(
          File('${WorldContentLoader.base}/economy.json').readAsStringSync())
      as Map<String, Object?>;
  eco['day_cycle'] = <String, Object?>{
    ...(eco['day_cycle'] as Map<String, Object?>? ?? <String, Object?>{}),
    'daily_activities': daily,
  };
  String read(String f) =>
      File('${WorldContentLoader.base}/$f').readAsStringSync();
  return worldConfigFromContent(WorldContent.parse(
      economy: jsonEncode(eco),
      jobs: read('jobs.json'),
      events: read('events.json')));
}

WorldGame _living({required bool daily}) {
  final WorldGame w = WorldGame(config: _config(daily: daily));
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return w;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, World w) async {
  await tester.runAsync(() async {
    await pumpWorldScreen(tester, const DailyLayer(child: RoomScreen()),
        world: w);
  });
  await _settle(tester);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

// Ловит (дела дня, контракт back §4): карточка видна при выключенном флаге
// или пропадает при включённом; «сил на N дел» и день не из мира; отдых
// и магазин меняют мир не так, как написано на кнопке.
void main() {
  testWidgets('флаг выключен — карточки «Сегодня» нет',
      (WidgetTester tester) async {
    await _pump(tester, _living(daily: false));
    expect(find.byKey(const ValueKey<String>('daily:card')), findsNothing);
  });

  testWidgets('флаг включён: «сил на N дел» — из мира',
      (WidgetTester tester) async {
    final WorldGame w = _living(daily: true);
    await _pump(tester, w);
    final ResourceSnapshot s = w.snapshot;
    expect(find.byKey(const ValueKey<String>('daily:card')), findsOneWidget);
    expect(_text(tester, 'daily:title'), 'Сегодня');
    final int n = (s.energy / w.cheapestActionEnergy + 1e-9).floor();
    expect(_text(tester, 'daily:left'), startsWith('сил на $n '));
    expect(_text(tester, 'daily:fridge'), 'Холодильник пуст');
  });

  testWidgets('«Отдых»: ⚡ и 😊 меняются как на кнопке',
      (WidgetTester tester) async {
    final WorldGame w = _living(daily: true);
    final DayCycle dc = w.config.dayCycle;
    await _pump(tester, w);
    final ResourceSnapshot before = w.snapshot;
    await tester.tap(find.byKey(const ValueKey<String>('daily:rest')));
    await _settle(tester);
    final ResourceSnapshot after = w.snapshot;
    expect(after.energy, closeTo(before.energy - dc.restEnergy, 1e-9));
    // 😊 отдыха минус день, который это дело заняло (−1 😊 за день, P7).
    expect(after.happiness, greaterThan(before.happiness));
    // Сделанное сегодня — из снимка мира (doneToday), переживёт перезапуск.
    expect(after.doneToday, contains('rest'));
    expect(_text(tester, 'daily:done'), contains('отдых'));
  });

  testWidgets('«Магазин»: порции в холодильнике, строка карточки о них',
      (WidgetTester tester) async {
    final WorldGame w = _living(daily: true);
    await _pump(tester, w);
    await tester.tap(find.byKey(const ValueKey<String>('daily:shop')));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 600)); // лист выехал
    // Лист открывается с числом порций, на которое хватает хоть одному
    // блюду (неделя из 7 дней: 7 порций дороже кошелька) — берём первое
    // доступное.
    final String food = w.catalog
        .where((WorldCatalogItem i) =>
            i.category == WorldCatalogCategory.food &&
            tester
                    .widget<OutlinedButton>(
                        find.byKey(ValueKey<String>('daily:fridge:${i.id}')))
                    .onPressed !=
                null)
        .first
        .id;
    final Finder pick = find.byKey(ValueKey<String>('daily:fridge:$food'));
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(w.snapshot.fridge[food], greaterThan(0));
    expect(_text(tester, 'daily:fridge'), startsWith('В холодильнике: '));
  });

  // Ловит (16.10): в альбомной карточка у «Сейчас» закрывала строку цели,
  // а при шрифте 1,3 после дела — и разделы «Неделя · Город · Прогресс».
  testWidgets('альбомная, шрифт 1,3: карточка не закрывает цель и разделы',
      (WidgetTester tester) async {
    final WorldGame w = _living(daily: true);
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const DailyLayer(child: RoomScreen()),
          world: w, size: landscape, textScale: 1.3);
    });
    await _settle(tester);
    // Высота ограничена разделами: второе дело — прокруткой карточки.
    await tester
        .ensureVisible(find.byKey(const ValueKey<String>('daily:rest')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('daily:rest')));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final Rect visible =
        tester.getRect(find.byKey(const ValueKey<String>('daily:scroll')));
    final Rect goal =
        tester.getRect(find.byKey(const ValueKey<String>('room:goal')));
    final Rect nav =
        tester.getRect(find.byKey(const ValueKey<String>('room:nav:progress')));
    expect(visible.top, greaterThanOrEqualTo(goal.bottom));
    expect(visible.bottom, lessThanOrEqualTo(nav.top));
    expect(find.byKey(const ValueKey<String>('daily:done')), findsOneWidget);
  });
}
