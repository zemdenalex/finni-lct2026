import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры: имя над Финни (DEN-25 A, флаг `room.pet_name`), сборка 7 дней,
/// шрифт 1,3, имя в 12 знаков:
///
///     flutter test --update-goldens tool/render_pet_name_test.dart
///       →  build/kadry-pet-name/*.png
///
/// На CI не гоняется (папка tool/).
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldGame _world(String name) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  e['room'] = <String, Object?>{
    ...(e['room']! as Map<String, Object?>),
    'pet_name': true,
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

Future<void> _frames(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(loadAppFonts);

  for (final (String name, Size size, String finni) in <(String, Size, String)>[
    ('01-imya-portret', const Size(360, 640), 'Константинка'),
    ('02-imya-albom', const Size(640, 360), 'Константинка'),
    ('03-imya-korotkoe-portret', const Size(360, 640), 'Бублик'),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: _world(finni), size: size, textScale: 1.3);
      });
      await _frames(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../build/kadry-pet-name/$name.png'));
    });
  }
}
