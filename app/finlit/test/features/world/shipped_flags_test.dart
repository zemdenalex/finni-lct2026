import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/theme.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/achievements/achievements_screen.dart';
import 'package:finlit/features/world/city/city_guide.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/screen_flags.dart';
import 'package:finlit/features/world/tutorial/tutorial_gate.dart';
import 'package:finlit/features/world/tutorial/tutorial_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Ответы Дениса 18.10 (тема 118) — флаги сборки в `economy.json`:
/// DEN-4 T1 `day_cycle.tutorial_ui`, DEN-35 B `day_cycle.xp_stages`, DEN-6 A
/// `achievements_days`, DEN-25 A `room.pet_name`, DEN-30 A
/// `city.label_scale`. Не включаются: `adult.weekly_bonus` (DEN-27 —
/// раздел взрослого убирают), `day_cycle.mood_pay_daily` (заменит DEN-36),
/// `room.customize`.
///
/// Защищает: каждый флаг в собранном мире включён, его поведение видно на
/// экране (обучалка — первый шаг, у работ 3 ступени, наград 18, имя над
/// Финни, подпись города — радиус шкалы); значения по умолчанию в коде (нет
/// ключа) = файл. Уронит: флаг выключили в файле или в одной из двух копий,
/// загрузчик перестал его читать, `main.dart` не передаёт его экрану.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

Map<String, Object?> _eco() =>
    jsonDecode(_read('economy.json')) as Map<String, Object?>;

Map<String, Object?> _sec(Map<String, Object?> e, String k) =>
    e[k]! as Map<String, Object?>;

WorldContent _parse(Map<String, Object?> e) => WorldContent.parse(
      economy: jsonEncode(e),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
      roomItems: _read('room_items.json'),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 20));
    }
  });
}

WorldGame _living({String name = 'Бублик'}) {
  final WorldGame w = contentDayWorld(
      onboarding: OnboardingProgress(
          step: OnboardingProgress.stepDone, finniName: name));
  if (w.phase == WeekPhase.weekStart || w.phase == WeekPhase.onboarding) {
    ok(w.startWeek());
  }
  if (w.phase == WeekPhase.planning) {
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  }
  return w;
}

void main() {
  final EconomyContent eco = shippedDayContent.economy;

  tearDown(() {
    tutorialLook = TutorialLook.off;
    cityLabelScale = EconomyContent.cityLabelScaleDefault;
  });

  test('сборка: пять флагов включены, три — выключены', () {
    expect(eco.tutorialUi, isTrue, reason: 'DEN-4 T1');
    expect(eco.dayCycle.xpStages, isTrue, reason: 'DEN-35 B');
    expect(eco.achievementsDays, isTrue, reason: 'DEN-6 A');
    expect(shippedDayContent.room.petName, isTrue, reason: 'DEN-25 A');
    expect(eco.cityLabelScale, isTrue, reason: 'DEN-30 A');
    final Map<String, Object?> e = _eco();
    expect(_sec(e, 'adult')['weekly_bonus'], isFalse, reason: 'DEN-27');
    expect(_sec(e, 'day_cycle')['mood_pay_daily'], isFalse,
        reason: 'заменит DEN-36');
    expect(_sec(e, 'room')['customize'], isFalse);
    // Комната в изометрии (V2) — вид по умолчанию (Денис 20.10, «1 + 4»): в
    // сборке и в content/ — iso. Уронит: «front» в любой копии. Откат —
    // «front» в обеих копиях (фронтальная комната осталась в коде).
    expect(_sec(e, 'room')['view'], 'iso', reason: 'Денис 20.10: iso');
    expect(shippedDayContent.room.view, 'iso');
    expect(shippedDayContent.room.iso, isTrue);
    final Map<String, Object?> src =
        jsonDecode(File('../../content/economy.json').readAsStringSync())
            as Map<String, Object?>;
    expect(_sec(src, 'room')['view'], 'iso', reason: 'content/economy.json');
  });

  test('room.view: «iso» и «front» читаются, чужое значение — ошибка с путём',
      () {
    final Map<String, Object?> e = _eco();
    _sec(e, 'room')['view'] = 'iso';
    expect(_parse(e).room.iso, isTrue);
    _sec(e, 'room')['view'] = 'front';
    expect(_parse(e).room.iso, isFalse, reason: 'откат флагом');
    _sec(e, 'room')['view'] = 'side';
    expect(() => _parse(e), throwsA(isA<WorldContentError>()));
  });

  test('без ключа — значения по умолчанию в коде, они же файл', () {
    expect(EconomyContent.tutorialUiDefault, eco.tutorialUi);
    expect(EconomyContent.achievementsDaysDefault, eco.achievementsDays);
    expect(EconomyContent.cityLabelScaleDefault, eco.cityLabelScale);
    expect(RoomCatalog.petNameDefault, shippedDayContent.room.petName);
    expect(RoomCatalog.viewDefault, shippedDayContent.room.view);
    expect(EconomyContent.xpStagesDefault, eco.dayCycle.xpStages);
    final Map<String, Object?> e = _eco();
    _sec(e, 'day_cycle')
      ..remove('tutorial_ui')
      ..remove('xp_stages');
    e.remove('achievements_days');
    _sec(e, 'room')
      ..remove('pet_name')
      ..remove('view');
    e.remove('city');
    final WorldContent c = _parse(e);
    expect(c.economy.tutorialUi, EconomyContent.tutorialUiDefault);
    expect(c.economy.dayCycle.xpStages, EconomyContent.xpStagesDefault);
    expect(c.economy.achievementsDays, EconomyContent.achievementsDaysDefault);
    expect(c.room.petName, RoomCatalog.petNameDefault);
    expect(c.room.view, RoomCatalog.viewDefault);
    expect(c.economy.cityLabelScale, EconomyContent.cityLabelScaleDefault);
  });

  test('DEN-35 B: у работ ступеней по 3, ступень считается в собранном мире',
      () {
    final WorldGame w = _living();
    for (final String job in w.config.dayCycle.xpStageJobs) {
      expect(w.xpStage(job), 1, reason: '$job: ступень с первой смены');
    }
    final Map<String, Object?> jobs = (jsonDecode(_read('jobs.json'))
        as Map<String, Object?>)['jobs']! as Map<String, Object?>;
    for (final String job in w.config.dayCycle.xpStageJobs) {
      expect(((jobs[job]! as Map<String, Object?>)['stages']! as List<Object?>),
          hasLength(3),
          reason: job);
    }
  });

  test('DEN-6 A: наград в собранном мире 18 (12 + 6 под дни)', () {
    expect(contentDayConfig.achievementsDays, isTrue);
    expect(contentDayConfig.achievements, hasLength(18));
  });

  testWidgets('DEN-6 A: из «Прогресса» открывается экран наград',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, const HistoryScreen(), world: _living());
    final Finder button =
        find.byKey(const ValueKey<String>('history:achievements'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AchievementsScreen), findsOneWidget);
  });

  testWidgets('DEN-4 T1: первый заход в комнату — первый шаг обучалки',
      (WidgetTester tester) async {
    applyContentScreenFlags(eco);
    expect(tutorialLook, TutorialLook.spotlight);
    final WorldGame w = _living();
    expect(isFirstVisit(w), isTrue);
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const TutorialGate(child: RoomScreen()),
          world: w);
    });
    await _settle(tester);
    expect(find.byKey(const ValueKey<String>('tutorial:step:hello')),
        findsOneWidget);
  });

  testWidgets('DEN-25 A: имя ребёнка над Финни', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(),
          world: _living(name: 'Бублик'));
    });
    await _settle(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('finni:name')))
            .data,
        'Бублик');
  });

  testWidgets('DEN-30 A: подписи города — радиус шкалы, не пилюля',
      (WidgetTester tester) async {
    cityLabelScale = false;
    applyContentScreenFlags(eco);
    expect(cityLabelScale, isTrue);
    await pumpWorldScreen(tester, const CityScreen(), world: _living());
    await _settle(tester);
    final Finder labels = find.byWidgetPredicate((Widget w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('city:label:'));
    expect(labels, findsWidgets);
    for (final Element el in labels.evaluate()) {
      final DecoratedBox box = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byWidget(el.widget), matching: find.byType(DecoratedBox))
          .first);
      final BorderRadius r =
          (box.decoration as BoxDecoration).borderRadius! as BorderRadius;
      expect(r.topLeft.x, Radii.label);
    }
  });
}
