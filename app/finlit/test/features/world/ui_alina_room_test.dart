import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Комната по макету Алины `alina-01` (18.10): верхняя строка — «Дома»,
/// «День N из 7», монеты · силы · настроение, ниже «Комната Финни» и
/// сытость; внизу на сцене — кнопка действия и меню Дом · Город · План ·
/// Мой путь · Ещё. С настоящим артом (значки HUD — картинки).
///
/// Защищает: меню из пяти разделов и все показатели (сытость — с моделью
/// дней) на 360×640, 640×360, 768×1024, 1440×900 при шрифте 1,0 и 1,3 —
/// без переполнения, подписи показателей не мельче 14 sp; «Ещё» открывает
/// прежнее меню ⋮ (настройки). Уронит: меню снова из трёх разделов,
/// показатель пропал, ряд показателей ужат ниже 14 sp или вылез за край.
World _day() {
  final World w = contentDayWorld()..startWeek();
  w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  return w;
}

Future<void> _pump(WidgetTester tester, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.runAsync(() async {
    await tester.pumpWidget(Provider<OnboardingScript>.value(
      value: contentScript,
      child: ChangeNotifierProvider<WorldState>.value(
        value: WorldState(_day()),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          routes: worldRoutes,
          home: const WorldTheme(child: RoomScreen()),
        ),
      ),
    ));
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final Size size in const <Size>[
    Size(360, 640),
    Size(640, 360),
    Size(768, 1024),
    Size(1440, 900),
  ]) {
    for (final double scale in <double>[1.0, 1.3]) {
      final String s =
          '${size.width.toInt()}×${size.height.toInt()}, шрифт $scale';
      testWidgets('$s: меню из пяти разделов и показатели по макету',
          (WidgetTester tester) async {
        await _pump(tester, size, scale);
        expect(tester.takeException(), isNull, reason: 'без переполнения');
        for (final (String id, String label) in <(String, String)>[
          ('home', 'Дом'),
          ('city', 'Город'),
          ('week', 'План'),
          ('progress', 'Мой путь'),
          ('more', 'Ещё'),
        ]) {
          final Finder item = find.byKey(ValueKey<String>('room:nav:$id'));
          expect(item, findsOneWidget, reason: 'раздел $label');
          expect(
              find.descendant(of: item, matching: find.text(label)),
              findsOneWidget);
        }
        for (final String k in <String>[
          'hud:coins',
          'hud:energy',
          'hud:happiness',
          'hud:fed',
        ]) {
          expect(find.byKey(ValueKey<String>(k)), findsOneWidget, reason: k);
        }
        expect(find.text('День 1 из 7'), findsOneWidget);
        // Подписи показателей — не мельче 14 sp: строка 14 × 1,1, ужатая
        // FittedBox меньше чем на 0,95, — уже мельче.
        for (final String word in <String>['монеты', 'силы', 'настроение']) {
          final double h = tester.getRect(find.text(word)).height;
          expect(h, greaterThanOrEqualTo(14 * 1.1 * 0.95),
              reason: '«$word» высотой $h');
        }
      });
    }
  }

  testWidgets('«Ещё» открывает прежнее меню ⋮: настройки',
      (WidgetTester tester) async {
    await _pump(tester, const Size(360, 640), 1.0);
    await tester.tap(find.byKey(const ValueKey<String>('room:nav:more')));
    // Спрайты анимируются бесконечно — pumpAndSettle не дождётся.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey<String>('room:settings')), findsOneWidget);
  });
}
