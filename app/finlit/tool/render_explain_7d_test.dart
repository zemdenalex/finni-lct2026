import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart' show JobPlayArgs;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/world_harness.dart';
import 'test_fonts.dart';

/// Кадры объяснений модели «7 дней» (везение на смене, «?» настроения,
/// опыт на карточке, сон) — настоящие экраны на движке сборки, 360×640,
/// шрифт 1,3:
///
///     flutter test --update-goldens tool/render_explain_7d_test.dart
///       →  build/kadry-7d/*.png
///
/// На CI не гоняется (папка tool/).
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Мир дней сборки; [luck] — выпадают всегда только эти сценарии.
WorldGame _dayWorld({List<String> luck = const <String>[]}) {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  final Map<String, Object?> dc = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
  };
  final Map<String, Object?> sl = dc['shift_luck']! as Map<String, Object?>;
  dc['shift_luck'] = <String, Object?>{
    'chance': 1,
    'scenarios': <Object?>[
      for (final Object? s in sl['scenarios']! as List<Object?>)
        if (luck.contains((s! as Map<String, Object?>)['id'])) s,
    ],
  };
  eco['day_cycle'] = dc;
  final WorldGame w = WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  )));
  ok(w.startWeek());
  ok(w.plan(needs: 100, wants: 100, goal: 0));
  return w;
}

Future<void> _frames(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(f);
  await _frames(tester);
}

/// Кассир без ошибок: сдачу считаем по тексту покупки на экране — порядок
/// покупателей зависит от раунда и контента (как в explain_7d_test).
Future<void> _playCashier(WidgetTester tester) async {
  await _tap(tester, 'job:start');
  for (int i = 0; i < 2; i++) {
    final String deal = tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey<String>('cashier:purchase')),
            matching: find.byType(Text),
            matchRoot: true))
        .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join(' ');
    final RegExpMatch m =
        RegExp(r'стоит (\d+)\. Покупатель даёт (\d+)').firstMatch(deal)!;
    int change = int.parse(m.group(2)!) - int.parse(m.group(1)!);
    for (final int c in <int>[10, 5, 2, 1]) {
      while (change >= c) {
        await _tap(tester, 'cashier:coin:$c');
        change -= c;
      }
    }
    await _tap(tester, 'cashier:give');
    await _tap(tester, 'cashier:next');
  }
}

/// Прокрутить так, чтобы [key] стоял на доле [at] высоты видимого.
Future<void> _scrollTo(WidgetTester tester, String key, double at) async {
  await Scrollable.ensureVisible(
      tester.element(find.byKey(ValueKey<String>(key))),
      alignment: at);
  await _frames(tester);
}

Future<void> _shot(String name) => expectLater(
    find.byType(MaterialApp), matchesGoldenFile('../build/kadry-7d/$name.png'));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('01 карточка смены: опыт', (WidgetTester tester) async {
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
        world: _dayWorld(), textScale: 1.3);
    await _frames(tester);
    await _scrollTo(tester, 'job:offer:xp', 0.15);
    await _shot('01-kartochka-opyt');
    await _tap(tester, 'job:offer:xpHow');
    await _shot('02-kak-schitaetsya-opyt');
  });

  testWidgets('итог смены: повезло, «?» настроения',
      (WidgetTester tester) async {
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
        world: _dayWorld(luck: <String>['cashier_good_exact']), textScale: 1.3);
    await _playCashier(tester);
    await _scrollTo(tester, 'job:result:luck', 0.05);
    await _shot('03-itog-povezlo');
    await _tap(tester, 'job:result:moodWhy');
    await _shot('04-pochemu-nastroenie');
  });

  testWidgets('итог смены: не повезло', (WidgetTester tester) async {
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
        world: _dayWorld(luck: <String>['cashier_bad_coins']), textScale: 1.3);
    await _playCashier(tester);
    await _scrollTo(tester, 'job:result:luck', 0.05);
    await _shot('05-itog-ne-povezlo');
  });

  testWidgets('итог смены: альбомная 640×360', (WidgetTester tester) async {
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
        world: _dayWorld(luck: <String>['cashier_good_exact']),
        size: landscape,
        textScale: 1.3);
    await _playCashier(tester);
    await _shot('06-itog-povezlo-albom');
  });

  testWidgets('диалог «Спать»', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(),
          world: _dayWorld(), textScale: 1.3);
    });
    await _frames(tester);
    await _tap(tester, 'room:bed');
    await _shot('07-son');
    await _tap(tester, 'sleep:more');
    await _shot('08-son-podrobnee');
  });
}
