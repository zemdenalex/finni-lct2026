import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/theme.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/event/event_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Картинка события (Настя 20.10: у «Скидки на игру» — многоэтажка,
/// «замени на иконку, которая ассоциируется с игрой»).
///
/// Защищает: событие со своим значком рисует значок, а не здание; у каждого
/// события Дома в `events.json` значок есть (здание Дома — многоэтажка, к
/// сюжету событий не относится).
/// Уронит: значок не подставляется, и снова идёт здание; новое событие Дома
/// без значка.
PendingEvent _event(String id, String building) => PendingEvent(
      id: id,
      topic: 'planning',
      title: 'Скидка на игру',
      text: '…',
      buildingId: building,
      choices: const <PendingEventChoice>[],
    );

void main() {
  testWidgets('«Скидка на игру»: значок игры, не здание',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: EventArt(_event('game_discount', 'home')))),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('event:icon:game_discount')),
        findsOneWidget);
    expect(find.byIcon(Icons.sports_esports_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: 'не картинка здания');
  });

  testWidgets('событие без значка — по-прежнему здание',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: EventArt(_event('x_unknown', 'grocery')))),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('event:icon:x_unknown')),
        findsNothing);
  });

  test('у каждого события Дома в events.json есть значок', () {
    final Object? root = jsonDecode(
        File('${WorldContentLoader.base}/events.json').readAsStringSync());
    final List<Object?> events = (root! as Map<String, Object?>)['events']!
        as List<Object?>;
    final List<String> missing = <String>[
      for (final Object? e in events)
        if (e is Map<String, Object?> &&
            e['building'] == 'home' &&
            !eventIcons.containsKey(e['id']))
          e['id']! as String,
    ];
    expect(missing, isEmpty);
  });
}
