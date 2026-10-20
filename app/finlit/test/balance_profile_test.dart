import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/world_harness.dart' show weekMode;

/// Профили баланса 7 дней (`balance_profile`, finni 17.10): выбранный профиль
/// ложится поверх economy.json; по умолчанию mid; запасной режим «неделя»
/// профилей не видит; неизвестный профиль — ошибка контента.
/// Уронит: профиль не применился (карманные 400 в днях), применился в
/// «неделе», или опечатка в имени профиля молча дала числа файла.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldConfig _with(String? profile, {bool week = false}) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  if (profile == null) {
    e.remove('balance_profile');
  } else {
    e['balance_profile'] = profile;
  }
  final String eco = jsonEncode(e);
  return worldConfigFromContent(WorldContent.parse(
    economy: week ? weekMode(eco) : eco,
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  ));
}

int _consultantPay(WorldConfig c) =>
    c.jobs.firstWhere((WorldJob j) => j.id == 'consultant').pay;

void main() {
  test('профили: карманные, оплата смены, сытость ночи, ужин дома', () {
    final WorldConfig soft = _with('soft');
    final WorldConfig mid = _with('mid');
    final WorldConfig strict = _with('strict');
    expect(<int>[soft.pocketMoney, mid.pocketMoney, strict.pocketMoney],
        <int>[900, 820, 480]);
    // 300 × 0,5 = 150; × 0,45 = 135 → 140; + прибавка 200 (Настя 20.10).
    expect(<int>[
      _consultantPay(soft),
      _consultantPay(mid),
      _consultantPay(strict)
    ], <int>[
      350,
      340,
      340
    ]);
    expect(<int>[
      soft.dayCycle.satietyNight,
      mid.dayCycle.satietyNight,
      strict.dayCycle.satietyNight,
    ], <int>[
      20,
      20,
      25
    ]);
    expect(strict.dayCycle.homeMealShare, 0.5);
  });

  test('по умолчанию — mid; без профиля — числа файла', () {
    final WorldConfig shipped = worldConfigFromContent(WorldContent.parse(
      economy: _read('economy.json'),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
    ));
    expect(shipped.pocketMoney, 820);
    expect(_with(null).pocketMoney, 400);
    expect(_consultantPay(_with(null)), 500, reason: '300 + прибавка 200');
  });

  test('режим «неделя» профилей не видит', () {
    final WorldConfig w = _with('strict', week: true);
    expect(w.pocketMoney, 400);
    expect(_consultantPay(w), 300);
  });

  test('неизвестный профиль — ошибка с путём', () {
    expect(
        () => _with('medium'),
        throwsA(isA<WorldContentError>().having((WorldContentError e) => '$e',
            'message', contains('balance_profile'))));
  });
}
