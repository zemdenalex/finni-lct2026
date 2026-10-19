import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/icons.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/achievements/achievements_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart';

/// Экран наград: все награды списком, у полученной видна
/// неделя выдачи, у остальных условие и прогресс. Открывается из «Прогресса»
/// только за флагом, по умолчанию выключен.
/// Уронит: экран не из снимка, получена и не получена выглядят одинаково,
/// кнопка видна при выключенном флаге или не ведёт на экран.
void main() {
  World withFirstShift() {
    final World w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 250, wants: 50, goal: 100));
    ok(w.completeJob('gardener', score: 1));
    return w;
  }

  // Первая смена после первого сна: награда `first_shift` выдана на дне 2.
  WorldGame dayWorldWithFirstShift() {
    final WorldGame d = contentDayWorld();
    ok(d.startWeek());
    ok(d.plan(needs: 0, wants: 0, goal: 0));
    ok(d.sleep());
    final JobOffer o = d.jobBoard.firstWhere((JobOffer j) => !j.blocked);
    ok(d.completeJob(o.jobId, variant: o.variant, score: 1));
    return d;
  }

  AchievementView view(World w, String id) =>
      w.snapshot.achievements.firstWhere((AchievementView v) => v.def.id == id);

  group('тексты строк', () {
    test('условие невыданной награды с прогрессом, выданной без него', () {
      final World w = withFirstShift();
      final AchievementView open = view(w, 'good_shifts_5');
      expect(
        AchievementsScreen.conditionLine(open),
        '${open.def.hint} · ${open.progress} из ${open.target}',
      );
      final AchievementView done = view(w, 'first_shift');
      expect(AchievementsScreen.conditionLine(done), done.def.hint);
    });

    test('неделя выдачи есть только у полученной', () {
      final World w = withFirstShift();
      final AchievementView done = view(w, 'first_shift');
      expect(
        AchievementsScreen.earnedLine(done),
        'Получено на неделе ${done.earnedWeek}',
      );
      expect(AchievementsScreen.earnedLine(view(w, 'own_pet')), isNull);
    });
  });

  testWidgets('список: выданные и невыданные, условие, неделя выдачи', (
    WidgetTester tester,
  ) async {
    final World w = withFirstShift();
    await pumpWorldScreen(tester, const AchievementsScreen(), world: w);

    final int total = w.snapshot.achievements.length;
    final int got = w.snapshot.achievements
        .where((AchievementView v) => v.status == AchievementStatus.earned)
        .length;
    expect(got, greaterThan(0));
    expect(find.text('Получено $got из $total'), findsOneWidget);

    final AchievementView done = view(w, 'first_shift');
    Finder pic(Pic p) => find.byWidgetPredicate(
          (Widget x) => x is Pictogram && x.pic == p,
        );
    Finder inTile(String id, Finder f) => find.descendant(
          of: find.byKey(ValueKey<String>('achievements:$id')),
          matching: f,
        );
    // Значок награды — рисунок, а не эмодзи (на Android 8 и в браузере
    // эмодзи рисуется по-разному или пусто): в тексте его нет.
    expect(
      inTile('first_shift', find.textContaining(done.def.title)),
      findsOneWidget,
    );
    expect(inTile('first_shift', pic(Pic.trophy)), findsOneWidget);
    expect(inTile('first_shift', find.textContaining('🏆')), findsNothing);
    expect(
      inTile('first_shift', find.text('Получено на неделе ${done.earnedWeek}')),
      findsOneWidget,
    );

    final AchievementView open = view(w, 'streak_no_family_3');
    final Finder tile = find.byKey(
      const ValueKey<String>('achievements:streak_no_family_3'),
    );
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('achievements:list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      inTile('streak_no_family_3', find.textContaining(open.def.title)),
      findsOneWidget,
    );
    expect(inTile('streak_no_family_3', pic(Pic.lock)), findsOneWidget);
    expect(
      inTile('streak_no_family_3', find.textContaining('🔒')),
      findsNothing,
    );
    expect(
      inTile('streak_no_family_3', find.textContaining('из ${open.target}')),
      findsOneWidget,
    );
    expect(
      inTile('streak_no_family_3', find.textContaining('Получено на неделе')),
      findsNothing,
    );
  });

  group('день выдачи на экране', () {
    Finder firstShiftCaption(String text) => find.descendant(
          of: find.byKey(const ValueKey<String>('achievements:first_shift')),
          matching: find.text(text),
        );

    testWidgets('запись с args.day: день и неделя', (
      WidgetTester tester,
    ) async {
      final WorldGame d = dayWorldWithFirstShift();
      final AchievementView done = view(d, 'first_shift');
      expect(done.earnedDay, 2);
      await pumpWorldScreen(tester, const AchievementsScreen(), world: d);
      expect(
        firstShiftCaption('Получено: день 2 недели ${done.earnedWeek}'),
        findsOneWidget,
      );
    });

    testWidgets('запись без args.day: только неделя', (
      WidgetTester tester,
    ) async {
      final WorldGame d = dayWorldWithFirstShift();
      final List<Object?> json =
          jsonDecode(jsonEncode(d.toJson())) as List<Object?>;
      for (final Object? e in json) {
        final Object? args = (e! as Map<String, Object?>)['args'];
        if (args is Map<String, Object?>) args.remove('day');
      }
      final WorldGame old = WorldGame.fromJson(json, config: d.config);
      final AchievementView done = view(old, 'first_shift');
      expect(done.earnedDay, isNull);
      await pumpWorldScreen(tester, const AchievementsScreen(), world: old);
      expect(
        firstShiftCaption('Получено на неделе ${done.earnedWeek}'),
        findsOneWidget,
      );
    });
  });

  group('вход из «Прогресса»', () {
    test('отдельного маршрута у наград нет', () {
      expect(worldRoutes.keys, isNot(contains('/w/achievements')));
    });

    // Экран наград — за тем же флагом `achievements_days` в economy.json, что
    // включает награды дней; отдельного флага сборки нет (баг-прогон 18.10:
    // без `--dart-define=ACHIEVEMENTS_SCREEN=true` флаг из файла был не виден
    // игроку). Уронит: кнопка снова только от флага сборки или видна при
    // выключенном флаге.
    for (final bool on in <bool>[false, true]) {
      testWidgets(
          'economy.json achievements_days = $on: кнопка «Награды» '
          '${on ? 'открывает экран' : 'не видна'}',
          (WidgetTester tester) async {
        final WorldConfig c =
            (await tester.runAsync(() => loadWorldConfig((String p) async {
                  final String s = await File(p).readAsString();
                  if (!p.endsWith('economy.json')) return s;
                  final Map<String, Object?> e =
                      jsonDecode(s) as Map<String, Object?>;
                  e['achievements_days'] = on;
                  return jsonEncode(e);
                })))!;
        final WorldGame w = WorldGame(config: c);
        ok(w.startWeek());
        ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
        await pumpWorldScreen(tester, const HistoryScreen(), world: w);
        final Finder button =
            find.byKey(const ValueKey<String>('history:achievements'));
        expect(button, on ? findsOneWidget : findsNothing);
        if (!on) return;
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(AchievementsScreen), findsOneWidget);
      });
    }

    testWidgets('флаг выключен: кнопки нет', (WidgetTester tester) async {
      await pumpWorldScreen(tester, const HistoryScreen());
      expect(
        find.byKey(const ValueKey<String>('history:achievements')),
        findsNothing,
      );
    });

    testWidgets('флаг включён: кнопка открывает награды и ведёт назад', (
      WidgetTester tester,
    ) async {
      await pumpWorldScreen(
        tester,
        const HistoryScreen(showAchievements: true),
        world: withFirstShift(),
      );
      final Finder button = find.byKey(
        const ValueKey<String>('history:achievements'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(AchievementsScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('achievements:back')));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementsScreen), findsNothing);
      expect(find.byType(HistoryScreen), findsOneWidget);
    });
  });

  // DEN-32: награда с баффом говорит, что даёт; без баффа строки нет.
  // Уронит: строка не показана, бафф назван не тем числом или днём.
  group('что даёт награда', () {
    test('строки баффов', () {
      expect(
          AchievementsScreen.effectLine(const MoodBuff(happiness: 3, days: 3)),
          'Даёт +3 😊 на 3 дня');
      expect(
          AchievementsScreen.effectLine(const MoodBuff(happiness: 2, days: 1)),
          'Даёт +2 😊 на 1 день');
      expect(AchievementsScreen.effectLine(const EnergyMaxBuff(value: 1)),
          'Даёт +1 ⚡ к запасу сил навсегда');
      expect(AchievementsScreen.effectLine(null), isNull);
    });

    for (final Size size in const <Size>[Size(360, 640), Size(640, 360)]) {
      testWidgets(
          'экран: строка у наград с баффом, шрифт 1,3 · '
          '${size.width.toInt()}×${size.height.toInt()}',
          (WidgetTester tester) async {
        final WorldConfig c =
            (await tester.runAsync(() => loadWorldConfig((String p) async {
                  final String s = await File(p).readAsString();
                  if (!p.endsWith('economy.json')) return s;
                  final Map<String, Object?> e =
                      jsonDecode(s) as Map<String, Object?>;
                  e['achievements_days'] = true;
                  return jsonEncode(e);
                })))!;
        final WorldGame w = WorldGame(config: c);
        ok(w.startWeek());
        ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
        await pumpWorldScreen(tester, const AchievementsScreen(),
            world: w, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
        final AchievementDef days7 =
            c.achievements.singleWhere((AchievementDef d) => d.id == 'days_7');
        final Finder line =
            find.byKey(const ValueKey<String>('achievements:effect:days_7'));
        await tester.scrollUntilVisible(line, 200,
            scrollable: find.descendant(
                of: find.byKey(const ValueKey<String>('achievements:list')),
                matching: find.byType(Scrollable)));
        expect(line, findsOneWidget);
        expect(AchievementsScreen.effectLine(days7.effect), contains('⚡'));
        expect(
            find.byKey(
                const ValueKey<String>('achievements:effect:first_shift')),
            findsNothing,
            reason: 'у наград без баффа строки нет');
      });
    }
  });
}
