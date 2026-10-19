import 'dart:io';

import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Подсказка города в нижней полосе портрета (кадры 0.1.2+3, night4 #5): на
/// 360 dp текст сборки «Куда пойдём? Нажми на здание или веди Финни
/// джойстиком.» обрезался многоточием («…веди Финни джо…»).
///
/// Правка — текст (`city.hint`): «Нажми на здание или веди Финни пальцем.»
/// Полосу выше сделать нельзя — `room_ui_budget_test` держит обе полосы
/// города ≤ 21 % экрана; джойстик плавающий, под пальцем, — «пальцем» о нём
/// и говорит.
///
/// Защищает: на 360 × 640 при шрифте 1,0 и 1,3 подсказка влезает целиком —
/// ни одна строка полосы не упирается в `maxLines`. Уронит: текст снова
/// длиннее места рядом с «Все места» или полоса снова режет его в 2 строки.
/// Почему не ловили: тесты города проверяли, что исключений нет, а
/// многоточие исключением не бывает.
/// Тексты сборки — тот же `onboarding.json`, что едет в APK.
final OnboardingScript _shipped = OnboardingScript.parse(
    File('assets/content/world/onboarding.json').readAsStringSync());

Future<void> _pumpCity(WidgetTester tester, double scale,
    OnboardingScript script, WorldGame world) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final WorldState state = WorldState(world);
  await tester.runAsync(() async {
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<WorldState>.value(value: state),
        Provider<OnboardingScript?>.value(value: script),
      ],
      child: MaterialApp(
          theme: buildAppTheme(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
          home: const CityScreen()),
    ));
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();
}

void main() {
  // Настоящие шрифты сборки: тестовый шрифт рисует каждую букву квадратом,
  // и ширина строки была бы выдуманной.
  setUpAll(loadAppFonts);

  for (final double scale in const <double>[1.0, 1.3]) {
    testWidgets('подсказка города целиком на 360 × 640, шрифт $scale',
        (WidgetTester tester) async {
      final OnboardingScript script = _shipped;
      expect(script.cityHint, isNotNull, reason: 'текст сборки, не запасной');
      // «Куда идти» молчит (неделя идёт, сил и монет хватает, событий нет) —
      // в полосе сама подсказка, как на кадрах.
      final WorldGame w = contentDayWorld();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      ok(w.demoGiveCoins(5000));
      if (w.pendingEvent case final PendingEvent e) {
        ok(w.resolveEvent(
            e.choices.firstWhere((PendingEventChoice c) => c.available).id));
      }
      expect(w.eventBuildingId, isNull);
      await _pumpCity(tester, scale, script, w);
      expect(tester.takeException(), isNull);
      final Finder bar = find.byKey(const ValueKey<String>('city:bar'));
      expect(bar, findsOneWidget);
      final List<RenderParagraph> lines = <RenderParagraph>[
        for (final Element e in find
            .descendant(of: bar, matching: find.byType(RichText))
            .evaluate())
          e.renderObject! as RenderParagraph,
      ];
      final List<String> hint = <String>[
        for (final RenderParagraph p in lines)
          if (p.text.toPlainText() == script.cityHint) p.text.toPlainText(),
      ];
      expect(hint, isNotEmpty,
          reason: 'подсказки нет в нижней полосе: ${[
            for (final p in lines) p.text.toPlainText()
          ]}');
      for (final RenderParagraph p in lines) {
        expect(p.didExceedMaxLines, isFalse,
            reason: 'обрезано: «${p.text.toPlainText()}»');
      }
    });
  }
}
