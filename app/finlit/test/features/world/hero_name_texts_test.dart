import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/domain/world/world_mood.dart';
import 'package:finlit/features/world/home/hud_chips.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_world.dart';
import '../../support/world_harness.dart';

/// Имя героя в текстах (баг-прогон 18.10, BG-01).
///
/// Ребёнок называет героя при знакомстве («Имя героя» → `finniName`), сам он
/// — ник (`{nick}`). Было: знакомство говорило «Пушистик», а итоги недели,
/// доска работ, уроки, награды и настроение — снова «Финни».
///
/// Защищает: в строках о герое из списка ниже нет «Финни», `{name}` даёт имя
/// героя (и не ник ребёнка); имя стоит только в именительном падеже
/// («Пушистик» склоняется, «Финни» — нет). «Финни» остаётся в имени по
/// умолчанию. Уронит: вернуть «Финни» в любую строку списка или забыть
/// подставить `{name}` на экране (в тексте останется «{name}»).
///
/// Подстановка в контенте считается здесь своей функцией [_hero], не
/// функцией приложения; экраны и домен проверяются по-настоящему.
const String _name = 'Пушистик';
const String _nick = 'Маша';

String _hero(String text) => text.replaceAll('{name}', _name);

WorldGame _named() => contentDayWorld(
    onboarding: const OnboardingProgress(
        nickname: _nick, finniName: _name, step: OnboardingProgress.stepDone));

/// Строка о герое: ни «Финни», ни ника ребёнка, ни неподставленных скобок.
void _expectHero(String what, String shown, {bool named = false}) {
  expect(shown, isNot(contains('Финни')), reason: '$what: «$shown»');
  expect(shown, isNot(contains(_nick)), reason: '$what: «$shown»');
  expect(shown, isNot(contains('{')), reason: '$what: «$shown»');
  if (named) expect(shown, contains(_name), reason: '$what: «$shown»');
}

/// Касание «😊» в шапке: карточка читает `hud.json` с диска — как в
/// `hud_explain_test.dart`, загрузка идёт в настоящем времени.
Future<void> _openMood(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey<String>('hud:happiness')));
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('контент: строки о герое — без «Финни», имя через {name}', () {
    final WorldConfig c = contentDayConfig;
    // jobs.json → university: «Финни учится на экономиста» (доска).
    _expectHero('university.short', _hero(contentJobGames.university.short),
        named: true);
    _expectHero('university.intro', _hero(contentJobGames.university.intro),
        named: true);
    // jobs.json → lessons.*.situation: «В студсовете Финни делал смету».
    for (final WorldLesson l in c.lessons) {
      _expectHero('lessons.${l.jobId}.situation', _hero(l.situation),
          named: const <String>{'cashier', 'accountant', 'dog_walker'}
              .contains(l.jobId));
    }
    // economy.json → day_cycle.shift_luck, mood_kinds (итог смены).
    for (final ShiftLuck l in c.dayCycle.luck) {
      _expectHero('shift_luck.${l.id}', _hero(l.text));
    }
    for (final MapEntry<String, MoodKind> k in c.dayCycle.moodKinds.entries) {
      _expectHero('mood_kinds.${k.key}', _hero(k.value.text));
    }
    // economy.json → achievements_days_items: «Проживи с Финни семь дней».
    for (final AchievementDef a
        in shippedDayContent.economy.achievementsDaysItems) {
      _expectHero('achievements_days_items.${a.id}', _hero(a.hint));
    }
    // events.json → events[].situation.
    for (final WorldEventSpec e in c.events) {
      _expectHero('events.${e.id}.situation', _hero(e.situation));
    }
    // explain.json → mood_why («Почему меняется настроение»).
    _expectHero('explain.mood_why', _hero(explainFor(_named()).moodWhy!),
        named: true);
  });

  test('причины настроения: без «Финни», имя только в именительном', () {
    const List<String> causes = <String>[
      'week.energy_out', 'bills.family_help', 'bills.from_goal',
      'bills.downgraded', 'week.tired', 'week.stagnation', 'week.growth',
      'leisure.done', 'event.leisure', 'buy.goal', 'buy.item', 'pet.tap',
      'finni.pet', 'meal.eaten', 'day.passed', 'sleep.bonus', 'job.payout',
      'week.closed', 'event.choice', //
    ];
    final Set<String> named = <String>{};
    for (final String cause in causes) {
      for (final int delta in <int>[-3, 3]) {
        for (final int happiness in <int>[20, 50, 80]) {
          final MoodReason r = moodReasonFor(
              happiness: happiness,
              phase: WeekPhase.living,
              causeCode: cause,
              causeDelta: delta);
          final String shown = _hero(r.text);
          _expectHero('${r.code} ($cause, $delta, $happiness)', shown);
          if (shown.contains(_name)) named.add(r.code);
        }
      }
    }
    for (final int happiness in <int>[20, 50, 80]) {
      final MoodReason r =
          moodReasonFor(happiness: happiness, phase: WeekPhase.living);
      _expectHero(r.code, _hero(r.text), named: true);
    }
    expect(named, containsAll(<String>['mood.growth', 'mood.shortfall_goal']));
  });

  test('движок: урок после смены и событие говорят имя героя', () {
    final WorldGame w = _named();
    ok(w.startWeek());
    ok(w.plan(needs: 300, wants: 300, goal: 0));
    if (w.pendingEvent case final PendingEvent e) {
      _expectHero('событие ${e.id}', e.text);
      ok(w.resolveEvent(
          e.choices.firstWhere((PendingEventChoice c) => c.available).id));
    }
    ok(w.completeJob('cashier', score: 1));
    final LessonOffer l = w.pendingLesson!;
    _expectHero('урок кассира', l.situation, named: true);

    // Копия мира для экранов (FakeWorld): событие недели 1 — автомат в парке.
    final FakeWorld f = FakeWorld(
        onboarding: const OnboardingProgress(
            nickname: _nick,
            finniName: _name,
            step: OnboardingProgress.stepDone));
    ok(f.startWeek());
    ok(f.plan(needs: f.snapshot.unallocated, wants: 0, goal: 0));
    _expectHero('событие FakeWorld', f.pendingEvent!.text, named: true);
  });

  testWidgets('доска работ и подсказка настроения: имя героя',
      (WidgetTester tester) async {
    final WorldGame w = _named();
    ok(w.startWeek());
    ok(w.plan(needs: 300, wants: 300, goal: 0));
    await pumpWorldScreen(tester, const JobBoardScreen(),
        world: w, size: const Size(360, 2000));
    await tester.pumpAndSettle();
    expect(find.textContaining('$_name учится на экономиста'), findsWidgets);
    expect(find.textContaining('Финни'), findsNothing);
    // «😊» в шапке: «Как чувствует себя Пушистик» и причина без «{name}».
    await _openMood(tester);
    final Finder dialog =
        find.byKey(const ValueKey<String>('hud:explain:happiness'));
    expect(dialog, findsOneWidget);
    expect(
        find.descendant(
            of: dialog,
            matching: find.textContaining('Как чувствует себя $_name')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('{')),
        findsNothing);
    expect(find.descendant(of: dialog, matching: find.textContaining('Финни')),
        findsNothing);
  });

  testWidgets('причина настроения в шапке комнаты: имя героя, без «{name}»',
      (WidgetTester tester) async {
    final WorldGame w = _named();
    ok(w.startWeek());
    ok(w.plan(needs: 300, wants: 300, goal: 0));
    // Сразу после плана — «обычное настроение»: причина с именем героя.
    expect(_hero(w.snapshot.moodReason.text), contains(_name));
    await pumpWorldScreen(
        tester, Scaffold(body: HudChips(snapshot: w.snapshot)),
        world: w);
    await _openMood(tester);
    final Finder dialog =
        find.byKey(const ValueKey<String>('hud:explain:happiness'));
    expect(
        find.descendant(
            of: dialog, matching: find.textContaining('$_name в обычном')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('{')),
        findsNothing);
  });

  test('«Финни» остаётся именем по умолчанию', () {
    expect(OnboardingProgress.defaultFinniName, 'Финни');
    // Пустое имя — «Финни» (шаг облика: «Имя можно оставить «Финни»»).
    expect(contentScript.t('look_help'), contains('«Финни»'));
    expect(const OnboardingProgress().finniName, 'Финни');
  });
}
