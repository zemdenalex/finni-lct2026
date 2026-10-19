import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Кнопка «Событие ждёт» в комнате (флаг `economy.json → room.event_badge`).
///
/// Защищает: пока у мира есть событие без ответа, в комнате видна кнопка
/// (раньше событие было видно только по «!» у здания в городе), TalkBack
/// читает название события, касание открывает экран события; без флага и
/// после ответа кнопки нет. Уронит: флаг не читается из json; кнопка не
/// смотрит на `pendingEvent`; касание ведёт не туда.

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Числа сборки (режим «неделя», как у экранных тестов) с флагом [badge].
WorldConfig _config({required bool badge}) {
  final Map<String, Object?> eco =
      jsonDecode(weekMode(_read('economy.json'))) as Map<String, Object?>;
  eco['room'] = <String, Object?>{
    ...(eco['room']! as Map<String, Object?>),
    'event_badge': badge,
  };
  return worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
    roomItems: _read('room_items.json'),
  ));
}

final WorldConfig _on = _config(badge: true);
final WorldConfig _off = _config(badge: false);

/// Мир, у которого ждёт событие: недели идут, пока оно не выпадет.
WorldGame _withEvent(WorldConfig c) {
  final WorldGame w = WorldGame(config: c);
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0));
  for (int week = 0; week < 12 && w.pendingEvent == null; week++) {
    ok(sleepWeek(w));
    w.payBills();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0));
  }
  expect(w.pendingEvent, isNotNull, reason: 'за 12 недель события не было');
  return w;
}

const ValueKey<String> _badge = ValueKey<String>('room:event');

void main() {
  test('флаг: в сборке включён (finni 17.10), из json читается', () {
    expect(shippedContent.room.eventBadge, isTrue);
    expect(shippedDayContent.room.eventBadge, isTrue);
    expect(_on.room.eventBadge, isTrue);
    expect(_off.room.eventBadge, isFalse);
  });

  testWidgets(
      'событие ждёт: кнопка видна, TalkBack — название, касание — экран '
      'события', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final WorldGame w = _withEvent(_on);
    final String title = w.pendingEvent!.title;
    await pumpWorldScreen(tester, const RoomScreen(), world: w);
    expect(find.byKey(_badge), findsOneWidget);
    expect(find.bySemanticsLabel('Событие ждёт: $title'), findsOneWidget);
    await tester.tap(find.byKey(_badge));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('event:back')), findsOneWidget);
    h.dispose();
  });

  testWidgets('без флага кнопки нет, хотя событие ждёт',
      (WidgetTester tester) async {
    final WorldGame w = _withEvent(_off);
    await pumpWorldScreen(tester, const RoomScreen(), world: w);
    expect(find.byKey(_badge), findsNothing);
  });

  testWidgets('событие решено — кнопка пропадает', (WidgetTester tester) async {
    final WorldGame w = _withEvent(_on);
    final PendingEventChoice c = w.pendingEvent!.choices
        .firstWhere((PendingEventChoice c) => c.available);
    ok(w.resolveEvent(c.id));
    await pumpWorldScreen(tester, const RoomScreen(), world: w);
    expect(find.byKey(_badge), findsNothing);
  });

  for (final MapEntry<String, Size> s in bothOrientations.entries) {
    testWidgets('${s.key}, шрифт 1,3: без переполнения, цели ≥ 48 dp',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await pumpWorldScreen(tester, const RoomScreen(),
          world: _withEvent(_on), size: s.value, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_badge), findsOneWidget);
      expect(
          tester.getSize(find.byKey(_badge)).height, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      h.dispose();
    });
  }
}
