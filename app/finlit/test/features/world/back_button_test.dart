import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Аудит доступности 16.10, п. 5: «назад» одинаковое на каждом экране —
/// скруглённая стрелка с подписью «Назад» для TalkBack. Экран открыт
/// поверх другого, как в игре (иначе возвращаться некуда).
///
/// Уронит: экран со стандартной стрелкой другого вида (так было у словарика
/// и сценок знакомства) или кнопку «назад» без подписи.
void main() {
  setUp(rootBundle.clear);

  /// Комната — начало игры: возвращаться из неё некуда. Регистрация
  /// знакомства на первом шаге — тоже.
  const Set<String> noBack = <String>{'S1 комната', 'S0 онбординг'};

  final WorldKind kind = worldKinds.last;
  for (final MapEntry<String, (Widget, World Function())> s
      in worldScreens(kind).entries) {
    if (noBack.contains(s.key)) continue;
    testWidgets('${s.key}: «назад» — скруглённая стрелка «Назад»',
        (WidgetTester tester) async {
      await pumpListedScreen(tester, s.key, (_Opener(s.value.$1), s.value.$2),
          size: portrait);
      await tester.runAsync(() async {
        for (int i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
      expect(find.byIcon(Icons.arrow_back), findsNothing,
          reason: 'стрелка другого вида');
      final Finder back = find.byWidgetPredicate((Widget w) =>
          w is IconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.arrow_back_rounded);
      expect(back, findsWidgets, reason: 'кнопка «назад» есть');
      for (final Element e in back.evaluate()) {
        final IconButton b = e.widget as IconButton;
        // Исключение одно: стрелка города с подсказкой «Куда идти»
        // (флаг city.guide, front-city) ведёт в комнату и так и говорит —
        // «Домой» (её проверяет city_guide_test). Остальные — «Назад».
        expect(
            b.tooltip,
            b.key == const ValueKey<String>('city:back')
                ? anyOf('Назад', 'Домой')
                : 'Назад');
      }
    });
  }
}

/// Открывает [screen] новым маршрутом поверх пустого — как в игре.
class _Opener extends StatefulWidget {
  const _Opener(this.screen);
  final Widget screen;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => WorldTheme(child: widget.screen)));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
