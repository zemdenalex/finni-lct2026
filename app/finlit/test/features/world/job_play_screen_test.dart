import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/games/cashier_game.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:finlit/features/world/home/world_hud.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

World _living(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 100, wants: 100, goal: 0));
  return w;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _coins(WidgetTester tester, List<int> coins) async {
  for (final int c in coins) {
    await _tap(tester, 'cashier:coin:$c');
  }
}

String _feedback(WidgetTester tester, String key) {
  final Finder box = find.byKey(ValueKey<String>(key));
  return tester
      .widgetList<Text>(find.descendant(of: box, matching: find.byType(Text)))
      .map((Text t) => t.data ?? '')
      .join(' ');
}

/// Кассир, смена 0: 10 − 7 = 3, затем 10 − 9 = 1 (вход — только «до 10»,
/// эксперт 16.10). Обе с ошибкой; первая сдача — другой верной комбинацией
/// (1 + 1 + 1 вместо 2 + 1).
/// Первая смена кассира (C3, от простого к сложному): 9 + 1 = 10, затем
/// 8 + 2 = 10. Уже первая ошибка показывает, на сколько, и счёт вверх с
/// суммой ребёнка (NAS-3 A, Настя 19.10).
Future<void> _playCashierWithMistakes(WidgetTester tester) async {
  await _coins(tester, <int>[2]);
  await _tap(tester, 'cashier:give');
  expect(_feedback(tester, 'cashier:feedback'), contains('лишнее: 1'));
  expect(_feedback(tester, 'cashier:feedback'), contains('9 + 2 = 11'));
  await _tap(tester, 'cashier:undo');
  await _coins(tester, <int>[1]);
  await _tap(tester, 'cashier:give');
  expect(_feedback(tester, 'cashier:feedback'), contains('Сдача верная'));
  expect(_feedback(tester, 'cashier:feedback'), contains('9 + 1 = 10'));
  await _tap(tester, 'cashier:next');

  await _coins(tester, <int>[1]);
  await _tap(tester, 'cashier:give');
  expect(_feedback(tester, 'cashier:feedback'), contains('Не хватает 1'));
  expect(_feedback(tester, 'cashier:feedback'), contains('8 + 1 = 9'));
  // Вторая ошибка подряд — другая сумма (1 + 2).
  await _coins(tester, <int>[2]);
  await _tap(tester, 'cashier:give');
  expect(_feedback(tester, 'cashier:feedback'), contains('лишнее: 1'));
  expect(_feedback(tester, 'cashier:feedback'), contains('8 + 3 = 11'));
  // Исправляем, не выбрасывая первую монету: 1 + 1 — не «жадный» набор.
  await _tap(tester, 'cashier:undo');
  await _coins(tester, <int>[1]);
  await _tap(tester, 'cashier:give');
  expect(_feedback(tester, 'cashier:feedback'), contains('Сдача верная'));
  await _tap(tester, 'cashier:next');
}

Future<void> _pumpGame(WidgetTester tester, Widget game) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body:
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: game),
    ),
  ));
}

void main() {
  test('кассир: сдача считается кодом, по кругу', () {
    expect(
        contentJobGames.cashier
            .purchasesFor(0)
            .map((CashierPurchase p) => p.change),
        <int>[1, 2]);
    for (final CashierPurchase p in contentJobGames.cashier.purchases) {
      expect(p.change, inInclusiveRange(1, 100));
    }
  });

  testWidgets(
      'кассир: любая верная комбинация, ошибка объясняется и '
      'исправляется', (WidgetTester tester) async {
    double? score;
    await _pumpGame(
        tester,
        CashierGame(
            content: contentJobGames.cashier, onDone: (double s) => score = s));
    await _playCashierWithMistakes(tester);
    expect(score, 0);
  });

  testWidgets('кассир: без ошибок — оценка 1', (WidgetTester tester) async {
    double? score;
    await _pumpGame(
        tester,
        CashierGame(
            content: contentJobGames.cashier, onDone: (double s) => score = s));
    await _coins(tester, <int>[1]);
    await _tap(tester, 'cashier:give');
    await _tap(tester, 'cashier:next');
    await _coins(tester, <int>[2]);
    await _tap(tester, 'cashier:give');
    await _tap(tester, 'cashier:next');
    expect(score, 1);
  });

  testWidgets(
      'консультант: неверная полка и неверный выбор объясняются и '
      'исправляются', (WidgetTester tester) async {
    double? score;
    await _pumpGame(
        tester,
        ConsultantGame(
            content: contentJobGames.consultant,
            onDone: (double s) => score = s));
    final ConsultantSet set = contentJobGames.consultant.setFor(0);
    expect(set.id, 'backpacks');

    // Лёгкий (дешевле) на «Дороже», Поход (дороже) на «Дешевле».
    await _tap(tester, 'consultant:shelf:bp_1:2');
    await _tap(tester, 'consultant:shelf:bp_2:1');
    await _tap(tester, 'consultant:shelf:bp_3:0');
    await _tap(tester, 'consultant:scan');
    expect(find.byKey(const ValueKey<String>('consultant:why:bp_1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('consultant:why:bp_3')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('consultant:why:bp_2')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('consultant:customer')),
        findsNothing);

    await _tap(tester, 'consultant:shelf:bp_1:0');
    await _tap(tester, 'consultant:shelf:bp_3:2');
    await _tap(tester, 'consultant:scan');
    expect(find.byKey(const ValueKey<String>('consultant:customer')),
        findsOneWidget);

    await _tap(tester, 'consultant:pick:bp_3');
    expect(_feedback(tester, 'consultant:feedback'),
        contains(set.customer.feedbackPricier));
    expect(find.byKey(const ValueKey<String>('consultant:done')), findsNothing);
    await _tap(tester, 'consultant:pick:bp_1');
    expect(_feedback(tester, 'consultant:feedback'),
        contains(set.customer.feedbackCheaper));
    await _tap(tester, 'consultant:pick:bp_2');
    expect(_feedback(tester, 'consultant:feedback'),
        contains(set.customer.feedbackFit));
    await _tap(tester, 'consultant:done');
    // Две неверные полки и два разных неверных совета (NAS-7: полка мягче).
    final ConsultantContent c = contentJobGames.consultant;
    expect(score, closeTo(1 - 2 * c.shelfPenalty - 2 * c.pickPenalty, 1e-9));
  });

  for (final WorldKind kind in worldKinds) {
    testWidgets(
        'смена с ошибками платит ровно ставку, ⚡ — цена карточки;  · $kind'
        'влезает в 360×640 при 1,3', (WidgetTester tester) async {
      final World world = _living(kind);
      final JobOffer offer = world.offer('cashier')!;
      final ResourceSnapshot before = world.snapshot;
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: world, textScale: 1.3);

      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey<String>('job:offer:pay')))
              .data,
          '${offer.pay}');
      await _tap(tester, 'job:start');
      await _playCashierWithMistakes(tester);

      final ResourceSnapshot after = world.snapshot;
      expect(after.free - before.free, offer.pay);
      expect(after.energy, closeTo(before.energy - offer.energyCost, 1e-9));
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey<String>('job:result:pay')))
              .data,
          '+${offer.pay}');
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey<String>('job:result:bonus')))
              .data,
          '+0');
      expect(tester.takeException(), isNull);
    });
  }

  // Ловит: бонус на итоге считается «монеты − ставка» на экране, а не
  // offer.bonusFor(score); хорошая смена не отличается от обычной.
  for (final WorldKind kind in worldKinds) {
    testWidgets(
        'хорошая смена: бонус = bonusFor(оценка), ⚡ и 😊 — из итога · $kind',
        (WidgetTester tester) async {
      final World world = _living(kind);
      final JobOffer offer = world.offer('cashier')!;
      expect(offer.isGoodScore(1), isTrue);
      final WorldState ws = await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: world);
      await _tap(tester, 'job:start');
      await _coins(tester, <int>[1]);
      await _tap(tester, 'cashier:give');
      await _tap(tester, 'cashier:next');
      await _coins(tester, <int>[2]);
      await _tap(tester, 'cashier:give');
      await _tap(tester, 'cashier:next');

      final WorldResult r = ws.lastResult!;
      expect(r.ok, isTrue, reason: r.reason);
      String text(String key) =>
          tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;
      expect(text('job:result:bonus'), '+${offer.bonusFor(1)}');
      expect(offer.bonusFor(1), greaterThan(0));
      expect(text('job:result:title'), 'Смена сделана хорошо!');
      expect(
          find.byKey(const ValueKey<String>('job:result:exp')), findsOneWidget);
      expect(world.snapshot.experience, 1);
      expect(r.happiness, lessThan(0), reason: 'хорошая смена стоит 😊');
      expect(text('job:result:happiness'), '−${-r.happiness}');
      expect(text('job:result:energy'), WorldHud.energyText(-r.energy));
      expect(-r.energy, greaterThan(offer.energyCost),
          reason: 'сверх карточки — goodEnergyExtra');
      expect(tester.takeException(), isNull);
    });
  }

  for (final WorldKind kind in worldKinds) {
    testWidgets('консультант в экране смены влезает в 360×640 при 1,3 · $kind',
        (WidgetTester tester) async {
      final World world = _living(kind);
      final JobOffer offer = world.offer('consultant')!;
      final int free = world.snapshot.free;
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('consultant')),
          world: world, textScale: 1.3);
      await _tap(tester, 'job:start');
      await _tap(tester, 'consultant:shelf:bp_1:0');
      await _tap(tester, 'consultant:shelf:bp_2:1');
      await _tap(tester, 'consultant:shelf:bp_3:2');
      await _tap(tester, 'consultant:scan');
      await _tap(tester, 'consultant:pick:bp_2');
      await _tap(tester, 'consultant:done');
      // Без ошибок — ставка плюс весь бонус.
      expect(world.snapshot.free - free, offer.pay + offer.efficiencyBonusMax);
      expect(tester.takeException(), isNull);
    });
  }

  for (final WorldKind kind in worldKinds) {
    testWidgets('вышел посреди игры — ничего не изменилось · $kind',
        (WidgetTester tester) async {
      final World world = _living(kind);
      final ResourceSnapshot before = world.snapshot;
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: world);
      await _tap(tester, 'job:start');
      await _coins(tester, <int>[2]);
      await _tap(tester, 'job:back');

      final ResourceSnapshot after = world.snapshot;
      expect(after.free, before.free);
      expect(after.goal, before.goal);
      expect(after.energy, before.energy);
      expect(after.experience, before.experience);
      expect(after.shiftsThisWeek, before.shiftsThisWeek);
    });
  }

  // Ловит (Настя 20.10, п. 12): касание экрана итогов мимо урока, пока он
  // ждёт ответа, ничего не говорит — ребёнок не понимает, что надо выбрать
  // вариант. Уронит: нет вспышки вариантов и выделенной подсказки по касанию
  // пустого места, или подсказка остаётся после ответа.
  testWidgets('касание мимо урока — варианты вспыхивают, подсказка жирнее',
      (WidgetTester tester) async {
    final World world = _living(worldKinds.last);
    ok(world.demoUnlockAllJobs());
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('dog_walker')),
        world: world, games: contentJobGamesDogStub);
    await _tap(tester, 'job:start');
    await _tap(tester, 'game:placeholder:do');
    Color border() => ((tester
                .widget<DecoratedBox>(
                    find.byKey(const ValueKey<String>('lesson:choices')))
                .decoration as BoxDecoration)
            .border! as Border)
        .top
        .color;
    FontWeight? hint() => tester
        .widget<Text>(find.byKey(const ValueKey<String>('job:lessonFirst')))
        .style
        ?.fontWeight;
    expect(border().a, 0, reason: 'до касания рамки нет');
    expect(hint(), isNot(FontWeight.w800));
    // Таблица оплаты — не кнопка: «пустое место» экрана итогов.
    final Finder pay = find.byKey(const ValueKey<String>('job:result:pay'));
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.tap(pay, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(border().a, greaterThan(0), reason: 'варианты вспыхнули');
    expect(hint(), FontWeight.w800);
    await tester.pumpAndSettle();
    // Ответ дан — подсказки нет, касание больше ни к чему не ведёт.
    final Finder choice = find.byKey(const ValueKey<String>('lesson:cushion'));
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('job:lessonFirst')), findsNothing);
    expect(find.byKey(const ValueKey<String>('lesson:choices')), findsNothing);
  });

  // Ловит (критерии ночи §4): после смены нет урока-решения; решение не
  // двигает монеты; итог не начинается с «Что мы поняли»; кнопки решений
  // меньше 48 dp в портрете 360 × 640 при шрифте 1,3; урок под сгибом —
  // ниже таблицы оплаты (ревью 2b58bdb §4.7);
  // рядом с уроком снова ползунок «сколько отложить».
  testWidgets(
      'после смены — урок выше оплаты: решение, «Что мы поняли», ≥ 48 dp',
      (WidgetTester tester) async {
    final World world = _living(worldKinds.last); // мир из content/
    ok(world.demoUnlockAllJobs()); // выгульщик — смена одной кнопкой
    await pumpWorldScreen(
        tester, const JobPlayScreen(args: JobPlayArgs('dog_walker')),
        world: world, textScale: 1.3, games: contentJobGamesDogStub);
    await _tap(tester, 'job:start');
    await _tap(tester, 'game:placeholder:do');
    expect(
        find.byKey(const ValueKey<String>('lesson:situation')), findsOneWidget);
    // Урок выше таблицы оплаты; «виден ли без прокрутки» — в
    // lesson_fits_test.dart (там настоящие шрифты, а не квадраты Ahem).
    expect(
        tester.getRect(find.byKey(const ValueKey<String>('lesson:title'))).top,
        lessThan(tester
            .getRect(find.byKey(const ValueKey<String>('job:result:pay')))
            .top));
    expect(find.byKey(const ValueKey<String>('job:slider')), findsNothing);
    expect(find.byKey(const ValueKey<String>('job:toPiggy')), findsNothing);
    // Урок обязателен (Денис 29.09): до ответа уйти нельзя. Но кнопки
    // выхода не гаснут (баг-репорт 15.10: «кнопки не работают, только
    // перезапуск») — ведут к уроку и говорят, что сделать.
    expect(
        find.byKey(const ValueKey<String>('job:lessonFirst')), findsOneWidget);
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final String k in <String>['job:toRoom', 'job:toBoard', 'job:back']) {
      final Finder b = find.byKey(ValueKey<String>(k));
      await tester.ensureVisible(b);
      await tester.pumpAndSettle();
      await tester.tap(b);
      await tester.pumpAndSettle();
      expect(find.byType(JobPlayScreen), findsOneWidget, reason: '$k увёл');
      final Rect last =
          tester.getRect(find.byKey(const ValueKey<String>('lesson:treat')));
      expect(last.top >= 0 && last.bottom <= screen.height, isTrue,
          reason: '$k: варианты урока не на экране ($last)');
    }
    final Finder choice = find.byKey(const ValueKey<String>('lesson:cushion'));
    await tester.ensureVisible(choice);
    expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
    final int goal = world.snapshot.goal;
    await _tap(tester, 'lesson:cushion');
    expect(world.snapshot.goal, greaterThan(goal));
    final Finder done = find.byKey(const ValueKey<String>('lesson:result'));
    expect(
        find.descendant(
            of: done, matching: find.textContaining('Что мы поняли')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('lesson:situation')), findsNothing);
    // После ответа — уйти можно.
    final Widget toBoard =
        tester.widget(find.byKey(const ValueKey<String>('job:toBoard')));
    expect((toBoard as ButtonStyleButton).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  // Баг-репорт из чата задачи (15.10, скриншот садовника): «вернуться с
  // работы не можешь, кнопки не работают — только перезапуск». Состояние
  // со скриншота: садовник, хорошая смена, урок ждёт ответа. Уронит: выход
  // не открывается после любого из трёх ответов, или до ответа кнопка
  // выхода молчит, а не ведёт к уроку.
  for (final String answer in <String>['tenth', 'third', 'none']) {
    testWidgets('садовник: урок «$answer» открывает выход',
        (WidgetTester tester) async {
      final World world = _living(worldKinds.last); // мир из content/
      ok(world.demoUnlockAllJobs());
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('gardener')),
          world: world);
      await _tap(tester, 'job:start');
      for (int turn = 0; turn < contentJobGames.gardener.calmTurns; turn++) {
        for (int i = 0; i < contentJobGames.gardener.beds; i++) {
          for (final String label in <String>['Полей!', 'Поникла']) {
            if (find
                .byKey(ValueKey<String>('gardener:bed:$i:$label'))
                .evaluate()
                .isNotEmpty) {
              await _tap(tester, 'gardener:bed:$i');
              break;
            }
          }
        }
        await _tap(tester, 'gardener:next');
      }
      await _tap(tester, 'gardener:done');
      expect(world.pendingLesson?.jobId, 'gardener', reason: 'настройка');
      // До ответа: «Домой» ведёт к уроку, а не молчит.
      final Finder home = find.byKey(const ValueKey<String>('job:toRoom'));
      await tester.ensureVisible(home);
      await tester.pumpAndSettle();
      await tester.tap(home);
      await tester.pumpAndSettle();
      expect(find.byType(JobPlayScreen), findsOneWidget);
      final Finder choice = find.byKey(ValueKey<String>('lesson:$answer'));
      final Rect seen = tester.getRect(choice);
      final double screenH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(seen.top >= 0 && seen.bottom <= screenH, isTrue,
          reason: 'после «Домой» вариант урока целиком на экране: $seen');
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(world.pendingLesson, isNull);
      final Widget b = tester.widget(home);
      expect((b as ButtonStyleButton).onPressed, isNotNull);
      expect(
          find.byKey(const ValueKey<String>('job:lessonFirst')), findsNothing);
    });
  }

  for (final WorldKind kind in worldKinds) {
    // Ловит: ползунок с итога смены убрали, а отложить на цель руками
    // стало негде — кнопка не ведёт в копилку или перенос там не работает.
    testWidgets('после урока — «Отложить на цель» ведёт в копилку · $kind',
        (WidgetTester tester) async {
      final World world = _living(kind);
      ok(world.demoUnlockAllJobs()); // программист — без ноутбука
      // Светофор программиста — самая короткая смена.
      await pumpWorldScreen(tester,
          const JobPlayScreen(args: JobPlayArgs('programmer', variant: 'easy')),
          world: world);
      await _tap(tester, 'job:start');
      for (final String id in <String>['red', 'yellow', 'green']) {
        await _tap(tester, 'programmer:cmd:$id');
      }
      await _tap(tester, 'programmer:run');
      await _tap(tester, 'programmer:done');

      if (world.pendingLesson != null) {
        // Пока урок ждёт — кнопки в копилку нет: сначала решение.
        expect(find.byKey(const ValueKey<String>('job:toPiggy')), findsNothing);
        await _tap(tester, 'lesson:invest');
      }
      await _tap(tester, 'job:toPiggy');
      expect(
          find.byKey(const ValueKey<String>('piggy:deposit')), findsOneWidget);

      final ResourceSnapshot before = world.snapshot;
      for (int i = 0; i < 3; i++) {
        await _tap(tester, 'deposit:plus');
      }
      await _tap(tester, 'deposit:go');
      final ResourceSnapshot after = world.snapshot;
      expect(after.goal - before.goal, 30);
      expect(before.free - after.free, 30);
    });
  }

  group('альбомная 640×360 при шрифте 1,3', () {
    // Ловит: в основной ориентации игра не влезает по высоте (переполнение)
    // или кнопки уезжают так, что смену не пройти.
    for (final WorldKind kind in worldKinds) {
      testWidgets('кассир: смена с ошибками проходится, итог и урок · $kind',
          (WidgetTester tester) async {
        final World world = _living(kind);
        final JobOffer offer = world.offer('cashier')!;
        final int free = world.snapshot.free;
        final int mood = world.snapshot.happiness;
        await pumpWorldScreen(
            tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
            world: world, size: landscape, textScale: 1.3);
        expect(find.byType(WorldHud), findsOneWidget);
        await _tap(tester, 'job:start');
        // Во время игры HUD спрятан: высота — полю.
        expect(find.byType(WorldHud), findsNothing);
        // Лоток и покупатель — рядом, не друг под другом.
        expect(
            tester
                .getRect(find.byKey(const ValueKey<String>('cashier:coin:1')))
                .left,
            greaterThan(tester
                .getRect(find.byKey(const ValueKey<String>('cashier:purchase')))
                .right));
        await _playCashierWithMistakes(tester);
        expect(world.snapshot.free - free, offer.pay);
        expect(find.byType(WorldHud), findsOneWidget);

        if (world.pendingLesson != null) {
          // Урок — в правой панели; «пересчитать» стоит 😊, не монет.
          await _tap(tester, 'lesson:recount');
          expect(find.byKey(const ValueKey<String>('lesson:result')),
              findsOneWidget);
          // Ловит (смоук 29.09): строка «Настроение» без −1 урока, а 😊 в
          // шапке уже меньше. Строка = вся перемена 😊 со старта смены.
          final int d = world.snapshot.happiness - mood;
          final Finder row =
              find.byKey(const ValueKey<String>('job:result:happiness'));
          await tester.ensureVisible(row);
          expect(tester.widget<Text>(row).data, d > 0 ? '+$d' : '−${-d}');
          expect(find.text('Настроение (после урока)'), findsOneWidget);
        }
        expect(world.snapshot.free - free, offer.pay);
        final Finder toBoard =
            find.byKey(const ValueKey<String>('job:toBoard'));
        await tester.ensureVisible(toBoard);
        expect(tester.getSize(toBoard).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });
    }

    for (final WorldKind kind in worldKinds) {
      testWidgets(
          'консультант: ошибки на полке и в выборе, смена пройдена · $kind',
          (WidgetTester tester) async {
        final World world = _living(kind);
        final JobOffer offer = world.offer('consultant')!;
        final int free = world.snapshot.free;
        await pumpWorldScreen(
            tester, const JobPlayScreen(args: JobPlayArgs('consultant')),
            world: world, size: landscape, textScale: 1.3);
        await _tap(tester, 'job:start');
        await _tap(tester, 'consultant:shelf:bp_1:2');
        await _tap(tester, 'consultant:shelf:bp_2:1');
        await _tap(tester, 'consultant:shelf:bp_3:0');
        await _tap(tester, 'consultant:scan');
        expect(find.byKey(const ValueKey<String>('consultant:why:bp_1')),
            findsOneWidget);
        await _tap(tester, 'consultant:shelf:bp_1:0');
        await _tap(tester, 'consultant:shelf:bp_3:2');
        await _tap(tester, 'consultant:scan');
        await _tap(tester, 'consultant:pick:bp_3');
        expect(find.byKey(const ValueKey<String>('consultant:done')),
            findsNothing);
        await _tap(tester, 'consultant:pick:bp_2');
        await _tap(tester, 'consultant:done');
        // Ставка целиком; ошибки режут только бонус сверху.
        expect(world.snapshot.free - free,
            inInclusiveRange(offer.pay, offer.pay + offer.efficiencyBonusMax));
        expect(
            find.byKey(const ValueKey<String>('job:result')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Ловит (критерии ночи §8 п. 4, 7): пройденный урок не виден в истории
  // и у взрослого; у взрослого появились оценки.
  testWidgets('история: «чему мы научились» после урока',
      (WidgetTester tester) async {
    final World world = _living(worldKinds.last);
    ok(world.completeJob('accountant', score: 0.5));
    ok(world.resolveLesson('goal'));
    await pumpWorldScreen(tester, const HistoryScreen(), world: world);
    expect(find.byKey(const ValueKey<String>('learned:panel')), findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey<String>('learned:topic:budget')))
            .data,
        contains('1 решение'));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('learned:words')))
            .data,
        contains('Бюджет'));
    expect(find.textContaining('оценк'), findsNothing);
  });
}
