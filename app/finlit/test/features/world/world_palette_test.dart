import 'dart:math' as math;

import 'package:finlit/core/world_theme.dart';
import 'package:flutter/material.dart';
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

/// Палитра «Лес» (стиль Алины, спека §2.1 и §3): каждая пара текст/фон, которую
/// рисует мир, ≥ 4,5:1 (ТЗ). Полупрозрачные фоны (затемнённая комната под
/// экраном, карточка на ней, нижнее меню) считаются поверх белого — худший
/// случай: под ними может оказаться светлая стена комнаты.
///
/// Уронит: новый оттенок текста или фона, который не читается (её светлые
/// подписи на бумаге 2,6–3,3:1, `.saving-footnote` 4,35:1).
void main() {
  const Color white = Color(0xFFFFFFFF);
  final Color backdropTop = Color.alphaBlend(WorldColors.backdropTop, white);
  final Color backdropBottom =
      Color.alphaBlend(WorldColors.backdropBottom, white);
  final Map<String, Color> dark = <String, Color>{
    'night': WorldColors.night,
    'panel': WorldColors.panel,
    'raised': WorldColors.raised,
    'needsBg': WorldColors.needsBg,
    'wantsBg': WorldColors.wantsBg,
    'goalBg': WorldColors.goalBg,
    'фон экрана сверху': backdropTop,
    'фон экрана снизу': backdropBottom,
    'карточка на фоне': Color.alphaBlend(WorldColors.surface, backdropTop),
    'строка на фоне': Color.alphaBlend(WorldColors.surfaceRow, backdropTop),
    'нижнее меню': Color.alphaBlend(WorldColors.dock, white),
  };
  final Map<String, Color> onDark = <String, Color>{
    'text': WorldColors.text,
    'textTitle': WorldColors.textTitle,
    'textSoft': WorldColors.textSoft,
    'textMute': WorldColors.textMute,
    'accentLime': WorldColors.accentLime,
    'gold': WorldColors.gold,
    'goldText': WorldColors.goldText,
    'needs': WorldColors.needs,
    'wants': WorldColors.wants,
    'energy': WorldColors.energy,
    'mood': WorldColors.mood,
    'fullness': WorldColors.fullness,
    'danger': WorldColors.danger,
  };

  test('текст на тёмных поверхностях ≥ 4,5:1', () {
    final List<String> bad = <String>[
      for (final MapEntry<String, Color> f in onDark.entries)
        for (final MapEntry<String, Color> b in dark.entries)
          if (_contrast(f.value, b.value) < 4.5)
            '${f.key} на ${b.key}: ${_contrast(f.value, b.value).toStringAsFixed(2)}',
    ];
    expect(bad, isEmpty);
  });

  test('сноска textFaint — только на фоне экрана и панели, ≥ 4,5:1', () {
    for (final Color b in <Color>[
      WorldColors.night,
      WorldColors.panel,
      backdropTop,
      backdropBottom,
    ]) {
      expect(_contrast(WorldColors.textFaint, b), greaterThanOrEqualTo(4.5));
    }
  });

  test('кнопки и бумажные карточки ≥ 4,5:1', () {
    final Map<String, (Color, Color)> pairs = <String, (Color, Color)>{
      'золотая кнопка': (WorldColors.onGold, WorldColors.gold),
      'кнопка-шалфей': (WorldColors.onSage, WorldColors.sage),
      for (final MapEntry<String, Color> p in <String, Color>{
        'paper': WorldColors.paper,
        'paperProduct': WorldColors.paperProduct,
        'needsPaper': WorldColors.needsPaper,
        'wantsPaper': WorldColors.wantsPaper,
        'goalPaper': WorldColors.goalPaper,
      }.entries) ...<String, (Color, Color)>{
        'onPaper на ${p.key}': (WorldColors.onPaper, p.value),
        'onPaperSoft на ${p.key}': (WorldColors.onPaperSoft, p.value),
      },
    };
    final List<String> bad = <String>[
      for (final MapEntry<String, (Color, Color)> p in pairs.entries)
        if (_contrast(p.value.$1, p.value.$2) < 4.5)
          '${p.key}: ${_contrast(p.value.$1, p.value.$2).toStringAsFixed(2)}',
    ];
    expect(bad, isEmpty);
  });

  test('три оттенка золота и шкала радиусов 6 · 10 · 14 · 20', () {
    expect(WorldColors.goal, WorldColors.gold,
        reason: 'цель — то же золото, что монетка');
    expect(WorldColors.goldText, isNot(WorldColors.gold));
    expect(<double>[
      WorldRadii.tag,
      WorldRadii.tile,
      WorldRadii.button,
      WorldRadii.panel,
    ], <double>[
      6,
      10,
      14,
      20
    ]);
  });
}
