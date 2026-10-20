import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Опыт (DEN-21 A, Денис 17.10: «экспоненциален + округление вверх»):
/// оплата × 1,01^(опыт × 3/D), в режиме дней — вверх до монеты. Защищает
/// таблицу множителя и то, что первая же хорошая смена видна в оплате.
/// Уронит: показатель без 3/D (при 7 днях рост втрое быстрее), округление
/// до десятка или вниз (опыт +1 не меняет оплату).
/// Мир сборки с днями, но оплата от настроения начала недели: опыт
/// проверяется отдельно от DEN-36 (`mood_pay_live`, своё — в
/// `mood_pay_live_test`), иначе 😊 после смены сдвигает оплату.
WorldGame _dayWorldWeekMood() {
  String read(String f) => File('assets/content/world/$f').readAsStringSync();
  final Map<String, Object?> e =
      jsonDecode(read('economy.json')) as Map<String, Object?>;
  e['day_cycle'] = <String, Object?>{
    ...(e['day_cycle']! as Map<String, Object?>),
    'mood_pay_live': false,
  };
  return WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
          economy: jsonEncode(e),
          jobs: read('jobs.json'),
          events: read('events.json'),
          roomItems: read('room_items.json'))));
}

void main() {
  test('множитель опыта: таблица при 7, 3 и 1 днях', () {
    double m(int exp, int days) =>
        experiencePayMult(base: 1.01, experience: exp, daysPerWeek: days);
    expect(m(0, 7), 1.0);
    expect(m(7, 7), closeTo(1.030301, 1e-9), reason: 'неделя по смене в день');
    expect(m(14, 7), closeTo(1.0615201506, 1e-9));
    expect(m(3, 3), closeTo(1.030301, 1e-9), reason: 'тот же недельный рост');
    expect(m(1, 7), closeTo(1.0042735, 1e-7));
    expect(m(2, 1), closeTo(1.0201, 1e-9), reason: 'неделя: 1,01^опыт');
  });

  test('оплата вверх до монеты', () {
    expect(ceilPay(301.28), 302);
    expect(ceilPay(300), 300, reason: 'целое не растёт');
    expect(ceilPay(309.09), 310);
  });

  test('режим дней: после хорошей смены оплата консультанта 340 → 342', () {
    final WorldGame w = _dayWorldWeekMood();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    final JobOffer before = w.offer('consultant')!;
    // Профиль mid: 300 × pay_scale 0,45 = 135 → вверх до десятка 140, + прибавка 200.
    expect(before.pay, 340);
    // Лимита смен в неделю нет (finni по DEN-18): в json `null`.
    expect(w.config.maxShiftsPerWeek, kNoShiftLimit);
    expect(before.shiftsUnlimited, isTrue);
    ok(w.completeJob('consultant', score: before.goodScoreMin));
    expect(w.snapshot.experience, 1);
    final JobOffer after = w.offer('consultant')!;
    expect(after.pay, 342, reason: '340 × 1,01^(3/7) = 341,45 → вверх');
    expect(after.experiencePercent, 1, reason: '+0,43 % вверх до процента');
  });
}
