import 'dart:convert';
import 'dart:io';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Финни бывает мальчиком и девочкой (знакомство: «Мальчик / Девочка»,
/// реплики `lines_girl`), а строки игры — одни на обоих (правило 5А Насти:
/// без рода).
///
/// Защищает: строки, которые ребёнок видит после отдыха и на доске работ,
/// не называют Финни в мужском роде. Было (путь ребёнка rc-7d, D3): выбрана
/// девочка, а на доске «Финни — сын экономистов… ему доступны», после парка —
/// «Финни отдохнул». Уронит: такая строка вернулась в домен или в jobs.json.
/// Правило 5 линта ловит только «ты …л» — Финни оно не видит.
final RegExp _gendered = RegExp(
    r'(?<![А-Яа-яЁё])(сын|дочь|ему|ей|он|она|сам|сама|рад|рада|доволен|'
    r'расстроен|переехал|устал)(?![А-Яа-яЁё])'
    // Прошедшее время мужского рода сразу после имени: «Финни отдохнул».
    r'|Финни\s+(не\s+)?[а-яё]+л(?![А-Яа-яЁё])',
    caseSensitive: false);

void main() {
  test('вуз на доске работ: без рода, обе копии jobs.json одинаковы', () {
    final Map<String, Object?> u =
        (jsonDecode(File('assets/content/world/jobs.json').readAsStringSync())
            as Map<String, Object?>)['university']! as Map<String, Object?>;
    for (final String k in <String>['title', 'short', 'intro']) {
      expect(u[k]! as String, isNot(matches(_gendered)), reason: k);
    }
    expect(File('../../content/jobs.json').readAsStringSync(),
        File('assets/content/world/jobs.json').readAsStringSync(),
        reason: 'копия content/ — та же');
  });

  test('отдых в парке: итог и причина настроения без рода', () {
    final WorldGame park = contentDayWorld();
    ok(park.startWeek());
    ok(park.plan(needs: 0, wants: 300, goal: 0));
    if (park.pendingEvent case final PendingEvent e) {
      ok(park.resolveEvent(
          e.choices.firstWhere((PendingEventChoice c) => c.available).id));
    }
    final WorldResult p = ok(park.leisure('park'));
    expect(p.reason, isNot(matches(_gendered)));
    expect(park.snapshot.moodReason.text, isNot(matches(_gendered)));
    // «Отдохнуть дома» в сборке выключено (`daily_activities`), его строка
    // правлена тем же правилом, но здесь не проверяется.
  });

  test('переезд в новый дом (знакомство): причина настроения без рода', () {
    final WorldGame w = contentDayWorld();
    expect(w.snapshot.moodReason.text, isNot(matches(_gendered)));
  });
}
