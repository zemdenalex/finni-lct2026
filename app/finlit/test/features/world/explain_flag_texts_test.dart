import 'dart:io';

import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/features/world/world_explain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart' show contentDayConfig;

/// Тексты флагов (finni 17.10): объяснение настроения в итоге смены говорит
/// правду о правиле оплаты. С `day_cycle.mood_pay_daily` оплата — от
/// настроения утра этого дня, и текст про «начало недели» был бы неправдой;
/// без флага — прежний текст. Уронит: строка выбирается не по флагу или
/// второго текста нет в файле. Почему не ловят прежние: `explain_7d_test`
/// проверяет, что «?» открывает текст, а не какой.
WorldExplain _explain({required bool daily, bool live = false}) {
  final DayCycle dc = contentDayConfig.dayCycle;
  return WorldExplain.parse(File(WorldExplain.asset).readAsStringSync(),
      dayCycle: DayCycle(
        daysPerWeek: dc.daysPerWeek,
        explainUi: true,
        moodPayDaily: daily,
        moodPayLive: live,
        sleepRule: dc.sleepRule,
      ));
}

void main() {
  test('флаг выключен — оплата от начала недели, так и сказано', () {
    final String why = _explain(daily: false).moodWhy!.toLowerCase();
    expect(why, contains('в начале недели'));
    expect(why, isNot(contains('утр')));
  });

  test('mood_pay_daily — про утро этого дня, без «недели»', () {
    final String why = _explain(daily: true).moodWhy!.toLowerCase();
    expect(why, contains('утр'));
    expect(why, isNot(contains('недел')));
  });

  // DEN-36 A: оплата от настроения на момент смены — текст «сейчас», без
  // утра и недели; сильнее mood_pay_daily.
  test('mood_pay_live — про настроение сейчас, без утра и недели', () {
    for (final bool daily in <bool>[false, true]) {
      final String why =
          _explain(daily: daily, live: true).moodWhy!.toLowerCase();
      expect(why, contains('сейчас'));
      expect(why, isNot(contains('утр')));
      expect(why, isNot(contains('недел')));
    }
  });
}
