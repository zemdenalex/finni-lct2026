import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/glossary/glossary_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

bool _isHelp(Widget w) =>
    w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>).value.endsWith(':help');

/// Словарик сам — справка, «?» на нём не нужен.
const Set<String> _noHelp = <String>{'S13 словарик'};

/// ТЗ 2.5.1.3: на каждом экране мира есть «?», и он открывает подсказку.
///
/// Ловит: новый экран без «?» — так было с S15 «Настройки», добавленным
/// 28.09 без подсказки (на старом коде тест падал на S15 и на S0, где
/// кнопка была значком Material без ключа).
void main() {
  setUp(rootBundle.clear);

  forEachWorld((WorldKind kind) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final MapEntry<String, (Widget, World Function())> s
          in worldScreens(kind).entries) {
        if (_noHelp.contains(s.key)) continue;
        testWidgets('${s.key} · ${o.key}: «?» есть и открывает подсказку',
            (WidgetTester tester) async {
          await pumpListedScreen(tester, s.key, s.value, size: o.value);
          final Finder help = find.byWidgetPredicate(_isHelp);
          expect(help, findsOneWidget);
          await tester.tap(help);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          // S0 — лист с подсказкой к текущему шагу, остальные — диалог.
          expect(
              find.byType(AlertDialog).evaluate().length +
                  find.byType(BottomSheet).evaluate().length,
              1);
        });
      }
    }
  });

  // ТЗ 2.5.11.2. Ловит: словарик снова недостижим из нового мира (до 28.09
  // он открывался только с главного экрана старой игры) или открывается
  // тёмным текстом старой темы на тёмном фоне мира.
  testWidgets(
      'словарик: «?» в комнате → «Словарик», все термины открыты, '
      'контраст AA на тёмной теме', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    await tester.runAsync(() async {
      final AppState app = AppState(MemoryStorage());
      await app.boot();
      await pumpWorldScreen(tester, const RoomScreen(),
          world: livingWorld(worldKinds.last), size: portrait, app: app);
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey<String>('room:help')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey<String>('help:glossary')));
    await tester.pumpAndSettle();
    expect(find.byType(GlossaryScreen), findsOneWidget);
    expect(find.text('Бюджет'), findsOneWidget);
    expect(find.text('откроется, когда встретится в игре'), findsNothing);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    sem.dispose();
  });
}
