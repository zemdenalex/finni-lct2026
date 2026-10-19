import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/daily/daily_layer.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tap_target_guideline.dart';
import '../../support/world_harness.dart';

/// Аудит доступности 16.10, п. 2: карточка «Сегодня» и лист холодильника.
/// Общий тест целей касания (`tap_targets_test.dart`) их не видит: дела
/// включаются флагом `day_cycle.daily_activities`, в сборке он выключен.
///
/// Уронит: дело или кнопка листа меньше 48 dp, дело без подписи для
/// TalkBack, бледный текст карточки; в альбомной — переполнение ряда дел.
void main() {
  WorldGame living() {
    final Map<String, Object?> eco = jsonDecode(
            File('${WorldContentLoader.base}/economy.json').readAsStringSync())
        as Map<String, Object?>;
    eco['day_cycle'] = <String, Object?>{
      ...(eco['day_cycle'] as Map<String, Object?>? ?? <String, Object?>{}),
      'daily_activities': true,
    };
    String read(String f) =>
        File('${WorldContentLoader.base}/$f').readAsStringSync();
    final WorldGame w = WorldGame(
        config: worldConfigFromContent(WorldContent.parse(
            economy: jsonEncode(eco),
            jobs: read('jobs.json'),
            events: read('events.json'))));
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    return w;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> guidelines(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(edgeTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  // Альбомная 640×360: карточка в узкой боковой «Сейчас» — дела друг под
  // другом (было переполнение 39 px, аудит 16.10, правка front3 41c18c5).
  for (final MapEntry<String, Size> o in <String, Size>{
    'портрет 360×640': portrait,
    'альбомная 640×360': landscape,
  }.entries) {
    testWidgets('«Сегодня» и лист холодильника · ${o.key}',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const DailyLayer(child: RoomScreen()),
            world: living(), size: o.value);
      });
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('daily:card')), findsOneWidget);
      await guidelines(tester);
      await tester.tap(find.byKey(const ValueKey<String>('daily:shop')));
      await settle(tester);
      await guidelines(tester);
      sem.dispose();
    });
  }
}
