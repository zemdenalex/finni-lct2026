import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/theme.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/games/dog_walker_game.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/jobs/mini_games.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/test_fonts.dart';
import '../../../support/world_harness.dart';

/// Мини-игра выгульщика собак (`jobs.json → jobs.dog_walker`) и её флаг
/// `economy.json → day_cycle.dog_walk_game`.
///
/// Защищает: при флаге true у выгульщика прогулка, а не «Сделать»; оценка
/// 1,0 за кратчайший путь, меньше за лишние шаги, не ниже 0,5; каждая
/// прогулка из файла решается, и `best_steps` — правда кратчайший путь (свой
/// BFS теста, не код игры); клетки ≥ 48 dp и без переполнения на 360 × 640 и
/// 640 × 360 при шрифте 1,3; метки клеток для TalkBack; без движения собака
/// переходит сразу. Уронит: оценка без лишних шагов, неверный `best_steps`
/// или стенка поперёк тропинки в файле, флаг мимо реестра, мелкие клетки.
typedef _Cell = ({int r, int c});

/// Состояние поиска: клетка и набор собранного (биты).
typedef _State = (_Cell, int);

DogWalkContent get _content => contentJobGames.dogWalker;

/// Кратчайший путь прогулки: собрать все предметы и дойти до дома.
/// Состояние — клетка и набор собранного; дом впускает только со всем.
List<_Cell>? _shortest(DogWalkLevel l, DogWalkContent c) {
  final int n = l.size;
  final List<_Cell> items = <_Cell>[
    for (int r = 0; r < n; r++)
      for (int k = 0; k < n; k++)
        if (c.items.containsKey(l.map[r][k])) (r: r, c: k),
  ];
  final int full = (1 << items.length) - 1;
  late _Cell start;
  for (int r = 0; r < n; r++) {
    for (int k = 0; k < n; k++) {
      if (l.map[r][k] == 'S') start = (r: r, c: k);
    }
  }
  final Map<_State, _State> from = <_State, _State>{};
  final Queue<_State> q = Queue<_State>()..add((start, 0));
  final Set<_State> seen = <_State>{(start, 0)};
  while (q.isNotEmpty) {
    final _State s = q.removeFirst();
    for (final (int, int) d in const <(int, int)>[
      (1, 0),
      (-1, 0),
      (0, 1),
      (0, -1)
    ]) {
      final _Cell p = (r: s.$1.r + d.$1, c: s.$1.c + d.$2);
      if (p.r < 0 || p.c < 0 || p.r >= n || p.c >= n) continue;
      final String t = l.map[p.r][p.c];
      if (c.blocks.containsKey(t)) continue;
      final int i = items.indexOf(p);
      final int mask = i < 0 ? s.$2 : s.$2 | (1 << i);
      if (t == 'G' && mask != full) continue;
      final _State next = (p, mask);
      if (!seen.add(next)) continue;
      from[next] = s;
      if (t == 'G') {
        final List<_Cell> path = <_Cell>[];
        for (_State at = next; at != (start, 0); at = from[at]!) {
          path.add(at.$1);
        }
        return path.reversed.toList();
      }
      q.add(next);
    }
  }
  return null;
}

Future<void> _pumpGame(WidgetTester tester, DogWalkLevel l,
    {required void Function(double) onDone,
    bool disableAnimations = false}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: DogWalkerGame(
            key: UniqueKey(), content: _content, variant: l.id, onDone: onDone),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _step(WidgetTester tester, _Cell p) async {
  final Finder f = find.byKey(ValueKey<String>('dogwalk:cell:${p.r}:${p.c}'));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _walk(WidgetTester tester, List<_Cell> path) async {
  for (final _Cell p in path) {
    await _step(tester, p);
  }
}

Future<void> _finish(WidgetTester tester) async {
  final Finder done = find.byKey(const ValueKey<String>('dogwalk:done'));
  await tester.ensureVisible(done);
  await tester.pumpAndSettle();
  await tester.tap(done);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) => tester
    .widgetList<Text>(find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Text),
        matchRoot: true))
    .map((Text t) => t.data ?? '')
    .join(' ');

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

World _withDog() {
  final World w = worldKinds.last.make(); // мир из content/
  ok(w.startWeek());
  ok(w.plan(needs: 100, wants: 100, goal: 0));
  ok(w.demoUnlockAllJobs());
  return w;
}

void main() {
  // Настоящие шрифты: «подсказка видна без прокрутки» меряется ими, а не
  // квадратами Ahem.
  setUpAll(loadAppFonts);

  group('контент jobs.dog_walker', () {
    test('три прогулки: 4×4, 5×5, 6×6 — от лёгкой к трудной', () {
      expect(_content.levels.map((DogWalkLevel l) => l.size), <int>[4, 5, 6]);
      for (final DogWalkLevel l in _content.levels) {
        for (final String row in l.map) {
          expect(row.length, l.size, reason: '${l.id}: карта квадратная');
        }
      }
    });

    for (final DogWalkLevel l in contentJobGames.dogWalker.levels) {
      test('${l.id}: прогулка решается, best_steps — кратчайший путь (BFS)',
          () {
        final List<_Cell>? path = _shortest(l, _content);
        expect(path, isNotNull, reason: 'собаку не провести');
        expect(l.bestSteps, path!.length);
      });
    }

    test('ступень по кругу от числа смен', () {
      expect(
          <String>[for (int r = 0; r < 4; r++) _content.levelFor(null, r).id],
          <String>['short', 'yard', 'park', 'short']);
    });

    test('нечего собрать — ошибка файла с путём до поля', () {
      final Map<String, Object?> jobs =
          jsonDecode(_read('jobs.json')) as Map<String, Object?>;
      final Map<String, Object?> dog = (jobs['jobs']!
          as Map<String, Object?>)['dog_walker']! as Map<String, Object?>;
      final Map<String, Object?> level =
          (dog['levels']! as List<Object?>).first! as Map<String, Object?>;
      level['map'] = <String>['S...', '....', '....', '...G'];
      expect(
          () => WorldContent.parse(
              economy: _read('economy.json'),
              jobs: jsonEncode(jobs),
              events: _read('events.json')),
          throwsA(isA<WorldContentError>().having((WorldContentError e) => '$e',
              'текст', contains('jobs.dog_walker.levels[0].map'))));
    });
  });

  group('флаг day_cycle.dog_walk_game', () {
    test('в сборке true; без ключа — значение по умолчанию, оно же файл', () {
      expect(shippedContent.economy.dogWalkGame, isTrue);
      expect(
          EconomyContent.dogWalkGameDefault, shippedContent.economy.dogWalkGame,
          reason: 'значение по умолчанию = файл');
      expect(contentJobGames.dogWalkGame, isTrue);
      final Map<String, Object?> eco =
          jsonDecode(_read('economy.json')) as Map<String, Object?>;
      final Map<String, Object?> dc = <String, Object?>{
        ...(eco['day_cycle']! as Map<String, Object?>)
      }..remove('dog_walk_game');
      eco['day_cycle'] = dc;
      WorldContent parse() => WorldContent.parse(
          economy: jsonEncode(eco),
          jobs: _read('jobs.json'),
          events: _read('events.json'));
      expect(parse().economy.dogWalkGame, EconomyContent.dogWalkGameDefault);
      dc['dog_walk_game'] = false;
      expect(parse().economy.dogWalkGame, isFalse);
    });

    test('true — прогулка с её подсказкой; false — заглушка «Сделать»', () {
      final MiniGame on = miniGameFor('dog_walker', contentJobGames);
      expect(on.help, dogWalkerHelp);
      expect(identical(on, placeholderGame), isFalse);
      final MiniGame off = miniGameFor('dog_walker', contentJobGamesDogStub);
      expect(identical(off, placeholderGame), isTrue);
      // Флаг касается только выгульщика.
      expect(miniGameFor('courier', contentJobGamesDogStub).help,
          isNot(placeholderGame.help));
    });

    testWidgets('экран смены: при флаге true — поле прогулки, не «Сделать»',
        (WidgetTester tester) async {
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('dog_walker')),
          world: _withDog());
      await tester
          .ensureVisible(find.byKey(const ValueKey<String>('job:start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('job:start')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('dogwalk:cell:0:0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('game:placeholder:do')),
          findsNothing);
    });
  });

  group('оценка', () {
    for (final DogWalkLevel l in contentJobGames.dogWalker.levels) {
      testWidgets('${l.id}: кратчайший путь — 1,0',
          (WidgetTester tester) async {
        double? score;
        await _pumpGame(tester, l, onDone: (double s) => score = s);
        await _walk(tester, _shortest(l, _content)!);
        expect(_text(tester, 'dogwalk:result'), contains('самый короткий'));
        await _finish(tester);
        expect(score, 1.0);
      });
    }

    // Короткая прогулка: best_steps 8. «Вправо и обратно» в начале — 10
    // шагов, 8 / 10 = 0,8.
    testWidgets('два лишних шага — 0,8; ставка не режется до нуля',
        (WidgetTester tester) async {
      final DogWalkLevel l = _content.levelFor('short', 0);
      double? score;
      await _pumpGame(tester, l, onDone: (double s) => score = s);
      await _walk(tester, <_Cell>[(r: 0, c: 1), (r: 0, c: 0)]);
      await _walk(tester, _shortest(l, _content)!);
      expect(_text(tester, 'dogwalk:status'), contains('Шаги: 10'));
      expect(_text(tester, 'dogwalk:result'), contains('короче'));
      await _finish(tester);
      expect(score, closeTo(0.8, 1e-9));
    });

    testWidgets('много лишних шагов — не ниже 0,5',
        (WidgetTester tester) async {
      final DogWalkLevel l = _content.levelFor('short', 0);
      double? score;
      await _pumpGame(tester, l, onDone: (double s) => score = s);
      for (int i = 0; i < 12; i++) {
        await _walk(tester, <_Cell>[(r: 0, c: 1), (r: 0, c: 0)]);
      }
      await _walk(tester, _shortest(l, _content)!);
      await _finish(tester);
      expect(score, 0.5);
    });

    testWidgets('препятствие и ранний дом — шаг не считается, подсказка урока',
        (WidgetTester tester) async {
      final DogWalkLevel l = _content.levelFor('short', 0);
      bool done = false;
      await _pumpGame(tester, l, onDone: (_) => done = true);
      // Короткая: «S..W» — лужа в (0, 3).
      await _walk(tester, <_Cell>[(r: 0, c: 1), (r: 0, c: 2)]);
      await _step(tester, (r: 0, c: 3));
      expect(_text(tester, 'dogwalk:note'), contains('неожиданная трата'));
      expect(_text(tester, 'dogwalk:status'), contains('Шаги: 2'));
      // Монета в (1, 3): заработок и «про запас».
      await _walk(tester, <_Cell>[(r: 1, c: 2), (r: 1, c: 3)]);
      expect(_text(tester, 'dogwalk:note'), contains('про запас'));
      expect(_text(tester, 'dogwalk:status'), contains('Собрано: 1 из 2'));
      // Дом в (3, 3), мячик ещё не собран — собака не входит.
      await _walk(tester, <_Cell>[(r: 2, c: 3)]);
      await _step(tester, (r: 3, c: 3));
      expect(_text(tester, 'dogwalk:note'), contains('Сначала собери всё'));
      expect(_text(tester, 'dogwalk:status'), contains('Шаги: 5'));
      expect(find.byKey(const ValueKey<String>('dogwalk:done')), findsNothing);
      expect(done, isFalse);
    });
  });

  group('доступность', () {
    testWidgets('метки клеток для TalkBack и нажатие через неё',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await _pumpGame(tester, _content.levelFor('short', 0), onDone: (_) {});
      expect(find.bySemanticsLabel('Клетка 1, 1: собака'), findsOneWidget);
      expect(find.bySemanticsLabel('Клетка 1, 4: лужа'), findsOneWidget);
      expect(find.bySemanticsLabel('Клетка 2, 4: монета'), findsOneWidget);
      expect(find.bySemanticsLabel('Клетка 3, 1: мячик'), findsOneWidget);
      expect(find.bySemanticsLabel('Клетка 4, 4: дом'), findsOneWidget);
      expect(
          tester.getSemantics(find.bySemanticsLabel('Клетка 1, 2: тропинка')),
          matchesSemantics(
              label: 'Клетка 1, 2: тропинка',
              isButton: true,
              hasTapAction: true));
      tester.semantics.tap(find.semantics.byLabel('Клетка 1, 2: тропинка'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Клетка 1, 2: собака'), findsOneWidget);
      sem.dispose();
    });

    testWidgets('«уменьшить движение»: собака переходит сразу, без анимации',
        (WidgetTester tester) async {
      Future<Offset> dogAfterTap(bool reduce) async {
        await _pumpGame(tester, _content.levelFor('short', 0),
            onDone: (_) {}, disableAnimations: reduce);
        final Finder dog = find.byKey(const ValueKey<String>('dogwalk:dog'));
        final Offset before = tester.getTopLeft(dog);
        await tester
            .tap(find.byKey(const ValueKey<String>('dogwalk:cell:1:0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.hasRunningAnimations, !reduce,
            reason: reduce ? 'движение выключено' : 'обычно собака идёт');
        final Offset after = tester.getTopLeft(dog) - before;
        await tester.pumpAndSettle();
        return after;
      }

      final Offset moving = await dogAfterTap(false);
      final Offset instant = await dogAfterTap(true);
      final double cell = tester
          .getSize(find.byKey(const ValueKey<String>('dogwalk:cell:0:0')))
          .height;
      expect(instant.dy, closeTo(cell, 0.01));
      expect(moving.dy, lessThan(cell));
    });

    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (int round = 0; round < 3; round++) {
        testWidgets(
            '${o.key}, шрифт 1,3, ступень ${round + 1}: без переполнения, '
            'клетки ≥ 48 dp', (WidgetTester tester) async {
          final World w = _withDog();
          // Ступень — по числу смен этой работы за игру (раунд — смены
          // профессии, NAS-7).
          // Предел смен одной работы в неделю — тогда следующая неделя.
          void open() {
            if (w.offer('dog_walker')?.blockReason == null) return;
            ok(sleepWeek(w));
            ok(w.payBills());
            ok(w.startWeek());
            ok(w.plan(needs: 100, wants: 100, goal: 0));
          }

          for (int i = 0; i < round; i++) {
            open();
            ok(w.completeJob('dog_walker', score: 1));
            if (w.pendingLesson case final LessonOffer lesson) {
              ok(w.resolveLesson(lesson.choices.first.id));
            }
          }
          open();
          expect(w.snapshot.shiftsByJobTotal['dog_walker'] ?? 0, round);
          expect(w.offer('dog_walker')?.blockReason, isNull);
          final SemanticsHandle sem = tester.ensureSemantics();
          await pumpWorldScreen(
              tester, const JobPlayScreen(args: JobPlayArgs('dog_walker')),
              world: w, size: o.value, textScale: 1.3);
          final Finder start = find.byKey(const ValueKey<String>('job:start'));
          await tester.ensureVisible(start);
          await tester.pumpAndSettle();
          await tester.tap(start);
          await tester.pumpAndSettle();
          final int n = _content.levels[round].size;
          expect(find.byKey(ValueKey<String>('dogwalk:cell:${n - 1}:${n - 1}')),
              findsOneWidget,
              reason: 'ступень ${round + 1} — поле $n×$n');
          final Size cell = tester
              .getSize(find.byKey(const ValueKey<String>('dogwalk:cell:0:0')));
          expect(cell.width, greaterThanOrEqualTo(48));
          // Задание прогулки под полем видно без прокрутки.
          final Finder note =
              find.byKey(const ValueKey<String>('dogwalk:note'));
          expect(
              tester.getRect(note).bottom, lessThanOrEqualTo(o.value.height));
          // Дальняя клетка — подсказка «на одну клетку».
          await tester.tap(
              find.byKey(ValueKey<String>('dogwalk:cell:${n - 1}:${n - 1}')));
          await tester.pumpAndSettle();
          expect(_text(tester, 'dogwalk:note'), contains('одну клетку'));
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          sem.dispose();
        });
      }
    }
  });

  testWidgets('смена целиком: прогулка → итог с уроком',
      (WidgetTester tester) async {
    final World w = _withDog();
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('dog_walker')),
        world: w, textScale: 1.3);
    final Finder start = find.byKey(const ValueKey<String>('job:start'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    await _walk(tester, _shortest(_content.levels.first, _content)!);
    // Собака дома — экран сам докрутил до «Закончить смену».
    expect(
        tester
            .getRect(find.byKey(const ValueKey<String>('dogwalk:done')))
            .bottom,
        lessThanOrEqualTo(640));
    await _finish(tester);
    expect(
        find.byKey(const ValueKey<String>('lesson:situation')), findsOneWidget);
    expect(w.snapshot.shiftsTotal, 1);
    expect(find.byType(DogWalkerGame), findsNothing);
  });
}
