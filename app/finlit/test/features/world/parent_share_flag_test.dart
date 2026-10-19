import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// EXP-9 «0» (Денис 18.10, тема 118: «не делаем»): кнопки «Отправить
/// родителю» на «Прогрессе» нет. Код кнопки остаётся за флагом
/// `economy.json → progress.share_parent`.
///
/// Защищает: в сборке флаг false и кнопки нет; флаг true — кнопка есть и
/// показывает, что увидит родитель. Уронит: кнопка вернулась без флага, флаг
/// не читается из файла (тогда её не включить без правки кода).
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Мир дней из файлов сборки; [on] — подменить флаг, null — как в файле.
WorldGame _world({bool? on}) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  if (on != null) {
    e['progress'] = <String, Object?>{
      ...?(e['progress'] as Map<String, Object?>?),
      'share_parent': on,
    };
  }
  final WorldGame w = WorldGame(
    config: worldConfigFromContent(WorldContent.parse(
      economy: jsonEncode(e),
      jobs: _read('jobs.json'),
      events: _read('events.json'),
      roomItems: _read('room_items.json'),
    )),
    onboarding: const OnboardingProgress(step: OnboardingProgress.stepDone),
  );
  ok(w.startWeek());
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return w;
}

void main() {
  final Finder share = find.byKey(const ValueKey<String>('history:share'));

  test('сборка: progress.share_parent = false', () {
    final Map<String, Object?> e =
        jsonDecode(_read('economy.json')) as Map<String, Object?>;
    expect((e['progress']! as Map<String, Object?>)['share_parent'], isFalse);
  });

  testWidgets('сборка: на «Прогрессе» кнопки «Отправить родителю» нет',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, const HistoryScreen(), world: _world());
    expect(share, findsNothing);
    expect(find.text('Отправить родителю'), findsNothing);
  });

  testWidgets('флаг включён — кнопка есть и показывает, что уйдёт родителю',
      (WidgetTester tester) async {
    await pumpWorldScreen(tester, const HistoryScreen(),
        world: _world(on: true));
    expect(share, findsOneWidget);
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('share:preview')), findsOneWidget);
  });
}
