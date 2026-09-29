import 'dart:convert';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Стадия = аренда (Денис 29.09, 941 п. 3; критерии ночи §7): переезд —
/// выбор ребёнка, открывается очками роста И деньгами на залог; две аренды —
/// город, потом Москва. Числа — конфиг по умолчанию (= `economy.json`).
void main() {
  const WorldConfig c = WorldConfig(startGift: 5000);

  /// Недели со сменой, счетами своими деньгами и взносом ≥ 10 % — по 3 очка.
  World grown(World w, int weeks) {
    for (int i = 0; i < weeks; i++) {
      ok(w.startWeek());
      ok(w.plan(needs: 300, wants: 0, goal: 100));
      ok(w.completeJob('consultant', score: 0.5)); // счета — своими деньгами
      ok(w.sleep());
      ok(w.payBills());
    }
    ok(w.startWeek());
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    return w;
  }

  for (final (String name, World Function() make)
      in <(String, World Function())>[
    ('FakeWorld', () => FakeWorld(config: c)),
    ('WorldGame', () => WorldGame(config: c)),
  ]) {
    group(name, () {
      // Защищает: деньги без очков не переселяют; очков без переезда стадия
      // не меняется (не автомат); переезд — стадия, ступень оплаты и новая
      // плата. Уронит: стадия снова по очкам сама, залог без проверки очков.
      test('переезд: только при очках и деньгах, по выбору ребёнка', () {
        final World w = grown(make(), 0);
        expect(
            w.snapshot.goal, greaterThanOrEqualTo(c.home('home_flat')!.price));
        expect(w.canDo(WorldAction.buy, id: 'home_flat')?.code, 'buy.points');
        expect(w.buy('home_flat').ok, isFalse);
        expect(w.snapshot.stage, WorldStage.village);

        final World g = grown(make(), 2);
        expect(g.snapshot.growthPoints,
            greaterThanOrEqualTo(c.stageMinPoints[WorldStage.town.index]));
        expect(g.snapshot.stage, WorldStage.village,
            reason: 'очков хватает, но переезд — выбор ребёнка');
        final int payBefore = g.offer('consultant')!.pay;
        final WorldResult r = ok(g.buy('home_flat'));
        expect(r.reason, contains('переезжает'));
        expect(g.snapshot.stage, WorldStage.town);
        expect(g.offer('consultant')!.pay, greaterThan(payBefore),
            reason: 'в городе платят больше (pay_step)');
        expect(g.snapshot.owned, contains('home_flat'));
      });

      // Защищает: нельзя «переехать назад» и в Москву — без очков Москвы.
      test('Москва — вторая аренда: свои очки; назад не переезжают', () {
        final World g = grown(make(), 2);
        ok(g.buy('home_flat'));
        expect(g.canDo(WorldAction.buy, id: 'home_house')?.code, 'buy.points');
        expect(g.canDo(WorldAction.chooseGoal, id: 'home_flat')?.code,
            'goal.owned');
      });

      // Защищает: очки есть, денег на залог нет — отказ с объяснением,
      // сколько не хватает; итог недели зовёт копить. Уронит: проверка
      // денег при переезде пропала (стадия бесплатно) или отказ без причины.
      test('очки есть, денег нет — отказ с объяснением', () {
        const WorldConfig poor = WorldConfig(startGift: 0);
        final World w = grown(
            name == 'FakeWorld'
                ? FakeWorld(config: poor)
                : WorldGame(config: poor),
            2);
        final int price = poor.home('home_flat')!.price;
        expect(w.snapshot.growthPoints,
            greaterThanOrEqualTo(poor.stageMinPoints[WorldStage.town.index]));
        expect(w.snapshot.goal, lessThan(price));
        expect(
            w.canDo(WorldAction.buy, id: 'home_flat')?.code, 'buy.goal_short');
        final WorldResult r = w.buy('home_flat');
        expect(r.ok, isFalse);
        expect(r.reason, contains('${price - w.snapshot.goal}'));
        expect(w.snapshot.stage, WorldStage.village);
        ok(w.sleep());
        final WorldResult week = ok(w.payBills());
        if (name == 'WorldGame') {
          expect(week.reason, contains('копи в копилке'));
        }
      });

      // Защищает: отказаться от переезда можно без наказания (§7 п. 7):
      // та же неделя в мире, где переезд недоступен (порог очков не
      // достижим), даёт ровно те же 😊. Уронит: любой «штраф за отказ».
      // Плюс: когда в копилке уже хватает, итог не зовёт «копи».
      test('не переезжать — без штрафа; в копилке хватает — так и сказано', () {
        const WorldConfig never =
            WorldConfig(startGift: 5000, stageMinPoints: <int>[0, 999, 9999]);
        final World g = grown(make(), 2);
        final World twin = grown(
            name == 'FakeWorld'
                ? FakeWorld(config: never)
                : WorldGame(config: never),
            2);
        expect(g.snapshot.happiness, twin.snapshot.happiness);
        ok(g.sleep());
        ok(twin.sleep());
        final WorldResult r = ok(g.payBills());
        ok(twin.payBills());
        expect(g.snapshot.stage, WorldStage.village);
        expect(g.snapshot.happiness, twin.snapshot.happiness,
            reason: 'только обычное правило недели, без «штрафа за отказ»');
        if (name == 'WorldGame') {
          expect(r.reason, contains('хватает на переезд'));
          expect(r.reason, contains('в копилке уже хватает'));
          expect(r.reason, isNot(contains('копи в копилке')));
        }
      });
    });
  }

  // Защищает: переезд — записи журнала (жильё и новая стадия), стадия
  // переживает перезапуск (ТЗ 2.5.13.1).
  test('переезд в журнале и после перезапуска', () {
    final WorldGame w = grown(WorldGame(config: c), 2) as WorldGame;
    ok(w.buy('home_flat'));
    expect(w.journal.last.kind, WorldLedgerKind.stageChanged);
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: c);
    expect(r.snapshot.stage, WorldStage.town);
  });

  // Защищает: что даст переезд, видно заранее (§7 п. 5).
  test('карточка жилья: что даст переезд и сколько очков нужно', () {
    final WorldCatalogItem flat = contentWorld().catalogItem('home_flat')!;
    expect(flat.perk, contains('Переезд в город'));
    expect(flat.perk, contains('${contentConfig.stageMinPoints[1]} очках'));
    expect(flat.weeklyCost, contentConfig.home('home_flat')!.weeklyCost);
  });
}
