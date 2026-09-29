import 'dart:convert';

import 'package:finlit/domain/ledger/ledger_entry.dart' show LedgerKind;
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'week_growth_scenario.dart';
import 'week_one_scenario.dart';

void main() {
  group('WorldGame', () {
    weekOneEnergyScenario(WorldGame.new);
    weekGrowthScenario((WorldConfig c) => WorldGame(config: c));
  });

  test(
      'пример Насти (v13, слайд 17): две смены консультанта, 500 в ЦЕЛЬ на '
      'рыбку, счёт 460 → ⚡ 2, остаток 40, 😊 60', () {
    // Слайд 17 написан до решений 27.09: рыбка 500 (теперь 400) и без
    // стартового подарка 200. Переопределяем ровно эти числа — заодно видно,
    // что они приходят из конфига, а не из кода. Смены обычные (оценка ниже
    // порога): ставка 300 без опыта и бонуса, как в примере (P1). Еда с 29.09
    // (Денис, 938) — три приёма: не выбранные Финни ест дома, три каши
    // по 70 = 210 вместо «простой еды» 200 на неделю.
    final WorldGame w = WorldGame(
      config: const WorldConfig(
        startGift: 0,
        pets: <WorldPet>[
          WorldPet(
              id: 'pet_fish',
              title: 'Рыбка',
              price: 500,
              foodPerWeek: 40,
              happinessPerWeek: 3),
        ],
      ),
    );
    w.startWeek();
    expect(w.plan(needs: 400, wants: 0, goal: 0).ok, isTrue);
    for (int i = 0; i < 2; i++) {
      expect(w.completeJob('consultant', score: 0.5).ok, isTrue);
    }
    expect(w.snapshot.free, 600);
    expect(w.leisure('park').ok, isTrue);
    expect(w.depositToGoal(500).ok, isTrue);
    expect(w.buy('pet_fish').ok, isTrue);
    expect(w.snapshot.energy, closeTo(2, 1e-9));
    expect(w.phase, WeekPhase.living);

    expect(w.sleep().ok, isTrue);
    final WorldResult bills = w.payBills();
    expect(bills.ok, isTrue, reason: bills.reason);

    final ResourceSnapshot s = w.snapshot;
    expect(s.available, 40,
        reason: '400 + 600 − 500 в ЦЕЛЬ − 460 счёт (3 × 70 еда + 250 жильё)');
    expect(s.goal, 0);
    expect(s.happiness, 60,
        reason: '50 + 6 парк + 10 цель + 3 сон + 0 за кашу дома − 6 '
            'остывание − 3 игровых дня (две смены и парк, P7); неделя 1 — без '
            'проверки роста');
    expect(s.owned, contains('pet_fish'));

    expect(w.startWeek().ok, isTrue);
    expect(w.snapshot.energy, closeTo(12.5, 1e-9),
        reason: '10 + 1 сон + 3 × 0,5 за кашу, съеденную дома в итогах');
    expect(w.snapshot.weeklyBill, 500, reason: 'корм рыбки +40 со 2-й недели');
  });

  test('неделя кончается ровно на 0 ⚡, не раньше; без сна нет переноса ⚡', () {
    // 4 смены, чтобы ⚡ кончилась раньше лимита (в файле лимит 3).
    final WorldGame w =
        WorldGame(config: const WorldConfig(maxShiftsPerWeek: 4))..startWeek();
    w.plan(needs: 400, wants: 0, goal: 0);
    w.completeJob('consultant', score: 0); // 10 → 7
    w.completeJob('consultant', score: 0); // 7 → 4
    w.completeJob('gardener', score: 0); // 4 → 2
    expect(w.snapshot.energy, closeTo(2, 1e-9));
    expect(w.phase, WeekPhase.living,
        reason: '2 ⚡ = цена самого дешёвого действия — неделя идёт');

    final WorldResult last = w.completeJob('gardener', score: 0); // 2 → 0
    expect(last.ok, isTrue, reason: last.reason);
    expect(w.snapshot.energy, closeTo(0, 1e-9));
    expect(w.phase, WeekPhase.review);
    expect(w.snapshot.endedBy, WeekEnd.energyOut);
    expect(w.leisure('park').ok, isFalse);
    expect(w.sleep().ok, isFalse);

    expect(w.payBills().ok, isTrue);
    expect(w.startWeek().ok, isTrue);
    expect(w.snapshot.energy, closeTo(10 + 3 * 0.5, 1e-9),
        reason: 'бонус сна только за «Спать» с ⚡ ≥ 1; три каши дома '
            'в итогах — +0,5 ⚡ каждый на новую неделю');
  });

  test(
      'P1: обычная смена — ровно ставка, опыт не растёт; хорошая — бонус до '
      '20 %, +1 опыт, сверх карточки +0,5 ⚡ и −1 😊, но не ниже 0 ⚡', () {
    final WorldGame w = WorldGame()..startWeek();
    w.plan(needs: 400, wants: 0, goal: 0);
    final JobOffer first = w.offer('consultant')!;
    expect(first.pay, 300);
    expect(first.energyCost, closeTo(3, 1e-9));
    expect(first.efficiencyBonusMax, 60);

    // Оценка 0,5 < 0,75 — обычная смена.
    final WorldResult poor = w.completeJob('consultant', score: 0.5);
    expect(poor.ok, isTrue, reason: poor.reason);
    expect(w.snapshot.free, 300, reason: 'ровно ставка, без бонуса');
    expect(w.snapshot.experience, 0);
    expect(w.snapshot.energy, closeTo(7, 1e-9), reason: 'ровно цена карточки');
    expect(w.snapshot.happiness, 49, reason: 'только игровой день, P7');
    expect(w.offer('consultant')!.pay, 300,
        reason: 'без опыта ставка не растёт');

    // Оценка 1 — хорошая: 300 + 60, ⚡ 3 + 0,5, 😊 −1 за старание и −1 день.
    final WorldResult good = w.completeJob('consultant', score: 1);
    expect(good.ok, isTrue, reason: good.reason);
    expect(w.snapshot.free, 660);
    expect(w.snapshot.experience, 1);
    expect(w.snapshot.energy, closeTo(3.5, 1e-9));
    expect(w.snapshot.happiness, 47);
    expect(good.energy, closeTo(-3.5, 1e-9));
    expect(good.happiness, -2);
    final JobOffer grown = w.offer('consultant')!;
    expect(grown.experiencePercent, 1);
    expect(grown.pay, roundTens(300 * 1.01),
        reason: '300 × 1,01 = 303 → до десятков 300 (ревью df2164a); '
            'настроение — по 😊 на начало недели (50)');

    // Ровно 0,75 — ещё хорошая. Кассир: 260 × 1,01 = 263 → 260, бонус
    // до 50 (260 × 0,2 = 52 → 50), × 0,75 = 37,5 → 40; ⚡ 3 + 0,5 — ровно
    // всё, что осталось.
    final WorldResult edge = w.completeJob('cashier', score: 0.75);
    expect(edge.ok, isTrue, reason: edge.reason);
    expect(w.snapshot.free, 660 + 260 + 40);
    expect(w.snapshot.experience, 2);
    expect(w.snapshot.energy, closeTo(0, 1e-9));
    expect(w.snapshot.happiness, 45);
    expect(w.phase, WeekPhase.review, reason: '⚡ кончилась — неделя закрыта');

    // Надбавка ⚡ — сколько осталось: хорошая смена ровно на остаток ⚡ не
    // уводит в минус (10 − 3 − 3 − 2 = 2, садовник стоит 2 + 0,5).
    final WorldGame low =
        WorldGame(config: const WorldConfig(maxShiftsPerWeek: 4))..startWeek();
    low.plan(needs: 400, wants: 0, goal: 0);
    low.completeJob('consultant', score: 0);
    low.completeJob('cashier', score: 0);
    low.completeJob('gardener', score: 0);
    expect(low.completeJob('gardener', score: 1).ok, isTrue);
    expect(low.snapshot.energy, closeTo(0, 1e-9),
        reason: 'надбавка ⚡ — сколько осталось, в минус не уходим');
  });

  group('правило нехватки', () {
    test(
        'карманов меньше корма: корм берёт все свои деньги, остальное — семья, '
        '−6 😊, без очка «обязательное закрыто», копилку не трогаем', () {
      final WorldGame w = _weekTwoWithFish()
        ..plan(needs: 0, wants: 280, goal: 120);
      expect(w.buy('cloth_cap').ok, isTrue); // 280 из ХОЧУ + 20 из заработка
      expect(w.snapshot.available, 20);
      w.sleep();
      final int pointsBefore = w.snapshot.growthPoints;

      final WorldResult r = w.payBills();
      expect(r.ok, isTrue, reason: r.reason);

      final List<Map<String, Object?>> paid = _bills(w);
      expect(paid.map((Map<String, Object?> b) => b['bill']),
          <String>['petFood', 'food', 'rent'],
          reason: 'корм оплачивается первым');
      expect(paid[0]['fromPockets'], 20);
      expect(paid[0]['fromFamily'], 20);
      expect(paid[1]['fromPockets'], 0);
      expect(paid[2]['fromPockets'], 0);

      final WorldEntry help = _last(w, WorldLedgerKind.familyHelp);
      expect(help.args['amount'], 480, reason: 'счёт 500 − 20 своих');
      expect(help.happiness, -6);
      expect(_lastOrNull(w, LedgerKind.savingsWithdraw), isNull);
      expect(w.snapshot.goal, 120, reason: 'без согласия копилка не тратится');
      expect(w.snapshot.available, 0);
      expect(_last(w, LedgerKind.periodClosed).args['why'],
          <String>['saved_regularly'],
          reason: 'семья помогла → нет очка «обязательное закрыто»; нехватка → '
              'нет «без нехватки»; отложено 120 из 400 дохода — очко есть');
      expect(w.snapshot.growthPoints, pointsBefore + 1);
    });

    test('с согласием — из копилки ровно недостающее, семья не нужна', () {
      final WorldGame w = _weekTwoWithFish()
        ..plan(needs: 0, wants: 0, goal: 400);
      w.completeJob('consultant', score: 0); // обычная смена: ровно 300
      final int pockets = w.snapshot.available;
      final int bill = w.snapshot.weeklyBill;
      final int missing = bill - pockets;
      expect(missing, greaterThan(0));
      w.sleep();

      expect(w.payBills(takeFromGoal: true).ok, isTrue);
      expect(w.snapshot.goal, 400 - missing);
      expect(_last(w, LedgerKind.savingsWithdraw).args['amount'], missing);
      expect(_lastOrNull(w, WorldLedgerKind.familyHelp), isNull);
      expect(w.snapshot.available, 0);
    });

    test('на вкусное домашнее меню не хватает — простое, остаток остаётся', () {
      final int tasty = _homeWeek('food_tasty');
      final int simple = _homeWeek('food_simple');
      final WorldGame w = _weekTwoWithFish()..chooseFood('food_tasty');
      w.plan(needs: 400, wants: 0, goal: 0);
      final int pay = w.offer('gardener')!.pay; // ставка по карточке
      w.completeJob('gardener', score: 0);
      final int pockets = w.snapshot.available;
      expect(pockets, 440 + pay);
      expect(pockets, lessThan(40 + tasty + 250),
          reason: 'на три пиццы не хватает');
      expect(pockets, greaterThanOrEqualTo(40 + simple + 250),
          reason: 'на три каши хватает');
      expect(w.snapshot.weeklyBill, 40 + tasty + 250);
      w.sleep();

      expect(w.payBills(takeFromGoal: true).ok, isTrue);
      final Map<String, Object?> food = _bills(w)[1];
      expect(food['foodId'], 'food_simple');
      expect(food['amount'], simple);
      expect(food['meals'], 3);
      expect(_lastOrNull(w, WorldLedgerKind.familyHelp), isNull);
      expect(w.snapshot.available, pockets - (40 + simple + 250));
    });

    test('баланс не уходит в минус ни в одном кармане', () {
      const List<(int, int, int)> plans = <(int, int, int)>[
        (400, 0, 0),
        (0, 400, 0),
        (0, 0, 400),
        (100, 100, 200),
      ];
      for (final (int n, int wa, int g) in plans) {
        for (final int shifts in <int>[0, 1, 2]) {
          for (final bool fromGoal in <bool>[false, true]) {
            final WorldGame w = _weekTwoWithFish()..chooseFood('food_tasty');
            w.plan(needs: n, wants: wa, goal: g);
            for (int i = 0; i < shifts; i++) {
              w.completeJob('cashier', score: 1);
            }
            w.buy('cloth_cap');
            w.leisure('cafe');
            if (w.phase == WeekPhase.living) w.sleep();
            expect(w.payBills(takeFromGoal: fromGoal).ok, isTrue);
            final String at =
                'план $n/$wa/$g, смен $shifts, из копилки $fromGoal';
            final ResourceSnapshot s = w.snapshot;
            expect(
                <int>[s.need, s.want, s.free, s.unallocated, s.goal]
                    .every((int v) => v >= 0),
                isTrue,
                reason: '$at: ${s.need}/${s.want}/${s.free}/'
                    '${s.unallocated}/${s.goal}');
            final int paid = _bills(w).fold<int>(0,
                (int a, Map<String, Object?> b) => a + (b['amount']! as int));
            expect(
                paid, greaterThanOrEqualTo(40 + _homeWeek('food_simple') + 250),
                reason: '$at: все счета закрыты, корм и еда не пропущены');
          }
        }
      }
    });
  });

  test(
      'очко «откладывал» — за чистое отложенное: положил 10 % и снял обратно '
      'в ту же неделю — очка нет', () {
    final WorldGame w = WorldGame()..startWeek();
    w.plan(needs: 360, wants: 0, goal: 40); // ровно 10 % от дохода 400
    expect(w.withdrawFromGoal(40).ok, isTrue);
    w.sleep();
    expect(w.payBills().ok, isTrue);
    expect(_last(w, LedgerKind.periodClosed).args['why'],
        isNot(contains('saved_regularly')),
        reason: 'взнос 40 − снято 40 = отложено 0');
  });

  // Защищает: 😊 досуга с питомцами и очки роста считаются по конфигу
  // (`per_extra_pet`, `growth.points`), а не константами в коде. Уронит:
  // вернули «+1 за питомца» или «одно очко за причину» — при числах файла
  // (все по 1) этого не видно, поэтому здесь числа другие.
  test('per_extra_pet и очки за причину недели — из конфига', () {
    const WorldConfig base = WorldConfig();
    final WorldGame w = WorldGame(
      config: WorldConfig(
        startGift: 2000,
        leisure: <WorldLeisure>[
          for (final WorldLeisure l in base.leisure)
            l.id == 'pet_play'
                ? WorldLeisure(
                    id: l.id,
                    title: l.title,
                    price: l.price,
                    energy: l.energy,
                    happiness: l.happiness,
                    perExtraPet: 3,
                    requires: l.requires)
                : l,
        ],
        growthPointsPerReason: const <String, int>{
          'required_covered': 2,
          'plan_kept': 0,
          'saved_regularly': 5,
        },
      ),
    )..startWeek();
    expect(w.plan(needs: 300, wants: 0, goal: 100).ok, isTrue);
    expect(w.completeJob('consultant', score: 0).ok, isTrue); // +300
    expect(w.buy('pet_fish').ok, isTrue);
    expect(w.buy('pet_hamster').ok, isTrue);
    expect(w.leisure('pet_play').ok, isTrue);
    expect(_last(w, WorldLedgerKind.leisure).happiness, 4 + 3,
        reason: 'база 4 + 3 за второго питомца');

    w.sleep();
    expect(w.payBills().ok, isTrue);
    final WorldEntry closed = _last(w, LedgerKind.periodClosed);
    expect(closed.args['why'],
        <String>['required_covered', 'plan_kept', 'saved_regularly']);
    expect(closed.args['points'], 2 + 0 + 5);
    expect(w.snapshot.growthPoints, 7);
  });

  test('состояние — свёртка журнала: перезапуск из JSON даёт тот же мир', () {
    final WorldGame w = _weekTwoWithFish()
      ..chooseFood('food_regular')
      ..chooseGoal('transport_bike');
    w.plan(needs: 300, wants: 50, goal: 50);
    w.completeJob('consultant', score: 0.5);
    w.leisure('pet_play');
    w.petTap('pet_fish');

    final List<Object?> saved =
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>;
    saved.add(<String, Object?>{
      'seq': saved.length,
      'weekNo': 2,
      'kind': 'world.fromTheFuture',
      'reasonCode': 'x',
    });
    final WorldGame r = WorldGame.fromJson(saved);

    expect(r.unreadable, 1, reason: 'неизвестный вид пропущен, не падаем');
    expect(r.phase, w.phase);
    expect(_describe(r.snapshot), _describe(w.snapshot));
    expect(r.jobBoard.map((JobOffer o) => '${o.jobId}${o.pay}${o.energyCost}'),
        w.jobBoard.map((JobOffer o) => '${o.jobId}${o.pay}${o.energyCost}'));
  });
}

/// Неделя 1 по умолчанию (подарок 200 + 200 с заработка → рыбка 400), счета
/// закрыты своими деньгами, в заработке 50. Неделя 2 начата, план не сделан.
WorldGame _weekTwoWithFish() {
  final WorldGame w = WorldGame()..startWeek();
  w.plan(needs: 400, wants: 0, goal: 0);
  w.completeJob('consultant', score: 0); // +300
  w.depositToGoal(200);
  expect(w.buy('pet_fish').ok, isTrue);
  w.sleep();
  w.payBills();
  expect(w.snapshot.available, 40, reason: '700 − 200 в ЦЕЛЬ − 460 счёт');
  expect(w.snapshot.goal, 0);
  w.startWeek();
  expect(w.snapshot.weeklyBill, 500, reason: 'корм 40 + еда 210 + жильё 250');
  return w;
}

/// Счёт еды недели, если все приёмы — это блюдо дома (из конфига по
/// умолчанию = `economy.json`).
int _homeWeek(String foodId) {
  const WorldConfig c = WorldConfig();
  return c.food(foodId)!.price * c.mealsPerWeek;
}

List<Map<String, Object?>> _bills(WorldGame w) {
  final int week = w.snapshot.weekNo;
  return w.journal
      .where((WorldEntry e) =>
          e.kind == WorldLedgerKind.billPaid && e.weekNo == week)
      .map((WorldEntry e) => e.args)
      .toList();
}

WorldEntry? _lastOrNull(WorldGame w, Enum kind) {
  final int week = w.snapshot.weekNo;
  WorldEntry? found;
  for (final WorldEntry e in w.journal) {
    if (e.kind == kind && e.weekNo == week) found = e;
  }
  return found;
}

WorldEntry _last(WorldGame w, Enum kind) => _lastOrNull(w, kind)!;

String _describe(ResourceSnapshot s) => <Object?>[
      s.weekNo,
      s.need,
      s.want,
      s.goal,
      s.free,
      s.unallocated,
      s.energy,
      s.happiness,
      s.growthPoints,
      s.stage,
      s.experience,
      s.shiftsThisWeek,
      s.weeklyBill,
      (s.owned.toList()..sort()).join(','),
      s.activeGoalId,
      s.activePetId,
      s.endedBy,
    ].join(' | ');
