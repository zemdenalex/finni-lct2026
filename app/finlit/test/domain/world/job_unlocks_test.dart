import 'dart:convert';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Работы открываются покупками (Денис 29.09, 941 п. 5): «больше работ, но
/// меньше доступов». С первого дня — финансовые и базовая; ноутбук —
/// программист, мощный ноутбук — сложные задачи, транспорт — курьер, собака
/// — выгульщик. Числа — из конфига по умолчанию (= `economy.json`, это
/// проверяет `world_config_from_content_test`).
void main() {
  // Подарок побольше — чтобы купить технику в первую же неделю.
  const WorldConfig rich = WorldConfig(startGift: 12500);
  final List<(String, World Function())> worlds = <(String, World Function())>[
    ('FakeWorld', () => FakeWorld(config: rich)),
    ('WorldGame', () => WorldGame(config: rich)),
  ];

  World living(World Function() make) {
    final World w = make();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    return w;
  }

  Set<String> open(World w) => <String>{
        for (final JobOffer o in w.jobBoard)
          if (!o.locked)
            o.variant == null ? o.jobId : '${o.jobId}/${o.variant}',
      };

  for (final (String name, World Function() make) in worlds) {
    group(name, () {
      // Защищает: Приложение А, шаг 6 — с первого запуска есть что делать, и
      // это финансовые работы вуза; остальное закрыто вещами. Уронит:
      // программист снова открыт со старта, закрыли всё, пропал замок у
      // курьера или выгульщика.
      test('первый запуск: открыты финансовые и базовая, остальное — замки',
          () {
        final World w = living(make);
        expect(open(w),
            <String>{'consultant', 'cashier', 'accountant', 'gardener'});
        expect(w.jobBoard.length, greaterThanOrEqualTo(10),
            reason: 'работ с уровнями больше, чем открыто');
      });

      // Защищает: замок говорит, что нужно и сколько стоит (критерии §3 п. 3).
      // Уронит: замок без цены, «собака» вместо ноутбука у программиста.
      test('замок называет вещь и её цену', () {
        final World w = living(make);
        final WorldConfig c = rich;
        String reason(String id, [String? v]) =>
            w.offer(id, variant: v)!.lockedReason!;
        expect(
            reason('programmer', 'easy'),
            allOf(contains('ноутбук'),
                contains('${c.tech('tech_laptop')!.price}')));
        expect(
            reason('programmer', 'hard'),
            allOf(contains('мощный ноутбук'),
                contains('${c.tech('tech_laptop_pro')!.price}')));
        expect(reason('courier', 'near'), contains('${c.transportPrice}'));
        expect(reason('dog_walker'), contains('${c.pet('pet_dog')!.price}'));
      });

      // Защищает: ноутбук открывает лёгкие и средние задачи, мощный — и
      // сложные, где платят больше. Уронит: замок уровня не читается (сложная
      // открыта простым ноутбуком), покупка не снимает замок, оплата уровня
      // не из конфига.
      test('ноутбук → программист; мощный ноутбук → сложные задачи дороже', () {
        final World w = living(make);
        ok(w.buy('tech_laptop'));
        expect(open(w),
            containsAll(<String>['programmer/easy', 'programmer/medium']));
        expect(open(w), isNot(contains('programmer/hard')));
        ok(w.buy('tech_laptop_pro'));
        expect(open(w), contains('programmer/hard'));
        final int medium = w.offer('programmer', variant: 'medium')!.basePay;
        final int hard = w.offer('programmer', variant: 'hard')!.basePay;
        expect(medium, rich.job('programmer', 'medium')!.pay);
        expect(hard, rich.job('programmer', 'hard')!.pay);
        expect(hard, greaterThan(medium));
      });

      // Защищает: мощный ноутбук заменяет простой — копить на простой после
      // него нельзя. Уронит: простой ноутбук снова цель после мощного.
      test('после мощного ноутбука простой — «уже есть»', () {
        final World w = living(make);
        ok(w.buy('tech_laptop_pro'));
        expect(open(w),
            containsAll(<String>['programmer/easy', 'programmer/hard']));
        expect(w.canDo(WorldAction.chooseGoal, id: 'tech_laptop')?.code,
            'goal.owned');
        expect(w.canDo(WorldAction.buy, id: 'tech_laptop')?.code, 'buy.owned');
      });

      // Защищает: ТЗ 2.5.8.5 — «Открыть все профессии» снимает все замки,
      // включая новые (ноутбук). Уронит: новый замок не знает про демо.
      test('демо «Открыть все профессии» снимает все замки', () {
        final World w = living(make);
        ok(w.demoUnlockAllJobs());
        expect(w.jobBoard.where((JobOffer o) => o.locked), isEmpty);
      });
    });
  }

  // Защищает: покупка техники — запись журнала, и после перезапуска
  // программист открыт (ТЗ 2.5.13.1). Уронит: вид записи не читается,
  // свёртка не кладёт технику во владение.
  test('ноутбук переживает перезапуск: программист открыт', () {
    final WorldGame w = WorldGame(config: rich)..startWeek();
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    ok(w.buy('tech_laptop'));
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: rich);
    expect(r.unreadable, 0);
    expect(r.snapshot.owned, contains('tech_laptop'));
    expect(r.offer('programmer', variant: 'easy')!.locked, isFalse);
    expect(r.offer('programmer', variant: 'hard')!.locked, isTrue);
  });

  // Защищает: инструмент — вложение: на карточке цели видно, за сколько
  // смен окупится (критерии §3 п. 4). Уронит: перк без окупаемости или с
  // числом не из цены и ставки.
  test('карточка ноутбука: что открывает и за сколько смен окупится', () {
    final WorldCatalogItem laptop = contentWorld().catalogItem('tech_laptop')!;
    expect(laptop.category, WorldCatalogCategory.tech);
    expect(laptop.isGoal, isTrue);
    // Окупает только прибавка к лучшей работе, открытой с первого дня
    // (ревью 28d9a1f): не 4 500 / 360, а 4 500 / (360 − 300).
    final int best = contentConfig.job('programmer', 'medium')!.pay;
    int base = 0;
    for (final WorldJob j in contentConfig.jobs) {
      if (j.needs == null && j.pay > base) base = j.pay;
    }
    final int gain = best - base;
    expect(gain, greaterThan(0));
    final int shifts = (laptop.price + gain - 1) ~/ gain;
    expect(shifts, isNot((laptop.price + best - 1) ~/ best));
    expect(laptop.perk, contains('Программист'));
    expect(laptop.perk, contains('Окупится примерно за $shifts'));
    // Недели — смены по потолку одной работы в неделю (ревью 2b58bdb §3.4).
    final int cap = contentConfig.maxShiftsPerJobPerWeek;
    expect(laptop.perk, contains('то есть за ${(shifts + cap - 1) ~/ cap} недел'));
    expect(laptop.perk, contains('на $gain больше'));
  });

  // Защищает: если вещь не даёт прибавки, игра не обещает окупаемость.
  // Уронит: «окупится за N» при оплате не выше уже открытой работы.
  test('нет прибавки — «только оплатой не окупится»', () {
    const WorldConfig c = WorldConfig(techs: <WorldTech>[
      WorldTech(
          id: 'tech_laptop',
          title: 'Ноутбук',
          price: 4500,
          unlocks: <String>['computer']),
    ], jobs: <WorldJob>[
      WorldJob(
          id: 'consultant', title: 'Продавец-консультант', pay: 300, energy: 2),
      WorldJob(
          id: 'programmer',
          variant: 'easy',
          title: 'Программист · лёгкая',
          pay: 260,
          energy: 2,
          needs: 'computer'),
    ]);
    final WorldCatalogItem laptop =
        WorldGame(config: c).catalogItem('tech_laptop')!;
    expect(laptop.perk, contains('Только оплатой не окупится'));
    expect(laptop.perk, isNot(contains('Окупится примерно')));
  });
}
