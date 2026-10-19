import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_game_loader.dart';
import '../../support/world_harness.dart' show contentDayConfig;

/// C8 / DEN-35 B: у работы 2–3 урока, после каждой смены с мини-игрой —
/// следующий по кругу. Защищает: порядок a → b → c → a; пропущенный урок не
/// задерживает очередь (новая смена — следующий урок); перезапуск из журнала
/// даёт тот же ждущий урок; в журнале выбора — id урока; одиночный урок
/// (объект, как раньше) работает без id; повтор id — ошибка загрузки.
/// Уронит: урок всегда первый, счёт смен обнуляется с неделей и чередование
/// после перезапуска сбивается, урок выбирается по числу решённых, а не смен.
/// Почему не ловят прежние: `lessons_test` знает один урок на работу.
Map<String, Object?> _jobs() =>
    jsonDecode(File('assets/content/world/jobs.json').readAsStringSync())
        as Map<String, Object?>;

/// Кассиру — три урока: копии первого с id a / b / c и своим заголовком.
String _threeCashier() {
  final Map<String, Object?> j = _jobs();
  final Map<String, Object?> ls = j['lessons']! as Map<String, Object?>;
  final Object? one = ls['cashier'];
  final Map<String, Object?> base = one is List<Object?>
      ? one.first! as Map<String, Object?>
      : one! as Map<String, Object?>;
  ls['cashier'] = <Object?>[
    for (final String id in <String>['a', 'b', 'c'])
      <String, Object?>{...base, 'id': 'cashier_$id', 'title': 'Урок $id'},
  ];
  return jsonEncode(j);
}

Future<WorldGame> _world() => openWorldGame(
    read: (String p) async =>
        p.endsWith('jobs.json') ? _threeCashier() : File(p).readAsString(),
    storage: MemoryStorage());

String? _pending(WorldGame w) => w.pendingLesson?.title;

void main() {
  test('сборка: по 3 урока на каждую из 7 работ, 21 урок, id разные', () {
    final Set<String> jobs = <String>{
      for (final WorldJob j in contentDayConfig.jobs) j.id,
    };
    expect(jobs, hasLength(7));
    for (final String j in jobs) {
      expect(contentDayConfig.lessonsFor(j), hasLength(3), reason: j);
    }
    expect(contentDayConfig.lessons, hasLength(21));
    expect(contentDayConfig.lessons.map((WorldLesson l) => l.lessonId).toSet(),
        hasLength(21));
  });

  test('уроки работы чередуются по сменам, пропуск не держит очередь',
      () async {
    final WorldGame w = await _world();
    expect(w.config.lessonsFor('cashier'), hasLength(3));
    expect(w.startWeek().ok, isTrue);
    expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
    final List<String?> seen = <String?>[];
    for (int i = 0; i < 4; i++) {
      expect(w.completeJob('cashier', score: 0.5).ok, isTrue);
      seen.add(_pending(w));
      if (i == 1) continue; // второй урок пропущен
      final LessonOffer l = w.pendingLesson!;
      final LessonChoiceView c =
          l.choices.firstWhere((LessonChoiceView c) => c.available);
      expect(w.resolveLesson(c.id).ok, isTrue);
      // За уроком может идти запись награды — берём последнюю запись урока.
      final WorldEntry e = w.journal
          .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.lessonChoice);
      expect(e.args['lessonId'], 'cashier_${'abca'[i]}');
      if (w.snapshot.dayInWeek < w.config.daysPerWeek) w.sleep();
    }
    expect(seen, <String>['Урок a', 'Урок b', 'Урок c', 'Урок a']);
  });

  test('перезапуск из журнала: тот же ждущий урок', () async {
    final WorldGame w = await _world();
    expect(w.startWeek().ok, isTrue);
    expect(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0).ok, isTrue);
    expect(w.completeJob('cashier', score: 0.5).ok, isTrue);
    w.sleep();
    expect(w.completeJob('cashier', score: 0.5).ok, isTrue);
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(_pending(r), 'Урок b');
    expect(_pending(r), _pending(w));
  });

  test('загрузчик: повтор id урока — ошибка; одиночный объект — без id', () {
    final Map<String, Object?> j =
        jsonDecode(_threeCashier()) as Map<String, Object?>;
    final List<Object?> c =
        (j['lessons']! as Map<String, Object?>)['cashier']! as List<Object?>;
    (c[1]! as Map<String, Object?>)['id'] = 'cashier_a';
    String read(String f) => File('assets/content/world/$f').readAsStringSync();
    expect(
        () => WorldContent.parse(
            economy: read('economy.json'),
            jobs: jsonEncode(j),
            events: read('events.json'),
            roomItems: read('room_items.json')),
        throwsA(isA<WorldContentError>()));
  });
}
