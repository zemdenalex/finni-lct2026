import 'dart:convert';
import 'dart:io';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_events.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// События недели на журнале (A10) и причины отказа (A13).
///
/// События — из настоящего `assets/content/world/events.json` (копия
/// `content/events.json`): тест ловит и расхождение кода с файлом.
List<WorldEventSpec> _realEvents() {
  final Map<String, Object?> json =
      jsonDecode(File('assets/content/world/events.json').readAsStringSync())
          as Map<String, Object?>;
  return parseWorldEvents(json['events']! as List<Object?>);
}

WorldEventSpec _event(String id) =>
    _realEvents().firstWhere((WorldEventSpec e) => e.id == id);

WorldGame _world(List<String> ids, {int startGift = 200}) => WorldGame(
      config: WorldConfig(
        startGift: startGift,
        events: ids.map(_event).toList(),
      ),
    );

/// Закрыть неделю (если идёт) и начать следующую с планом: [wants] в ХОЧУ,
/// [goal] в ЦЕЛЬ, остальное — в НУЖНО.
void _nextWeek(WorldGame w, {int wants = 0, int goal = 0}) {
  if (w.phase == WeekPhase.living) expect(w.sleep().ok, isTrue);
  if (w.phase == WeekPhase.review) expect(w.payBills().ok, isTrue);
  final WorldResult start = w.startWeek();
  expect(start.ok, isTrue, reason: start.reason);
  final int have = w.snapshot.unallocated;
  final WorldResult plan =
      w.plan(needs: have - wants - goal, wants: wants, goal: goal);
  expect(plan.ok, isTrue, reason: plan.reason);
}

List<WorldEntry> _since(WorldGame w, int from) => w.journal.sublist(from);

void main() {
  test(
      'events.json: 21 событие разбирается, у каждого здание города, ссылки '
      'на досуг, товар, смену и цель есть в конфиге', () {
    final List<WorldEventSpec> events = _realEvents();
    expect(events, hasLength(21)); // 11 + 10 из контент-предложений 29.09
    const Set<String> buildings = <String>{
      'home',
      'grocery',
      'job-centre',
      'pet-shop',
      'park',
      'cinema',
      'piggy-bank',
    };
    const WorldConfig config = WorldConfig();
    for (final WorldEventSpec e in events) {
      expect(buildings, contains(e.buildingId), reason: e.id);
      for (final WorldEventOptionSpec o in e.options) {
        final EventEffects f = o.effects;
        final String where = '${e.id}/${o.id}';
        if (f.leisure != null) {
          expect(config.leisureKind(f.leisure!), isNotNull, reason: where);
        }
        if (f.buy != null) {
          expect(config.cloth(f.buy!) ?? config.decorItem(f.buy!), isNotNull,
              reason: where);
        }
        if (f.shift != null) {
          expect(config.job(f.shift!, null), isNotNull, reason: where);
        }
        if (f.simulation != null) {
          expect(e.simulation?.id, f.simulation, reason: where);
        }
      }
    }
  });

  test('неизвестный эффект в файле — ошибка с путём, а не тихий пропуск', () {
    expect(
      () => parseWorldEvents(<Object?>[
        <String, Object?>{
          'id': 'x',
          'topic': 'planning',
          'building': 'home',
          'title': 't',
          'situation': 's',
          'options': <Object?>[
            <String, Object?>{
              'id': 'a',
              'label': 'a',
              'finni': 'f',
              'effects': <String, Object?>{'moneyy_pocket_x': 1},
            },
            <String, Object?>{'id': 'b', 'label': 'b', 'finni': 'f'},
          ],
        },
      ]),
      throwsA(isA<FormatException>().having((FormatException e) => e.message,
          'message', contains('events[0].options[0].effects.moneyy_pocket_x'))),
    );
  });

  test(
      'выбор в событии пишет в журнал запись с причиной; превью совпадает с '
      'тем, что случилось', () async {
    final WorldGame w = _world(<String>['grandma_gift']);
    await w.setNickname('Лиса');
    _nextWeek(w, wants: 100, goal: 100);
    expect(w.pendingEvent, isNull, reason: 'min_week 2 — в неделю 1 рано');

    _nextWeek(w, wants: 100, goal: 100);
    final PendingEvent? ev = w.pendingEvent;
    expect(ev?.id, 'grandma_gift');
    expect(w.eventBuildingId, 'home');
    final PendingEventChoice half =
        ev!.choices.firstWhere((PendingEventChoice c) => c.id == 'half_half');
    expect(half.available, isTrue);

    final ResourceSnapshot before = w.snapshot;
    final int mark = w.journal.length;
    final WorldResult r = w.resolveEvent('half_half');
    expect(r.ok, isTrue, reason: r.reason);
    expect(r.reasonCode, 'event.choice');
    expect(r.reason, contains('Лиса'), reason: 'реплика Финни с ником');

    final List<WorldEntry> added = _since(w, mark);
    expect(added, hasLength(1));
    final WorldEntry choice = added.single;
    expect(choice.kind, WorldLedgerKind.eventChoice);
    expect(choice.reasonCode, 'event.choice');
    expect(choice.args['eventId'], 'grandma_gift');
    expect(choice.args['choiceId'], 'half_half');
    expect(choice.args['reason'], r.reason);
    expect(choice.goal, 200, reason: '0,5 × карманные 400 — в копилку');
    expect(choice.free, 200, reason: 'вторая половина — в кошелёк');

    final ResourceSnapshot after = w.snapshot;
    expect(r.coins, after.available - before.available);
    expect(r.goal, after.goal - before.goal);
    expect(r.happiness, after.happiness - before.happiness);
    expect((coins: r.coins, goal: r.goal, happiness: r.happiness),
        (coins: half.preview.coins, goal: half.preview.goal, happiness: 4));

    expect(w.pendingEvent, isNull);
    expect(w.canDo(WorldAction.resolveEvent)?.code, 'event.none');
  });

  test(
      'досуг из копилки: отдельная запись event.leisure с −ЦЕЛЬ; без денег в '
      'копилке вариант погашен той же причиной, что вернёт выбор', () {
    final WorldGame rich = _world(<String>['want_cafe_empty_want']);
    _nextWeek(rich, goal: 100);
    _nextWeek(rich, goal: 100);
    expect(rich.pendingEvent?.id, 'want_cafe_empty_want');
    final int goalBefore = rich.snapshot.goal;
    final int mark = rich.journal.length;
    expect(rich.resolveEvent('from_savings').ok, isTrue);
    final List<WorldEntry> added = _since(rich, mark);
    // P7: выбор тратит ⚡ — сначала проходит игровой день (−😊), один раз.
    expect(added.map((WorldEntry e) => e.reasonCode),
        <String>['day.passed', 'event.choice', 'event.leisure']);
    expect(added.last.kind, WorldLedgerKind.leisure);
    expect(added.last.goal, -200, reason: 'кафе 200 — из копилки');
    expect(added.last.energy, lessThan(0));
    expect(rich.snapshot.goal, goalBefore - 200);
    // A12: последней 😊 меняет запись досуга — причина «отдохнул», а не
    // фраза по уровню.
    expect(rich.snapshot.moodReason.code, 'mood.leisure');
    // T1 — чистое отложенное: 100 в план, 200 из копилки на кафе → −100,
    // очка «откладывал» нет.
    expect(rich.sleep().ok, isTrue);
    expect(rich.payBills().ok, isTrue);
    expect(
        rich.journal
            .lastWhere((WorldEntry e) => e.reasonCode == 'week.closed')
            .args['why'],
        isNot(contains('saved_regularly')));

    final WorldGame poor =
        _world(<String>['want_cafe_empty_want'], startGift: 0);
    _nextWeek(poor);
    _nextWeek(poor);
    final PendingEventChoice cafe = poor.pendingEvent!.choices
        .firstWhere((PendingEventChoice c) => c.id == 'from_savings');
    expect(cafe.blockReason?.code, 'event.goal_short');
    final int len = poor.journal.length;
    final WorldResult refused = poor.resolveEvent('from_savings');
    expect(refused.ok, isFalse);
    expect(refused.reasonCode, 'event.goal_short');
    expect(poor.journal.length, len, reason: 'отказ ничего не пишет');
    expect(poor.pendingEvent?.id, 'want_cafe_empty_want',
        reason: 'событие ждёт другого выбора');
    expect(poor.resolveEvent('park_free').ok, isTrue,
        reason: 'бесплатный вариант есть всегда');
  });

  test('сломался рюкзак: добавка к счёту недели платится в payBills', () {
    final WorldGame w = _world(<String>['backpack_broke']);
    for (int i = 0; i < 3; i++) {
      _nextWeek(w);
    }
    expect(w.pendingEvent?.id, 'backpack_broke');
    final int bill = w.snapshot.weeklyBill;
    final PendingEventChoice cheap = w.pendingEvent!.choices
        .firstWhere((PendingEventChoice c) => c.id == 'cheap_one');
    expect(cheap.preview.weeklyBill, 160);
    expect(w.resolveEvent('cheap_one').ok, isTrue);
    expect(w.snapshot.weeklyBill, bill + 160);

    w.sleep();
    final int mark = w.journal.length;
    expect(w.payBills().ok, isTrue);
    final WorldEntry extra = _since(w, mark)
        .firstWhere((WorldEntry e) => e.reasonCode == 'bills.extra');
    expect(extra.args['amount'], 160);
    expect(w.startWeek().ok, isTrue);
    expect(w.snapshot.weeklyBill, bill, reason: 'добавка — только на неделю');
  });

  test(
      'продолжение по метке: через неделю — день рождения с вариантами своей '
      'метки; старая метка второй раз событие не вызывает', () {
    final WorldGame w =
        _world(<String>['friend_birthday', 'friend_birthday_day']);
    _nextWeek(w, wants: 200);
    expect(w.pendingEvent, isNull);
    _nextWeek(w, wants: 200);
    expect(w.pendingEvent?.id, 'friend_birthday');
    expect(w.resolveEvent('set_aside').ok, isTrue);
    expect(w.pendingEvent, isNull,
        reason: 'метка работает со следующей недели');

    _nextWeek(w, wants: 200);
    expect(w.pendingEvent?.id, 'friend_birthday_day');
    expect(w.pendingEvent!.choices.map((PendingEventChoice c) => c.id),
        <String>['card_now', 'give_ready'],
        reason: 'buy_now — только при gift_last_minute');
    expect(w.resolveEvent('buy_now').reasonCode, 'event.unknown');
    expect(w.resolveEvent('give_ready').ok, isTrue);

    // Неделя 6: friend_birthday снова (2 + 4), но выбор не сделан — метки нет.
    for (int week = 4; week <= 10; week++) {
      _nextWeek(w, wants: 200);
      expect(w.pendingEvent?.id, isNot('friend_birthday_day'),
          reason: 'неделя $week: метка недели 2 уже прочитана');
    }
  });

  test(
      'челлендж «Копилка»: 10 % сейчас из кошелька и 4 недели по 10 % '
      'карманных до плана', () {
    final WorldGame w = _world(<String>['piggy_challenge']);
    for (int i = 0; i < 3; i++) {
      _nextWeek(w, wants: 100);
    }
    expect(w.pendingEvent?.id, 'piggy_challenge');
    final int wantBefore = w.snapshot.want;
    final int goalBefore = w.snapshot.goal;
    expect(w.resolveEvent('join_small').ok, isTrue);
    expect(w.snapshot.want, wantBefore - 40, reason: 'перевод, не подарок');
    expect(w.snapshot.goal, goalBefore + 40);

    final List<int> movedPerWeek = <int>[];
    for (int week = 4; week <= 8; week++) {
      final int mark = w.journal.length;
      _nextWeek(w, wants: 100);
      movedPerWeek.add(_since(w, mark)
          .where((WorldEntry e) => e.reasonCode == 'event.recurring')
          .fold<int>(0, (int a, WorldEntry e) {
        expect(e.unallocated, -e.goal, reason: 'из карманных недели');
        return a + e.goal;
      }));
    }
    expect(movedPerWeek, <int>[40, 40, 40, 40, 0]);
  });

  test(
      'перезапуск посреди недели: ждущее событие, метка и повтор челленджа '
      'восстанавливаются из журнала', () {
    final WorldConfig config = WorldConfig(events: <WorldEventSpec>[
      _event('piggy_challenge'),
      _event('tired_but_good_shift'),
    ]);
    final WorldGame w = WorldGame(config: config);
    for (int i = 0; i < 3; i++) {
      _nextWeek(w, wants: 100);
    }
    expect(w.pendingEvent?.id, 'piggy_challenge');
    expect(w.resolveEvent('join_small').ok, isTrue);
    _nextWeek(w, wants: 100); // неделя 4: первый повтор челленджа
    // Три смены и парк: с ⚡ домашних обедов прошлой недели (+1,5) неделя
    // начинается выше, и в окно 3–5 ⚡ события попадаем после парка.
    for (final WorldResult Function() act in <WorldResult Function()>[
      () => w.completeJob('cashier', score: 0),
      () => w.completeJob('gardener', score: 0),
      () => w.completeJob('gardener', score: 0),
      () => w.leisure('park'),
    ]) {
      if (w.pendingEvent != null) break;
      expect(act().ok, isTrue);
    }
    expect(w.pendingEvent?.id, 'tired_but_good_shift');

    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: config);
    expect(r.unreadable, 0);
    String show(World x) => <Object?>[
          x.phase,
          x.snapshot.available,
          x.snapshot.goal,
          x.snapshot.energy,
          x.snapshot.happiness,
          x.snapshot.weeklyBill,
          x.snapshot.shiftsThisWeek,
          x.pendingEvent?.id,
          for (final PendingEventChoice c in x.pendingEvent!.choices)
            '${c.id} ${c.preview.text} ${c.blockReason?.code}',
        ].join(' | ');
    expect(show(r), show(w));

    for (final WorldGame x in <WorldGame>[w, r]) {
      expect(x.resolveEvent('sleep_now').ok, isTrue);
      _nextWeek(x, wants: 100);
    }
    expect(r.snapshot.goal, w.snapshot.goal);
    expect(r.snapshot.energy, w.snapshot.energy);
    expect(r.journal.length, w.journal.length);
    expect(r.journal.where((WorldEntry e) => e.reasonCode == 'event.recurring'),
        hasLength(2),
        reason: 'повтор недели 5 после перезапуска не потерян');
  });

  test('автомат понарошку: счёт в журнале, деньги и копилка не меняются', () {
    final WorldGame w = _world(<String>['slot_machine_sim']);
    _nextWeek(w);
    expect(w.pendingEvent?.id, 'slot_machine_sim');
    expect(w.eventBuildingId, 'park');
    final ResourceSnapshot before = w.snapshot;
    final WorldResult r = w.resolveEvent('simulate');
    expect(r.ok, isTrue);
    final WorldEntry sim = w.journal
        .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.simulationRun);
    final int spent = sim.args['spent']! as int;
    final int won = sim.args['won']! as int;
    expect(spent, 200, reason: '20 вращений по 10');
    expect(won, lessThanOrEqualTo(spent ~/ 2),
        reason: 'проигрыш всегда не меньше выигрыша');
    expect(r.reason, contains('потрачено бы $spent, выиграно бы $won'));
    expect(w.snapshot.available, before.available);
    expect(w.snapshot.goal, before.goal);
  });

  test(
      'устал, а смена выгодная: событие появляется посреди недели при ⚡ 3–5; '
      'смена из события идёт в лимиты и отказывает их причиной', () {
    final WorldGame w = _world(<String>['tired_but_good_shift']);
    _nextWeek(w);
    expect(w.pendingEvent, isNull, reason: '⚡ 10 — не устал');
    expect(w.completeJob('cashier', score: 0).ok, isTrue); // 10 → 7
    expect(w.pendingEvent, isNull);
    expect(w.completeJob('gardener', score: 0).ok, isTrue); // 7 → 5
    expect(w.pendingEvent?.id, 'tired_but_good_shift');
    expect(w.eventBuildingId, 'job-centre');

    final int mark = w.journal.length;
    final WorldResult r = w.resolveEvent('take_shift');
    expect(r.ok, isTrue, reason: r.reason);
    final List<WorldEntry> added = _since(w, mark);
    final WorldEntry payout =
        added.firstWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout);
    expect(payout.reasonCode, 'event.shift');
    expect(payout.free, 300, reason: 'ставка консультанта с карточки');
    expect(w.snapshot.shiftsThisWeek, 3);
    expect(w.snapshot.experience, 0, reason: 'смена без игры — не «хорошая»');

    // Две смены консультанта уже есть → вариант со сменой гаснет лимитом.
    final WorldGame full = _world(<String>['tired_but_good_shift']);
    _nextWeek(full);
    full.completeJob('consultant', score: 0); // 10 → 7
    full.completeJob('consultant', score: 0); // 7 → 4
    final PendingEventChoice take = full.pendingEvent!.choices
        .firstWhere((PendingEventChoice c) => c.id == 'take_shift');
    expect(take.blockReason?.code, 'job.limit');
    expect(full.resolveEvent('take_shift').reasonCode, 'job.limit');
  });

  test(
      'одна и та же последовательность действий даёт одни и те же события; '
      'не больше 2 в неделю и одно событие не чаще раза в 4 недели', () {
    List<(int, String)> run() {
      final WorldGame w = WorldGame(config: WorldConfig(events: _realEvents()));
      for (int week = 1; week <= 12; week++) {
        _nextWeek(w, wants: 100, goal: 100);
        for (int guard = 0; guard < 3 && w.pendingEvent != null; guard++) {
          final PendingEventChoice c = w.pendingEvent!.choices
              .firstWhere((PendingEventChoice c) => c.available);
          expect(w.resolveEvent(c.id).ok, isTrue);
        }
        if (w.phase == WeekPhase.living) w.completeJob('cashier', score: 0.9);
      }
      return <(int, String)>[
        for (final WorldEntry e in w.journal)
          if (e.kind == WorldLedgerKind.eventShown)
            (e.weekNo, e.args['eventId']! as String),
      ];
    }

    final List<(int, String)> a = run();
    expect(run(), a);
    expect(a.map(((int, String) x) => x.$2).toSet().length,
        greaterThanOrEqualTo(6),
        reason: 'за 12 недель показано разнообразие, а не одно событие');
    final Map<int, int> perWeek = <int, int>{};
    final Map<String, int> last = <String, int>{};
    for (final (int week, String id) in a) {
      perWeek[week] = (perWeek[week] ?? 0) + 1;
      final int? prev = last[id];
      expect(prev == null || week - prev >= 4, isTrue,
          reason: '$id: недели $prev и $week');
      last[id] = week;
    }
    expect(perWeek.values.every((int n) => n <= 2), isTrue, reason: '$perWeek');
  });

  group(
      'A13: почему смену нельзя взять — одна причина на доске, в canDo и '
      'в отказе completeJob', () {
    void expectBlocked(WorldGame w, String jobId, String code,
        {String? variant, String? text}) {
      final BlockReason? can =
          w.canDo(WorldAction.job, id: jobId, variant: variant);
      expect(can?.code, code);
      if (text != null) expect(can!.text, text);
      final JobOffer? offer = w.offer(jobId, variant: variant);
      if (offer != null) expect(offer.blockReason?.code, code);
      final int len = w.journal.length;
      final WorldResult r = w.completeJob(jobId, variant: variant, score: 1);
      expect((r.ok, r.reasonCode, r.reason), (false, code, can!.text));
      expect(w.journal.length, len, reason: 'отказ ничего не пишет');
    }

    test('до плана — фаза', () {
      final WorldGame w = WorldGame()..startWeek();
      expectBlocked(w, 'consultant', 'phase.job',
          text: 'Сначала план недели: разложи карманные по конвертам.');
    });

    test('нет такой работы', () {
      final WorldGame w = WorldGame();
      _nextWeek(w);
      expectBlocked(w, 'astronaut', 'job.unknown');
    });

    test('курьер без транспорта — замок, даже когда ещё и ⚡ мало', () {
      final WorldGame w = WorldGame();
      _nextWeek(w);
      final String transport = 'Нужен транспорт: велосипед, самокат или скейт '
          '(${const WorldConfig().transportPrice}) — копи в копилке';
      expectBlocked(w, 'courier', 'job.locked',
          variant: 'near', text: transport);
      w.completeJob('consultant', score: 0); // 10 → 7
      w.completeJob('consultant', score: 0); // 7 → 4
      expectBlocked(w, 'courier', 'job.locked',
          variant: 'far', text: transport);
    });

    test('две смены одной работы — лимит работы, раньше нехватки ⚡', () {
      final WorldGame w = WorldGame();
      _nextWeek(w);
      w.completeJob('consultant', score: 0);
      w.completeJob('consultant', score: 0); // ⚡ 4 — на третью хватило бы
      expectBlocked(w, 'consultant', 'job.limit',
          text: 'На этой неделе смен здесь больше нет.');
    });

    // Денис 28.09: не больше 3 смен в неделю — четвёртая отказывает общим
    // лимитом, хотя ⚡ на неё хватает. ⚡ 14, чтобы упереться в лимит, а не в
    // силы; лимит — по умолчанию конфига, тот же, что в файле.
    test('четвёртая смена недели — общий лимит (3), раньше нехватки ⚡', () {
      final WorldGame w =
          WorldGame(config: const WorldConfig(energyBasePerWeek: 14));
      _nextWeek(w);
      w.completeJob('gardener', score: 0); // 14 → 12
      w.completeJob('gardener', score: 0); // 12 → 10
      w.completeJob('consultant', score: 0); // 10 → 7
      expect(w.phase, WeekPhase.living);
      // Программист закрыт ноутбуком — снимаем замки, чтобы проверить порядок
      // «лимит раньше ⚡» на сложной задаче.
      expect(w.demoUnlockAllJobs().ok, isTrue);
      const String text = 'На этой неделе смен больше нет — хватит работать.';
      expectBlocked(w, 'cashier', 'job.limit', text: text); // ⚡ 3 из 7 есть
      expectBlocked(w, 'programmer', 'job.limit', variant: 'hard', text: text);
    });

    test('⚡ не хватает на смену', () {
      final WorldGame w = WorldGame();
      _nextWeek(w);
      w.completeJob('consultant', score: 0); // 10 → 7
      w.completeJob('cashier', score: 0); // 7 → 4
      expect(w.demoUnlockAllJobs().ok, isTrue); // программист — без ноутбука
      // Как на полосе ⚡: без «5.0» и точки (ребёнку 7–11 лет).
      expectBlocked(w, 'programmer', 'job.energy',
          variant: 'hard', text: 'Нужно ⚡ 5, есть 4.');
      expect(
          w.canDo(WorldAction.job, id: 'programmer', variant: 'medium'), isNull,
          reason: 'на ⚡ 4 средняя задача (3 + 1) ещё берётся');
    });

    test('⚡ в отказе — шагом 0,5; совпали после округления — без двух чисел',
        () {
      expect(energyShortText(3.5, 2), 'Нужно ⚡ 3,5, есть 2.');
      // Цена смены при 😊 ниже нормы — 3,02; есть 2,99: «нужно 3, есть 3» — нет.
      expect(energyShortText(3.02, 2.99), 'Сил чуть-чуть не хватает: ⚡ 3.');
    });
  });
}
