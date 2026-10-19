import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:finlit/features/world/demo/world_checklist.dart';
import 'package:finlit/features/world/demo/world_demo_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// DEN-27 (Денис 18.10, тема 118: «Взрослых мы вообще убираем пока как
/// раздел»), флаг `economy.json → adult.section`.
///
/// Защищает: в сборке входа «Взрослым» в меню комнаты нет; в «Настройках» —
/// «Начать игру заново» за примером на умножение (ТЗ §3.5.5) и с тем же
/// подтверждением («Отмена» ничего не стирает, «Стереть и начать» — снова
/// знакомство) и «Режим проверки» за тем же примером (ТЗ §2.5, демо-режим),
/// который открывает все профессии; ни один из этих барьеров не отмечает в
/// чек-листе «Раздел взрослого открыт»; при `adult.section` true — всё как
/// раньше. Уронит: вход в раздел остался, сброс без примера, без
/// подтверждения или без возврата к знакомству, режим проверки без барьера
/// или пропал, флаг не читается из файла.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Мир из файлов сборки; [section] — подменить флаг, null — как в файле.
WorldGame _world({bool? section, bool week = false}) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  if (section != null) {
    e['adult'] = <String, Object?>{
      ...(e['adult']! as Map<String, Object?>),
      'section': section,
    };
  }
  final String eco = jsonEncode(e);
  return WorldGame(
    config: worldConfigFromContent(WorldContent.parse(
      economy: week ? weekMode(eco) : eco,
      jobs: _read('jobs.json'),
      events: _read('events.json'),
      roomItems: _read('room_items.json'),
    )),
  );
}

Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<AppState> _booted(WidgetTester tester) async {
  final AppState app = AppState(MemoryStorage());
  await tester.runAsync(app.boot);
  return app;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _step(tester);
}

/// Верный ответ на пример барьера.
Future<void> _solve(WidgetTester tester) async {
  final String q =
      tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
  await tester.enterText(find.byKey(WorldAdultScreen.answerKey),
      '${WorldAdultScreen.answerOf(q)}');
  await _tap(tester, find.byKey(const ValueKey<String>('adult:enter')));
  await _step(tester);
}

void main() {
  setUp(() {
    rootBundle.clear();
    WorldDemoSession.clear();
  });

  test('сборка: adult.section = false', () {
    final Map<String, Object?> e =
        jsonDecode(_read('economy.json')) as Map<String, Object?>;
    expect((e['adult']! as Map<String, Object?>)['section'], isFalse);
  });

  for (final bool section in <bool>[false, true]) {
    testWidgets(
        'adult.section = $section: «Взрослым» в меню комнаты '
        '${section ? 'есть' : 'нет'}', (WidgetTester tester) async {
      final WorldGame w = _world(section: section ? true : null, week: true);
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 100, goal: 50));
      await tester.runAsync(() => pumpWorldScreen(tester, const RoomScreen(),
          world: w, size: landscape));
      await tester.pump();
      await _tap(tester, find.byKey(const ValueKey<String>('room:menu')));
      expect(find.byKey(const ValueKey<String>('room:adult')),
          section ? findsOneWidget : findsNothing);
      expect(
          find.byKey(const ValueKey<String>('room:settings')), findsOneWidget);
    });

    testWidgets(
        'adult.section = $section: в «Настройках» сброс и режим проверки '
        '${section ? 'нет (они во «Взрослым»)' : 'есть'}',
        (WidgetTester tester) async {
      final AppState app = await _booted(tester);
      await pumpWorldScreen(tester, const WorldSettingsScreen(),
          world: _world(section: section ? true : null),
          app: app,
          size: const Size(360, 1400));
      expect(find.byKey(const ValueKey<String>('settings:reset')),
          section ? findsNothing : findsOneWidget);
      expect(find.byKey(const ValueKey<String>('settings:demo')),
          section ? findsNothing : findsOneWidget);
      expect(find.textContaining('в разделе «Взрослым»'),
          section ? findsOneWidget : findsNothing,
          reason: 'текст не отправляет в раздел, которого нет');
    });
  }

  // Ловит (ТЗ §3.5.5): «Начать игру заново» в настройках сразу открывает
  // подтверждение, без примера для взрослого, — ребёнок стирает прогресс
  // сам; или неверный ответ / «Назад» на барьере всё-таки ведут к сбросу.
  testWidgets(
      '«Начать игру заново» в настройках: сначала пример, «Отмена» — '
      'ничего, «Стереть и начать» — знакомство', (WidgetTester tester) async {
    final AppState app = await _booted(tester);
    final WorldGame w = _world(week: true);
    WorldAutopilot(w).playWeeks(2);
    final WorldState ws = await pumpWorldScreen(
        tester, const WorldSettingsScreen(),
        world: w, app: app, size: const Size(360, 1400));
    final int weeks = ws.snapshot.weekNo;
    expect(weeks, greaterThan(1));
    final Finder reset = find.byKey(const ValueKey<String>('settings:reset'));
    final Finder erase = find.text('Стереть и начать');

    // Барьер — тот же пример, что у «Режима проверки»; неверно — ни
    // подтверждения, ни сброса.
    await _tap(tester, reset);
    expect(find.byKey(WorldAdultScreen.questionKey), findsOneWidget,
        reason: 'сброс — только после примера для взрослого');
    expect(erase, findsNothing);
    await tester.enterText(find.byKey(WorldAdultScreen.answerKey), '1');
    await _tap(tester, find.byKey(const ValueKey<String>('adult:enter')));
    expect(erase, findsNothing);
    expect(find.byKey(WorldAdultScreen.questionKey), findsOneWidget);

    // «Назад» с барьера — обратно в настройки, ничего не стёрто.
    await _tap(tester, find.byKey(const ValueKey<String>('adult:back')));
    expect(find.byKey(WorldAdultScreen.questionKey), findsNothing);
    expect(erase, findsNothing);
    expect(reset, findsOneWidget);
    expect(ws.snapshot.weekNo, weeks);

    // Верный ответ — подтверждение; «Отмена» — снова настройки.
    await _tap(tester, reset);
    await _solve(tester);
    expect(find.text('Отмена'), findsOneWidget);
    expect(erase, findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await _step(tester);
    expect(ws.snapshot.weekNo, weeks, reason: '«Отмена» ничего не стирает');
    expect(reset, findsOneWidget);

    // Снова пример, «Стереть и начать» — знакомство.
    await _tap(tester, reset);
    expect(find.byKey(WorldAdultScreen.questionKey), findsOneWidget);
    await _solve(tester);
    await tester.runAsync(() async {
      await tester.tap(erase);
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await _step(tester);
    expect(ws.phase, WeekPhase.onboarding);
    expect(ws.snapshot.weekNo, 0);
    expect(find.byType(WorldOnboardingScreen), findsOneWidget);
    expect(WorldDemoSession.adultOpened, isFalse,
        reason: 'барьер сброса — не открытие раздела S14');
  });

  testWidgets(
      '«Режим проверки» в настройках — за примером, открывает все '
      'профессии', (WidgetTester tester) async {
    final AppState app = await _booted(tester);
    final WorldGame w = _world(week: true);
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 0, goal: 0));
    expect(w.offer('dog_walker')!.locked, isTrue);
    await pumpWorldScreen(tester, const WorldSettingsScreen(),
        world: w, app: app, size: const Size(360, 1400));
    await _tap(tester, find.byKey(const ValueKey<String>('settings:demo')));

    // Барьер — тот же пример, что у «Взрослым»; неверный ответ не пускает.
    expect(find.byKey(WorldAdultScreen.questionKey), findsOneWidget);
    expect(find.byType(WorldDemoScreen), findsNothing);
    await tester.enterText(find.byKey(WorldAdultScreen.answerKey), '1');
    await _tap(tester, find.byKey(const ValueKey<String>('adult:enter')));
    expect(find.byType(WorldDemoScreen), findsNothing);
    final String q =
        tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
    await tester.enterText(find.byKey(WorldAdultScreen.answerKey),
        '${WorldAdultScreen.answerOf(q)}');
    await _tap(tester, find.byKey(const ValueKey<String>('adult:enter')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WorldDemoScreen), findsOneWidget);
    // Ловит: барьер режима проверки отмечает в чек-листе «Раздел взрослого
    // открыт», хотя S14 не открывали (шаг 12 Приложения А).
    expect(WorldDemoSession.adultOpened, isFalse,
        reason: 'пройден барьер режима проверки, а не раздел S14');

    final Finder jobs = find.byKey(const ValueKey<String>('demo:jobs'));
    await tester.scrollUntilVisible(jobs, 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Открыть все профессии'), findsOneWidget);
    await _tap(tester, jobs);
    expect(w.offer('dog_walker')!.locked, isFalse);
  });

  testWidgets(
      'adult.section = true: раздел как раньше — пример, затем '
      '«Начать игру заново» во «Взрослым»', (WidgetTester tester) async {
    final WorldGame w = _world(section: true, week: true);
    ok(w.startWeek());
    await pumpWorldScreen(tester, WorldAdultScreen(random: Random(1)),
        world: w);
    expect(find.text('Взрослым'), findsOneWidget);
    final String q =
        tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
    await tester.enterText(find.byKey(WorldAdultScreen.answerKey),
        '${WorldAdultScreen.answerOf(q)}');
    await _tap(tester, find.byKey(const ValueKey<String>('adult:enter')));
    final Finder reset = find.byKey(const ValueKey<String>('adult:reset'));
    await tester.scrollUntilVisible(reset, 200,
        scrollable: find.byType(Scrollable).last);
    expect(reset, findsOneWidget);
    await _tap(tester, reset);
    expect(find.text('Стереть и начать'), findsOneWidget);
  });
}
