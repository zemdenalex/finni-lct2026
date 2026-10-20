import 'package:finlit/features/world/goal_eta_text.dart';
import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/domain/phrases.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/world_hud.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/shop/pet_shop_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Неделя идёт, все карманные в копилке (и стартовый подарок), тратить
/// нечего.
World _savedWorld(WorldKind kind) {
  final World w = kind.make();
  ok(w.startWeek());
  ok(w.plan(needs: 0, wants: 0, goal: w.snapshot.unallocated));
  return w;
}

/// Экран с настоящим реестром арта. 🔴 Всегда через runAsync: реестр
/// кешируется на весь запуск, и загрузка, начатая в фейковом времени,
/// не завершится и в следующих тестах.
Future<WorldState> _pump(WidgetTester tester, Widget screen, World w,
    {double textScale = 1, Size size = portrait}) async {
  final WorldState st = (await tester.runAsync(() async {
    final WorldState st = await pumpWorldScreen(tester, screen,
        world: w, textScale: textScale, size: size);
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
    return st;
  }))!;
  await _step(tester);
  return st;
}

/// Спрайты анимируются бесконечно — pumpAndSettle не дождётся покоя.
Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Открытая вкладка магазина. n5 #4: касание по надписи вкладки за краем
/// ленты не попадало (hit-test warning), и проверка «влезает» на других
/// отделах молча шла по первому.
int _tabIndex(WidgetTester tester) =>
    DefaultTabController.of(tester.element(find.byType(TabBarView))).index;

/// Касание вкладки [id] (`tab:<id>`): лента вкладок прокручивается, и
/// вкладка за краем сначала подводится под палец — иначе касание уходит
/// мимо (n5 #4: 12 hit-test warnings в двух тестах «влезает при шрифте 1,3»).
Future<void> _tapTab(WidgetTester tester, String id) async {
  final Finder tab = find.byKey(ValueKey<String>('tab:$id'));
  await tester.ensureVisible(tab);
  await _step(tester);
  await tester.tap(tab);
  await _step(tester);
}

/// Список экрана (вертикальный), а не вкладки.
final Finder _list = find.byWidgetPredicate(
    (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down);

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: _list.first);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _step(tester);
}

String _text(WidgetTester tester, String key) => tester
    .widgetList<Text>(find.descendant(
        of: find.byKey(ValueKey<String>(key)), matching: find.byType(Text)))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' ');

void main() {
  forEachWorld((WorldKind kind) {
    // Ловит: окупаемость инструмента есть только в данных, а в копилке, где
    // выбирают цель, её не видно (критерии ночи §3 п. 4).
    testWidgets('копилка: у ноутбука видно, что открывает и когда окупится',
        (WidgetTester tester) async {
      final World w = _savedWorld(kind);
      await _pump(tester, const PiggyScreen(), w);
      final Finder f = find.byKey(const ValueKey<String>('perk:tech_laptop'));
      await tester.scrollUntilVisible(f, 200, scrollable: _list.first);
      expect(tester.widget<PicText>(f).text,
          allOf(contains('Программист'), contains('Окупится примерно за')));
      expect(tester.takeException(), isNull);
    });

    // Настя 18.10: экран, куда ведёт здание «Банк», называется «Банк» в шапке
    // и в справке (было «Копилка»). Ловит: шапка снова «Копилка».
    testWidgets('экран банка: в шапке «Банк», не «Копилка»',
        (WidgetTester tester) async {
      await _pump(tester, const PiggyScreen(), _savedWorld(kind));
      expect(find.text('Банк'), findsWidgets);
      expect(find.text('Копилка'), findsNothing,
          reason: 'в шапке и справке экрана копилки — «Банк»');
      expect(tester.takeException(), isNull);
    });

    // Т6 А (Настя 19.10, решение pm): прогресс цели — монетами «640 из
    // 1000», у полосы и для TalkBack, без процентов. Ловит: процент вернулся.
    testWidgets('копилка: накоплено — «640 из 1000», без процентов',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      final World w = _savedWorld(kind);
      ok(w.chooseGoal('pet_fish'));
      await _pump(tester, const PiggyScreen(), w);
      final int price = w.catalogItem('pet_fish')!.price;
      final int goal = w.snapshot.goal;
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey<String>('piggy:percent')))
              .data,
          '$goal из $price');
      expect(find.bySemanticsLabel(RegExp('Накоплено $goal из $price')),
          findsWidgets);
      sem.dispose();
    });

    // Ловит: карточка еды без шкал пользы и вкуса, «Съесть» ест без
    // подтверждения или диалог не называет цену, ⚡ и 😊 до еды (ТЗ 2.5.6,
    // 2.5.6.2; Денис 29.09, 938).
    testWidgets('еда: шкалы на карточке, «Съесть» — с ценой, ⚡ и 😊 до еды',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      ok(w.leisure('park'));
      final WorldCatalogItem fish = w.catalogItem('food_fish')!;
      await _pump(tester, const WorldShopScreen(), w);

      expect(find.byKey(const ValueKey<String>('scale:energy:food_fish')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('scale:taste:food_fish')),
          findsOneWidget);
      expect(_text(tester, 'card:food_fish'), contains('${fish.price}'));

      await _tap(tester, 'eat:food_fish');
      expect(w.snapshot.mealsThisWeek, 0, reason: 'до подтверждения не едим');
      final String dialog = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Text)))
          .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join(' ');
      expect(dialog, contains('${fish.price}'));
      expect(dialog, contains('Нужно'));
      final int need = w.snapshot.need;
      expect(dialog, contains('В части «Нужно» сейчас $need'),
          reason: 'остаток конверта до еды (ревью 28d9a1f)');
      String hudEnergy() => tester
          .getSemantics(find.bySemanticsLabel(RegExp('^Сил: ')).first)
          .label;
      final double before = w.snapshot.energy;
      // Верх шкалы — из мира: неделя 14, режим дней 20.
      final String top = WorldHud.energyText(WorldHud.energyMaxOf(w));
      expect(hudEnergy(), 'Сил: ${energyShown(before)} из $top');
      await _tap(tester, 'confirm:yes');
      expect(w.snapshot.mealsThisWeek, 1);
      // ⚡ сразу видно в HUD (критерии §2 п. 4).
      expect(w.snapshot.energy, closeTo(before + fish.energy, 1e-9));
      await _step(tester);
      expect(hudEnergy(), 'Сил: ${energyShown(w.snapshot.energy)} из $top');
      // «Почему» — в итоге действия (§2 п. 6).
      expect(
          tester
              .widget<PicText>(find.byKey(
                  const ValueKey<String>('result:reason'),
                  skipOffstage: false))
              .text,
          contains('полезная'));
      expect(tester.takeException(), isNull);
    });

    // Ловит: кнопка еды меньше 48 dp на 360 × 640 при шрифте 1,3 (ТЗ 3.6).
    // «Готовить дома» убрана (Настя, Денис 20.10 23:36): одна кнопка.
    testWidgets('еда при шрифте 1,3: «Купить и съесть» ≥ 48 dp',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
      await _pump(tester, const WorldShopScreen(), w, textScale: 1.3);
      const String key = 'eat:food_regular';
      final Finder f = find.byKey(const ValueKey<String>(key));
      await tester.scrollUntilVisible(f, 200, scrollable: _list.first);
      final Size size = tester.getSize(f);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(find.byKey(const ValueKey<String>('home:food_regular')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    // Ловит: превью счёта врёт — ребёнок покупает питомца, а со следующей
    // недели счёт другой, чем ему показали до покупки.
    testWidgets('превью счёта недели = счёт мира через неделю после питомца',
        (WidgetTester tester) async {
      final World w = _savedWorld(kind);
      await _pump(tester, const PetShopScreen(), w);

      await _tap(tester, 'buy:pet_fish');
      final RegExpMatch m =
          RegExp(r'(\d+) → (\d+)').firstMatch(_text(tester, 'bill:preview'))!;
      expect(int.parse(m[1]!), w.snapshot.weeklyBill);
      final int promised = int.parse(m[2]!);
      expect(promised, greaterThan(w.snapshot.weeklyBill));

      await _tap(tester, 'confirm:yes');
      expect(w.snapshot.owned, contains('pet_fish'));
      // На этой неделе рыбка ещё не ест.
      expect(w.snapshot.weeklyBill, int.parse(m[1]!));

      expect(sleepWeek(w).ok, isTrue);
      expect(w.payBills().ok, isTrue);
      expect(w.startWeek().ok, isTrue);
      expect(w.snapshot.weeklyBill, promised);
    });

    // Ловит: при нехватке экран молчит, даёт нажать или что-то списывает.
    // Причина — та, что вернул бы мир (`canDo`), с суммой из каталога мира.
    testWidgets('покупка без денег: кнопка погашена, причина мира на карточке',
        (WidgetTester tester) async {
      final World w = _savedWorld(kind);
      await _pump(tester, const WorldShopScreen(), w);
      final ResourceSnapshot before = w.snapshot;
      final int price = w.catalogItem('poster_city')!.price;

      await tester.tap(find.text('Уют и декор'));
      await _step(tester);
      final Finder buy = find.byKey(const ValueKey<String>('buy:poster_city'));
      await tester.scrollUntilVisible(buy, 200, scrollable: _list.first);
      expect(tester.widget<OutlinedButton>(buy).onPressed, isNull);
      final BlockReason block = w.canDo(WorldAction.buy, id: 'poster_city')!;
      expect(block.text, contains('Не хватает $price'));
      expect(_text(tester, 'block:poster_city'), contains(block.text));
      expect(_text(tester, 'block:poster_city'), contains(block.nextStep!));

      await tester.tap(buy, warnIfMissed: false);
      await _step(tester);
      expect(find.byKey(const ValueKey<String>('confirm:yes')), findsNothing);
      final ResourceSnapshot after = w.snapshot;
      expect(after.available, before.available);
      expect(after.goal, before.goal);
      expect(after.owned, before.owned);
    });

    testWidgets('питомец дороже копилки: причина мира, копилка цела',
        (WidgetTester tester) async {
      final World w = _savedWorld(kind);
      await _pump(tester, const PetShopScreen(), w);
      final int saved = w.snapshot.goal;
      final int short = w.catalogItem('pet_dog')!.price - saved;

      final Finder buy = find.byKey(const ValueKey<String>('buy:pet_dog'));
      await tester.scrollUntilVisible(buy, 200, scrollable: _list.first);
      expect(_text(tester, 'block:pet_dog'), contains('Не хватает $short'));
      await tester.tap(buy, warnIfMissed: false);
      await _step(tester);

      expect(find.byKey(const ValueKey<String>('confirm:yes')), findsNothing);
      expect(w.snapshot.goal, saved);
      expect(w.snapshot.owned, isNot(contains('pet_dog')));
    });

    // Ловит: цена на карточке разошлась с каталогом мира.
    testWidgets('карточки зоомагазина: цена и корм из каталога мира',
        (WidgetTester tester) async {
      final World w = _savedWorld(kind);
      await _pump(tester, const PetShopScreen(), w);
      final WorldCatalogItem fish = w.catalogItem('pet_fish')!;
      final String card = _text(tester, 'card:pet_fish');
      expect(card, contains(fish.title));
      expect(card, contains('Корм ${fish.weeklyCost} в неделю'));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey<String>('card:pet_fish')),
              matching: find.textContaining('${fish.price}')),
          findsWidgets);
    });

    // Ловит: в копилке кнопка «Купить» есть, хотя мир откажет, или причина
    // своя, а не мира.
    testWidgets('копилка: цель не по карману — причина мира вместо покупки',
        (WidgetTester tester) async {
      final World w = _savedWorld(kind);
      ok(w.chooseGoal('pet_dog'));
      await _pump(tester, const PiggyScreen(), w);
      expect(find.byKey(const ValueKey<String>('piggy:buy')), findsNothing);
      expect(_text(tester, 'piggy:block'),
          contains(w.canDo(WorldAction.buy, id: 'pet_dog')!.text));

      // Цель по карману — выбрана через экран, кнопка появилась.
      await _tap(tester, 'goal:pet_fish');
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('piggy:buy')), -200,
          scrollable: _list.first);
      expect(find.byKey(const ValueKey<String>('piggy:block')), findsNothing);
    });

    // Ловит (ТЗ 2.5.7.4, вариант A 17.10): срока до цели на S9 нет, он
    // показан до первого взноса или до конца недели с взносом, или не
    // появляется после итогов этой недели.
    testWidgets(
        'срок до цели: до законченной недели с взносом — объяснение, '
        'после — по среднему', (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 0, wants: 0, goal: 0));
      ok(w.chooseGoal('pet_dog'));
      await _pump(tester, const PiggyScreen(), w);
      String eta() => tester
          .widget<Text>(find.byKey(const ValueKey<String>('piggy:eta')))
          .data!;
      expect(
          eta(),
          'Сколько ждать, станет ясно, когда ты в первый раз отложишь '
          'монеты.');

      final World w2 = kind.make();
      ok(w2.startWeek());
      ok(w2.plan(needs: 0, wants: 0, goal: 100));
      ok(w2.chooseGoal('pet_dog'));
      await _pump(tester, const PiggyScreen(), w2);
      expect(w2.weekHistory.last.goal.actual, 100,
          reason: 'настройка: в этой неделе отложено ровно 100');
      expect(eta(), goalEtaWeekNotOver,
          reason: 'неделя идёт — среднего ещё нет, и это не «после первого '
              'взноса»: взнос уже есть');

      ok(sleepWeek(w2));
      ok(w2.payBills());
      await _pump(tester, const PiggyScreen(), w2);
      expect(w2.weekHistory.last.billsPaid, isTrue,
          reason: 'настройка: неделя с взносом закончена');
      final int left = w2.catalogItem('pet_dog')!.price - w2.snapshot.goal;
      expect(left, greaterThan(100),
          reason: 'настройка: копить не одну неделю');
      final int weeks = (left / 100).ceil();
      expect(
          eta(),
          'Если откладывать как сейчас (около 100 в неделю) — примерно $weeks '
          '${Phrases.weekWord(weeks)}.');
    });

    // Ловит: снятие без отдельного подтверждения (ТЗ 2.5.7.5).
    testWidgets('снять из копилки — только после подтверждения',
        (WidgetTester tester) async {
      final World w = _savedWorld(kind);
      await _pump(tester, const PiggyScreen(), w);
      final int saved = w.snapshot.goal;

      for (int i = 0; i < 5; i++) {
        await _tap(tester, 'withdraw:plus');
      }
      await _tap(tester, 'withdraw:go');
      expect(find.textContaining('было $saved → станет ${saved - 50}'),
          findsOneWidget);
      await _tap(tester, 'confirm:no');
      expect(w.snapshot.goal, saved);

      await _tap(tester, 'withdraw:go');
      await _tap(tester, 'confirm:yes');
      expect(w.snapshot.goal, saved - 50);
      expect(w.snapshot.free, 50);
    });

    // Ловит (проход демо 16.10): ползунок для TalkBack говорит «50» при
    // сумме 0 — читает проценты шкалы, а не монеты.
    testWidgets('ползунок для TalkBack называет сумму, а не проценты',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      final World w = _savedWorld(kind);
      await _pump(tester, const PiggyScreen(), w);
      // Нижнее меню (стиль Алины) забрало 60 dp: ползунок — ниже первого
      // экрана, список строит его, когда до него докрутили.
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('withdraw:slider')), 200,
          scrollable: _list.first);
      // Узел ползунка ищем по флагу isSlider: ключ стоит на виджете Slider,
      // и в разных версиях Flutter `getSemantics` по ключу отдаёт то сам
      // ползунок, то панель «Снять» над ним (тогда value пустое — тест
      // падал от устройства дерева, а не от того, что слышит TalkBack).
      String said() {
        SemanticsNode? found;
        bool visit(SemanticsNode n) {
          if (n.getSemanticsData().flagsCollection.isSlider) {
            found = n;
            return false;
          }
          n.visitChildren(visit);
          return found == null;
        }

        visit(tester.getSemantics(
            find.byKey(const ValueKey<String>('withdraw:slider'))));
        expect(found, isNotNull, reason: 'у «Снять» нет узла ползунка');
        return found!.getSemanticsData().value;
      }

      expect(said(), '0 ${Phrases.coinsNom(0)}');
      for (int i = 0; i < 3; i++) {
        await _tap(tester, 'withdraw:plus');
      }
      expect(said(), '30 ${Phrases.coinsNom(30)}');
      sem.dispose();
    });

    // Ловит (ТЗ 2.5.7.5): при снятии с цели не видно, как сдвинется срок,
    // хотя срок на экране считается.
    testWidgets('снятие: в подтверждении — как изменится срок до цели',
        (WidgetTester tester) async {
      final World w = kind.make();
      ok(w.startWeek());
      ok(w.plan(needs: 0, wants: 0, goal: 100));
      ok(w.chooseGoal('pet_dog'));
      // Срок есть только после законченной недели с взносом (вариант A).
      ok(sleepWeek(w));
      ok(w.payBills());
      ok(w.startWeek());
      ok(w.plan(needs: 0, wants: 0, goal: 0));
      await _pump(tester, const PiggyScreen(), w);
      final int left = w.catalogItem('pet_dog')!.price - w.snapshot.goal;
      final int before = (left / 100).ceil();
      final int after = ((left + 50) / 100).ceil();
      expect(after, greaterThan(before), reason: 'настройка: срок сдвинется');
      for (int i = 0; i < 5; i++) {
        await _tap(tester, 'withdraw:plus');
      }
      await _tap(tester, 'withdraw:go');
      expect(
          find.textContaining('Срок до цели: примерно $before → $after '
              '${Phrases.weekWord(after)}'),
          findsOneWidget);
      await _tap(tester, 'confirm:no');
    });

    // Ловит: вёрстка ломается на маленьком телефоне с крупным шрифтом.
    for (final (String name, Widget screen) in <(String, Widget)>[
      ('магазин', const WorldShopScreen()),
      ('зоомагазин', const PetShopScreen()),
      ('копилка', const PiggyScreen()),
    ]) {
      testWidgets('$name влезает в 360×640 при шрифте 1,3',
          (WidgetTester tester) async {
        final World w = _savedWorld(kind);
        ok(w.chooseGoal('pet_fish'));
        await _pump(tester, screen, w, textScale: 1.3);
        expect(tester.takeException(), isNull);
        if (screen is PetShopScreen) {
          expect(find.byType(SpriteAnim), findsWidgets);
        }
        if (screen is WorldShopScreen) {
          for (final (int index, String tab) in <(int, String)>[
            (1, 'want'),
            (2, 'clothes'),
            (3, 'furniture')
          ]) {
            await _tapTab(tester, tab);
            expect(_tabIndex(tester), index,
                reason: 'касание «$tab» не попало во вкладку');
            expect(tester.takeException(), isNull);
          }
        }
        await tester.drag(_list.first, const Offset(0, -2000));
        await _step(tester);
        expect(tester.takeException(), isNull);
      });
    }

    group('альбомная 640×360', () {
      // Ловит: в основной ориентации список — растянутый портретный столбик,
      // и на экране высотой 360 dp видна одна карточка.
      testWidgets('магазин: еда тремя карточками в ряд, вкладки в шапке',
          (WidgetTester tester) async {
        await _pump(tester, const WorldShopScreen(), _savedWorld(kind),
            size: landscape);
        final Rect a = tester
            .getRect(find.byKey(const ValueKey<String>('card:food_simple')));
        final Rect b = tester
            .getRect(find.byKey(const ValueKey<String>('card:food_regular')));
        expect(a.top, b.top);
        expect(a.right, lessThan(b.left));
        // Вкладки — в строке заголовка, над HUD.
        expect(
            tester
                .getRect(find.byKey(const ValueKey<String>('tab:want')))
                .bottom,
            lessThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });

      // Ловит (проход RC 17.10, находка 8): итог покупки оставался над
      // списком и на другой вкладке, закрывая ~120 px чужого отдела.
      testWidgets('итог покупки уходит при смене вкладки',
          (WidgetTester tester) async {
        final World w = kind.make();
        ok(w.startWeek());
        ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
        await _pump(tester, const WorldShopScreen(), w);
        final String food = w.catalog
            .firstWhere(
                (WorldCatalogItem i) => i.category == WorldCatalogCategory.food)
            .id;
        await _tap(tester, 'eat:$food');
        await _tap(tester, 'confirm:yes');
        expect(
            find.byKey(const ValueKey<String>('result:card')), findsOneWidget);
        // Как смахивание: вкладку меняет контроллер.
        DefaultTabController.of(tester.element(find.byType(TabBarView)))
            .animateTo(2);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey<String>('result:card')), findsNothing);
      });

      testWidgets('зоомагазин: питомцы по два в ряд, покупка работает',
          (WidgetTester tester) async {
        final World w = _savedWorld(kind);
        await _pump(tester, const PetShopScreen(), w, size: landscape);
        final Rect fish =
            tester.getRect(find.byKey(const ValueKey<String>('card:pet_fish')));
        final Rect hamster = tester
            .getRect(find.byKey(const ValueKey<String>('card:pet_hamster')));
        expect(fish.top, hamster.top);
        await _tap(tester, 'buy:pet_fish');
        await _tap(tester, 'confirm:yes');
        expect(w.snapshot.owned, contains('pet_fish'));
        // Итог справа от сетки, не над ней.
        expect(
            tester
                .getRect(find.byKey(const ValueKey<String>('result:card')))
                .left,
            greaterThan(320));
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'копилка: цель слева, перенос справа; снятие с подтверждением',
          (WidgetTester tester) async {
        final World w = _savedWorld(kind);
        ok(w.chooseGoal('pet_fish'));
        await _pump(tester, const PiggyScreen(), w, size: landscape);
        final int saved = w.snapshot.goal;
        final Rect goal =
            tester.getRect(find.byKey(const ValueKey<String>('piggy:goal')));
        final Rect deposit =
            tester.getRect(find.byKey(const ValueKey<String>('piggy:deposit')));
        expect(goal.right, lessThan(deposit.left));
        expect(goal.top, deposit.top);
        for (int i = 0; i < 5; i++) {
          await _tap(tester, 'withdraw:plus');
        }
        await _tap(tester, 'withdraw:go');
        await _tap(tester, 'confirm:yes');
        expect(w.snapshot.goal, saved - 50);
        // Итог — в правой панели над переносом.
        expect(
            tester
                .getRect(find.byKey(const ValueKey<String>('result:card')))
                .left,
            greaterThanOrEqualTo(deposit.left));
        expect(tester.takeException(), isNull);
      });

      for (final (String name, Widget screen) in <(String, Widget)>[
        ('магазин', const WorldShopScreen()),
        ('зоомагазин', const PetShopScreen()),
        ('копилка', const PiggyScreen()),
      ]) {
        testWidgets('$name влезает при шрифте 1,3',
            (WidgetTester tester) async {
          final World w = _savedWorld(kind);
          ok(w.chooseGoal('pet_fish'));
          await _pump(tester, screen, w, textScale: 1.3, size: landscape);
          expect(tester.takeException(), isNull);
          if (screen is WorldShopScreen) {
            for (final (int index, String tab) in <(int, String)>[
              (1, 'want'),
              (2, 'clothes'),
              (3, 'furniture')
            ]) {
              await _tapTab(tester, tab);
              expect(_tabIndex(tester), index,
                  reason: 'касание «$tab» не попало во вкладку');
              expect(tester.takeException(), isNull);
            }
          }
          for (final Element e in _list.evaluate().toList()) {
            await tester.drag(
                find.byWidget(e.widget).first, const Offset(0, -2000),
                warnIfMissed: false);
            await _step(tester);
          }
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
