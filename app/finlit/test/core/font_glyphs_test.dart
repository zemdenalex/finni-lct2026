import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:finlit/domain/world/contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/world_harness.dart';

/// Кодовые точки, которые есть в шрифте (таблица `cmap`, форматы 4 и 12).
Set<int> _cmap(String path) {
  final ByteData b = ByteData.sublistView(File(path).readAsBytesSync());
  final int tables = b.getUint16(4);
  int cmap = -1;
  for (int i = 0; i < tables; i++) {
    final int rec = 12 + i * 16;
    if (String.fromCharCodes(<int>[
          for (int j = 0; j < 4; j++) b.getUint8(rec + j),
        ]) ==
        'cmap') {
      cmap = b.getUint32(rec + 8);
    }
  }
  final Set<int> out = <int>{};
  final int n = b.getUint16(cmap + 2);
  for (int i = 0; i < n; i++) {
    final int sub = cmap + b.getUint32(cmap + 4 + i * 8 + 4);
    final int format = b.getUint16(sub);
    if (format == 4) {
      final int segs = b.getUint16(sub + 6) ~/ 2;
      final int ends = sub + 14;
      final int starts = ends + segs * 2 + 2;
      for (int s = 0; s < segs; s++) {
        final int end = b.getUint16(ends + s * 2);
        final int start = b.getUint16(starts + s * 2);
        if (start == 0xFFFF) continue;
        for (int c = start; c <= end; c++) {
          out.add(c);
        }
      }
    } else if (format == 12) {
      final int groups = b.getUint32(sub + 12);
      for (int g = 0; g < groups; g++) {
        final int at = sub + 16 + g * 12;
        for (int c = b.getUint32(at); c <= b.getUint32(at + 4); c++) {
          out.add(c);
        }
      }
    }
  }
  return out;
}

Iterable<String> _texts(Object? v) sync* {
  if (v is Map<String, Object?>) {
    for (final MapEntry<String, Object?> e in v.entries) {
      if (!e.key.startsWith('_')) yield* _texts(e.value);
    }
  } else if (v is List<Object?>) {
    for (final Object? x in v) {
      yield* _texts(x);
    }
  } else if (v is String) {
    yield v;
  }
}

/// Ловит (ревью df2164a): «≈» в строке окупаемости рисовался пустым — в
/// Onest нет U+2248 (тот же класс, что «−» U+2212). Каждая буква текстов
/// ребёнку из content/ и строк каталога должна быть в шрифте игры. Эмодзи
/// (U+2600 и выше) рисует системный шрифт — их здесь не проверяем.
void main() {
  final Set<int> font = _cmap('assets/fonts/Onest-Regular.ttf');

  test('шрифт прочитан: кириллица есть, «≈» нет', () {
    expect(font, containsAll(<int>[0x0416, 0x0451, 0x00AB, 0x2014]));
    expect(font, isNot(contains(0x2248)));
  });

  test('тексты content/ и каталога — только буквы шрифта игры', () {
    final List<String> texts = <String>[
      for (final String f in <String>[
        'assets/content/world/economy.json',
        'assets/content/world/jobs.json',
        'assets/content/world/events.json',
        'assets/content/glossary.json',
      ])
        ..._texts(jsonDecode(File(f).readAsStringSync())),
      for (final WorldCatalogItem i in contentWorld().catalog) ...<String>[
        i.title,
        if (i.perk != null) i.perk!,
      ],
    ];
    final Map<String, String> missing = <String, String>{};
    for (final String t in texts) {
      for (final int r in t.runes) {
        if (r >= 128 && r < 0x2600 && !font.contains(r)) {
          missing[String.fromCharCode(r)] = t;
        }
      }
    }
    expect(missing, isEmpty);
  });
}
