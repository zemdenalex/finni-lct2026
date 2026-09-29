import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/jobs/games/programmer_game.dart';
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/jobs/mini_games.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контент нового мира: настоящие файлы грузятся, битые — падают с именем
/// поля, копия в assets совпадает с `content/` в корне репозитория.
void main() {
  const WorldContentLoader loader = WorldContentLoader(_readFile);

  Future<Map<String, String>> realTexts() async => <String, String>{
        for (final String f in _files)
          f: await _readFile('${WorldContentLoader.base}/$f'),
      };

  WorldContent parse(Map<String, String> t) => WorldContent.parse(
        economy: t['economy.json']!,
        jobs: t['jobs.json']!,
        events: t['events.json']!,
      );

  /// Портит поле по пути и ждёт ошибку, называющую это поле.
  Future<void> expectFieldError(
    String file,
    List<Object> path,
    Object? Function(Object? old) change,
    String expected,
  ) async {
    final Map<String, String> t = await realTexts();
    final Object? json = jsonDecode(t[file]!);
    Object? node = json;
    for (final Object step in path.sublist(0, path.length - 1)) {
      node = step is int
          ? (node! as List<Object?>)[step]
          : (node! as Map<String, Object?>)[step as String];
    }
    final Object last = path.last;
    if (last is int) {
      final List<Object?> list = node! as List<Object?>;
      list[last] = change(list[last]);
    } else {
      final Map<String, Object?> map = node! as Map<String, Object?>;
      final Object? v = change(map[last as String]);
      if (v == _remove) {
        map.remove(last);
      } else {
        map[last] = v;
      }
    }
    t[file] = jsonEncode(json);
    expect(
      () => parse(t),
      throwsA(
        isA<WorldContentError>().having(
          (WorldContentError e) => e.toString(),
          'message',
          contains('$file → $expected'),
        ),
      ),
    );
  }

  test('настоящие файлы из assets грузятся и несут числа Насти v13', () async {
    final WorldContent c = await loader.load();
    final EconomyContent e = c.economy;
    expect(e.pocketMoney, 400);
    expect(e.startGiftAmount, 200);
    expect(e.energyBasePerWeek, 10);
    expect(e.energyMaxPerWeek, 14);
    // В файле базовая ⚡ работы; +1 «на жизнь» добавляет домен.
    expect(e.jobs['consultant']!.tier(null)!.energy, 2);
    expect(e.jobs['courier']!.tier('far')!.pay, 520);
    expect(e.stages.map((StageRule s) => s.payStep),
        <double>[1, 1.2, 1.35]); // перепроверка 29.09
    expect(e.stageRule(WorldStage.moscow).minPoints, 9);
    expect(
      c.jobs.keys,
      containsAll(<String>[
        'consultant',
        'cashier',
        'gardener',
        'courier',
        'programmer',
      ]),
    );
    expect(c.events.length, greaterThanOrEqualTo(8));
  });

  // Защищает: выбор еды — компромисс, а не «правильная кнопка» (ТЗ §8.4,
  // Денис 29.09, 938): ни одно блюдо не лучше другого сразу по цене, вкусу и
  // пользе. Уронит: правка economy.json, после которой одно блюдо не хуже
  // другого по всем трём шкалам и лучше хотя бы по одной; блюд меньше шести.
  test('еда: ни одно блюдо не лучше другого по всем трём шкалам', () async {
    final WorldContent c = parse(await realTexts());
    final List<FoodOption> food = c.economy.food;
    expect(food.length, greaterThanOrEqualTo(6));
    expect(c.economy.mealsPerWeek, greaterThan(0));
    final List<String> dominated = <String>[];
    for (final FoodOption a in food) {
      for (final FoodOption b in food) {
        if (identical(a, b)) continue;
        final bool noWorse = a.price <= b.price &&
            a.happiness >= b.happiness &&
            a.energyNow >= b.energyNow;
        final bool better = a.price < b.price ||
            a.happiness > b.happiness ||
            a.energyNow > b.energyNow;
        if (noWorse && better) dominated.add('${a.id} лучше ${b.id}');
      }
    }
    expect(dominated, isEmpty);
  });

  // Защищает: вуз Финни — советы с настоящими источниками из раздела 6 ТЗ,
  // и ребёнок из игры никуда не уходит: ссылка в карточке — ошибка загрузки
  // (ТЗ §3.1.5, §3.5). Уронит: карточек меньше пяти, источник не назван,
  // адрес сайта попал в текст карточки.
  test('вуз: ≥ 5 советов с источником, ссылок в карточках нет', () async {
    final WorldContent c = parse(await realTexts());
    final UniversityContent u = c.university;
    expect(u.cards.length, greaterThanOrEqualTo(5));
    expect(u.intro, contains('экономист'));
    for (final UniversityCard card in u.cards) {
      expect(card.source,
          anyOf(contains('Банк России'), contains('Открытый бюджет')),
          reason: card.id);
    }
    expect(u.cards.map((UniversityCard k) => k.source).toSet(), hasLength(2),
        reason: 'оба источника ТЗ');
    expect(u.adultNote, allOf(contains('fincult'), contains('budget.mos.ru')),
        reason: 'адреса — у взрослого');
    await expectFieldError(
      'jobs.json',
      <Object>['university', 'cards', 0, 'text'],
      (_) => 'Подробнее: https://fincult.info',
      'university.cards[0].text: ссылок в игре нет',
    );
  });

  // Защищает: битый урок называет поле (критерии §4 п. 10).
  test('урок: доля вне 0..1 — ошибка с путём', () async {
    await expectFieldError(
      'jobs.json',
      <Object>['lessons', 'accountant', 'choices', 1, 'effects', 'goal_share'],
      (_) => 2,
      'lessons.accountant.choices[1].effects.goal_share: доля от 0 до 1',
    );
  });

  // Ловит (ревью df2164a §1.2): позиция с ценой или оплатой без `_note` —
  // число, которое нельзя проследить до разведки или решения команды.
  test('у каждой позиции с ценой или оплатой есть _note', () async {
    final List<String> missing = <String>[];
    int positions = 0;
    void walk(Object? v, String path) {
      if (v is Map<String, Object?>) {
        if (v.containsKey('id') &&
            (v.containsKey('price') || v.containsKey('pay'))) {
          positions++;
          if (!v.containsKey('_note')) missing.add('$path/${v['id']}');
        }
        v.forEach((String k, Object? x) => walk(x, '$path.$k'));
      } else if (v is List<Object?>) {
        for (final Object? x in v) {
          walk(x, path);
        }
      }
    }

    walk(jsonDecode(await File('../../content/economy.json').readAsString()),
        'economy');
    expect(positions, greaterThan(40));
    expect(missing, isEmpty);
  });

  test('копия в assets совпадает с content/ в корне репозитория', () async {
    // Правят content/, а в сборку едет assets/: забытая копия — это игра
    // на старых числах при зелёном симуляторе.
    for (final String f in _files) {
      final String root = await File('../../content/$f').readAsString();
      final String asset =
          await File('${WorldContentLoader.base}/$f').readAsString();
      expect(
        asset.replaceAll('\r\n', '\n'),
        root.replaceAll('\r\n', '\n'),
        reason: 'скопируй content/$f в ${WorldContentLoader.base}/',
      );
    }
  });

  test('пропущенное поле называется полным путём', () async {
    await expectFieldError(
      'economy.json',
      <Object>['jobs', 'courier', 'tiers', 1, 'pay'],
      (_) => _remove,
      'jobs.courier.tiers[1].pay: поле отсутствует',
    );
  });

  test('поле не того типа называется полным путём', () async {
    await expectFieldError(
      'economy.json',
      <Object>['pocket_money', 'base'],
      (_) => '400',
      'pocket_money.base: ожидалось целое число',
    );
  });

  test('ссылка на несуществующий id называется полем', () async {
    await expectFieldError(
      'jobs.json',
      <Object>['jobs', 'programmer', 'tasks', 0, 'tier'],
      (_) => 'expert',
      'jobs.programmer.tasks[0].tier: «expert» — такого id нет',
    );
  });

  // ТЗ 2.5.14.1 / 3.2.3: мини-игры профессий читают jobs.json, а не копии
  // в коде. Граница — тот же путь, что в приложении: файл → WorldContent →
  // JobGames.
  test('каждая мини-игра реестра берёт содержание из jobs.json', () async {
    final WorldContent c = await loader.load();
    expect(c.jobs.keys.toSet(), miniGames.keys.toSet(),
        reason: 'у профессии из jobs.json нет игры или наоборот');
    final JobGames g = JobGames.fromData(c.jobData);
    // Симуляция программиста знает устройства по id задачи — задача с
    // незнакомым устройством молча исполнилась бы как полив.
    for (final ProgTask t in g.programmer.tasks) {
      expect(programmerDevices, contains(t.id));
    }
  });

  test('новый товар, покупка и заказ — правка jobs.json, без кода', () async {
    final Map<String, String> t = await realTexts();
    final Map<String, Object?> json =
        jsonDecode(t['jobs.json']!) as Map<String, Object?>;
    final Map<String, Object?> jobs = json['jobs']! as Map<String, Object?>;
    Map<String, Object?> job(String id) => jobs[id]! as Map<String, Object?>;
    List<Object?> list(String id, String k) => job(id)[k]! as List<Object?>;

    list('cashier', 'purchases').add(<String, Object?>{
      'id': 'c_new',
      'item': 'Пирожок',
      'price': 13,
      'paid_with': 50,
    });
    final Map<String, Object?> set =
        jsonDecode(jsonEncode(list('consultant', 'sets').first))
            as Map<String, Object?>;
    set['id'] = 'set_new';
    set['category'] = 'Кружки';
    list('consultant', 'sets').add(set);
    final Map<String, Object?> order =
        jsonDecode(jsonEncode(list('courier', 'orders').first))
            as Map<String, Object?>;
    order['title'] = 'Новый заказ';
    order['map'] = <String>['S.H..', '..H..', '.....', 'HH.H.', '....G'];
    list('courier', 'orders').insert(0, order);
    job('gardener')['calm_turns'] = 4;
    t['jobs.json'] = jsonEncode(json);

    final JobGames g = JobGames.fromData(parse(t).jobData);
    expect(g.cashier.purchases.last.item, 'Пирожок');
    expect(g.cashier.purchases.last.change, 37);
    expect(g.consultant.sets.last.category, 'Кружки');
    expect(g.courier.orderFor('near').title, 'Новый заказ');
    expect(g.gardener.calmTurns, 4);
  });

  group('мини-игры: битое содержание называет поле', () {
    final List<(String, List<Object>, Object? Function(Object?), String)>
        cases = <(String, List<Object>, Object? Function(Object?), String)>[
      (
        'курьер: на карте нет дома клиента',
        <Object>['jobs', 'courier', 'orders', 0, 'map', 4],
        (_) => 'P....',
        'jobs.courier.orders[0].map: нужен ровно один S и один G',
      ),
      (
        'курьер: буква стены, которой нет в walls',
        <Object>['jobs', 'courier', 'orders', 0, 'map', 2],
        (_) => 'Z...F',
        'jobs.courier.orders[0].map[2]: «Z» — такой стены нет',
      ),
      (
        'курьер: строка карты короче maze',
        <Object>['jobs', 'courier', 'orders', 1, 'map', 0],
        (_) => 'S..',
        'jobs.courier.orders[1].map[0]: в строке 3 клеток',
      ),
      (
        'программист: решение ссылается на блок не из палитры',
        <Object>['jobs', 'programmer', 'tasks', 1, 'solution', 0],
        (_) => 'jump',
        'jobs.programmer.tasks[1].solution[0]: «jump» — такого id нет',
      ),
      (
        'кассир: ни одного покупателя за смену',
        <Object>['jobs', 'cashier', 'customers_per_shift'],
        (_) => 0,
        'jobs.cashier.customers_per_shift: нужен хотя бы один покупатель',
      ),
      (
        'кассир: покупатель платит меньше цены',
        <Object>['jobs', 'cashier', 'purchases', 0, 'paid_with'],
        (_) => 5,
        'jobs.cashier.purchases[0]: покупатель платит не больше цены',
      ),
      (
        'садовник: сетка не сходится с числом грядок',
        <Object>['jobs', 'gardener', 'grid'],
        (_) => <int>[4, 2],
        'jobs.gardener.grid: нужно [столбцы, строки]',
      ),
      (
        'курьер: неверная посылка без объяснения',
        <Object>['jobs', 'courier', 'orders', 0, 'parcels', 1, 'why'],
        (_) => _remove,
        'jobs.courier.orders[0].parcels[1].why: поле отсутствует',
      ),
    ];
    for (final (
          String name,
          List<Object> path,
          Object? Function(Object?) f,
          String want
        ) in cases) {
      test(name, () => expectFieldError('jobs.json', path, f, want));
    }
  });

  test('не JSON — ошибка называет файл', () async {
    final Map<String, String> t = await realTexts();
    t['events.json'] = '{ "events": [ ';
    expect(
      () => parse(t),
      throwsA(
        isA<WorldContentError>().having(
          (WorldContentError e) => e.toString(),
          'message',
          contains('events.json: не JSON'),
        ),
      ),
    );
  });
}

const List<String> _files = <String>[
  'economy.json',
  'jobs.json',
  'events.json',
];

const Object _remove = Object();

Future<String> _readFile(String path) => File(path).readAsString();
