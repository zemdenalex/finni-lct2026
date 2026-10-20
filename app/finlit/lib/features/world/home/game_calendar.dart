import '../../../domain/world/contract.dart' show FinniGender, heroGendered;

/// Игровой календарь (Настя 20.10): день показывается как «Вт, 6 окт», а не
/// «День 2 из 7». Дата — игровая, от фиксированного начала, без реального
/// времени устройства: неделя игры — 7 дней, день 1 — понедельник.
///
/// 🟡 ratify: начало — понедельник 5 октября 2026 (выбрано агентом:
/// начало октября, понедельник — первый день игровой недели).
abstract final class GameCalendar {
  /// День 1 недели 1. UTC: прибавление дней не спотыкается о переход на
  /// летнее время.
  static final DateTime start = DateTime.utc(2026, 10, 5);

  static const List<String> _weekdayShort = <String>[
    'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс', //
  ];

  static const List<String> _weekdayFull = <String>[
    'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', //
    'воскресенье',
  ];

  static const List<String> _monthShort = <String>[
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн', //
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  static const List<String> _monthFull = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', //
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  /// Дата дня [day] (1…7) недели [week] (с 1). Неделя 0 (до первой
  /// стипендии) — как неделя 1.
  static DateTime dateOf({required int week, required int day}) {
    final int w = week < 1 ? 1 : week;
    final int d = day < 1 ? 1 : day;
    return start.add(Duration(days: (w - 1) * 7 + d - 1));
  }

  /// «Вт, 6 окт» — на экране.
  static String short({required int week, required int day}) {
    final DateTime t = dateOf(week: week, day: day);
    return '${_weekdayShort[t.weekday - 1]}, ${t.day} '
        '${_monthShort[t.month - 1]}';
  }

  /// «Вторник, 6 октября» — для TalkBack: сокращения он читает по буквам.
  static String spoken({required int week, required int day}) {
    final DateTime t = dateOf(week: week, day: day);
    final String wd = _weekdayFull[t.weekday - 1];
    return '${wd[0].toUpperCase()}${wd.substring(1)}, ${t.day} '
        '${_monthFull[t.month - 1]}';
  }
}

/// Реплика Финни при каждой смене дня (Настя 20.10: «Я устал, пойду
/// спать»). Род — героя из знакомства (правило 5Б); пол не выбран — без рода.
String finniSleepLine(FinniGender? gender) => heroGendered(gender,
    neutral: 'Сил больше нет — пойду спать.',
    boy: 'Я устал, пойду спать.',
    girl: 'Я устала, пойду спать.');
