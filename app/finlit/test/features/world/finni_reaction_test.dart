import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/finni_reaction.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/finni_bubble.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

ResourceSnapshot _s({
  int weekNo = 1,
  int want = 50,
  int goal = 0,
  double energy = 6,
  int happiness = 50,
  WorldStage stage = WorldStage.village,
  int mealsPerWeek = 7,
  int meals = 0,
  int snacks = 0,
}) =>
    ResourceSnapshot(
      weekNo: weekNo,
      need: 100,
      want: want,
      goal: goal,
      free: 0,
      unallocated: 0,
      energy: energy,
      happiness: happiness,
      growthPoints: 0,
      stage: stage,
      experience: 0,
      shiftsThisWeek: 0,
      weeklyBill: 100,
      owned: const <String>{},
      foodId: 'food_home',
      mealsPerWeek: mealsPerWeek,
      mealsThisWeek: meals,
      snacksThisWeek: snacks,
    );

/// Финни виден в комнате, арт догружен.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
}

Finder _reaction(String line) =>
    find.byKey(ValueKey<String>('finni:reaction:$line'));

void main() {
  // Контракт реакции: какое решение — какая эмоция. Уронит: перепутан
  // порядок (отложил на цель, а Финни грустит), реакция на ничто (мигает
  // при каждой перерисовке) или молчание на настоящее решение.
  group('reactionFor', () {
    const double tired = 1;
    for (final (
          String name,
          ResourceSnapshot a,
          ResourceSnapshot b,
          FinniReaction? want
        ) in <(String, ResourceSnapshot, ResourceSnapshot, FinniReaction?)>[
      ('ничего не изменилось', _s(), _s(), null),
      (
        'отложил на цель',
        _s(goal: 20),
        _s(goal: 70, want: 0),
        const FinniReaction(FinniMood.joy, '+50 на цель!'),
      ),
      (
        'вырос — главнее цели',
        _s(goal: 0),
        _s(goal: 30, stage: WorldStage.town),
        const FinniReaction(FinniMood.joy, 'Новый дом!'),
      ),
      (
        'потратил всё на «хочу», копилка пуста',
        _s(want: 40),
        _s(want: 0),
        const FinniReaction(FinniMood.sad, 'На цель ничего не осталось'),
      ),
      (
        'потратил «хочу», но копилка есть',
        _s(want: 40, goal: 30),
        _s(want: 0, goal: 30),
        null
      ),
      (
        'смена — сил меньше дешёвого дела',
        _s(energy: 3),
        _s(energy: 0.5),
        const FinniReaction(FinniMood.tired, 'Сил нет: пора спать'),
      ),
      ('смена — силы ещё есть', _s(energy: 5), _s(energy: 3), null),
      (
        'съел последнее',
        _s(meals: 6),
        _s(meals: 7),
        const FinniReaction(
            FinniMood.hungry, 'Холодильник пуст — доем дома в конце недели'),
      ),
      (
        'настроение +5',
        _s(happiness: 50),
        _s(happiness: 58),
        const FinniReaction(FinniMood.joy, 'Стало веселее!'),
      ),
      (
        'настроение −5',
        _s(happiness: 50),
        _s(happiness: 44),
        const FinniReaction(FinniMood.sad, 'Стало грустнее'),
      ),
      ('настроение ±2 — молчит', _s(happiness: 50), _s(happiness: 48), null),
    ]) {
      test(name, () {
        expect(reactionFor(a, b, tiredBelow: tired), want);
      });
    }
  });

  // Строка над Финни в покое. Уронит: голодный Финни «всё хорошо» или
  // голод до первой недели (холодильник ещё не наполнялся).
  test('finniStatus: голод, усталость, грусть, радость, покой', () {
    FinniMood m(ResourceSnapshot s, {bool living = true}) =>
        finniStatus(s, living: living, tiredBelow: 1).mood;
    expect(m(_s(meals: 7)), FinniMood.hungry);
    expect(m(_s(meals: 7), living: false), FinniMood.calm);
    // Меню не выбрано (0 приёмов) — пусто не значит «голоден».
    expect(m(_s(mealsPerWeek: 0)), FinniMood.calm);
    expect(m(_s(energy: 0.5)), FinniMood.tired);
    expect(m(_s(happiness: 20)), FinniMood.sad);
    expect(m(_s(happiness: 80)), FinniMood.joy);
    expect(m(_s()), FinniMood.calm);
  });

  test('позы: радость и усталость нарисованы, грусть и голод — обычная', () {
    expect(finniPoseTag(FinniMood.joy, 2), 'joy-2');
    expect(finniPoseTag(FinniMood.tired, 3), 'sleep-3');
    expect(finniPoseTag(FinniMood.sad, 1), isNull);
    expect(finniPoseTag(FinniMood.hungry, 1), isNull);
  });

  // Комната. Уронит: реакция не показана, показана поверх другого экрана
  // (ребёнок её не увидел) или не дошла после возврата.
  forEachWorld((WorldKind kind) {
    testWidgets('решение в комнате — поза и строка сразу, потом покой',
        (WidgetTester tester) async {
      final World world = kind.make();
      ok(world.startWeek());
      ok(world.plan(needs: 250, wants: 100, goal: 0));
      late WorldState s;
      await tester.runAsync(() async {
        s = await pumpWorldScreen(tester, const RoomScreen(), world: world);
      });
      await _settle(tester);
      final int from = s.snapshot.goal;
      final WorldResult r = s.act((World w) => w.depositToGoal(20));
      if (!r.ok) {
        markTestSkipped('копилка недоступна в ${kind.name}: ${r.reason}');
        return;
      }
      await tester.pump();
      // ≤ 300 мс: строка и поза радости.
      await tester.pump(const Duration(milliseconds: 300));
      final int put = s.snapshot.goal - from;
      expect(_reaction('+$put на цель!'), findsOneWidget);
      expect(
          find.byKey(ValueKey<String>('room:finni:pose:joy-${s.profile.look}')),
          findsOneWidget);
      // Через 1,5 с — снова строка состояния и обычная поза.
      await tester.pump(const Duration(milliseconds: 1300));
      expect(
          find.byKey(const ValueKey<String>('finni:status')), findsOneWidget);
      expect(
          find.byKey(ValueKey<String>('room:finni:pose:joy-${s.profile.look}')),
          findsNothing);
    });

    testWidgets('решение на другом экране — реакция при возврате',
        (WidgetTester tester) async {
      final World world = kind.make();
      ok(world.startWeek());
      ok(world.plan(needs: 250, wants: 100, goal: 0));
      late WorldState s;
      await tester.runAsync(() async {
        s = await pumpWorldScreen(tester, const RoomScreen(), world: world);
      });
      await _settle(tester);
      final NavigatorState nav =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      // Экран сверху; закроется pop ниже — ждать его future не нужно.
      // ignore: unawaited_futures
      nav.push(MaterialPageRoute<void>(
          builder: (BuildContext c) => const Scaffold(body: Text('другой'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final int from = s.snapshot.goal;
      final WorldResult r = s.act((World w) => w.depositToGoal(20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (!r.ok) {
        markTestSkipped('копилка недоступна в ${kind.name}: ${r.reason}');
        return;
      }
      final int put = s.snapshot.goal - from;
      // Пока комната под другим экраном — ничего, и реакция не «сгорает»
      // там, где её не видно: ребёнок задержался дольше её времени.
      expect(_reaction('+$put на цель!'), findsNothing);
      await tester.pump(const Duration(milliseconds: 2000));
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_reaction('+$put на цель!'), findsOneWidget);
    });
  });

  // ТЗ 2.5.10.3: причина настроения — по касанию Финни. Денис 20.10: «Финни
  // друг, и при нажатии на него он должен говорить как друг с игроком» —
  // не «погладить», не «мурлычет», без сердечек питомца. Решение 16.10
  // остаётся: +1 😊 раз в игровой день. Уронит: касание снова «гладит»
  // (сердечки, «погладили»), реплика не облачком, одна и та же фраза два
  // раза подряд, «+1» без начисления или снекбар над кнопками комнаты.
  testWidgets('касание Финни: реплика друга облачком, +1 😊 один раз в день',
      (WidgetTester tester) async {
    final World world = worldKinds.first.make();
    ok(world.startWeek());
    ok(world.plan(needs: 250, wants: 100, goal: 50));
    late WorldState s;
    await tester.runAsync(() async {
      s = await pumpWorldScreen(tester, const RoomScreen(), world: world);
    });
    await _settle(tester);
    Iterable<String> lines() =>
        tester.widgetList(find.byWidgetPredicate((Widget w) {
          final Key? k = w.key;
          return k is ValueKey<String> && k.value.startsWith('finni:reaction:');
        })).map((Widget w) =>
            (w.key! as ValueKey<String>).value.substring('finni:reaction:'.length));
    final int mood0 = s.snapshot.happiness;
    await tester.tap(find.byKey(const ValueKey<String>('room:finni')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.snapshot.happiness, mood0 + 1);
    final String first = lines().single;
    expect(first, endsWith('+1 😊'));
    expect(first, isNot(matches(RegExp('мурл|глад|Мур', caseSensitive: false))));
    expect(find.byType(SpeechBubble), findsOneWidget,
        reason: 'Финни говорит облачком, а не строкой-плашкой');
    expect(find.byKey(const ValueKey<String>('finni:hearts')), findsNothing,
        reason: 'сердечки — эффект питомца, не друга');
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('room:finni')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.snapshot.happiness, mood0 + 1, reason: 'второй раз в день — 0');
    final String second = lines().single;
    expect(second, isNot(contains('+')));
    expect(second, isNot(first.split('\n').first),
        reason: 'две одинаковые фразы подряд');
  });

  // Уронит: реакция мира сменила разговор, а облачко осталось над чужой
  // строкой (ревью 16.10 — тогда сердечки).
  testWidgets('поговорили, потом решение — облачко уходит',
      (WidgetTester tester) async {
    final World world = worldKinds.first.make();
    ok(world.startWeek());
    ok(world.plan(needs: 250, wants: 100, goal: 0));
    late WorldState s;
    await tester.runAsync(() async {
      s = await pumpWorldScreen(tester, const RoomScreen(), world: world);
    });
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('room:finni')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SpeechBubble), findsOneWidget);
    final WorldResult r = s.act((World w) => w.depositToGoal(20));
    expect(r.ok, isTrue, reason: r.reason);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SpeechBubble), findsNothing);
  });

  // Ревью 16.10. Уронит: строка снова в слое Финни (кровать и холодильник
  // закрывают её, когда он за ними) или у края кадра уходит за экран.
  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    testWidgets('${o.key}: строка над Финни — сверху и в кадре у края',
        (WidgetTester tester) async {
      final World world = worldKinds.first.make();
      ok(world.startWeek());
      ok(world.plan(needs: 250, wants: 100, goal: 50));
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: world, size: o.value);
      });
      await _settle(tester);
      final Finder status = find.byKey(const ValueKey<String>('finni:status'));
      expect(find.ancestor(of: status, matching: find.byType(FinniBadgeLayer)),
          findsOneWidget,
          reason: 'строка — в верхнем слое, не в слое Финни');
    });
  }

  // У края кадра строка сдвигается внутрь, под HUD не залезает. Уронит:
  // строка по центру Финни у левого края — половина текста за экраном.
  for (final (String name, Offset finni) in <(String, Offset)>[
    ('левый край', const Offset(0, 300)),
    ('правый край', const Offset(320, 300)),
    ('под HUD', const Offset(160, 20)),
  ]) {
    testWidgets('FinniBadgeLayer: $name — строка в кадре',
        (WidgetTester tester) async {
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 640,
            child: Stack(children: <Widget>[
              Positioned(
                left: finni.dx,
                top: finni.dy,
                child: SizedBox(key: key, width: 40, height: 80),
              ),
              Positioned.fill(
                child: FinniBadgeLayer(
                  finniKey: key,
                  topLimit: 60,
                  child: const SizedBox(
                      key: ValueKey<String>('badge'), width: 200, height: 30),
                ),
              ),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final Rect r =
          tester.getRect(find.byKey(const ValueKey<String>('badge')));
      expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$r');
      expect(r.right, lessThanOrEqualTo(360.5), reason: '$r');
      expect(r.top, greaterThanOrEqualTo(59.5), reason: '$r');
    });
  }
}
