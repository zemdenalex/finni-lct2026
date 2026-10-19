import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/tutorial/tutorial_gate.dart';
import 'package:finlit/features/world/tutorial/tutorial_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Обучалка на комнате по макету Алины (alina-01, 18.10): верхняя строка
/// без плашки, золотая кнопка внизу справа, меню Дом · Город · План · Мой
/// путь · Ещё.
///
/// Защищает: на 360×640, 640×360, 768×1024 и 1440×900 при шрифте 1,0 и 1,3
/// каждый шаг светит свой предмет — его прямоугольник непустой и внутри
/// экрана; карточка шага целиком на экране, «Дальше» нажимается; реплика
/// не говорит про исчезнувшее («Сейчас:», ⋮). Уронит: цель шага уехала за
/// край или под меню, карточка не влезла (кнопка за экраном), в тексте
/// снова старый интерфейс.
void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

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
      for (int i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 20));
      }
    });
  }

  final Finder next = find.byKey(const ValueKey<String>('tutorial:next'));
  final RegExp oldUi = RegExp(r'Сейчас:|⋮');

  for (final Size size in const <Size>[
    Size(360, 640),
    Size(640, 360),
    Size(768, 1024),
    Size(1440, 900),
  ]) {
    for (final double scale in <double>[1.0, 1.3]) {
      final String s =
          '${size.width.toInt()}×${size.height.toInt()}, шрифт $scale';
      testWidgets('$s: каждый шаг светит свой предмет, карточка на экране',
          (WidgetTester tester) async {
        await tester.runAsync(() async {
          await pumpWorldScreen(
              tester,
              const TutorialGate(
                  look: TutorialLook.spotlight, child: RoomScreen()),
              world: firstVisit(),
              size: size,
              textScale: scale);
        });
        await settle(tester);
        final Rect screen = Offset.zero & size;
        for (final TutorialStep st in tutorialSteps) {
          final Finder card =
              find.byKey(ValueKey<String>('tutorial:step:${st.id}'));
          expect(card, findsOneWidget, reason: 'шаг ${st.id}');
          final String key = st.targets.firstWhere(
              (String k) =>
                  find.byKey(ValueKey<String>(k)).evaluate().isNotEmpty,
              orElse: () => '');
          expect(key, isNotEmpty, reason: 'цель шага ${st.id} есть');
          final Rect target =
              tester.getRect(find.byKey(ValueKey<String>(key)).first);
          expect(target.isEmpty, isFalse, reason: '${st.id}: $key $target');
          expect(
              screen.inflate(0.5).contains(target.topLeft) &&
                  screen.inflate(0.5).contains(target.bottomRight),
              isTrue,
              reason: '${st.id}: $key $target за экраном $screen');
          final Rect c = tester.getRect(card);
          expect(screen.inflate(0.5).contains(c.bottomRight), isTrue,
              reason: '${st.id}: карточка $c не влезла');
          expect(next.hitTestable(), findsOneWidget,
              reason: '${st.id}: «Дальше» не нажать');
          // «Пропустить» целиком: на 360 dp ×1,3 резалось до «Пропустит».
          expect(
              tester
                  .renderObject<RenderParagraph>(find.descendant(
                      of: find.byKey(const ValueKey<String>('tutorial:skip')),
                      matching: find.byType(RichText)))
                  .didExceedMaxLines,
              isFalse,
              reason: '${st.id}: «Пропустить» обрезано');
          final String text = <String>[
            for (final Element e in find
                .descendant(of: card, matching: find.byType(RichText))
                .evaluate())
              (e.widget as RichText).text.toPlainText(),
          ].join(' ');
          expect(oldUi.firstMatch(text)?.group(0), isNull,
              reason: '${st.id}: «$text»');
          await tester.tap(next);
          await settle(tester);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
