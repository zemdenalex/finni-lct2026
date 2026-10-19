import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/tutorial/tutorial_gate.dart';
import 'package:finlit/features/world/tutorial/tutorial_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// C4 / DEN-4 (Денис 18.10 выбрал T1): обучалка первого
/// захода включается флагом `economy.json → day_cycle.tutorial_ui`, как
/// `explain_ui` и `shift_choices_ui`. В сборке — true (Денис 18.10, T1). Защищает: флаг
/// выключен — обучалки нет; включён — вид T1, первый шаг на первом заходе в
/// комнату, после первого дела — нет. Уронит: флаг не читается из файла,
/// включает не тот вид или обучалка показывается без флага.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

bool _parsed({bool? on}) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  if (on != null) {
    e['day_cycle'] = <String, Object?>{
      ...(e['day_cycle']! as Map<String, Object?>),
      'tutorial_ui': on,
    };
  }
  return WorldContent.parse(
    economy: jsonEncode(e),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  ).economy.tutorialUi;
}

void main() {
  tearDown(() => tutorialLook = TutorialLook.off);

  test('флаг из файла: в сборке включён (DEN-4 T1), выключенный читается', () {
    expect(_parsed(), isTrue);
    expect(_parsed(on: false), isFalse);
    expect(_parsed(on: true), isTrue);
    expect(tutorialLookFor(tutorialUi: false), TutorialLook.off);
    expect(tutorialLookFor(tutorialUi: true), TutorialLook.spotlight);
  });

  WorldGame firstVisit() {
    final WorldGame w = contentDayWorld(
        onboarding:
            const OnboardingProgress(step: OnboardingProgress.stepDone));
    if (w.phase == WeekPhase.weekStart || w.phase == WeekPhase.onboarding) {
      ok(w.startWeek());
    }
    if (w.phase == WeekPhase.planning) {
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    }
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

  final Finder hello =
      find.byKey(const ValueKey<String>('tutorial:step:hello'));

  for (final bool on in <bool>[true, false]) {
    testWidgets('tutorial_ui=$on: первый заход в комнату (режим дней)',
        (WidgetTester tester) async {
      tutorialLook = tutorialLookFor(tutorialUi: _parsed(on: on));
      final WorldGame w = firstVisit();
      expect(isFirstVisit(w), isTrue);
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const TutorialGate(child: RoomScreen()),
            world: w);
      });
      await settle(tester);
      expect(hello, on ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('флаг включён, но первое дело сделано — обучалки нет',
      (WidgetTester tester) async {
    tutorialLook = tutorialLookFor(tutorialUi: true);
    final WorldGame w = firstVisit();
    ok(w.completeJob('cashier', score: 1));
    expect(isFirstVisit(w), isFalse);
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const TutorialGate(child: RoomScreen()),
          world: w);
    });
    await settle(tester);
    expect(hello, findsNothing);
  });
}
