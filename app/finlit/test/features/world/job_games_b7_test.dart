import 'dart:collection';

import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/games/courier_game.dart';
import 'package:finlit/features/world/jobs/games/gardener_game.dart';
import 'package:finlit/features/world/jobs/games/programmer_game.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

World _living(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 100, wants: 100, goal: 0));
  return w;
}

/// Неделя идёт, и программист открыт. Ноутбук копится неделями, а тест про
/// саму мини-игру — поэтому замки снимает демо «Открыть все профессии»
/// (замки проверяет `test/domain/world/job_unlocks_test.dart`).
World _programmer(WorldKind kind) {
  final World w = _living(kind);
  ok(w.demoUnlockAllJobs());
  return w;
}

/// Мир с купленным транспортом: копим стипендию, пока не хватит на велосипед.
World _withTransport(WorldKind kind) {
  final World w = kind.make();
  for (int week = 0; week < 20; week++) {
    ok(w.startWeek());
    final ResourceSnapshot s = w.snapshot;
    ok(w.plan(needs: 0, wants: 0, goal: s.unallocated));
    if (w.snapshot.goal >= w.catalogItem('transport_bike')!.price) break;
    w.sleep();
    w.payBills();
  }
  expect(w.buy('transport_bike').ok, isTrue);
  return w;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Для садовника в обычном темпе: таймер тикает всегда, pumpAndSettle нельзя.
Future<void> _tapNow(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

String _textIn(WidgetTester tester, String key) {
  final Finder box = find.byKey(ValueKey<String>(key));
  return tester
      .widgetList<Text>(find.descendant(
          of: box, matching: find.byType(Text), matchRoot: true))
      .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' ');
}

Future<void> _pumpGame(WidgetTester tester, Widget game,
    {bool disableAnimations = false, double textScale = 1}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body:
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: game),
    ),
  ));
  await tester.pump();
}

bool _bedIs(String label, int i) => find
    .byKey(ValueKey<String>('gardener:bed:$i:$label'))
    .evaluate()
    .isNotEmpty;

/// Спокойный темп: поливаем всё сухое и жмём «Дальше» до конца.
Future<void> _playGardenerCalm(WidgetTester tester,
    {bool tapGreenOnce = false}) async {
  bool tried = !tapGreenOnce;
  for (int turn = 0; turn < contentJobGames.gardener.calmTurns; turn++) {
    if (!tried) {
      final int green =
          List<int>.generate(contentJobGames.gardener.beds, (int i) => i)
              .firstWhere(
        (int i) => _bedIs('Растёт', i),
      );
      await _tap(tester, 'gardener:bed:$green');
      expect(_textIn(tester, 'gardener:note'), contains('ещё влажная'));
      tried = true;
    }
    for (int i = 0; i < contentJobGames.gardener.beds; i++) {
      if (_bedIs('Полей!', i) || _bedIs('Поникла', i)) {
        await _tap(tester, 'gardener:bed:$i');
      }
    }
    await _tap(tester, 'gardener:next');
  }
}

/// Лабиринт: кратчайший путь BFS как последовательность ходов.
List<String> _route(CourierOrder o) {
  final int n = o.size;
  bool open(int r, int c) =>
      r >= 0 && c >= 0 && r < n && c < n && '.SG'.contains(o.map[r][c]);
  late (int, int) start;
  late (int, int) goal;
  for (int r = 0; r < n; r++) {
    for (int c = 0; c < n; c++) {
      if (o.map[r][c] == 'S') start = (r, c);
      if (o.map[r][c] == 'G') goal = (r, c);
    }
  }
  const Map<String, (int, int)> dirs = <String, (int, int)>{
    'up': (-1, 0),
    'down': (1, 0),
    'left': (0, -1),
    'right': (0, 1),
  };
  final Map<(int, int), ((int, int), String)> from =
      <(int, int), ((int, int), String)>{};
  final Queue<(int, int)> q = Queue<(int, int)>()..add(start);
  final Set<(int, int)> seen = <(int, int)>{start};
  while (q.isNotEmpty) {
    final (int, int) p = q.removeFirst();
    for (final MapEntry<String, (int, int)> d in dirs.entries) {
      final (int, int) nx = (p.$1 + d.value.$1, p.$2 + d.value.$2);
      if (open(nx.$1, nx.$2) && seen.add(nx)) {
        from[nx] = (p, d.key);
        q.add(nx);
      }
    }
  }
  if (!seen.contains(goal)) return const <String>[];
  final List<String> moves = <String>[];
  (int, int) at = goal;
  while (at != start) {
    moves.add(from[at]!.$2);
    at = from[at]!.$1;
  }
  return moves.reversed.toList();
}

/// Курьер, ближний заказ: неверная посылка, стена, тупик, шаг назад — и
/// доставка.
Future<void> _playCourierNearWithMistakes(WidgetTester tester) async {
  await _tap(tester, 'courier:parcel:p2');
  expect(_textIn(tester, 'courier:feedback'), contains('Адрес другой'));
  expect(find.byKey(const ValueKey<String>('courier:toRoute')), findsNothing);
  await _tap(tester, 'courier:parcel:p1');
  expect(_textIn(tester, 'courier:feedback'), contains('Та самая'));
  await _tap(tester, 'courier:toRoute');

  // Вниз со старта — дома.
  await _tap(tester, 'courier:move:down');
  expect(_textIn(tester, 'courier:note'), contains('дома'));
  // В тупик (4, 1) и обратно.
  for (final String m in <String>[
    'right',
    'down',
    'down',
    'right',
    'down',
    'down',
  ]) {
    await _tap(tester, 'courier:move:$m');
  }
  await _tap(tester, 'courier:move:left');
  expect(_textIn(tester, 'courier:note'), contains('Тупик'));
  await _tap(tester, 'courier:back');
  expect(find.byKey(const ValueKey<String>('courier:note')), findsNothing);
  // Соседняя клетка тапом, затем стрелкой.
  await _tap(tester, 'courier:cell:4:3');
  await _tap(tester, 'courier:move:right');
  await _tap(tester, 'courier:done');
}

Future<void> _addBlocks(WidgetTester tester, List<String> ids) async {
  for (final String id in ids) {
    await _tap(tester, 'programmer:cmd:$id');
  }
}

/// Программист, робот: поворот не в ту сторону → объяснение → исправление.
Future<void> _playRobotWithMistake(WidgetTester tester) async {
  await _addBlocks(tester, <String>['fwd', 'fwd', 'left', 'fwd', 'drop']);
  await _tap(tester, 'programmer:run');
  final String fb = _textIn(tester, 'programmer:feedback');
  expect(fb, contains('Шаг 3'));
  expect(fb, contains('налево'));
  expect(fb, contains('направо'));
  expect(find.byKey(const ValueKey<String>('programmer:done')), findsNothing);
  // Убрать шаги 3–5 и поставить верные.
  await _tap(tester, 'programmer:slot:2');
  await _tap(tester, 'programmer:slot:2');
  await _tap(tester, 'programmer:slot:2');
  await _addBlocks(tester, <String>['right', 'fwd', 'drop']);
  await _tap(tester, 'programmer:run');
  expect(_textIn(tester, 'programmer:feedback'), contains('Всё сработало'));
  await _tap(tester, 'programmer:done');
}

void main() {
  group('садовник', () {
    // Ловит (критерии ночи §8.8, ревью df2164a): у садовника снова часы —
    // обратный отсчёт «Осталось N с» при обычных настройках.
    testWidgets('обычные настройки — по ходам, без часов; onDone один раз',
        (WidgetTester tester) async {
      final List<double> scores = <double>[];
      await _pumpGame(tester,
          GardenerGame(content: contentJobGames.gardener, onDone: scores.add));
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
          find.byKey(const ValueKey<String>('gardener:turn')), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      expect(
          find.byKey(const ValueKey<String>('gardener:summary')), findsNothing,
          reason: 'время само не идёт');
      await _playGardenerCalm(tester, tapGreenOnce: false);
      expect(_textIn(tester, 'gardener:summary'), contains('Ты полил'));
      await _tap(tester, 'gardener:done');
      await _tapNow(tester, 'gardener:done');
      expect(scores, <double>[1]);
    });

    testWidgets('анимации выключены — по ходам, без часов; проходится',
        (WidgetTester tester) async {
      final List<double> scores = <double>[];
      await _pumpGame(tester,
          GardenerGame(content: contentJobGames.gardener, onDone: scores.add),
          disableAnimations: true);
      expect(
          find.byKey(const ValueKey<String>('gardener:turn')), findsOneWidget);
      // Время само не идёт.
      await tester.pump(const Duration(seconds: 60));
      expect(
          find.byKey(const ValueKey<String>('gardener:summary')), findsNothing);
      await _playGardenerCalm(tester, tapGreenOnce: true);
      expect(_textIn(tester, 'gardener:summary'),
          contains(contentJobGames.gardener.lineGreat));
      await _tap(tester, 'gardener:done');
      expect(scores, <double>[1]);
    });

    for (final WorldKind kind in worldKinds) {
      testWidgets(
          'в экране смены: ставка не зависит от политых, 360×640 при 1,3 · $kind',
          (WidgetTester tester) async {
        final World world = _living(kind);
        final JobOffer offer = world.offer('gardener')!;
        final int free = world.snapshot.free;
        await pumpWorldScreen(
            tester, const JobPlayScreen(args: JobPlayArgs('gardener')),
            world: world, textScale: 1.3);
        await _tap(tester, 'job:start');
        // Крупный шрифт — спокойный темп. Ничего не поливаем.
        for (int t = 0; t < contentJobGames.gardener.calmTurns; t++) {
          await _tap(tester, 'gardener:next');
        }
        expect(_textIn(tester, 'gardener:summary'),
            contains(contentJobGames.gardener.lineLow));
        await _tap(tester, 'gardener:done');
        expect(world.snapshot.free - free, offer.pay);
        expect(
            tester
                .widget<Text>(
                    find.byKey(const ValueKey<String>('job:result:pay')))
                .data,
            '+${offer.pay}');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('курьер', () {
    test('в каждом лабиринте есть путь от старта до дома клиента', () {
      for (final CourierOrder o in contentJobGames.courier.orders) {
        expect(o.map.every((String row) => row.length == o.size), isTrue,
            reason: o.id);
        expect(_route(o), isNotEmpty, reason: o.id);
        expect(o.parcels.where((CourierParcel p) => p.correct), hasLength(1),
            reason: o.id);
      }
      expect(contentJobGames.courier.orderFor('far').size, 9);
    });

    testWidgets('ошибки объясняются и исправляются, onDone один раз',
        (WidgetTester tester) async {
      final List<double> scores = <double>[];
      await _pumpGame(
          tester,
          CourierGame(
              content: contentJobGames.courier,
              variant: 'near',
              onDone: scores.add));
      await _playCourierNearWithMistakes(tester);
      await _tap(tester, 'courier:done');
      expect(scores, <double>[0.5]);
    });

    testWidgets('дальний заказ проходится', (WidgetTester tester) async {
      final List<double> scores = <double>[];
      await _pumpGame(
          tester,
          CourierGame(
              content: contentJobGames.courier,
              variant: 'far',
              onDone: scores.add));
      await _tap(tester, 'courier:parcel:p3');
      await _tap(tester, 'courier:toRoute');
      for (final String m in _route(contentJobGames.courier.orderFor('far'))) {
        await _tap(tester, 'courier:move:$m');
      }
      await _tap(tester, 'courier:done');
      expect(scores, <double>[1]);
    });

    for (final WorldKind kind in worldKinds) {
      testWidgets(
          'в экране смены: с ошибками платит ставку; 360×640 при 1,3 · $kind',
          (WidgetTester tester) async {
        final World world = _withTransport(kind);
        final JobOffer offer = world.offer('courier', variant: 'near')!;
        expect(offer.locked, isFalse);
        final int free = world.snapshot.free;
        await pumpWorldScreen(tester,
            const JobPlayScreen(args: JobPlayArgs('courier', variant: 'near')),
            world: world, textScale: 1.3);
        await _tap(tester, 'job:start');
        await _playCourierNearWithMistakes(tester);
        expect(world.snapshot.free - free,
            inInclusiveRange(offer.pay, offer.pay + offer.efficiencyBonusMax));
        expect(
            tester
                .widget<Text>(
                    find.byKey(const ValueKey<String>('job:result:pay')))
                .data,
            '+${offer.pay}');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('программист', () {
    test('проверка — симуляция, а не сравнение строк', () {
      final ProgTask robot = contentJobGames.programmer.taskFor('medium');
      expect(programmerFirstMismatch(robot, robot.solution), isNull);
      expect(
          programmerFirstMismatch(
              robot, <String>['fwd', 'fwd', 'left', 'fwd', 'drop']),
          3);
      expect(programmerFirstMismatch(robot, <String>['fwd']), 2);
      final ProgTask garden = contentJobGames.programmer.taskFor('hard');
      expect(programmerFirstMismatch(garden, garden.solution), isNull);
      // Лишний блок вместо нужного — расхождение на его шаге.
      expect(
          programmerFirstMismatch(garden, <String>[
            'open',
            'water1',
            'turn',
            'water2',
            'close',
            'extra_music',
          ]),
          6);
      final ProgTask light = contentJobGames.programmer.taskFor(null);
      expect(light.id, 'traffic_light');
      expect(programmerFirstMismatch(light, light.solution), isNull);
    });

    testWidgets('робот: ошибка на шаге объясняется и исправляется',
        (WidgetTester tester) async {
      final List<double> scores = <double>[];
      await _pumpGame(
          tester,
          ProgrammerGame(
              content: contentJobGames.programmer,
              variant: 'medium',
              onDone: scores.add));
      await _playRobotWithMistake(tester);
      await _tap(tester, 'programmer:done');
      expect(scores, <double>[0.5]);
    });

    testWidgets('светофор и полив проходятся без анимаций',
        (WidgetTester tester) async {
      for (final String tier in <String>['easy', 'hard']) {
        final List<double> scores = <double>[];
        final ProgTask task = contentJobGames.programmer.taskFor(tier);
        await _pumpGame(
            tester,
            ProgrammerGame(
                content: contentJobGames.programmer,
                key: ValueKey<String>(tier),
                variant: tier,
                onDone: scores.add),
            disableAnimations: true);
        await _addBlocks(tester, task.solution);
        await _tap(tester, 'programmer:run');
        await _tap(tester, 'programmer:done');
        expect(scores, <double>[1], reason: tier);
      }
    });

    for (final WorldKind kind in worldKinds) {
      testWidgets(
          'в экране смены: с ошибкой платит ставку; 360×640 при 1,3 · $kind',
          (WidgetTester tester) async {
        final World world = _programmer(kind);
        final JobOffer offer = world.offer('programmer', variant: 'medium')!;
        final int free = world.snapshot.free;
        await pumpWorldScreen(
            tester,
            const JobPlayScreen(
                args: JobPlayArgs('programmer', variant: 'medium')),
            world: world,
            textScale: 1.3);
        await _tap(tester, 'job:start');
        await _playRobotWithMistake(tester);
        expect(world.snapshot.free - free,
            inInclusiveRange(offer.pay, offer.pay + offer.efficiencyBonusMax));
        expect(
            tester
                .widget<Text>(
                    find.byKey(const ValueKey<String>('job:result:pay')))
                .data,
            '+${offer.pay}');
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Ловит: в основной, альбомной ориентации игра не влезает в 360 dp высоты
  // (переполнение) или поле уезжает так, что смену не пройти.
  group('альбомная 640×360 при шрифте 1,3', () {
    for (final WorldKind kind in worldKinds) {
      testWidgets('садовник: огород 3 × 2 во всю высоту, ходы до итога · $kind',
          (WidgetTester tester) async {
        final World world = _living(kind);
        final JobOffer offer = world.offer('gardener')!;
        final int free = world.snapshot.free;
        await pumpWorldScreen(
            tester, const JobPlayScreen(args: JobPlayArgs('gardener')),
            world: world, size: landscape, textScale: 1.3);
        await _tap(tester, 'job:start');
        // Все шесть грядок видны сразу, кнопка хода — справа от них.
        for (int i = 0; i < contentJobGames.gardener.beds; i++) {
          final Rect bed =
              tester.getRect(find.byKey(ValueKey<String>('gardener:bed:$i')));
          expect(bed.bottom, lessThanOrEqualTo(landscape.height));
          expect(bed.height, greaterThanOrEqualTo(48));
        }
        expect(
            tester
                .getRect(find.byKey(const ValueKey<String>('gardener:next')))
                .left,
            greaterThan(tester
                .getRect(find.byKey(const ValueKey<String>('gardener:bed:2')))
                .right));
        await _playGardenerCalm(tester, tapGreenOnce: true);
        expect(_textIn(tester, 'gardener:summary'),
            contains(contentJobGames.gardener.lineGreat));
        await _tap(tester, 'gardener:done');
        expect(
            world.snapshot.free - free, offer.pay + offer.efficiencyBonusMax);
        expect(tester.takeException(), isNull);
      });
    }

    for (final WorldKind kind in worldKinds) {
      testWidgets(
          'курьер: карта слева, стрелки справа; ошибки и доставка · $kind',
          (WidgetTester tester) async {
        final World world = _withTransport(kind);
        final JobOffer offer = world.offer('courier', variant: 'near')!;
        final int free = world.snapshot.free;
        await pumpWorldScreen(tester,
            const JobPlayScreen(args: JobPlayArgs('courier', variant: 'near')),
            world: world, size: landscape, textScale: 1.3);
        await _tap(tester, 'job:start');
        await _playCourierNearWithMistakes(tester);
        expect(world.snapshot.free - free,
            inInclusiveRange(offer.pay, offer.pay + offer.efficiencyBonusMax));
        expect(
            find.byKey(const ValueKey<String>('job:result')), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Дальний заказ, 9 × 9: карта целиком на экране и левее стрелок.
        await tester.pumpWidget(const SizedBox());
        await pumpWorldScreen(tester,
            const JobPlayScreen(args: JobPlayArgs('courier', variant: 'far')),
            world: _withTransport(kind), size: landscape, textScale: 1.3);
        await _tap(tester, 'job:start');
        await _tap(tester, 'courier:parcel:p3');
        await _tap(tester, 'courier:toRoute');
        final Rect goal = tester
            .getRect(find.byKey(const ValueKey<String>('courier:cell:8:8')));
        expect(goal.bottom, lessThanOrEqualTo(landscape.height));
        final Rect down = tester
            .getRect(find.byKey(const ValueKey<String>('courier:move:down')));
        expect(
            tester
                .getRect(
                    find.byKey(const ValueKey<String>('courier:move:left')))
                .left,
            greaterThan(goal.right));
        expect(down.bottom, lessThanOrEqualTo(landscape.height));
        for (final String m
            in _route(contentJobGames.courier.orderFor('far'))) {
          await _tap(tester, 'courier:move:$m');
        }
        await _tap(tester, 'courier:done');
        expect(
            find.byKey(const ValueKey<String>('job:result')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final WorldKind kind in worldKinds) {
      testWidgets(
          'программист: три панели, ошибка на шаге и исправление · $kind',
          (WidgetTester tester) async {
        final World world = _programmer(kind);
        final JobOffer offer = world.offer('programmer', variant: 'medium')!;
        final int free = world.snapshot.free;
        await pumpWorldScreen(
            tester,
            const JobPlayScreen(
                args: JobPlayArgs('programmer', variant: 'medium')),
            world: world,
            size: landscape,
            textScale: 1.3);
        await _tap(tester, 'job:start');
        // Устройство, программа и блоки — рядом, слева направо.
        final Rect device = tester
            .getRect(find.byKey(const ValueKey<String>('programmer:device')));
        final Rect slot = tester
            .getRect(find.byKey(const ValueKey<String>('programmer:slot:0')));
        final Rect run = tester
            .getRect(find.byKey(const ValueKey<String>('programmer:run')));
        expect(device.right, lessThan(slot.left));
        expect(slot.right, lessThan(run.left));
        expect(run.bottom, lessThanOrEqualTo(landscape.height));
        await _playRobotWithMistake(tester);
        expect(world.snapshot.free - free,
            inInclusiveRange(offer.pay, offer.pay + offer.efficiencyBonusMax));
        expect(
            find.byKey(const ValueKey<String>('job:result')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final WorldKind kind in worldKinds) {
      testWidgets('программист: полив (6 шагов, 7 блоков) проходится · $kind',
          (WidgetTester tester) async {
        final World world = _programmer(kind);
        await pumpWorldScreen(
            tester,
            const JobPlayScreen(
                args: JobPlayArgs('programmer', variant: 'hard')),
            world: world,
            size: landscape,
            textScale: 1.3);
        await _tap(tester, 'job:start');
        await _addBlocks(
            tester, contentJobGames.programmer.taskFor('hard').solution);
        await _tap(tester, 'programmer:run');
        await _tap(tester, 'programmer:done');
        expect(
            find.byKey(const ValueKey<String>('job:result')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
