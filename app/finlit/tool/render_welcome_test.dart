import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart'
    show contentDayConfig, contentScript;
import 'test_fonts.dart';

/// Кадры первого экрана знакомства (n6-welcome 20.10): шаг 1 (Финни,
/// облачко, ник, облик) и шаг 2 (имя друга) на телефоне, боком и на
/// компьютере, шрифт ×1 и ×1,3:
///
///     flutter test tool/render_welcome_test.dart  →  build/welcome/*.png
///
/// На CI не гоняется.

const Map<String, Size> _sizes = <String, Size>{
  '360x640': Size(360, 640),
  '640x360': Size(640, 360),
  '1440x900': Size(1440, 900),
};

Future<void> _shot(GlobalKey key, String name) async {
  final RenderRepaintBoundary b =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image img = await b.toImage(pixelRatio: 1);
  final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
  final File out = File('build/welcome/$name.png');
  await out.create(recursive: true);
  await out.writeAsBytes(png!.buffer.asUint8List());
}

Future<void> _settle(WidgetTester tester, [int n = 12]) async {
  for (int i = 0; i < n; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final MapEntry<String, Size> s in _sizes.entries) {
    for (final double scale in <double>[1, 1.3]) {
      final String name = 'welcome-${s.key}-x$scale';
      testWidgets(name, (WidgetTester tester) async {
        await tester.runAsync(() async {
          tester.view.physicalSize = s.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final GlobalKey key = GlobalKey();
          final WorldState ws =
              WorldState(WorldGame(config: contentDayConfig));
          await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: Provider<OnboardingScript>.value(
              value: contentScript,
              child: ChangeNotifierProvider<WorldState>.value(
                value: ws,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildAppTheme(),
                  routes: worldRoutes,
                  builder: (BuildContext c, Widget? child) => MediaQuery(
                    data: MediaQuery.of(c)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: const WorldTheme(child: WorldOnboardingScreen()),
                ),
              ),
            ),
          ));
          await _settle(tester);
          await _shot(key, '$name-1');
          await tester.enterText(
              find.byKey(const ValueKey<String>('onboarding-nick')),
              'Звёздочка');
          final Finder look =
              find.byKey(const ValueKey<String>('look:finni-a1:2'));
          await tester.ensureVisible(look);
          await tester.tap(look);
          await _settle(tester, 6);
          await _shot(key, '$name-1b');
          final Finder next =
              find.byKey(const ValueKey<String>('onboarding-next'));
          await tester.ensureVisible(next);
          await tester.tap(next);
          await _settle(tester);
          await _shot(key, '$name-2');
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
}
