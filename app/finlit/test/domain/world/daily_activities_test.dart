import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Ежедневные дела дня по энергии (контракт §4, включаются решением Дениса):
/// холодильник (закупка за раз, Финни ест сам по утрам) и «отдохнуть дома».
///
/// Защищает: при выключенном флаге дел нет (отказ `feature.off`); при
/// включённом — закупка списывает деньги и ⚡ один раз, утром Финни ест из
/// холодильника сам, отдых даёт 😊 за ⚡, всё переживает перезапуск.
/// Уронит: флаг не выключает дела, утренняя еда берёт деньги второй раз,
/// холодильник живёт в памяти, а не в журнале.
void main() {
  WorldConfig configWith(Map<String, Object?> dayCycle) {
    final Map<String, Object?> eco = jsonDecode(
            File('${WorldContentLoader.base}/economy.json').readAsStringSync())
        as Map<String, Object?>;
    eco['day_cycle'] = <String, Object?>{
      ...(eco['day_cycle'] as Map<String, Object?>? ?? <String, Object?>{}),
      ...dayCycle,
    };
    String read(String f) =>
        File('${WorldContentLoader.base}/$f').readAsStringSync();
    return worldConfigFromContent(WorldContent.parse(
        economy: jsonEncode(eco),
        jobs: read('jobs.json'),
        events: read('events.json')));
  }

  WorldGame living(WorldConfig c) {
    final WorldGame w = WorldGame(config: c);
    ok(w.startWeek());
    ok(w.plan(needs: 300, wants: 0, goal: 0));
    return w;
  }

  final WorldConfig on =
      configWith(<String, Object?>{'daily_activities': true});

  test('по умолчанию дела выключены: отказ feature.off', () {
    final WorldConfig off = configWith(const <String, Object?>{});
    expect(off.dayCycle.dailyActivities, isFalse);
    final WorldGame w = living(off);
    expect(w.stockFridge('food_simple', 2).reasonCode, 'feature.off');
    expect(w.restAtHome().reasonCode, 'feature.off');
  });

  test('холодильник: деньги и ⚡ за закупку один раз, утром Финни ест сам', () {
    final WorldGame w = living(on);
    final ResourceSnapshot before = w.snapshot;
    final int price = on.food('food_simple')!.price;
    final WorldResult r = w.stockFridge('food_simple', 2);
    expect(r.ok, isTrue, reason: r.reason);
    expect(r.reasonCode, 'fridge.stocked');
    expect(w.snapshot.fridge['food_simple'], 2);
    expect(
        before.need +
            before.want +
            before.free -
            (w.snapshot.need + w.snapshot.want + w.snapshot.free),
        price * 2);
    expect(w.snapshot.energy, lessThan(before.energy),
        reason: 'поход в магазин');
    final int coins = w.snapshot.need + w.snapshot.want + w.snapshot.free;
    final int meals = w.snapshot.mealsThisWeek;
    ok(w.sleep()); // утро дня 2: завтрак из холодильника
    expect(w.snapshot.fridge['food_simple'], 1);
    expect(w.snapshot.mealsThisWeek, meals + 1);
    expect(w.snapshot.need + w.snapshot.want + w.snapshot.free, coins,
        reason: 'еда уже оплачена при закупке');
  });

  test('отдохнуть дома: −⚡, +😊', () {
    final WorldGame w = living(on);
    final ResourceSnapshot before = w.snapshot;
    final WorldResult r = w.restAtHome();
    expect(r.reasonCode, 'rest.done');
    expect(w.snapshot.energy, lessThan(before.energy));
    expect(w.snapshot.happiness, greaterThan(before.happiness));
  });

  test('перезапуск: холодильник тот же', () {
    final WorldGame w = living(on);
    ok(w.stockFridge('food_simple', 3));
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.unreadable, 0);
    expect(r.snapshot.fridge, w.snapshot.fridge);
  });

  // Защищает: экран «Сегодня» гасит кнопку с той же причиной, что и вызов
  // (контракт §4). Уронит: canDo молчит, а вызов отказывает, или наоборот.
  test('canDo: те же причины, что у вызова', () {
    final WorldConfig off = configWith(const <String, Object?>{});
    final WorldGame w0 = living(off);
    expect(w0.canDo(WorldAction.stockFridge, id: 'food_simple')?.code,
        'feature.off');
    expect(w0.canDo(WorldAction.restAtHome)?.code, 'feature.off');

    final WorldGame w = living(on);
    expect(w.canDo(WorldAction.stockFridge, id: 'food_simple'), isNull);
    expect(w.canDo(WorldAction.restAtHome), isNull);
    final String many = '${w.snapshot.available ~/ 10 + 1}';
    final BlockReason? short =
        w.canDo(WorldAction.stockFridge, id: 'food_simple', variant: many);
    expect(short?.code, 'fridge.short');
    expect(
        w.stockFridge('food_simple', int.parse(many)).reasonCode, short?.code);
  });

  // Защищает: экран «Сегодня» знает, что уже сделано за день, и это
  // переживает перезапуск; утром список пустой. Уронит: список живёт в
  // памяти экрана или не сбрасывается на новый день.
  test('doneToday: дела дня из журнала, утром — пусто', () {
    final WorldGame w = living(on);
    expect(w.snapshot.doneToday, isEmpty);
    ok(w.stockFridge('food_simple', 1));
    ok(w.restAtHome());
    expect(w.snapshot.doneToday, containsAll(<String>['fridge', 'rest']));
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.snapshot.doneToday, w.snapshot.doneToday);
    ok(r.sleep());
    expect(r.snapshot.doneToday, isNot(contains('rest')),
        reason: 'новый день — дела заново');
  });
}
