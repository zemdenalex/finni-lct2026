import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Реплика Финни в сценках знакомства — облачком над ним (Денис 20.10: «на
/// шаге 3 и дальше надо, чтобы было написано не сбоку, а облачко над
/// Финни»).
///
/// Защищает: в каждой реплике разговора облачко стоит в комнате, над
/// головой Финни (не закрывает его ниже макушки), целиком на экране и не
/// заходит на «Дальше» — на телефоне, в альбомной и на широком экране, при
/// шрифте 1,3 с настоящим шрифтом.
///
/// Уронит: реплика вернулась в боковую панель (облачка нет в комнате),
/// облачко сползло на Финни или за край, налезло на кнопку.
///
/// Почему не ловят другие тесты: `world_onboarding_screen_test` проверяет
/// текст и порядок реплик, но не где они на экране.
void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry<String, Size> size in <String, Size>{
    '360×640': portrait,
    '640×360': landscape,
    '1280×760': const Size(1280, 760),
  }.entries) {
    testWidgets('облачко над Финни во всех репликах · ${size.key} · ×1,3',
        (WidgetTester tester) async {
      rootBundle.clear();
      final World world = contentWorld(
          onboarding: const OnboardingProgress(
              step: OnboardingProgress.stepMoney, nickname: 'Звёздочка'));
      ok(world.startWeek());
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const WorldOnboardingScreen(),
            world: world, size: size.value, textScale: 1.3);
        for (int i = 0; i < 12; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      final Finder next = find.byKey(const ValueKey<String>('onboarding-next'));
      final Finder bubble = find.byKey(const ValueKey<String>('finni:bubble'));
      final Finder finni = find.byKey(const ValueKey<String>('room:finni'));
      final Finder stage =
          find.byKey(const ValueKey<String>('onboarding:stage'));
      int talks = 0;
      for (int guard = 0;
          guard < 20 &&
              find.byKey(const ValueKey<String>('plus:need')).evaluate().isEmpty;
          guard++) {
        // Финни дошёл до предмета, облачко встало за ним.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(bubble, findsOneWidget, reason: 'реплика $talks — облачком');
        final Rect b = tester.getRect(bubble);
        final Rect f = tester.getRect(finni);
        final Rect room = tester.getRect(stage);
        final Rect n = tester.getRect(next);
        // Телефон, конверты: комнате мало места — облачко над конвертами
        // (портрет: хвостиком вверх, альбомная: влево к Финни).
        if (size.value.width < 1000 &&
            find
                .byKey(const ValueKey<String>('envelope:need'))
                .evaluate()
                .isNotEmpty) {
          expect(b.overlaps(room), isFalse,
              reason: 'облачко $b в панели, не в комнате $room');
          // Узкая панель при ×1,3 прокручивается: начало реплики видно.
          expect(b.top, lessThan(n.top));
          expect(
              find
                  .byKey(const ValueKey<String>('envelope:need'))
                  .evaluate()
                  .isNotEmpty,
              isTrue);
          talks++;
          await tester.tap(next);
          await tester.pump();
          continue;
        }
        expect(b.left, greaterThanOrEqualTo(room.left - 0.5),
            reason: 'реплика $talks: облачко $b в комнате $room');
        expect(b.right, lessThanOrEqualTo(room.right + 0.5));
        // Над комнатой в портрете — полоса под облачко: не выше шапки.
        expect(
            b.overlaps(tester.getRect(
                find.byKey(const ValueKey<String>('onboarding:steps')))),
            isFalse,
            reason: 'облачко не на шапке шагов');
        expect(b.top, greaterThanOrEqualTo(0));
        expect(b.bottom, lessThanOrEqualTo(room.bottom + 0.5));
        // Хвостик — к макушке: облачко не закрывает лицо (верхняя четверть
        // кадра спрайта — листья над головой).
        expect(b.bottom, lessThanOrEqualTo(f.top + f.height * 0.25),
            reason: 'реплика $talks: облачко $b над Финни $f');
        expect(b.overlaps(n), isFalse,
            reason: 'реплика $talks: облачко $b не на «Дальше» $n');
        talks++;
        await tester.tap(next);
        await tester.pump();
      }
      final int expected = contentScript.scenes
          .where((OnboardingScene s) => s.kind == SceneKind.talk)
          .fold<int>(0, (int a, OnboardingScene s) => a + s.lines.length);
      expect(talks, expected, reason: 'все реплики разговора пройдены');
    });
  }
}
