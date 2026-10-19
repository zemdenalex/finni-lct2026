import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// DEN-25, вариант A (ТЗ 2.5.2.2 «имя видно на главном»), за флагом
/// `economy.json → room.pet_name`: строка над Финни — «Имя · состояние».
/// Защищает: флаг выключен — как сдано (имени нет); включён — имя, которое
/// выбрал ребёнок, над Финни и в озвучке; имя до 12 знаков при шрифте 1,3 на
/// 360 dp не вылезает (длиннее — «…»). Уронит: имя не то (по умолчанию
/// вместо выбранного), флаг не читается, длинное имя ломает строку.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldGame _world({required bool on, String name = 'Бублик'}) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  e['room'] = <String, Object?>{
    ...(e['room']! as Map<String, Object?>),
    'pet_name': on,
  };
  final WorldGame w = WorldGame(
    config: worldConfigFromContent(WorldContent.parse(
      economy: jsonEncode(e),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
      roomItems: _read('room_items.json'),
    )),
    onboarding:
        OnboardingProgress(step: OnboardingProgress.stepDone, finniName: name),
  );
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return w;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 20));
    }
  });
}

final Finder _name = find.byKey(const ValueKey<String>('finni:name'));

void main() {
  // Ширина имени меряется настоящим шрифтом приложения, не подстановочным.
  setUpAll(loadAppFonts);

  test('сборка: флаг включён (DEN-25 A, Денис 18.10)', () {
    final Map<String, Object?> e =
        jsonDecode(_read('economy.json')) as Map<String, Object?>;
    expect((e['room']! as Map<String, Object?>)['pet_name'], isTrue);
  });

  testWidgets('флаг выключен — имени над Финни нет',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(),
          world: _world(on: false));
    });
    await _settle(tester);
    expect(_name, findsNothing);
  });

  testWidgets('флаг включён — имя ребёнка над Финни и в озвучке',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(),
          world: _world(on: true));
    });
    await _settle(tester);
    expect(tester.widget<Text>(_name).data, 'Бублик');
    expect(find.bySemanticsLabel(RegExp('Бублик')), findsWidgets);
    sem.dispose();
  });

  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('имя в 12 знаков, шрифт 1,3 — без переполнения · ${o.key}',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: _world(on: true, name: 'Константинка'),
            size: o.value,
            textScale: 1.3);
      });
      await _settle(tester);
      expect(tester.takeException(), isNull);
      final Text t = tester.widget<Text>(_name);
      expect(t.data, 'Константинка');
      expect(t.maxLines, 1);
      expect(t.overflow, TextOverflow.ellipsis);
      // Имя до 12 знаков — целиком, без «…».
      expect(tester.renderObject<RenderParagraph>(_name).didExceedMaxLines,
          isFalse,
          reason: 'имя в 12 знаков обрезано');
      // Строка состояния рядом не пропала.
      expect(
          find.byKey(const ValueKey<String>('finni:status')), findsOneWidget);
    });
  }
}
