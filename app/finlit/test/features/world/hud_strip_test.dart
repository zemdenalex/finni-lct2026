import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/features/world/home/hud_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final double la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Верхняя плашка (Денис 29.09): одна полупрозрачная полоса, пиксельные
/// значки, текст читается на светлой стене.
void main() {
  test('белый текст на плашке поверх любой стены — контраст ≥ 4,5', () {
    final Map<String, Object?> layout = jsonDecode(
            File('assets/content/world/room_layout.json').readAsStringSync())
        as Map<String, Object?>;
    final Map<String, Object?> stages =
        layout['stages']! as Map<String, Object?>;
    // Потолок и стены фонов светлее полей — берём и самый светлый край.
    final List<Color> walls = <Color>[
      for (final Object? st in stages.values)
        Color(0xFF000000 |
            int.parse(
                ((st! as Map<String, Object?>)['edge_wall']! as String)
                    .substring(1),
                radix: 16)),
      const Color(0xFFF1E6D8), // самый светлый потолок фонов
    ];
    for (final Color wall in walls) {
      final Color under = Color.alphaBlend(HudStrip.backing, wall);
      expect(_contrast(Colors.white, under), greaterThanOrEqualTo(4.5),
          reason: 'стена $wall → подложка $under');
    }
  });

  testWidgets('значки монет, ⚡ и 😊 — пиксельные картинки из реестра',
      (WidgetTester tester) async {
    late AssetRegistry reg;
    await tester.runAsync(() async {
      reg = await AssetRegistry.load();
      for (final String id in <String>['hud_coin', 'hud_bolt', 'hud_smile']) {
        await rootBundle.load(reg.hudIcon(id)!);
      }
    });
    final World w = FakeWorld();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HudStrip(snapshot: w.snapshot, registry: reg))));
    for (final String id in <String>['hud_coin', 'hud_bolt', 'hud_smile']) {
      final Image img =
          tester.widget<Image>(find.byKey(ValueKey<String>('hud:icon:$id')));
      expect(img.filterQuality, FilterQuality.none, reason: '$id — пиксели');
    }
    // Одна плашка на всю ширину, значения — кнопки с подписью.
    expect(
        tester.getSize(find.byKey(const ValueKey<String>('hud:strip'))).width,
        800);
    expect(find.bySemanticsLabel(RegExp('^Энергия: ')), findsOneWidget);
  });
}
