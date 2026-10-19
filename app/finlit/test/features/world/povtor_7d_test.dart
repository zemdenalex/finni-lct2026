import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Находки повторного прохода «путь ребёнка» на rc-7d (17.10, n1–n4,
/// `docs/final/put-rebenka/povtor-rc-7d.md`).

WorldGame _living() {
  final WorldGame w = contentDayWorld();
  ok(w.startWeek());
  ok(w.plan(needs: 100, wants: 100, goal: 0));
  ok(w.demoUnlockAllJobs());
  return w;
}

void main() {
  setUpAll(loadAppFonts);

  // n1. Уронит: при шрифте 1,3 «эффективность» рядом с «до 30» снова
  // переносится по буквам («эффективност / ь»).
  testWidgets('карточка смены, 360 × 1,3: «эффективность» целиком в строке',
      (WidgetTester tester) async {
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('consultant')),
        world: _living(), textScale: 1.3);
    final Finder label = find.textContaining('эффективность');
    expect(label, findsOneWidget);
    final RenderParagraph p = tester.renderObject<RenderParagraph>(label);
    final String text = p.text.toPlainText();
    final int start = text.indexOf('эффективность');
    final List<TextBox> boxes = p.getBoxesForSelection(TextSelection(
        baseOffset: start, extentOffset: start + 'эффективность'.length));
    expect(boxes.map((TextBox b) => b.top).toSet(), hasLength(1),
        reason: 'слово на одной строке');
    expect(p.textScaler.scale(p.text.style?.fontSize ?? 14),
        greaterThanOrEqualTo(14),
        reason: 'не мельче 14 sp');
  });

  // n2. Уронит: без цели строка цели в HUD комнаты снова режется («цель
  // не в…») в одном ряду с «День N из 7» и «в копилке N».
  for (final double scale in <double>[1.0, 1.3]) {
    testWidgets('комната без цели, 360 × $scale: подпись цели не обрезана',
        (WidgetTester tester) async {
      final WorldGame w = _living();
      expect(w.snapshot.activeGoalId, isNull, reason: 'настройка: цели нет');
      await pumpWorldScreen(tester, const RoomScreen(),
          world: w, textScale: scale);
      final Finder t = find.descendant(
          of: find.byKey(const ValueKey<String>('room:goal')),
          // Макет Алины: цель — двумя строками во втором ряду HUD, место
          // есть и для полной фразы.
          matching:
              find.textContaining(RegExp('^(без цели|цель не выбрана)\$')));
      expect(t, findsOneWidget);
      expect(
          tester.renderObject<RenderParagraph>(t).didExceedMaxLines, isFalse);
    });
  }

  // n3 (и дефект 7). Уронит: объяснение настроения снова не говорит, что
  // настроение меняет оплату и силы, или расходится с типами работ.
  test('«Почему меняется настроение»: типы работ и что оно меняет', () {
    final String why = explainFor(_living()).moodWhy!;
    for (final String part in <String>[
      'интересная работа с монетами радует',
      'нудная огорчает',
      'весёлая радует',
      'однообразная огорчает',
      'больше платят',
      'меньше уходит сил',
    ]) {
      expect(why, contains(part));
    }
  });

  // n4. Уронит: строки сна снова говорят о Финни в мужском роде (правило 5А)
  // или со значком ⚡ посреди фразы.
  test('сон: без рода и без значка посреди фразы', () {
    final WorldGame w = _living();
    final WorldResult night = ok(w.sleep());
    expect(night.reasonCode, 'day.next');
    expect(night.reason, contains('Силы после сна'));
    final RegExp gendered = RegExp(r'выспался|лёг спать|голоден|устал\b');
    expect(night.reason, isNot(matches(gendered)));
    expect(night.reason, isNot(contains('⚡')));
    expect(w.snapshot.moodReason.text, isNot(matches(gendered)));
  });
}
