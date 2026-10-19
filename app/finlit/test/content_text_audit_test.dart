import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/world_harness.dart' show weekMode;

/// Тексты по аудиту Разведчика (17.10), то, что проверяется не глазами.
/// 1. Подсказка выбора в смене называет **цену** в силах: вариант с
///    `energy` > 0 — «чуть устанешь» · «устанешь (намного) сильнее» по величине;
///    «меньше сил» ребёнок 7–8 лет читал как выгоду. Уронит: новую подсказку
///    написали по-старому или величина слов разошлась с `energy`.
/// 2. Урок курьера считает пример: «заработал A, потратил B — осталось C» и
///    после масштаба монет профиля (вверх до десятка) A − B = C. Уронит:
///    числа в тексте поменяли без пересчёта или масштаб сломал разность.
/// Почему не ловят прежние: `shift_choice_test` проверяет, что подсказка
/// есть, а не что она говорит; `lesson_scale_test` — что плейсхолдер
/// подставлен, а не что пример сходится.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldConfig _config({bool week = false}) =>
    worldConfigFromContent(WorldContent.parse(
      economy: week ? weekMode(_read('economy.json')) : _read('economy.json'),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
    ));

void main() {
  test('выбор в смене: подсказка называет цену в силах по величине energy', () {
    final Map<String, Object?> e =
        jsonDecode(_read('economy.json')) as Map<String, Object?>;
    final List<Object?> items =
        ((e['day_cycle']! as Map<String, Object?>)['shift_choices']!
            as Map<String, Object?>)['items']! as List<Object?>;
    int checked = 0;
    for (final Object? q in items) {
      final Map<String, Object?> m = q! as Map<String, Object?>;
      for (final Object? o in m['options']! as List<Object?>) {
        final Map<String, Object?> opt = o! as Map<String, Object?>;
        final double energy = (opt['energy'] as num? ?? 0).toDouble();
        final String hint = opt['effect_hint'] as String? ?? '';
        final String where = '${m['id']}.${opt['id']}: «$hint»';
        expect(hint, isNot(contains('меньше сил')), reason: where);
        if (energy <= 0) {
          expect(hint, isNot(contains('устан')), reason: where);
          continue;
        }
        final String want = energy >= 1.5
            ? 'устанешь намного сильнее'
            : energy >= 1
                ? 'устанешь сильнее'
                : 'чуть устанешь';
        expect(hint, contains(want), reason: where);
        checked++;
      }
    }
    expect(checked, greaterThanOrEqualTo(21), reason: 'варианты с ценой есть');
  });

  for (final bool week in <bool>[false, true]) {
    test(
        'урок курьера: пример сходится после масштаба · '
        '${week ? 'неделя' : 'дни, профиль сборки'}', () {
      final String text = _config(week: week).lesson('courier')!.understood;
      final RegExpMatch? m = RegExp(r'Заработал (\d+), потратил (\d+) .*'
              r'осталось (\d+)')
          .firstMatch(text);
      expect(m, isNotNull, reason: text);
      final int a = int.parse(m![1]!), b = int.parse(m[2]!);
      expect(int.parse(m[3]!), a - b, reason: text);
      expect(text, isNot(contains('{coins')));
    });
  }
}
