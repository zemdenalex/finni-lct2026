import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// «Мало контента» (Денис, ночь 18.10, п. 2 и 6; finni): данные без новой
/// механики. Защищает счёт на работу и на тему: вопросов в смене — не меньше
/// 4 на каждую из 7 работ, сценариев везения — 5, событий по каждой теме ТЗ
/// — не меньше 18 (было 32 / 16). Уронит: вопрос привязан не к той работе
/// (`work` с опечаткой — у работы снова 3), событие потерялось при слиянии
/// копий. Почему не ловят прежние: тесты считают общее число, а не по работе.
void main() {
  test('вопросов в смене ≥ 4 и везений = 5 на каждую работу', () {
    final DayCycle dc = contentDayConfig.dayCycle;
    for (final WorldJob j in contentDayConfig.jobs) {
      expect(dc.shiftChoices.where((ShiftChoice q) => q.work == j.id).length,
          greaterThanOrEqualTo(4),
          reason: j.id);
      expect(dc.luck.where((ShiftLuck l) => l.job == j.id).length, 5,
          reason: j.id);
    }
  });

  test('событий по каждой теме ТЗ ≥ 18', () {
    for (final String topic in <String>['planning', 'savings']) {
      expect(
          contentDayConfig.events
              .where((WorldEventSpec e) => e.topic == topic)
              .length,
          greaterThanOrEqualTo(18),
          reason: topic);
    }
  });
}
