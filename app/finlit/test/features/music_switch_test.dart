import 'dart:convert';
import 'dart:io';

import 'package:finlit/app_state.dart';
import 'package:finlit/core/music.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/world_harness.dart';

/// Флаг `audio.background_music` (DEN-34: права на трек не подтверждены —
/// музыку должно быть можно убрать одной правкой контента).
///
/// Защищает: флаг выключен — плеер не создаётся и не играет, «Музыка» не
/// видна ни в настройках, ни в меню ⋮ комнаты; включён — всё как раньше.
/// Уронит: флаг не читается из economy.json, плеер создаётся при старте мимо
/// флага, тумблер или пункт меню остаются мёртвыми ручками.
class _Sink implements MusicSink {
  final List<String> calls = <String>[];
  @override
  Future<void> play(String asset) async => calls.add('play');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async {}
}

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

WorldContent _content(String economy) => WorldContent.parse(
    economy: economy, jobs: _read('jobs.json'), events: _read('events.json'));

/// Спрайты анимируются бесконечно — pumpAndSettle не дождётся покоя.
Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<AppState> _booted(WidgetTester tester) async {
  final AppState app = AppState(MemoryStorage());
  await tester.runAsync(app.boot);
  return app;
}

void main() {
  setUp(rootBundle.clear);

  test('сборка: флаг включён; false в json — выключен; нет ключа — включён',
      () {
    expect(shippedDayContent.economy.backgroundMusic, isTrue);
    final Map<String, Object?> eco =
        jsonDecode(_read('economy.json')) as Map<String, Object?>;
    eco['audio'] = <String, Object?>{'background_music': false};
    expect(_content(jsonEncode(eco)).economy.backgroundMusic, isFalse);
    eco.remove('audio');
    expect(_content(jsonEncode(eco)).economy.backgroundMusic, isTrue);
  });

  for (final bool enabled in <bool>[false, true]) {
    testWidgets('флаг ${enabled ? 'включён' : 'выключен'}: плеер и мелодия',
        (WidgetTester tester) async {
      final AppState app = await _booted(tester);
      expect(app.game.profile.settings.musicOn, isTrue);
      expect(app.game.profile.settings.soundOn, isTrue);
      int created = 0;
      final _Sink sink = _Sink();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: BackgroundMusic(
          enabled: enabled,
          createSink: () {
            created++;
            return sink;
          },
          child: const SizedBox(),
        ),
      ));
      await tester.pump();
      if (enabled) {
        expect(created, 1);
        expect(sink.calls, <String>['play']);
      } else {
        expect(created, 0, reason: 'флаг выключен — плеер не создаётся');
        expect(sink.calls, isEmpty);
      }
    });

    testWidgets(
        'флаг ${enabled ? 'включён' : 'выключен'}: «Музыка» в настройках',
        (WidgetTester tester) async {
      final AppState app = await _booted(tester);
      await pumpWorldScreen(tester,
          BackgroundMusic(enabled: enabled, child: const WorldSettingsScreen()),
          app: app, size: const Size(360, 1400));
      expect(find.byKey(WorldSettingsScreen.soundKey), findsOneWidget);
      expect(find.byKey(WorldSettingsScreen.motionKey), findsOneWidget);
      expect(find.byKey(WorldSettingsScreen.musicKey),
          enabled ? findsOneWidget : findsNothing);
      await tester.tap(find.byKey(WorldSettingsScreen.helpKey));
      await _step(tester);
      expect(find.textContaining('«Музыка»'),
          enabled ? findsOneWidget : findsNothing,
          reason: 'подсказка не описывает тумблер, которого нет');
    });

    testWidgets('флаг ${enabled ? 'включён' : 'выключен'}: пункт меню ⋮',
        (WidgetTester tester) async {
      final AppState app = await _booted(tester);
      final World w = worldKinds.last.make();
      ok(w.startWeek());
      ok(w.plan(needs: 250, wants: 100, goal: 50));
      await tester.runAsync(() => pumpWorldScreen(
          tester, BackgroundMusic(enabled: enabled, child: const RoomScreen()),
          world: w, app: app, size: landscape));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('room:menu')));
      await _step(tester);
      // Меню открыто («Взрослым» в сборке нет — DEN-27, `adult.section`).
      expect(
          find.byKey(const ValueKey<String>('room:settings')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('room:music')),
          enabled ? findsOneWidget : findsNothing);
    });
  }
}
