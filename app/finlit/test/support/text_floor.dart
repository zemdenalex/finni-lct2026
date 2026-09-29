import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🔴 Мерить с настоящим шрифтом приложения (`tool/test_fonts.dart`,
/// `loadAppFonts`): подстановочный шрифт тестов рисует каждую букву
/// квадратом в кегль, строка выходит почти вдвое шире — и `FittedBox`
/// ужимает её там, где на телефоне она влезает.
///
/// ТЗ 3.6.4 и `docs/design-system.md` §3: читаемый текст ≥ 16 sp, 14 —
/// только подпись, которая дублирует иконку или число. Ниже 14 в новом мире
/// не бывает ничего.
const double textFloor = 14;

/// Буква или цифра: абзац из одних эмодзи или знаков — значок, а не текст.
final RegExp _readable = RegExp(r'[0-9A-Za-zА-Яа-яЁё]');

/// Кегль, который видит ребёнок: размер шрифта × масштаб шрифта системы ×
/// сжатие `FittedBox` и прочих трансформаций над абзацем. Абзац без букв и
/// цифр — бесконечность (значок, не текст).
///
/// Ловит и то, чего не видно поиском по `fontSize`: подпись, которую
/// `FittedBox` ужал на узком экране, и стиль темы по умолчанию Material
/// (`labelSmall` — 11, `titleSmall` — 14), взятый без своего размера.
double shownTextSize(RenderParagraph p) {
  double smallest = double.infinity;
  void visit(InlineSpan span, double inherited) {
    final double size = span.style?.fontSize ?? inherited;
    if (span is TextSpan) {
      if ((span.text ?? '').contains(_readable)) {
        smallest = size < smallest ? size : smallest;
      }
      for (final InlineSpan c in span.children ?? const <InlineSpan>[]) {
        visit(c, size);
      }
    }
  }

  visit(p.text, 14);
  if (smallest == double.infinity) return smallest;
  return p.textScaler.scale(smallest) * squeezeOf(p);
}

/// Сжатие абзаца трансформациями над ним (`FittedBox`, `Transform.scale`):
/// меньший из масштабов по X и Y.
///
/// 🔴 Не `getMaxScaleOnAxis()`: он берёт максимум и по оси Z, а она у
/// плоских трансформаций всегда 1 — сжатие `FittedBox` им не видно вовсе
/// (так было до 28.09: подпись «Прогресс», ужатая до 0,41, числилась 16 sp).
double squeezeOf(RenderObject o) {
  final Matrix4 m = o.getTransformTo(null);
  double axis(int col) => math.sqrt(
      m.entry(0, col) * m.entry(0, col) + m.entry(1, col) * m.entry(1, col));
  return math.min(axis(0), axis(1));
}

/// Все видимые абзацы мельче [textFloor]: «текст» — кегль.
List<String> textsBelowFloor(WidgetTester tester) => <String>[
      for (final Element e in find.byType(RichText).evaluate())
        if (e.renderObject case final RenderParagraph p
            when p.attached && p.hasSize && shownTextSize(p) < textFloor - 0.05)
          '«${p.text.toPlainText()}» — '
              '${shownTextSize(p).toStringAsFixed(1)} sp',
    ];
