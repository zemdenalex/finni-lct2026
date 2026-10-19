import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/tutorial/tutorial_gate.dart';
import 'package:finlit/features/world/tutorial/tutorial_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Обучалка первого захода над комнатой (D6, страница docs/final/tutorial/).
///
/// Защищает: шаги идут по порядку и каждый светит настоящий предмет комнаты;
/// флаг `off` — первый заход как сдано; пропущенная обучалка не возвращается,
/// когда комнату строят заново (возврат из города); после первого дела её
/// нет. Уронит: переименованный ключ цели, обучалка при выключенном флаге,
/// повтор шагов после «Пропустить».
void main() {
  /// Мир на пороге комнаты: знакомство пройдено, неделя 1 разложена.
  WorldGame firstVisit() {
    final WorldGame w = contentWorld(
        onboarding:
            const OnboardingProgress(step: OnboardingProgress.stepDone));
    if (w.phase == WeekPhase.weekStart || w.phase == WeekPhase.onboarding) {
      ok(w.startWeek());
    }
    if (w.phase == WeekPhase.planning) {
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    }
    expect(isFirstVisit(w), isTrue, reason: 'настройка: первый заход');
    return w;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (int i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 20));
      }
    });
  }

  Finder step(String id) => find.byKey(ValueKey<String>('tutorial:step:$id'));
  final Finder next = find.byKey(const ValueKey<String>('tutorial:next'));
  final Finder skip = find.byKey(const ValueKey<String>('tutorial:skip'));

  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets(
        'T1 · ${o.key}: шесть шагов по порядку, каждый светит '
        'свой предмет', (WidgetTester tester) async {
      final WorldGame w = firstVisit();
      await tester.runAsync(() async {
        await pumpWorldScreen(
            tester,
            const TutorialGate(
                look: TutorialLook.spotlight, child: RoomScreen()),
            world: w,
            size: o.value);
      });
      await settle(tester);
      for (final TutorialStep s in tutorialSteps) {
        expect(step(s.id), findsOneWidget, reason: 'шаг ${s.id}');
        expect(
            s.targets.any((String k) =>
                find.byKey(ValueKey<String>(k)).evaluate().isNotEmpty),
            isTrue,
            reason: 'цель шага ${s.id} есть в комнате');
        await tester.tap(next);
        await settle(tester);
      }
      expect(find.byKey(const ValueKey<String>('tutorial:next')), findsNothing,
          reason: '«Играть» на последнем шаге закрывает обучалку');
    });
  }

  testWidgets('флаг off — первый заход без обучалки', (WidgetTester t) async {
    await t.runAsync(() async {
      await pumpWorldScreen(
          t, const TutorialGate(look: TutorialLook.off, child: RoomScreen()),
          world: firstVisit());
    });
    await settle(t);
    expect(step('hello'), findsNothing);
    expect(tutorialLook, TutorialLook.off,
        reason: 'в сборке обучалка выключена, пока Денис не выбрал вид');
  });

  // Финни бывает мальчиком и девочкой, ребёнок — тоже: реплики обучалки без
  // рода (баг-прогон 18.10, = D3: у девочки «живу сам», «весёлый / грустный»,
  // «Дальше — сам!»). Уронит: слово рода или «я + прошедшее / прилагательное»
  // в любой реплике или подсказке шести шагов.
  testWidgets('реплики и подсказки всех шагов — без рода',
      (WidgetTester t) async {
    final WorldGame w = firstVisit();
    final RegExp gender = RegExp(
        r'(?<![а-яё])(сам|сама|один|одна|весёлый|весёлая|веселый|веселая|'
        r'грустный|грустная|рад|рада|готов|готова|доволен|довольна|'
        r'устал|устала)(?![а-яё])'
        r'|(?<![а-яё])я (?:[а-яё]+(?:л|ла)|[а-яё]+(?:ый|ий|ой|ая|яя))(?![а-яё])');
    expect(tutorialSteps, hasLength(6));
    for (final TutorialStep s in tutorialSteps) {
      for (final String line in <String>[s.say(w), s.short(w)]) {
        expect(gender.firstMatch(line.toLowerCase())?.group(0), isNull,
            reason: '${s.id}: «$line»');
      }
    }
  });

  testWidgets('реплики: «опыт» — из одного ключа, настроение и оплата',
      (WidgetTester t) async {
    final WorldGame w = firstVisit();
    String say(String id) =>
        tutorialSteps.firstWhere((TutorialStep s) => s.id == id).say(w);
    expect(say('xp'), contains(TutorialWords.xp));
    expect(say('mood'), contains('платят'));
    expect(say('rent'), contains('${w.snapshot.weeklyBill}'));
    expect(say('shop'), contains('${weeklyFoodCost(w)}'));
    expect(weeklyFoodCost(w), greaterThan(0));
  });

  testWidgets(
      '«Пропустить» — обучалка не возвращается, когда комнату '
      'строят заново', (WidgetTester t) async {
    final WorldGame w = firstVisit();
    Future<void> room(Key k) => t.runAsync(() async {
          await pumpWorldScreen(
              t,
              TutorialGate(
                  key: k,
                  look: TutorialLook.spotlight,
                  child: const RoomScreen()),
              world: w);
        });
    await room(const ValueKey<int>(1));
    await settle(t);
    await t.tap(next);
    await settle(t);
    expect(step('rent'), findsOneWidget);
    await t.tap(skip);
    await settle(t);
    expect(step('rent'), findsNothing);
    await room(const ValueKey<int>(2));
    await settle(t);
    expect(find.byKey(const ValueKey<String>('tutorial:next')), findsNothing);
  });

  testWidgets('после первого дела обучалки нет', (WidgetTester t) async {
    final WorldGame w = firstVisit();
    final String food = w.snapshot.foodId!;
    ok(w.eat(food));
    expect(isFirstVisit(w), isFalse);
    await t.runAsync(() async {
      await pumpWorldScreen(t,
          const TutorialGate(look: TutorialLook.spotlight, child: RoomScreen()),
          world: w);
    });
    await settle(t);
    expect(step('hello'), findsNothing);
  });

  for (final TutorialLook look in <TutorialLook>[
    TutorialLook.dialog,
    TutorialLook.hints,
  ]) {
    testWidgets(
        '${look.name}: первый шаг виден, «дальше» ведёт ко второму, '
        '«пропустить» закрывает', (WidgetTester t) async {
      await t.runAsync(() async {
        await pumpWorldScreen(
            t, TutorialGate(look: look, child: const RoomScreen()),
            world: firstVisit());
      });
      await settle(t);
      expect(step('hello'), findsOneWidget);
      await t.tap(next);
      await settle(t);
      expect(step('rent'), findsOneWidget);
      if (look == TutorialLook.hints) {
        expect(skip, findsNothing,
            reason: '«Без подсказок» — только у первой подсказки');
        return;
      }
      await t.tap(skip);
      await settle(t);
      expect(step('rent'), findsNothing);
    });
  }
}
