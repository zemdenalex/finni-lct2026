import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/features/world/onboarding/finni_bubble.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Первый экран знакомства (Денис 20.10 13:46: «экран, где слева Финни,
/// справа "привет я Финни, а как зовут тебя?" и там ввод ника игрока и выбор
/// внешнего вида Финни»).
///
/// Защищает: на одном первом экране Финни, его реплика облачком рядом с ним,
/// поле ника и плитки обликов; поле ника видно без прокрутки; облик,
/// выбранный плиткой, сразу виден у Финни на этом же экране и уходит в мир.
/// Уронит: старый первый экран (только «Как тебя зовут?» и поле, облик — на
/// втором шаге), реплика не рядом с Финни, превью не меняется от плитки.
/// Почему не ловят другие: `world_onboarding_screen_test` проверяет порядок
/// шагов и сохранение, но не раскладку экрана и не связь плитки с превью.

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// Финни экрана (не плитки: у плиток картинки, а не [SpriteAnim]).
Finder get _finni => find.byType(SpriteAnim);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Экран с настоящим реестром арта: он читается из бандла, поэтому под
/// runAsync, как в onboarding_bubble_test.
Future<WorldState> _pump(WidgetTester tester, Size size,
    {double textScale = 1}) async {
  late WorldState ws;
  // rootBundle кеширует Future из зоны прошлого теста — арт бы не пришёл.
  rootBundle.clear();
  await tester.runAsync(() async {
    ws = await pumpWorldScreen(tester, const WorldOnboardingScreen(),
        size: size, textScale: textScale);
    for (int i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await _settle(tester);
  return ws;
}

void main() {
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    for (final double scale in <double>[1, 1.3]) {
      testWidgets('${o.key} · шрифт ×$scale: Финни, облачко, ник и облик',
          (WidgetTester tester) async {
        await _pump(tester, o.value, textScale: scale);

        final Finder say = _key('onboarding:welcome:say');
        expect(say, findsOneWidget);
        expect(find.descendant(of: say, matching: find.textContaining('Финни')),
            findsOneWidget);
        expect(_finni, findsOneWidget, reason: 'Финни на первом экране');
        final Rect f = tester.getRect(_finni);
        final Rect b = tester.getRect(say);
        expect(f.center.dx, lessThan(b.left),
            reason: 'Финни слева от облачка: $f, $b');
        expect(find.byType(SpeechBubble), findsOneWidget);

        final Rect nick = tester.getRect(_key('onboarding-nick'));
        expect(nick.bottom, lessThanOrEqualTo(o.value.height),
            reason: 'поле ника видно без прокрутки: $nick');
        expect(_key('look:finni-a2:3'), findsOneWidget,
            reason: 'облик выбирают на этом же экране');
        final Rect tile = tester.getRect(_key('look:finni-a2:3'));
        expect(tile.height, greaterThanOrEqualTo(48));
        expect(_key('onboarding-finni-name'), findsNothing,
            reason: 'имя друга — на втором экране');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${o.key}: плитка облика меняет Финни на экране и в мире',
        (WidgetTester tester) async {
      final WorldState ws = await _pump(tester, o.value);
      final SpriteAnim before = tester.widget<SpriteAnim>(_finni);
      final Finder tile = _key('look:finni-a3:2');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await _settle(tester);
      final SpriteAnim after = tester.widget<SpriteAnim>(_finni);
      expect(after.tag, 'idle-2');
      expect(after.key, isNot(before.key));
      expect(ws.onboarding.finniSpecies, 'finni-a3');
      expect(ws.onboarding.finniLook, 2);
    });
  }
}
