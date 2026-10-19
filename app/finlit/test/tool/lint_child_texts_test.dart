import 'package:flutter_test/flutter_test.dart';

import '../../tool/lint_child_texts.dart';

/// Линт детских текстов (`tool/lint_child_texts.dart`) на маленьком наборе.
///
/// Защищает: плохие строки ловятся каждая своим правилом, хорошие проходят;
/// склеенные литералы Dart читаются одной строкой. Уронит: правило пропало
/// или стало пропускать кириллицу (в RegExp Dart `\b` и `\w` — только
/// латиница: так «закончил ты сам» проходило мимо правила 5).
void main() {
  test('плохие строки ловятся своим правилом', () {
    final Map<String, String> bad = <String, String>{
      'Разложи монеты по конвертам.': '1-konvert',
      'Очки роста: 5. Неделю закончил ты сам.': '2-ochki-stadiya-zalog',
      'Финни отдохнул, ⚡ стало больше — теперь неделя легче, спать рано.':
          '3-znachok',
    };
    for (final MapEntry<String, String> e in bad.entries) {
      final List<String> got =
          lintText('тест', e.key).map((Finding f) => f.rule).toList();
      expect(got, contains(e.value), reason: e.key);
    }
    // Одна строка может нарушать несколько правил сразу.
    expect(
        lintText('тест', 'Очки роста: 5. Неделю закончил ты сам.')
            .map((Finding f) => f.rule),
        containsAll(<String>['2-ochki-stadiya-zalog', '5-rod']));
  });

  test('хорошие строки проходят', () {
    for (final String s in <String>[
      'Раздели монеты недели на три части: «Нужно», «Хочу», «Копилка».',
      'Звёзды: 5. Финни переехал в город.',
      'Получилось полить 4 грядки из 6.',
    ]) {
      expect(lintText('тест', s), isEmpty, reason: s);
    }
  });

  test('склеенные литералы Dart — одна строка, с номером первой строки', () {
    const String src = "final a = 'Сначала '\n    'обязательное.';\n"
        "// 'Комментарий не берём'\n";
    expect(dartStrings(src), <(int, String)>[(1, 'Сначала обязательное.')]);
  });
}
