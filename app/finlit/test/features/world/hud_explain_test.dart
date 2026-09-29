import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/icons.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/features/world/home/world_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Денис 29.09: «иконку энергии на молнию … после нажатия на число
/// написано, что это такое»; копилка ушла из HUD.
void main() {
  final Map<String, Object?> texts =
      jsonDecode(File('assets/content/world/hud.json').readAsStringSync())
          as Map<String, Object?>;

  test('копия hud.json в сборке совпадает с content/hud.json', () {
    expect(File('assets/content/world/hud.json').readAsStringSync(),
        File('../../content/hud.json').readAsStringSync());
  });

  Future<ResourceSnapshot> pumpHud(WidgetTester tester) async {
    final World w = FakeWorld();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WorldHud(snapshot: w.snapshot)),
    ));
    return w.snapshot;
  }

  testWidgets('в HUD нет копилки, ⚡ — молния', (WidgetTester tester) async {
    await pumpHud(tester);
    expect(find.byKey(const ValueKey<String>('hud:saved')), findsNothing);
    final Iterable<Widget> pics = tester.widgetList(find.descendant(
        of: find.byKey(const ValueKey<String>('hud:energy')),
        matching: find.byType(Pictogram)));
    expect(pics.map((Widget p) => (p as Pictogram).pic), contains(Pic.bolt));
  });

  for (final (String id, String hud) in <(String, String)>[
    ('coins', 'hud:coins'),
    ('energy', 'hud:energy'),
    ('happiness', 'hud:happiness'),
  ]) {
    testWidgets('касание числа $id — что это и сколько сейчас',
        (WidgetTester tester) async {
      final ResourceSnapshot s = await pumpHud(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey<String>(hud)));
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(ValueKey<String>('hud:explain:$id')), findsOneWidget);
      final String value = tester
          .widget<Text>(find.byKey(ValueKey<String>('hud:explain:$id:value')))
          .data!;
      final String now = switch (id) {
        'energy' => WorldHud.energyText(s.energy),
        'happiness' => '${s.happiness}',
        _ => '${s.available}',
      };
      expect(value, contains(now));
      final String text =
          (texts[id]! as Map<String, Object?>)['text']! as String;
      expect(find.text(text), findsOneWidget, reason: 'текст — из hud.json');
      if (id != 'coins') {
        expect(
            find.descendant(
                of: find.byKey(ValueKey<String>('hud:explain:$id')),
                matching: find.byType(LinearProgressIndicator)),
            findsOneWidget,
            reason: 'полоса в карточке');
      }
    });
  }
}
