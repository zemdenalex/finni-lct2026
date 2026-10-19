import 'dart:convert';
import 'dart:io';

import 'package:finlit/app_state.dart';
import 'package:finlit/core/build_info.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Номер сборки (finni 18.10): раздел «Взрослым» скрыт (`adult.section`
/// false, DEN-27), и «Сборка …» переехала в блок «Игра заново и проверка»
/// внизу настроек — иначе номера не видно нигде. При открытом разделе строка
/// там (`adult_build_line_test`), в настройках её нет. Уронит: строку
/// потеряли при переносе правил текстов или показали дважды.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldGame _world({required bool section}) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  e['adult'] = <String, Object?>{
    ...(e['adult']! as Map<String, Object?>),
    'section': section,
  };
  return WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
          economy: jsonEncode(e),
          jobs: _read('jobs.json'),
          events: _read('events.json'),
          roomItems: _read('room_items.json'))));
}

void main() {
  for (final bool section in <bool>[false, true]) {
    testWidgets(
        'adult.section = $section: «Сборка» в настройках '
        '${section ? 'нет' : 'внизу'}', (WidgetTester tester) async {
      // Без профиля экран ждёт и блоков не строит — как в приложении.
      final AppState app = AppState(MemoryStorage());
      await tester.runAsync(app.boot);
      await pumpWorldScreen(tester, const WorldSettingsScreen(),
          world: _world(section: section),
          app: app,
          size: const Size(360, 1400));
      final Finder line = find.byKey(WorldSettingsScreen.buildKey);
      if (section) {
        expect(line, findsNothing);
        return;
      }
      expect(line, findsOneWidget);
      expect(find.descendant(of: line, matching: find.text('Сборка $buildSha')),
          findsOneWidget);
    });
  }
}
