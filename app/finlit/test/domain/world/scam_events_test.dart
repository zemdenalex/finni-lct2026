import 'dart:convert';
import 'dart:io';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Мошенничество (голосовое Дениса 15.10 22:54, finni 18.10): 3 события в
/// подаче Дениса — «из банка» просят код или цифры, приз за адрес. Защищает:
/// признак «просят код, цифры или личные данные» назван в ситуации и в
/// ответе Финни; безопасный вариант есть всегда и ничего не стоит; поддаться
/// — минус монеты и настроение; полиции и налоговой нет; на движке сборки
/// событие приходит в свой день, не чаще одного в день, звонок «из банка» —
/// не раньше второй недели. Уронит: событие без безопасного варианта или с
/// бесплатной ошибкой, тексты без признака, событие в первый же день или два
/// события в один день. Почему не ловят прежние: `events_pool_test` считает
/// события, но не проверяет смысл этих трёх.
const List<String> _scams = <String>[
  'scam_sms_code',
  'scam_bank_call',
  'scam_prize',
];

Map<String, Map<String, Object?>> _events() => <String, Map<String, Object?>>{
      for (final Object? e in (jsonDecode(
              File('assets/content/world/events.json').readAsStringSync())
          as Map<String, Object?>)['events']! as List<Object?>)
        (e! as Map<String, Object?>)['id']! as String:
            e as Map<String, Object?>,
    };

List<Map<String, Object?>> _options(Map<String, Object?> e) =>
    (e['options']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _fx(Map<String, Object?> o) =>
    o['effects']! as Map<String, Object?>;

num _n(Map<String, Object?> fx, String k) => (fx[k] as num?) ?? 0;

/// Неделя за неделей до первого показа [id]: (неделя, день) или null.
(int, int)? _firstShown(WorldGame w, String id,
    {int weeks = 2, bool keepWant = true}) {
  for (int week = 0; week < weeks; week++) {
    ok(w.startWeek());
    // «Хочу» не пустое — мошенникам есть что забрать (кроме [keepWant]).
    final int all = w.snapshot.unallocated;
    final int need = keepWant ? w.snapshot.weeklyBill : all;
    ok(w.plan(needs: need, wants: all - need, goal: 0));
    while (true) {
      final PendingEvent? ev = w.pendingEvent;
      if (ev?.id == id) return (w.snapshot.weekNo, w.snapshot.dayInWeek);
      if (ev != null) {
        for (final PendingEventChoice c in ev.choices) {
          if (c.available && w.resolveEvent(c.id).ok) break;
        }
      }
      if (w.sleep().reasonCode != 'day.next') break;
    }
    ok(w.payBills());
  }
  return null;
}

void main() {
  test('три события: признак назван, безопасный вариант бесплатный', () {
    final Map<String, Map<String, Object?>> all = _events();
    final RegExp sign = RegExp('код|цифр|адрес');
    for (final String id in _scams) {
      final Map<String, Object?> e = all[id]!;
      // Только то, что видит ребёнок: заметки `_note` — для команды.
      final String text = jsonEncode(<String, Object?>{
        for (final MapEntry<String, Object?> kv in e.entries)
          if (!kv.key.startsWith('_')) kv.key: kv.value,
      }).toLowerCase();
      expect(text, isNot(contains('полиц')), reason: id);
      expect(text, isNot(contains('налогов')), reason: id);
      expect((e['situation']! as String).toLowerCase(), matches(sign),
          reason: '$id: признак в ситуации');
      final List<Map<String, Object?>> opts = _options(e);
      final List<Map<String, Object?>> safe = opts.where((o) {
        final Map<String, Object?> fx = _fx(o);
        return _n(fx, 'money_pocket_x') >= 0 &&
            _n(fx, 'savings_pocket_x') >= 0 &&
            _n(fx, 'energy') >= 0 &&
            _n(fx, 'happiness') >= 0;
      }).toList();
      expect(safe, isNotEmpty, reason: '$id: безопасный вариант');
      expect(
          safe.any((Map<String, Object?> o) =>
              RegExp('взросл').hasMatch(o['label']! as String)),
          isTrue,
          reason: '$id: «спросить взрослого»');
      final List<Map<String, Object?>> fooled = opts.where((o) {
        final Map<String, Object?> fx = _fx(o);
        return _n(fx, 'loss_wallet_share') > 0 ||
            _n(fx, 'loss_savings_share') > 0;
      }).toList();
      expect(fooled, hasLength(1), reason: '$id: поддаться — один вариант');
      expect(_n(_fx(fooled.single), 'happiness'), lessThan(0));
      expect((fooled.single['finni']! as String).toLowerCase(),
          contains('мошенник'),
          reason: '$id: Финни называет, что это было');
      for (final Map<String, Object?> o in opts) {
        for (final String k in <String>['finni', 'next_step', 'label']) {
          final String? s = o[k] as String?;
          if (s == null) continue;
          expect(s.length, lessThanOrEqualTo(140), reason: '$id.${o['id']}.$k');
        }
      }
    }
  });

  test('движок сборки: «из банка» с кодом — день 4 недели 1, один в день', () {
    final WorldGame w = contentDayWorld();
    expect(_firstShown(w, 'scam_sms_code'), (1, 4));
    final Iterable<WorldEntry> today = w.journal
        .where((WorldEntry e) =>
            e.kind == WorldLedgerKind.eventShown && e.weekNo == 1)
        .skip(3);
    expect(today, hasLength(1), reason: 'в этот день — только это событие');
    final int coins = w.snapshot.available;
    final int pockets = w.snapshot.want + w.snapshot.free;
    expect(pockets, greaterThan(0), reason: 'есть что забрать из «Хочу»');
    final int mood = w.snapshot.happiness;
    ok(w.resolveEvent('tell_code'));
    // Сначала уходит «Хочу» и свободные, потом «Нужно».
    expect(w.snapshot.want + w.snapshot.free, lessThan(pockets));
    expect(w.snapshot.available, lessThan(coins), reason: 'монеты пропали');
    // Ощутимо: около трети всех монет («Нужно», «Хочу», свободные).
    expect(coins - w.snapshot.available, greaterThanOrEqualTo(coins * 0.25));
    expect(coins - w.snapshot.available, lessThanOrEqualTo(coins * 0.35));
    expect(w.snapshot.happiness, lessThan(mood));
  });

  test('«Хочу» пустое — вариант доступен, монеты уходят из «Нужно»', () {
    final WorldGame w = contentDayWorld();
    expect(_firstShown(w, 'scam_sms_code', keepWant: false), isNotNull);
    expect(w.snapshot.want + w.snapshot.free, 0);
    final int need = w.snapshot.need;
    final PendingEventChoice tell = w.pendingEvent!.choices
        .singleWhere((PendingEventChoice c) => c.id == 'tell_code');
    expect(tell.available, isTrue, reason: 'нехватка не блокирует');
    final int mood = w.snapshot.happiness;
    ok(w.resolveEvent('tell_code'));
    expect(w.snapshot.want + w.snapshot.free, 0);
    expect(w.snapshot.need, lessThan(need), reason: 'забрали из «Нужно»');
    expect(w.snapshot.need, greaterThanOrEqualTo(0));
    expect(w.snapshot.happiness, lessThan(mood));
  });

  test('безопасный вариант: монеты целы', () {
    final WorldGame w = contentDayWorld();
    expect(_firstShown(w, 'scam_sms_code'), isNotNull);
    final int coins = w.snapshot.available;
    ok(w.resolveEvent('ask_adult'));
    expect(w.snapshot.available, coins);
  });

  test('звонок «из банка» и приз — не раньше второй недели', () {
    for (final String id in <String>['scam_bank_call', 'scam_prize']) {
      final (int, int)? at = _firstShown(contentDayWorld(), id);
      expect(at, isNotNull, reason: '$id показан за две недели');
      expect(at!.$1, 2, reason: id);
    }
  });

  test('звонок: из копилки уходит не больше, чем в ней', () {
    final WorldGame w = contentDayWorld();
    expect(_firstShown(w, 'scam_bank_call'), isNotNull);
    final int goal = w.snapshot.goal;
    ok(w.resolveEvent('say_numbers'));
    expect(w.snapshot.goal, lessThanOrEqualTo(goal));
    expect(w.snapshot.goal, greaterThanOrEqualTo(0));
    if (goal > 0) expect(w.snapshot.goal, lessThan(goal));
  });

  test('загрузчик: доля потери вне 0–1 — ошибка', () {
    for (final double bad in <double>[-0.1, 1.5]) {
      expect(
          () => EventEffects.fromJson(
              <String, Object?>{'loss_wallet_share': bad}, 'events[0]'),
          throwsFormatException,
          reason: '$bad');
    }
    expect(
        EventEffects.fromJson(
                <String, Object?>{'loss_savings_share': 0.25}, 'e')
            .lossSavingsX,
        0.25);
  });
}
