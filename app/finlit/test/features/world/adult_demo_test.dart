import 'dart:math';

import 'package:finlit/app.dart' show BootScreen;

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:finlit/features/world/demo/world_checklist.dart';
import 'package:finlit/features/world/demo/world_demo_screen.dart';
import 'package:finlit/features/world/event/event_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Спрайты анимируются бесконечно — pumpAndSettle не дождётся покоя.
Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  if (f.evaluate().isEmpty) {
    // Сначала к началу списка, потом вниз до кнопки. Прыжком, а не
    // броском: журнал автопилота за 5 недель длиннее любого броска.
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

/// Прокрутить весь список до конца: переполнение строки на любом месте
/// экрана бросает исключение, и тест его ловит.
Future<void> _scrollThrough(WidgetTester tester, String listKey) async {
  final Finder list = find.byKey(ValueKey<String>(listKey));
  for (int i = 0; i < 60; i++) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pump();
  }
  expect(tester.takeException(), isNull);
}

Future<void> _unlockAdult(WidgetTester tester) async {
  final String q =
      tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
  await tester.enterText(find.byKey(WorldAdultScreen.answerKey),
      '${WorldAdultScreen.answerOf(q)}');
  await _tap(tester, 'adult:enter');
}

void main() {
  setUp(WorldDemoSession.clear);

  // Ловит: панель не доводит настоящий мир до 5 закрытых недель, журнал
  // автопилота не делится на недели, чек-лист не видит журнал движка
  // (имена видов записей разошлись) или сброс не возвращает мир к первому
  // запуску.
  testWidgets('демо: 5 недель на движке, чек-лист по журналу, сброс → неделя 0',
      (WidgetTester tester) async {
    final WorldState ws =
        await pumpWorldScreen(tester, const WorldDemoScreen());
    expect(ws.world, isA<WorldGame>());
    await _tap(tester, 'demo:auto5');
    // Пять недель закрыты, шестая открыта с карманными, но без плана —
    // как её увидит ребёнок.
    expect(ws.snapshot.weekNo, 6);
    expect(ws.phase, WeekPhase.planning);
    expect(find.byKey(const ValueKey<String>('demo:report')), findsOneWidget);
    for (int week = 1; week <= 5; week++) {
      expect(find.textContaining('Неделя $week: +'), findsOneWidget,
          reason: 'неделя $week в журнале автопилота');
    }
    expect(find.textContaining('Неделя 6: +'), findsNothing);
    expect(
        find.textContaining('Баланс ни разу не ушёл в минус.'), findsOneWidget);
    // Шаги «по журналу» отмечены журналом движка: план (5), смена (6),
    // цель и копилка (8).
    for (final int no in <int>[5, 6, 8]) {
      final Finder step = find.byKey(ValueKey<String>('demo:step:$no'));
      await tester.scrollUntilVisible(step, 200,
          scrollable: find.byType(Scrollable).last);
      expect(
          find.descendant(
              of: step, matching: find.text('Выполнено · по журналу')),
          findsOneWidget,
          reason: 'шаг $no');
    }

    await _tap(tester, 'demo:reset');
    await tester.tap(find.byKey(const ValueKey<String>('demo:confirm:no')));
    await _step(tester);
    expect(ws.snapshot.weekNo, 6, reason: 'отмена ничего не сбрасывает');

    await _tap(tester, 'demo:reset');
    await tester.tap(find.byKey(const ValueKey<String>('demo:confirm:yes')));
    await _step(tester);
    expect(ws.phase, WeekPhase.onboarding);
    expect(ws.snapshot.weekNo, 0);
    expect(ws.snapshot.growthPoints, 0);
    expect(WorldDemoSession.resetDone, isTrue);

    // Приложение А, шаг 11: после сброса эксперт гоняет автопилот и
    // перезапускает приложение — заставка обязана вести в комнату недели 6,
    // а не на шаг цели недоигранного онбординга.
    await _tap(tester, 'demo:auto5');
    expect(ws.snapshot.weekNo, 6);
    expect(BootScreen.targetFor(ws.onboarding), WorldRoutes.room);
  });

  // Ловит: «Открыть все профессии» (ТЗ 2.5.8.5) не открывает выгульщика на
  // доске S6, остаётся нажимаемой после первого раза или переживает
  // «Начать игру заново».
  testWidgets('демо: «Открыть все профессии» → выгульщик на доске, сброс',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 0, goal: 0));
    expect(w.offer('dog_walker')!.locked, isTrue);
    final WorldState ws =
        await pumpWorldScreen(tester, const WorldDemoScreen(), world: w);
    VoidCallback? jobsButton() => tester
        .widget<ButtonStyleButton>(
            find.byKey(const ValueKey<String>('demo:jobs')))
        .onPressed;

    await _tap(tester, 'demo:jobs');
    expect(jobsButton(), isNull, reason: 'второй раз нажать нечего');

    await _tap(tester, 'demo:go:${WorldRoutes.jobs}');
    await tester.pump(const Duration(seconds: 1));
    final Finder take =
        find.byKey(const ValueKey<String>('jobs:take:dog_walker'));
    await tester.scrollUntilVisible(take, 200,
        scrollable: find.byType(Scrollable).last);
    expect(take, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('jobs:back')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey<String>('jobs:back')), findsNothing);

    await _tap(tester, 'demo:reset');
    await tester.tap(find.byKey(const ValueKey<String>('demo:confirm:yes')));
    await _step(tester);
    expect(ws.world.offer('dog_walker')!.locked, isTrue);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('demo:jobs')), 200,
        scrollable: find.byType(Scrollable).last);
    expect(jobsButton(), isNotNull, reason: 'сброс снимает демо-запись');
  });

  // Ловит: «Показать событие» (ТЗ 2.5.8.5) не даёт выбрать событие вне
  // расписания или S10 после выбора показывает не его (пусто или событие по
  // расписанию).
  testWidgets('демо: «Показать событие» → любое событие открывается в S10',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 0, goal: 0));
    const String id = 'grandma_gift'; // min_week 2: в неделю 1 не придёт
    expect(w.pendingEvent?.id, isNot(id));
    final String title = contentConfig.event(id)!.title;
    await pumpWorldScreen(tester, const WorldDemoScreen(), world: w);

    await _tap(tester, 'demo:showEvent');
    await _tap(tester, 'demo:event:$id');
    await tester.pump(const Duration(seconds: 1));
    expect(
        find.descendant(
            of: find.byType(EventScreen), matching: find.text(title)),
        findsOneWidget);
  });

  // Ловит: взрослый (или ребёнок) сбрасывает игру одним тапом.
  testWidgets('взрослым: сброс только после подтверждения → онбординг',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    WorldAutopilot(w).playWeeks(2);
    final WorldState ws = await pumpWorldScreen(
        tester, WorldAdultScreen(random: Random(1)),
        world: w);
    expect(find.byKey(const ValueKey<String>('adult:reset')), findsNothing,
        reason: 'до барьера управления не видно');
    await _unlockAdult(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('adult:weeks'),
                skipOffstage: false))
            .data,
        'Игровых недель: 3',
        reason: 'две недели закрыты, третья уже идёт');

    await _tap(tester, 'adult:reset');
    expect(ws.snapshot.weekNo, 3, reason: 'один тап не сбрасывает');
    await tester.tap(find.byKey(const ValueKey<String>('adult:confirm:no')));
    await _step(tester);
    expect(ws.snapshot.weekNo, 3);

    await _tap(tester, 'adult:reset');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('adult:confirm:yes')));
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await _step(tester);
    expect(ws.phase, WeekPhase.onboarding);
    expect(ws.snapshot.weekNo, 0);
    expect(find.byType(WorldOnboardingScreen), findsOneWidget);
  });

  // Ловит: источники советов вуза (с адресами) не видны взрослому — ссылки
  // разрешены только в S14 (ТЗ §3.1.5); или адреса пропали из JSON.
  testWidgets('взрослым: источники советов вуза с адресами',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, WorldAdultScreen(random: Random(5)));
    await _unlockAdult(tester);
    final Finder f = find.byKey(const ValueKey<String>('adult:sources'));
    final Finder list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(f, 200, scrollable: list);
    final String text = tester.widget<Text>(f).data!;
    expect(
        text,
        allOf(contains('Финансовая культура'), contains('fincult'),
            contains('budget.mos.ru')));
  });

  // Ловит: из нового мира не добраться до лицензий шрифтов (OFL 1.1 —
  // текст лицензии идёт вместе со шрифтом, §3.3); раньше экран был только
  // в настройках старой игры.
  testWidgets('взрослым: «Лицензии» открывают экран лицензий',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, WorldAdultScreen(random: Random(5)));
    await _unlockAdult(tester);
    await _tap(tester, 'adult:licenses');
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LicensePage), findsOneWidget);
  });

  // Ловит (ТЗ 2.5.12.3): на S14 нет кнопки бонуса или она даёт монеты;
  // второй раз за неделю кнопка снова нажимается; в истории S12 не видно,
  // что смену открыл взрослый.
  testWidgets('взрослым: «Открыть дополнительную смену» → раз в неделю, S12',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 0, goal: 0));
    final int base = w.shiftsLimitThisWeek;
    final int coins = w.snapshot.available;
    final WorldState ws = await pumpWorldScreen(
        tester, WorldAdultScreen(random: Random(6)),
        world: w);
    await _unlockAdult(tester);
    VoidCallback? bonusButton() => tester
        .widget<ButtonStyleButton>(
            find.byKey(const ValueKey<String>('adult:bonus')))
        .onPressed;
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('adult:bonus')), 200,
        scrollable: find.byType(Scrollable).last);
    expect(
        tester
            .widget<PicText>(
                find.byKey(const ValueKey<String>('adult:bonus:rule')))
            .text,
        contains('одну дополнительную смену'));
    expect(bonusButton(), isNotNull);

    await _tap(tester, 'adult:bonus');
    expect(find.byKey(const ValueKey<String>('adult:bonus:result')),
        findsOneWidget,
        reason: 'нажатие подтверждено');
    expect(find.textContaining(parentBonusReason), findsOneWidget);
    expect(bonusButton(), isNull, reason: 'второй раз за неделю — нечего');
    expect(find.text('Дополнительная смена открыта'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('adult:bonus:why')))
            .data,
        parentBonusDone.text);
    expect(ws.world.shiftsLimitThisWeek, base + 1);
    expect(ws.snapshot.available, coins, reason: 'бонус — не монеты');

    await pumpWorldScreen(tester, const HistoryScreen(), state: ws);
    expect(
        find.textContaining('от взрослого: дополнительная смена',
            findRichText: true),
        findsOneWidget);
  });

  // Ловит: бонус нажимается до плана недели, когда ни одной смены ещё нет.
  testWidgets('взрослым: до плана недели бонус выключен и сказано почему',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    await pumpWorldScreen(tester, WorldAdultScreen(random: Random(7)),
        world: w);
    await _unlockAdult(tester);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('adult:bonus')), 200,
        scrollable: find.byType(Scrollable).last);
    expect(
        tester
            .widget<ButtonStyleButton>(
                find.byKey(const ValueKey<String>('adult:bonus')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('adult:bonus:why')))
            .data,
        w.canDo(WorldAction.parentBonus)!.text);
    expect(w.canDo(WorldAction.parentBonus)!.code, 'phase.parentBonus');
  });

  // Ловит: неверный ответ на барьере открывает раздел.
  testWidgets('взрослым: неверный ответ не открывает раздел',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, WorldAdultScreen(random: Random(2)));
    await tester.enterText(find.byKey(WorldAdultScreen.answerKey), '1');
    await _tap(tester, 'adult:enter');
    expect(find.byKey(const ValueKey<String>('adult:reset')), findsNothing);
    expect(WorldDemoSession.adultOpened, isFalse);
    // Новый пример и подсказка «для взрослых».
    expect(find.textContaining('Этот раздел для взрослых'), findsOneWidget);
  });

  // Ловит: пример снова решается в уме — цифрами, однозначный множитель
  // или ×10/×20.
  testWidgets('взрослым: пример словами, оба множителя 12–29 без 20',
      (WidgetTester tester) async {
    for (int seed = 0; seed < 20; seed++) {
      await pumpWorldScreen(tester, WorldAdultScreen(random: Random(seed)));
      final String q =
          tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
      expect(RegExp(r'\d').hasMatch(q), isFalse, reason: q);
      final List<String> parts = q.split(' × ');
      expect(parts, hasLength(2));
      for (final String p in parts) {
        final int n = WorldAdultScreen.factorWords.entries
            .firstWhere((MapEntry<int, String> e) => e.value == p)
            .key;
        expect(n, inInclusiveRange(12, 29));
        expect(n, isNot(20));
      }
      expect(WorldAdultScreen.answerOf(q), greaterThanOrEqualTo(144));
    }
  });

  /// Прокрутить список [listKey] до [key] и нажать — для альбомной, где
  /// на экране две прокрутки рядом.
  Future<void> tapIn(WidgetTester tester, String listKey, String key) async {
    final Finder f = find.byKey(ValueKey<String>(key));
    final Finder list = find.descendant(
        of: find.byKey(ValueKey<String>(listKey)),
        matching: find.byType(Scrollable));
    // Сначала к началу списка, потом вниз до кнопки.
    tester.state<ScrollableState>(list.first).position.jumpTo(0);
    await _step(tester);
    await tester.scrollUntilVisible(f, 120, scrollable: list.first);
    await tester.pump();
    await tester.tap(f);
    await _step(tester);
  }

  // Ловит: в альбомной (основной) барьер не влезает в 640 × 360 при шрифте
  // 1,3 или требует системную клавиатуру; сброс срабатывает без
  // подтверждения.
  testWidgets('взрослым, альбомная 640×360, шрифт 1,3: барьер цифрами, сброс',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    WorldAutopilot(w).playWeeks(2);
    final WorldState ws = await pumpWorldScreen(
        tester, WorldAdultScreen(random: Random(4)),
        world: w, size: landscape, textScale: 1.3);
    expect(tester.takeException(), isNull);
    // Пример, поле, все цифры и «Войти» — на экране без прокрутки.
    for (final Key k in <Key>[
      WorldAdultScreen.questionKey,
      WorldAdultScreen.answerKey,
      const ValueKey<String>('adult:enter'),
      const ValueKey<String>('adult:key:0'),
      const ValueKey<String>('adult:key:9'),
      const ValueKey<String>('adult:key:erase'),
    ]) {
      expect(find.byKey(k).hitTestable(), findsOneWidget, reason: '$k');
    }
    expect(
        tester
            .widget<TextField>(find.byKey(WorldAdultScreen.answerKey))
            .keyboardType,
        TextInputType.none,
        reason: 'системная клавиатура не должна закрывать пример');

    // Ответ — экранными цифрами, с ошибкой и «стереть».
    final String q =
        tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
    final int answer = WorldAdultScreen.answerOf(q);
    await tester.tap(find.byKey(const ValueKey<String>('adult:key:1')));
    await tester.tap(find.byKey(const ValueKey<String>('adult:key:erase')));
    for (final String d in '$answer'.split('')) {
      await tester.tap(find.byKey(ValueKey<String>('adult:key:$d')));
    }
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(WorldAdultScreen.answerKey))
            .controller!
            .text,
        '$answer');
    await tester.tap(find.byKey(const ValueKey<String>('adult:enter')));
    await _step(tester);
    expect(tester.takeException(), isNull);
    expect(WorldDemoSession.adultOpened, isTrue);

    // Две колонки: прогресс слева, «чему учит» справа.
    expect(find.byKey(const ValueKey<String>('adult:list')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('adult:list:more')), findsOneWidget);
    await _scrollThrough(tester, 'adult:list');
    await _scrollThrough(tester, 'adult:list:more');

    await tapIn(tester, 'adult:list', 'adult:reset');
    await tester.tap(find.byKey(const ValueKey<String>('adult:confirm:no')));
    await _step(tester);
    expect(ws.snapshot.weekNo, 3, reason: 'отмена ничего не сбрасывает');

    await tapIn(tester, 'adult:list', 'adult:reset');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('adult:confirm:yes')));
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await _step(tester);
    expect(ws.phase, WeekPhase.onboarding);
    expect(ws.snapshot.weekNo, 0);
    expect(find.byType(WorldOnboardingScreen), findsOneWidget);
  });

  // Ловит: в альбомной журнал автопилота и чек-лист не видны рядом с
  // кнопками, или панель переполняется при шрифте 1,3.
  testWidgets('проверка, альбомная 640×360, шрифт 1,3: автопилот и журнал',
      (WidgetTester tester) async {
    final WorldState ws = await pumpWorldScreen(tester, const WorldDemoScreen(),
        size: landscape, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tapIn(tester, 'demo:list', 'demo:auto5');
    expect(ws.snapshot.weekNo, 6);
    expect(tester.takeException(), isNull);
    // Итог и журнал — в правой колонке, рядом с кнопками.
    final Finder report = find.byKey(const ValueKey<String>('demo:report'));
    expect(report, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('result:card')), findsOneWidget);
    expect(
        tester.getTopLeft(report).dx,
        greaterThan(tester
            .getCenter(find.byKey(const ValueKey<String>('demo:auto5')))
            .dx));
    await _scrollThrough(tester, 'demo:list');
    await _scrollThrough(tester, 'demo:log');

    await tapIn(tester, 'demo:list', 'demo:reset');
    await tester.tap(find.byKey(const ValueKey<String>('demo:confirm:yes')));
    await _step(tester);
    expect(ws.snapshot.weekNo, 0);
  });

  // Ловит: панель или раздел не помещаются на 360×640 при крупном шрифте.
  testWidgets('оба экрана помещаются на 360×640 при шрифте 1,3',
      (WidgetTester tester) async {
    final WorldGame w = contentWorld();
    await pumpWorldScreen(tester, const WorldDemoScreen(),
        world: w, textScale: 1.3);
    await _tap(tester, 'demo:auto1');
    await _scrollThrough(tester, 'demo:list');

    await pumpWorldScreen(tester, WorldAdultScreen(random: Random(3)),
        world: w, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await _unlockAdult(tester);
    await _scrollThrough(tester, 'adult:list');
    // 2.5.12.2: без негативных оценок ребёнка.
    for (final String bad in <String>['ошиб', 'плохо', 'отста']) {
      expect(find.textContaining(bad), findsNothing);
    }
  });
}
