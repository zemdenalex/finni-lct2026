import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/world_hud.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
}

String _label(WidgetTester tester, String key) => tester
    .getSemantics(find.byKey(ValueKey<String>(key)))
    .getSemanticsData()
    .label
    .trim();

// Ловит: HUD дня показывает моковые числа (рендер вариантов), а не снимок
// мира (контракт back §1): день недели, дней в неделе, сытость. И в прежней
// неделе без дней (флаг days_per_week: 1) HUD не меняется против сданного.
void main() {
  testWidgets('дни включены: «День N из M» и сытость — из снимка мира',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final World w = contentDayWorld()..startWeek();
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    expect(w.snapshot.daysPerWeek, greaterThan(1), reason: 'контент: дни');
    late WorldState ws;
    await tester.runAsync(() async {
      ws = await pumpWorldScreen(tester, const RoomScreen(), world: w);
    });
    await _settle(tester);
    ResourceSnapshot s = w.snapshot;
    // Игровой календарь (Настя 20.10): день 1 недели 1 — пн 5 октября,
    // «день N из M» остаётся для TalkBack.
    expect(s.weekNo, 1);
    expect(_label(tester, 'hud:daytime'),
        'Понедельник, 5 октября, день 1 из ${s.daysPerWeek}');
    expect(find.text('Пн, 5 окт'), findsOneWidget);
    // Сытость — во втором ряду HUD словом и числом (вид E, 17.10).
    expect(_label(tester, 'hud:fed'), 'Сытость: ${s.satiety} из 100');
    // Верх шкалы ⚡ — мира (7 дней: 20), а не прежние 14 недели (17.10).
    final double top = (w as WorldGame).config.energyMax;
    expect(top, isNot(14), reason: 'контент: шкала дней');
    expect(_label(tester, 'hud:energy'),
        endsWith('из ${WorldHud.energyText(top)}'));

    // Не последний день — утро той же недели; как в игре, через состояние.
    ok(ws.act((World x) => x.sleep()));
    await _settle(tester);
    s = w.snapshot;
    expect(s.dayInWeek, 2);
    expect(_label(tester, 'hud:daytime'),
        'Вторник, 6 октября, день 2 из ${s.daysPerWeek}');
    expect(find.text('Вт, 6 окт'), findsOneWidget);
    // Сытость — во втором ряду HUD словом и числом (вид E, 17.10).
    expect(_label(tester, 'hud:fed'), 'Сытость: ${s.satiety} из 100');
    sem.dispose();
  });

  testWidgets('без дней (FakeWorld, прежняя неделя) — HUD как сдано',
      (WidgetTester tester) async {
    final World w = worldKinds.first.make();
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 100, goal: 50));
    expect(w.snapshot.satiety, isNull);
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(), world: w);
    });
    await _settle(tester);
    expect(find.byKey(const ValueKey<String>('hud:daytime')), findsNothing);
    expect(find.byKey(const ValueKey<String>('finni:fed')), findsNothing);
    expect(find.byKey(const ValueKey<String>('hud:happiness')), findsOneWidget);
  });

  // Защищает: после дела, которое двигает настроение (смена, еда, отдых),
  // у числа в HUD на 3 с видно «+N / −N» (модель 7 дней, Денис 17.10).
  // Уронит: HUD без значка (обёртку убрали), значок с неверным знаком или
  // не исчезает.
  testWidgets('настроение ±: значок сдвига у числа и через 3 с пропадает',
      (WidgetTester tester) async {
    final WorldGame w = contentDayWorld()..startWeek();
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    late WorldState ws;
    await tester.runAsync(() async {
      ws = await pumpWorldScreen(tester, const RoomScreen(), world: w);
    });
    await _settle(tester);
    const ValueKey<String> badge = ValueKey<String>('hud:happiness:delta');
    expect(find.byKey(badge), findsNothing, reason: 'при входе значка нет');
    final WorldFood tasty =
        w.config.foods.firstWhere((WorldFood f) => f.happiness > 0);
    final int before = w.snapshot.happiness;
    ok(ws.act((World x) => x.eat(tasty.id)));
    await tester.pump();
    final int d = w.snapshot.happiness - before;
    expect(d, greaterThan(0));
    expect(
        tester
            .widget<Text>(find.descendant(
                of: find.byKey(badge), matching: find.byType(Text)))
            .data,
        '+$d');
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(badge), findsNothing);
  });
  // Стиль Алины, шаг 5: верхняя строка экранов — монеты · силы · настроение
  // · день. Защищает: «День N из M» на экране не-комнаты из снимка мира, и
  // HUD в одну строку (не выше 56 dp, прежние две строки — 104) при шрифте
  // 1,3. Уронит: дня нет в HUD экрана, день не тот, HUD снова в две строки.
  testWidgets('HUD экрана: «День N из M» в строке, высота ≤ 56 при ×1,3',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final World w = contentDayWorld()..startWeek();
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const PiggyScreen(),
          world: w, textScale: 1.3);
    });
    await _settle(tester);
    final ResourceSnapshot s = w.snapshot;
    expect(_label(tester, 'hud:day'),
        'Понедельник, 5 октября, день 1 из ${s.daysPerWeek}');
    final Rect hud = tester.getRect(find.byType(WorldHud));
    expect(hud.height, lessThanOrEqualTo(WorldHud.landscapeHeight));
    final Rect coins =
        tester.getRect(find.byKey(const ValueKey<String>('hud:coins')));
    final Rect mood =
        tester.getRect(find.byKey(const ValueKey<String>('hud:happiness')));
    expect(mood.top, coins.top, reason: 'одна строка');
    expect(coins.height, greaterThanOrEqualTo(48));
    sem.dispose();
  });
}
