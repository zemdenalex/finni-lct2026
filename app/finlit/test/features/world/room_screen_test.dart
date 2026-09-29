import 'package:finlit/app_state.dart';
import 'package:finlit/core/feel.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/home/world_hud.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/review/week_review_screen.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/text_floor.dart';
import '../../support/world_harness.dart';

/// Мир посреди недели: карманные получены, план составлен, есть питомец.
World _livingWorld(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 250, wants: 100, goal: 50));
  return w;
}

/// Дать арту из бандла догрузиться: rootBundle в тестах асинхронный.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pump();
}

String _textIn(WidgetTester tester, String key) => tester
    .widgetList<Text>(find.descendant(
        of: find.byKey(ValueKey<String>(key)), matching: find.byType(Text)))
    .map((Text t) => t.data)
    .join(' ');

/// Спрайты анимируются бесконечно — pumpAndSettle не дождётся покоя.
Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Фейк, у которого самое дешёвое дело стоит ровно столько ⚡, сколько
/// есть, плюс [over]: граница «сил хватает на дело» ставится точно.
class _CostWorld extends FakeWorld {
  double over = 0;

  @override
  double get cheapestActionEnergy => snapshot.energy + over;
}

/// Размеры S1 из брифа этапа 1 (фидбек дизайнера 28.09): обе ориентации,
/// узкий и длинный экран.
const Map<String, Size> _roomSizes = <String, Size>{
  ...bothOrientations,
  'альбомная 800×360': Size(800, 360),
  'портрет 360×800': Size(360, 800),
};

/// Разделы нижней панели в текущем варианте ([RoomScreen.threeTabs]).
const List<String> _navIds = RoomScreen.threeTabs
    ? <String>['week', 'city', 'progress']
    : <String>['plan', 'jobs', 'shop', 'piggy', 'progress'];

void main() {
  // AppState.boot() читает контент через rootBundle, а он кеширует Future
  // из зоны первого теста — второй boot() в файле завис бы молча.
  setUp(rootBundle.clear);

  // Ловит: из мира не выключить анимации (ТЗ 3.6.7) — или тумблер пишет
  // флаг, а Финни в комнате под экраном настроек продолжает двигаться.
  testWidgets('⚙ в комнате → «Анимации» выкл. → комната замирает',
      (WidgetTester tester) async {
    final AppState app = AppState(MemoryStorage());
    await tester.runAsync(() async {
      await app.boot();
      await pumpWorldScreen(tester, const RoomScreen(),
          world: _livingWorld(worldKinds.last), app: app, size: landscape);
    });
    await _settle(tester);
    expect(tester.hasRunningAnimations, isTrue,
        reason: 'пока анимации включены, Финни двигается');

    await tester.tap(find.byKey(const ValueKey<String>('room:menu')));
    await _step(tester);
    await tester.tap(find.byKey(const ValueKey<String>('room:settings')));
    await _step(tester);
    await tester.ensureVisible(find.byKey(WorldSettingsScreen.motionKey));
    await tester.pump();
    await tester.tap(find.byKey(WorldSettingsScreen.motionKey));
    await _step(tester);
    expect(app.game.profile.settings.animationsOn, isFalse);
    await tester.tap(find.byKey(const ValueKey<String>('settings:back')));
    await _step(tester);

    expect(find.byType(RoomScreen), findsOneWidget);
    expect(tester.element(find.byType(RoomScreen)).motion(Motion.state),
        Duration.zero);
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'анимации выключены — в комнате ничего не движется');
  });

  forEachWorld((WorldKind kind) {
    // Ловит: HUD показывает не тот снимок (кешированный, не перерисован после
    // действия) — ребёнок видит старые монеты и ⚡.
    testWidgets('HUD совпадает со снимком после действия',
        (WidgetTester tester) async {
      final World world = _livingWorld(kind);
      final WorldState state = WorldState(world);
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(), state: state);
      });
      await _settle(tester);

      void expectHud() {
        final ResourceSnapshot s = state.snapshot;
        expect(_textIn(tester, 'hud:coins'), contains('${s.available}'));
        // Копилка — не в HUD, а над копилкой в комнате (Денис 29.09).
        expect(find.byKey(const ValueKey<String>('hud:saved')), findsNothing);
        expect(_textIn(tester, 'room:piggy:amount'), contains('${s.saved}'));
        expect(_textIn(tester, 'hud:energy'),
            contains(WorldHud.energyText(s.energy)));
        expect(_textIn(tester, 'hud:happiness'), contains('${s.happiness}'));
      }

      expectHud();
      final int before = state.snapshot.available;
      state.act((World w) => w.completeJob('gardener', score: 1));
      await tester.pump();
      expect(state.snapshot.available, greaterThan(before));
      expectHud();
    });

    // Ловит: на маленьком телефоне с крупным шрифтом HUD, Финни, карточки или
    // кнопки вылезают за экран (ТЗ 2.5.3.1: всё без прокрутки на 360 dp) —
    // в альбомной (основной) и в портрете, на узком и на длинном экране.
    for (final MapEntry<String, Size> o in _roomSizes.entries) {
      for (final double scale in <double>[1, 1.3]) {
        testWidgets('помещается без прокрутки · ${o.key} · шрифт $scale',
            (WidgetTester tester) async {
          final World world = _livingWorld(kind);
          await tester.runAsync(() async {
            await pumpWorldScreen(tester, const RoomScreen(),
                world: world, size: o.value, textScale: scale);
          });
          await _settle(tester);
          expect(tester.takeException(), isNull);
          final Rect view = Offset.zero & o.value;
          for (final String key in <String>[
            'hud:coins',
            'hud:energy',
            'hud:happiness',
            'room:finni',
            'room:goal',
            'room:now',
            for (final String id in _navIds) 'room:nav:$id',
            'room:menu',
            'room:help',
          ]) {
            final Rect r = tester.getRect(find.byKey(ValueKey<String>(key)));
            expect(
                view.contains(r.topLeft) &&
                    view.contains(r.bottomRight - const Offset(0.01, 0.01)),
                isTrue,
                reason: '$key $r вне $view');
          }
          // Кнопки — не меньше 48 dp.
          for (final (String key, double min) in <(String, double)>[
            ('room:now', 48),
            ('room:menu', 48),
            ('room:help', 48),
          ]) {
            expect(tester.getSize(find.byKey(ValueKey<String>(key))).height,
                greaterThanOrEqualTo(min),
                reason: key);
          }
          expect(find.byType(Scrollable), findsNothing);
        });
      }
    }

    // Ловит: подписи нижней панели ужимаются каждая сама по себе, и
    // «Прогресс» выходит мельче «Плана» — панель выглядит сломанной.
    // Один кегль на всех — тот, что влезает у самой длинной. Пол ТЗ 3.6.4
    // проверяет `text_size_test.dart` на настоящем шрифте.
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final double scale in <double>[1, 1.3]) {
        testWidgets('подписи панели одного кегля · ${o.key} · шрифт $scale',
            (WidgetTester tester) async {
          await tester.runAsync(() async {
            await pumpWorldScreen(tester, const RoomScreen(),
                world: _livingWorld(kind), size: o.value, textScale: scale);
          });
          await _settle(tester);
          final List<double> sizes = <double>[
            for (final String id in _navIds)
              // Подпись — `Text`; значок Material тоже рисуется RichText.
              shownTextSize(tester.renderObject<RenderParagraph>(
                  find.descendant(
                      of: find.descendant(
                          of: find.byKey(ValueKey<String>('room:nav:$id')),
                          matching: find.byType(Text)),
                      matching: find.byType(RichText)))),
          ];
          for (final double s in sizes) {
            expect(s, closeTo(sizes.first, 0.05), reason: '$sizes');
          }
        });
      }
    }

    // Ловит: в альбомной комната осталась полоской в масштабе ×1 — сцене
    // не хватило высоты под HUD и панелью.
    testWidgets('альбомная: комната слева, карточки справа, масштаб ×2',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: _livingWorld(kind), size: landscape);
      });
      await _settle(tester);
      final Rect scene = tester.getRect(find.byType(RoomScene));
      final Rect now =
          tester.getRect(find.byKey(const ValueKey<String>('room:now')));
      expect(scene.right, lessThanOrEqualTo(now.left));
      // Фон 272×168 при ×2 — 336 в высоту: сцена показывает ≥ ¾ этого.
      expect(scene.height, greaterThanOrEqualTo(168 * 2 * 0.75));
      // Финни целиком в кадре комнаты, а не срезан потолком или краем.
      final Rect finni =
          tester.getRect(find.byKey(const ValueKey<String>('room:finni')));
      expect(scene.inflate(0.5).contains(finni.topLeft), isTrue);
      expect(scene.inflate(0.5).contains(finni.bottomRight), isTrue);
    });

    // Ловит: тап по Финни показывает фразу экрана по уровню 😊, а не
    // причину настроения от мира (A12, ТЗ 2.5.10.3).
    testWidgets('тап по Финни — причина настроения от мира',
        (WidgetTester tester) async {
      final World world = _livingWorld(kind);
      ok(world.leisure('park'));
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(), world: world);
      });
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('room:finni')));
      await _step(tester);
      final String reason = world.snapshot.moodReason.text;
      expect(reason, isNotEmpty);
      expect(
          find.descendant(
              of: find.byType(SnackBar), matching: find.text(reason)),
          findsOneWidget);
    });

    // Ловит: итоги недели молчат, почему у Финни такое настроение (S11).
    testWidgets('итоги недели показывают причину настроения',
        (WidgetTester tester) async {
      final World world = _livingWorld(kind);
      ok(world.sleep());
      await pumpWorldScreen(tester, const WeekReviewScreen(),
          world: world, size: landscape);
      final Finder pay = find.byKey(const ValueKey<String>('review:pay'));
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await _step(tester);
      final String reason = '💬 ${world.snapshot.moodReason.text}';
      expect(
          find.byWidgetPredicate(
              (Widget w) => w is PicText && w.text == reason),
          findsOneWidget);
    });

    // Ловит: карточка цели берёт название и цену не из каталога мира.
    testWidgets('строка «Цель» — название и цена из каталога мира',
        (WidgetTester tester) async {
      final World world = _livingWorld(kind);
      ok(world.chooseGoal('pet_hamster'));
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(), world: world);
      });
      await _settle(tester);
      final WorldCatalogItem goal = world.catalogItem('pet_hamster')!;
      final int saved = world.snapshot.saved;
      // Строка цели (вариант В2): название и «накоплено/цена» — на экране,
      // остаток — в подписи для TalkBack.
      for (final String part in <String>[
        goal.title,
        '$saved/${goal.price}',
      ]) {
        expect(
            find.descendant(
                of: find.byKey(const ValueKey<String>('room:goal')),
                matching: find.textContaining(part, findRichText: true)),
            findsOneWidget,
            reason: part);
      }
      final SemanticsHandle sem = tester.ensureSemantics();
      await tester.pump();
      expect(
          tester
              .getSemantics(find.byKey(const ValueKey<String>('room:goal')))
              .label,
          allOf(contains(goal.title),
              contains('осталось ${goal.price - saved}')));
      sem.dispose();
    });

    // Ловит: «Спать» не закрывает неделю или не ведёт к итогам.
    testWidgets('«Спать» заканчивает неделю и открывает итоги',
        (WidgetTester tester) async {
      final World world = _livingWorld(kind);
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(), world: world);
      });
      await _settle(tester);

      // «Спать» раньше срока — кровать в комнате (вариант В: одна кнопка
      // «Сейчас» ведёт в город, пока есть силы).
      await tester.tap(find.byKey(const ValueKey<String>('room:bed')));
      await _step(tester);
      await tester.tap(find.byKey(const ValueKey<String>('sleep:confirm')));
      await _step(tester);
      expect(world.phase, WeekPhase.review);
      expect(find.textContaining('Финни'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey<String>('sleep:next')));
      await _step(tester);
      expect(find.byType(RoomScreen), findsNothing);
      expect(find.byType(WeekReviewScreen), findsOneWidget);
    });

    // Ловит: строка цели легла на комнату или оторвалась от «Сейчас»
    // (Денис 29.09, вариант В: внизу — строка цели и одна кнопка), или не
    // открывает копилку.
    for (final MapEntry<String, Size> o in _roomSizes.entries) {
      testWidgets('цель — тонкой строкой под показателями · ${o.key}',
          (WidgetTester tester) async {
        final World world = _livingWorld(kind);
        ok(world.chooseGoal('pet_hamster'));
        await tester.runAsync(() async {
          await pumpWorldScreen(tester, const RoomScreen(),
              world: world, size: o.value);
        });
        await _settle(tester);
        final Rect scene = tester.getRect(find.byType(RoomScene));
        final Finder goalKey = find.byKey(const ValueKey<String>('room:goal'));
        final Rect goal = tester.getRect(goalKey);
        final Rect now =
            tester.getRect(find.byKey(const ValueKey<String>('room:now')));
        final Rect coins =
            tester.getRect(find.byKey(const ValueKey<String>('hud:coins')));
        final Rect finni =
            tester.getRect(find.byKey(const ValueKey<String>('room:finni')));
        // Вариант В2 (ревью 29.09): в портрете — тонкая строка под
        // показателями поверх сцены; в альбомной — в боковом столбце под
        // «Сейчас» (над комнатой только ряд фишек, иначе она мельчает).
        // Не на Финни, не на «Сейчас», не кнопка.
        expect(goal.overlaps(now), isFalse);
        expect(goal.overlaps(finni), isFalse,
            reason: 'цель $goal закрывает Финни $finni');
        if (o.value.width > o.value.height) {
          final Rect side =
              tester.getRect(find.byKey(const ValueKey<String>('room:side')));
          expect(side.contains(goal.center), isTrue,
              reason: 'цель $goal в столбце $side');
          expect(goal.top, greaterThanOrEqualTo(now.bottom));
          expect(goal.height, lessThanOrEqualTo(80),
              reason: 'три строки, не карточка');
        } else {
          expect(goal.top, greaterThanOrEqualTo(coins.bottom),
              reason: 'цель $goal выше показателей $coins');
          expect(goal.height, lessThanOrEqualTo(40),
              reason: 'строка, не карточка');
          expect(goal.left, greaterThanOrEqualTo(scene.left));
        }
      });
    }

    // Ловит: раздел пропал с панели или открывает не тот экран; экран,
    // до которого раньше был раздел, стал недостижим (вариант Б: план и
    // копилка — через «Неделю», работа, магазин и прогулки — через город).
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final (
            String id,
            String label,
            String? then,
            Finder Function() opened
          ) in RoomScreen.threeTabs
              ? <(String, String, String?, Finder Function())>[
                  (
                    'week',
                    'Неделя',
                    'room:week:plan',
                    () => find.byKey(const ValueKey<String>('plan:confirm'))
                  ),
                  (
                    'week',
                    'Неделя',
                    'room:week:piggy',
                    () => find.byType(PiggyScreen)
                  ),
                  ('city', 'Город', null, () => find.byType(CityScreen)),
                  (
                    'progress',
                    'Прогресс',
                    null,
                    () => find.byType(HistoryScreen)
                  ),
                ]
              : <(String, String, String?, Finder Function())>[
                  (
                    'plan',
                    'План',
                    null,
                    () => find.byKey(const ValueKey<String>('plan:confirm'))
                  ),
                  ('jobs', 'Работа', null, () => find.byType(JobBoardScreen)),
                  ('shop', 'Магазин', null, () => find.byType(WorldShopScreen)),
                  ('piggy', 'Копилка', null, () => find.byType(PiggyScreen)),
                  (
                    'progress',
                    'Прогресс',
                    null,
                    () => find.byType(HistoryScreen)
                  ),
                ]) {
        testWidgets(
            'панель: «$label»${then == null ? '' : ' → $then'} открывает '
            'свой экран · ${o.key}', (WidgetTester tester) async {
          // План открывает лист только до плана недели.
          final bool toPlan = id == 'plan' || then == 'room:week:plan';
          final World world = kind.make();
          ok(world.startWeek());
          if (!toPlan) ok(world.plan(needs: 250, wants: 100, goal: 50));
          await tester.runAsync(() async {
            await pumpWorldScreen(tester, const RoomScreen(),
                world: world, size: o.value);
          });
          await _settle(tester);
          final Finder navItems = find.byWidgetPredicate((Widget w) {
            final Key? k = w.key;
            return k is ValueKey<String> && k.value.startsWith('room:nav:');
          });
          expect(navItems, findsNWidgets(_navIds.length));
          final Finder item = find.byKey(ValueKey<String>('room:nav:$id'));
          expect(_textIn(tester, 'room:nav:$id'), label);
          await tester.tap(item);
          await _step(tester);
          if (then != null) {
            await tester.tap(find.byKey(ValueKey<String>(then)));
            await _step(tester);
          }
          expect(opened(), findsOneWidget);
        });
      }
    }

    // Ловит: TalkBack читает «Работа» без слова «мини-игры» — незрячий
    // ребёнок тоже не найдёт игры.
    testWidgets('«Работа» для TalkBack — «Работа — мини-игры»',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: _livingWorld(kind));
      });
      await _settle(tester);
      // Вариант Б: работа — в городе, подпись «Города» называет мини-игры.
      expect(
          find.bySemanticsLabel(
              RegExp('Работа — мини-игры|работа — мини-игры')),
          findsOneWidget);
      sem.dispose();
    });

    // Ловит: корм питомца не виден до конца недели (дизайнер 28.09, п. 9):
    // план недели и итоги называют только сумму счёта.
    testWidgets('корм питомца назван в плане недели и в счёте итогов',
        (WidgetTester tester) async {
      final World world = kind.make();
      ok(world.startWeek());
      ok(world.plan(needs: 0, wants: 0, goal: 200));
      ok(world.chooseGoal('pet_fish'));
      ok(world.buy('pet_fish'));
      ok(world.sleep());
      ok(world.payBills());
      ok(world.startWeek()); // неделя 2: рыбка, купленная в неделе 1, ест
      final String food =
          'корм питомца ${world.catalogItem('pet_fish')!.weeklyCost}';

      final WorldState state = WorldState(world);
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(), state: state);
      });
      await _settle(tester);
      // План недели: «Сейчас» до плана (в обоих вариантах панели).
      await tester.tap(find.byKey(const ValueKey<String>('room:now')));
      await _step(tester);
      expect(find.textContaining(food), findsOneWidget,
          reason: 'план недели: $food');

      await tester.tap(find.byKey(const ValueKey<String>('plan:confirm')));
      await _step(tester);
      ok(world.sleep());
      await pumpWorldScreen(tester, const WeekReviewScreen(),
          world: world, size: landscape);
      await tester.pump();
      expect(
          find.descendant(
              of: find.byKey(const ValueKey<String>('review:bills')),
              matching: find.textContaining(food, findRichText: true)),
          findsWidgets,
          reason: 'итоги: $food');
    });
  });
  // Ловит: посреди недели золотая кнопка — «Спать», хотя «Сейчас» зовёт
  // в город или на смену (одна золотая кнопка — главное действие,
  // design-system §1 п. 6), или «Спать» не становится главной, когда
  // сил на дело уже нет. Граница — ровно цена самого дешёвого дела.
  for (final (double over, bool cityGold) in <(double, bool)>[
    (0, true),
    (0.5, false),
  ]) {
    testWidgets(
        'кнопка «Сейчас»: ⚡ = цена дела ${over == 0 ? '' : '− 0,5 '}→ '
        '${cityGold ? '«в город»' : '«спать»'}', (WidgetTester tester) async {
      final _CostWorld w = _CostWorld()..over = over;
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await pumpWorldScreen(tester, const RoomScreen(), world: w);
      await _settle(tester);
      // Одна золотая кнопка «Сейчас: …» (вариант В): её текст — шаг.
      expect(tester.widget(find.byKey(const ValueKey<String>('room:now'))),
          isA<FilledButton>());
      expect(find.byType(FilledButton), findsOneWidget);
      expect(_textIn(tester, 'room:now'),
          cityGold ? isNot(contains('спать')) : 'Сейчас: спать');
    });
  }

  // ТЗ 2.5.2.2: имя, которое выбрал ребёнок, видно на главном — табличкой
  // в комнате, а не только в подписи для TalkBack. Самое длинное допустимое
  // имя (16 символов) видно целиком в обеих ориентациях.
  for (final WorldKind kind in worldKinds) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      testWidgets('$kind · ${o.key}: имя Финни видно на табличке в комнате',
          (WidgetTester tester) async {
        const String name = 'Пончик-Бубликоff';
        expect(name.length, OnboardingProgress.maxNameLength);
        final World w = kind.make(
            onboarding: const OnboardingProgress(
                step: OnboardingProgress.stepDone, finniName: name));
        ok(w.startWeek());
        ok(w.plan(needs: 250, wants: 100, goal: 50));
        await pumpWorldScreen(tester, const RoomScreen(),
            world: w, size: o.value);
        await _settle(tester);
        final Finder plate = find.byKey(const ValueKey<String>('room:name'));
        expect(_textIn(tester, 'room:name'), name);
        final RenderParagraph p = tester.renderObject<RenderParagraph>(
            find.descendant(of: plate, matching: find.byType(RichText)));
        expect(p.didExceedMaxLines, isFalse, reason: 'имя обрезано');
        // Табличка — поверх сцены в ряду показателей (вариант В), на экране
        // и не на кнопках: сцена начинается у верхнего края.
        final Rect scene = tester.getRect(find.byType(RoomScene));
        final Rect r = tester.getRect(plate);
        final Rect now =
            tester.getRect(find.byKey(const ValueKey<String>('room:now')));
        expect((Offset.zero & o.value).contains(r.bottomRight), isTrue);
        expect(r.overlaps(now), isFalse);
        expect(r.left, greaterThanOrEqualTo(scene.left));
      });
    }
  }
}
