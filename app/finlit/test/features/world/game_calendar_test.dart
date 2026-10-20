import 'package:finlit/domain/world/contract.dart' show FinniGender;
import 'package:finlit/features/world/home/game_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

// Защищает: игровой календарь (Настя 20.10) — неделя игры 7 дней с
// понедельника, дата идёт подряд через недели и месяцы, без реального
// времени. Уронит: день недели сдвинут (неделя не с Пн), номер недели не
// учтён (каждая неделя снова 5 окт), месяц не переходит (32 окт).
void main() {
  test('день 1 — Пн, день 7 — Вс; неделя 2 продолжает дату', () {
    expect(GameCalendar.short(week: 1, day: 1), 'Пн, 5 окт');
    expect(GameCalendar.short(week: 1, day: 2), 'Вт, 6 окт');
    expect(GameCalendar.short(week: 1, day: 7), 'Вс, 11 окт');
    expect(GameCalendar.short(week: 2, day: 1), 'Пн, 12 окт');
  });

  test('переход месяца: неделя 4, день 7 — Вс, 1 ноя', () {
    expect(GameCalendar.short(week: 4, day: 7), 'Вс, 1 ноя');
    expect(GameCalendar.spoken(week: 4, day: 7), 'Воскресенье, 1 ноября');
  });

  test('до первой недели (неделя 0) — как неделя 1', () {
    expect(GameCalendar.short(week: 0, day: 1), 'Пн, 5 окт');
  });

  test('реплика сна — в роде героя, без рода, если пол не выбран', () {
    expect(finniSleepLine(FinniGender.boy), 'Я устал, пойду спать.');
    expect(finniSleepLine(FinniGender.girl), 'Я устала, пойду спать.');
    expect(finniSleepLine(null), isNot(contains('устал')));
  });
}
