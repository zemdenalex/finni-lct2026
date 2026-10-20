import 'package:finlit/core/theme.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/world_harness.dart';

/// Подсказка выбора на шаге 2 консультанта и помощника бухгалтера (Настя
/// 20.10, п. 13: «не ясно, что снова нужно что-то решать, сделай подсказку,
/// если будет тыкать не туда»).
///
/// Защищает: касание мимо карточек, пока выбор не сделан, — подсказка
/// «Нажми на …» жирнее и золотом, рамка вокруг карточек вспыхивает; касание
/// карточки подсказкой не считается.
/// Уронит: слой касаний снят или считает касания карточек; подсказка не
/// меняется. Почему не ловят другие: job_play_screen_test проверяет итоги
/// смены (218f53c5), не шаги мини-игр.
Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  final Map<String, ConsultantContent> engines = <String, ConsultantContent>{
    'консультант': contentJobGames.consultant,
    'бухгалтер': contentJobGames.accountant,
  };

  for (final MapEntry<String, ConsultantContent> e in engines.entries) {
    testWidgets('${e.key}: касание мимо предложений — подсказка выбора', (
      WidgetTester tester,
    ) async {
      final ConsultantContent content = e.value;
      final ConsultantSet set = content.setFor(0);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConsultantGame(content: content, onDone: (_) {}),
            ),
          ),
        ),
      );
      for (final ConsultantItem i in set.items) {
        await _tap(tester, 'consultant:shelf:${i.id}:${set.tierOf(i)}');
      }
      await _tap(tester, 'consultant:scan');

      final Finder hint = find.byKey(
        const ValueKey<String>('consultant:pickHint'),
      );
      FontWeight? weight() => tester.widget<Text>(hint).style?.fontWeight;
      double frameAlpha() {
        final DecoratedBox b = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey<String>('consultant:choices')),
        );
        return ((b.decoration as BoxDecoration).border! as Border).top.color.a;
      }

      expect(hint, findsOneWidget);
      expect(find.text(content.texts.pick), findsOneWidget);
      expect(weight(), isNot(FontWeight.w800), reason: 'пока не касались');

      // Неверное предложение — касание внутри: подсказкой не считается.
      final ConsultantItem wrong = set.items.firstWhere(
        (ConsultantItem i) => i.id != set.customer.bestFit,
      );
      await _tap(tester, 'consultant:pick:${wrong.id}');
      expect(weight(), isNot(FontWeight.w800), reason: 'жал на предложение');

      // Мимо — по реплике покупателя.
      final Finder who = find.byKey(
        const ValueKey<String>('consultant:customer'),
      );
      await tester.ensureVisible(who);
      await tester.pumpAndSettle();
      await tester.tap(who);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(weight(), FontWeight.w800);
      expect(frameAlpha(), greaterThan(0.5), reason: 'рамка вспыхнула');
      await tester.pumpAndSettle();
      expect(frameAlpha(), 0, reason: 'и погасла');
    });
  }
}
