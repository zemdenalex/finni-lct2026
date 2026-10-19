import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/jobs/shift_choice_view.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Флаг экрана `day_cycle.shift_choices_ui` и подсказка варианта словами.
///
/// Защищает: в сборке флаг включён, без ключа — выключен; выключенный флаг
/// возвращает прежний экран даже при вопросе у смены; подсказка словами
/// (`effectHint`) заменяет значки под подписью и читается TalkBack.
/// Уронит: флаг читается не из того места или по умолчанию true; экран
/// показывает вопрос мимо флага; подсказка теряется или дублирует значки.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldContent _content(String economy) => WorldContent.parse(
    economy: economy, jobs: _read('jobs.json'), events: _read('events.json'));

void main() {
  test('сборка: флаг включён; нет ключа — выключен', () {
    expect(shippedDayContent.economy.shiftChoicesUi, isTrue);
    expect(contentJobGames.shiftChoicesUi, isTrue,
        reason: 'экраны тестов видят флаг как в релизе');
    final Map<String, Object?> eco =
        jsonDecode(_read('economy.json')) as Map<String, Object?>;
    final Map<String, Object?> dc = <String, Object?>{
      ...(eco['day_cycle']! as Map<String, Object?>)
    }..remove('shift_choices_ui');
    eco['day_cycle'] = dc;
    expect(_content(jsonEncode(eco)).economy.shiftChoicesUi, isFalse);
  });

  testWidgets('флаг выключен: у смены вопрос, а экран прежний',
      (WidgetTester tester) async {
    final World w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    if (w.pendingEvent case final PendingEvent e) {
      ok(w.resolveEvent(
          e.choices.firstWhere((PendingEventChoice c) => c.available).id));
    }
    ok(w.demoUnlockAllJobs());
    String? job;
    for (int i = 0; i < 40 && job == null; i++) {
      for (final JobOffer o in w.jobBoard) {
        if (o.choice != null && o.blockReason == null && o.variant == null) {
          job = o.jobId;
          break;
        }
      }
      if (job == null) ok(w.depositToGoal(1));
    }
    expect(job, isNotNull, reason: 'нужна смена с вопросом');
    final JobGames off = JobGames.fromData(shippedContent.jobData,
        university: shippedContent.university);
    expect(off.shiftChoicesUi, isFalse);
    await pumpWorldScreen(tester, JobPlayScreen(args: JobPlayArgs(job!)),
        world: w, games: off);
    expect(find.byKey(const ValueKey<String>('job:choice')), findsNothing);
    expect(find.byKey(const ValueKey<String>('job:start')), findsOneWidget);
  });

  group('подсказка варианта словами', () {
    const JobOffer offer = JobOffer(
      jobId: 'courier',
      title: 'Курьер',
      basePay: 100,
      experiencePercent: 0,
      stageStep: 1,
      pay: 100,
      efficiencyBonusMax: 20,
      energyCost: 4,
      shiftsLeft: 3,
      goodScoreMin: 0.8,
      goodEnergyExtra: 0,
      goodHappiness: 0,
    );
    const ShiftChoice q = ShiftChoice(
      id: 'courier_extra',
      work: 'courier',
      question: 'По пути есть ещё один заказ.',
      options: <ShiftChoiceOption>[
        ShiftChoiceOption(
            id: 'take', label: 'Взять заказ', payX: 1.25, energy: 3),
        ShiftChoiceOption(id: 'one', label: 'Сначала этот'),
      ],
    );

    Future<void> pump(
        WidgetTester tester, String? Function(ShiftChoiceOption) hintOf) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: WorldTheme(
          child: Scaffold(
            body: ShiftChoiceBlock(
                offer: offer, question: q, onPick: (_) {}, hintOf: hintOf),
          ),
        ),
      ));
    }

    // Ревью (17.10): слова не заменяют числа.
    testWidgets('есть подсказка — под подписью слова и значки',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await pump(
          tester,
          (ShiftChoiceOption o) =>
              o.id == 'take' ? 'больше монет, но меньше сил' : null);
      final Finder take = find.byKey(const ValueKey<String>('job:choice:take'));
      expect(
          find.descendant(
              of: take, matching: find.text('больше монет, но меньше сил')),
          findsOneWidget);
      expect(find.descendant(of: take, matching: find.byType(PicText)),
          findsOneWidget);
      final String said = tester.getSemantics(take).label;
      expect(said, startsWith('Взять заказ. больше монет, но меньше сил.'));
      expect(said, contains('Монеты +'));
      // У варианта без подсказки — значки.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey<String>('job:choice:one')),
              matching: find.byType(Text)),
          findsOneWidget,
          reason: '«Сначала этот» ничего не меняет — только подпись');
      h.dispose();
    });

    testWidgets('нет подсказки — последствия числами',
        (WidgetTester tester) async {
      await pump(tester, shiftChoiceHint);
      final Finder take = find.byKey(const ValueKey<String>('job:choice:take'));
      expect(
          tester
              .widget<PicText>(
                  find.descendant(of: take, matching: find.byType(PicText)))
              .text,
          '+25 💰 · −3 ⚡');
    });
  });
}
