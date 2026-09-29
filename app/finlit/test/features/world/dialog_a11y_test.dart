import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:finlit/features/world/shop/pet_shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/tap_target_guideline.dart';
import '../../support/text_floor.dart';
import '../../support/world_harness.dart';

/// Что открыть: экран, мир под ним и ключ кнопки, которая открывает
/// диалог или лист.
typedef _Opened = (Widget screen, World Function(WorldKind) world, String tap);

World _living(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 250, wants: 0, goal: 0));
  return w;
}

/// Карманные ещё не разложены — «План» открывает лист.
World _planning(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  return w;
}

/// Всё в копилке — рыбка по карману, покупка спрашивает подтверждения.
World _saved(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
  return w;
}

/// Неделя закрыта, на счета не хватает, в копилке есть — итоги предлагают
/// взять из копилки.
World _short(WorldKind kind) {
  final World w = _living(kind);
  ok(w.sleep());
  return w;
}

/// Главные диалоги и листы мира — то, что ребёнок открывает чаще всего.
final Map<String, _Opened> _dialogs = <String, _Opened>{
  // До плана «Сейчас: план недели» открывает лист плана.
  'лист «План недели»': (const RoomScreen(), _planning, 'room:now'),
  'подсказка HUD «Монеты»': (const RoomScreen(), _living, 'hud:coins'),
  'подсказка «?» комнаты': (const RoomScreen(), _living, 'room:help'),
  '«Лечь спать?»': (const RoomScreen(), _living, 'room:bed'),
  'покупка питомца': (const PetShopScreen(), _saved, 'buy:pet_fish'),
  'итоги: «Взять из копилки?»': (
    const WeekReviewScreen(),
    _short,
    'review:pay_goal'
  ),
  'лист-подсказка онбординга': (
    const WorldOnboardingScreen(),
    (WorldKind k) => k.make(),
    'onboarding:help'
  ),
};

/// ТЗ 3.6.3 и 3.6.4 — и за начальным состоянием экрана: в открытом диалоге
/// или листе цели касания ≥ 48 dp (в том числе у края экрана) и текст не
/// мельче [textFloor].
///
/// Ловит: кнопку диалога без своего `minimumSize` — `TextButton` Material
/// по умолчанию 40 dp в высоту; подпись, ужатую в листе. `tap_targets_test`
/// и `text_size_test` смотрят только начальное состояние экранов.
void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  forEachWorld((WorldKind kind) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final MapEntry<String, _Opened> d in _dialogs.entries) {
        testWidgets('${d.key} · ${o.key}: цели ≥ 48 dp, текст ≥ $textFloor',
            (WidgetTester tester) async {
          final SemanticsHandle sem = tester.ensureSemantics();
          final (Widget screen, World Function(WorldKind) world, String tap) =
              d.value;
          await tester.runAsync(() async {
            await pumpWorldScreen(tester, screen,
                world: world(kind), size: o.value);
            for (int i = 0; i < 8; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              await tester.pump();
            }
          });
          final Finder opener = find.byKey(ValueKey<String>(tap));
          await tester.ensureVisible(opener);
          await tester.pump();
          await tester.tap(opener);
          // Спрайты анимируются бесконечно — pumpAndSettle не дождётся.
          // Кровать: Финни сначала доходит до неё (RoomScene.roomWalk).
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
          // Без этого промах мимо кнопки проверил бы сам экран — зелёным.
          expect(
              find.byType(AlertDialog).evaluate().length +
                  find.byType(BottomSheet).evaluate().length,
              1,
              reason: 'диалог или лист не открылся');

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(edgeTapTargetGuideline));
          final List<String> small = textsBelowFloor(tester);
          expect(small, isEmpty, reason: 'мелкий текст: $small');
          sem.dispose();
        });
      }
    }
  });
}
