import 'package:finlit/data/onboarding_store.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт C2 (A10–A14) на обоих мирах: экраны потока B пишутся на
/// `FakeWorld`, а работать будут на `WorldGame` — поведение на границе
/// [World] обязано совпадать.
typedef NewWorld = World Function(
    {OnboardingProgress onboarding, OnboardingSave? saveOnboarding});

void main() {
  group('FakeWorld', () {
    _contractC2(({
      OnboardingProgress onboarding = const OnboardingProgress(),
      OnboardingSave? saveOnboarding,
    }) =>
        FakeWorld(onboarding: onboarding, saveOnboarding: saveOnboarding));
  });
  group('WorldGame', () {
    _contractC2(({
      OnboardingProgress onboarding = const OnboardingProgress(),
      OnboardingSave? saveOnboarding,
    }) =>
        WorldGame(onboarding: onboarding, saveOnboarding: saveOnboarding));

    test('A10: событий на журнале пока нет (A7) — честный отказ, не заглушка',
        () {
      final WorldGame w = WorldGame()..startWeek();
      w.plan(needs: 400, wants: 0, goal: 0);
      expect(w.pendingEvent, isNull);
      expect(w.eventBuildingId, isNull);
      expect(w.resolveEvent('any').reasonCode, 'event.none');
    });
  });

  group('FakeWorld · события (A10)', _fakeEvents);
}

void _contractC2(NewWorld newWorld) {
  // Защищает: доска S6 гасит карточку ровно тогда, когда completeJob
  // откажет, и с тем же кодом. Уронит: правило поменяли в одном месте.
  test(
      'A13: blockReason карточки = canDo = отказ completeJob — фаза, замок, '
      'лимит, ⚡', () {
    final World w = newWorld();
    void same(String jobId, String? variant, String code) {
      final JobOffer o = w.offer(jobId, variant: variant)!;
      expect(o.blockReason?.code, code, reason: '$jobId: карточка');
      expect(w.canDo(WorldAction.job, id: jobId, variant: variant)?.code, code,
          reason: '$jobId: canDo');
      final WorldResult r = w.completeJob(jobId, variant: variant, score: 0.5);
      expect(r.ok, isFalse);
      expect(r.reasonCode, code, reason: '$jobId: действие');
      expect(r.reason, o.blockReason!.text);
    }

    same('consultant', null, 'phase.job');
    w.startWeek();
    w.plan(needs: 400, wants: 0, goal: 0);
    expect(w.offer('consultant')!.blockReason, isNull);
    expect(w.canDo(WorldAction.job, id: 'consultant'), isNull);
    same('courier', 'near', 'job.locked');
    expect(w.offer('courier', variant: 'near')!.locked, isTrue,
        reason: 'транспорт — постоянный замок');
    expect(w.offer('consultant')!.locked, isFalse,
        reason: 'фаза и ⚡ в locked не попадают — иначе ломается конец недели');

    w.completeJob('consultant', score: 0.5);
    w.completeJob('consultant', score: 0.5);
    same('consultant', null, 'job.limit');
    same('programmer', 'hard', 'job.locked'); // нужен мощный ноутбук
    // Замок снят (демо) — дальше по порядку ⚡.
    expect(w.demoUnlockAllJobs().ok, isTrue);
    same('programmer', 'hard', 'job.energy'); // 4 ⚡, смена стоит 5
  });

  test('A13: canDo покупки и досуга — тот же код, что у отказа действия', () {
    final World w = newWorld()..startWeek();
    w.plan(needs: 400, wants: 0, goal: 0);
    for (final (WorldAction a, String id, String code) c
        in <(WorldAction, String, String)>[
      (WorldAction.buy, 'pet_dog', 'buy.goal_short'),
      (WorldAction.buy, 'poster_music', 'buy.short'),
      (WorldAction.buy, 'nothing', 'buy.unknown'),
      (WorldAction.leisure, 'pet_play', 'leisure.no_pet'),
      (WorldAction.leisure, 'cafe', 'leisure.short'),
    ]) {
      expect(w.canDo(c.$1, id: c.$2)?.code, c.$3, reason: c.$2);
      final WorldResult r =
          c.$1 == WorldAction.buy ? w.buy(c.$2) : w.leisure(c.$2);
      expect(r.reasonCode, c.$3, reason: c.$2);
    }
    expect(w.canDo(WorldAction.leisure, id: 'park'), isNull);
    expect(w.canDo(WorldAction.payBills)?.code, 'phase.payBills');
  });

  // Защищает: цена на экране = списание. Уронит: каталог собрали из других
  // чисел, чем берёт buy/leisure.
  test('A11: цена и ⚡ из каталога = то, что списывают buy и leisure', () {
    final World w = newWorld()..startWeek();
    w.plan(needs: 0, wants: 200, goal: 200); // ЦЕЛЬ 200 + подарок 200
    final WorldCatalogItem poster = w.catalogItem('poster_city')!;
    final WorldCatalogItem fish = w.catalogItem('pet_fish')!;
    final WorldCatalogItem park = w.catalogItem('park')!;
    expect(poster.category, WorldCatalogCategory.decor);
    expect(fish.isGoal, isTrue);
    expect(fish.weeklyCost, greaterThan(0), reason: 'корм');
    expect(w.catalogItem('pet_play')!.requires, 'any_pet');
    expect(w.catalogItem('home_room'), isNull, reason: 'комната не продаётся');

    expect(w.leisure('park').energy, closeTo(park.energy, 1e-9));
    expect(w.buy('poster_city').coins, -poster.price);
    expect(w.buy('pet_fish').goal, -fish.price);
    for (final WorldCatalogCategory c in WorldCatalogCategory.values) {
      expect(
          w.catalog.where((WorldCatalogItem i) => i.category == c), isNotEmpty,
          reason: '$c');
    }
  });

  // Защищает: тап по Финни объясняет настроение последним, что его
  // изменило (ТЗ 2.5.10.3). Уронит: причина не обновляется.
  test('A12: причина настроения — последнее, что изменило 😊', () {
    final World w = newWorld();
    expect(w.snapshot.moodReason.code, 'mood.new_home');
    w.startWeek();
    w.plan(needs: 0, wants: 0, goal: 0); // счёт 450, в кошельке 400
    w.leisure('park');
    expect(w.snapshot.moodReason.code, 'mood.leisure');
    expect(w.snapshot.moodReason.text, isNotEmpty);
    w.sleep();
    w.payBills();
    expect(w.snapshot.moodReason.code, 'mood.family_help');
  });

  // Ловит (смоук 29.09 после слияния еды): ⚡ «на следующую неделю» после
  // сна печаталась сырым double — «+1.0 ⚡». Ребёнку — как на полосе: «+1».
  test('сон: ⚡ на следующую неделю без «.0» и точки', () {
    final World w = newWorld();
    w.startWeek();
    w.plan(needs: 0, wants: 0, goal: 0);
    final WorldResult r = w.sleep();
    expect(r.reason, contains('⚡'));
    expect(r.reason, isNot(contains(RegExp(r'\d\.\d'))), reason: r.reason);
  });

  // Защищает: нехватка на счета называется, даже если помощь семьи не
  // понадобилась и 😊 за это не штрафуется. Уронит: причина берётся только
  // из записей, изменивших 😊, — тогда итоги говорят «радость остыла».
  test('A12: нехватку закрыли копилкой — причина называет копилку', () {
    final World w = newWorld()..startWeek();
    w.plan(needs: 0, wants: 0, goal: 0); // 400 против счёта 450
    w.sleep();
    final WorldResult r = w.payBills(takeFromGoal: true);
    expect(r.goal, lessThan(0), reason: 'взяли из копилки');
    expect(w.snapshot.moodReason.code, 'mood.shortfall_goal');
  });

  test('A12: на выбранную еду не хватило — причина называет простую еду', () {
    final World w = newWorld()..startWeek();
    w.plan(needs: 0, wants: 0, goal: 0);
    w.withdrawFromGoal(100); // в карманах 500
    w.chooseFood('food_regular'); // счёт 550 → с простой едой 450
    expect(w.snapshot.weeklyBill, greaterThan(w.snapshot.available));
    w.sleep();
    expect(w.payBills().goal, 0, reason: 'копилку не трогали');
    expect(w.snapshot.moodReason.code, 'mood.shortfall_food');
  });

  // Защищает: «силы кончились» объясняет настроение, хотя в файле штраф 😊
  // за это 0. Уронит: причина — только записи с изменением 😊.
  test('A12: силы кончились — Финни устал, и в итогах недели тоже', () {
    final World w = newWorld()..startWeek();
    w.withdrawFromGoal(100); // + 400 в НУЖНО = 500 против счёта 450
    expect(w.plan(needs: 400, wants: 0, goal: 0).ok, isTrue);
    while (w.phase == WeekPhase.living) {
      expect(w.leisure('park').ok, isTrue);
    }
    expect(w.snapshot.endedBy, WeekEnd.energyOut);
    expect(w.snapshot.moodReason.code, 'mood.tired');
    w.payBills();
    expect(w.snapshot.moodReason.code, 'mood.tired_week');
  });

  // Карточка A14, «готово когда»: перезапуск посреди онбординга продолжает с
  // того же шага. Уронит: выбор не сохранили сразу на шаге.
  test('A14: ник, облик и имя сохраняются сразу — новый мир продолжает', () {
    Future<void> run() async {
      final MemoryStorage storage = MemoryStorage();
      final World first = newWorld(
          onboarding: await loadOnboarding(storage),
          saveOnboarding: saveOnboardingTo(storage));
      expect((await first.setNickname('x' * 17)).ok, isFalse);
      expect((await first.setNickname('  Кузя ')).ok, isTrue);
      expect(first.onboarding.step, OnboardingProgress.stepFinni);
      await first.setFinniLook(
          species: 'finni-a2', gender: FinniGender.girl, look: 3);

      // «Перезапуск» после облика, до имени.
      World again = newWorld(onboarding: await loadOnboarding(storage));
      expect(again.onboarding.nickname, 'Кузя');
      expect(again.onboarding.finniSpecies, 'finni-a2');
      expect(again.onboarding.finniGender, FinniGender.girl);
      expect(again.onboarding.finniLook, 3);
      expect(again.onboarding.step, OnboardingProgress.stepFinni);

      await first.setFinniName('');
      again = newWorld(onboarding: await loadOnboarding(storage));
      expect(again.onboarding.finniName, 'Финни');
      expect(again.onboarding.step, OnboardingProgress.stepMoney);
      // Неделя 1 ещё не начата — продолжаем с облика: переход с него и
      // начисляет карманные, один раз.
      expect(again.onboarding.resumeStep(phase: again.phase, goalChosen: false),
          OnboardingProgress.stepFinni);

      await clearOnboarding(storage);
      expect((await loadOnboarding(storage)).nickname, isEmpty);
    }

    return run();
  });

  // Уронит: `buy` снимает activeGoalId, и перезапуск после покупки цели в
  // неделе 1 (пример Насти — рыбка) или на неделе 2 открывал онбординг снова.
  test(
      'A14: цель куплена в неделе 1 или идёт неделя 2 — онбординг не '
      'возвращается', () {
    const OnboardingProgress stuck =
        OnboardingProgress(step: OnboardingProgress.stepMoney);
    final World w = newWorld(onboarding: stuck)..startWeek();
    expect(stuck.resumeFrom(phase: w.phase, snapshot: w.snapshot),
        OnboardingProgress.stepMoney);
    w.plan(needs: 0, wants: 0, goal: 200); // + подарок 200 = 400
    expect(stuck.resumeFrom(phase: w.phase, snapshot: w.snapshot),
        OnboardingProgress.stepGoal);
    w.chooseGoal('pet_fish');
    expect(w.buy('pet_fish').ok, isTrue);
    expect(w.snapshot.activeGoalId, isNull);
    expect(stuck.resumeFrom(phase: w.phase, snapshot: w.snapshot),
        OnboardingProgress.stepDone);

    w.sleep();
    w.payBills();
    w.startWeek();
    expect(w.phase, WeekPhase.planning);
    expect(stuck.resumeFrom(phase: w.phase, snapshot: w.snapshot),
        OnboardingProgress.stepDone);
  });
}

void _fakeEvents() {
  FakeWorld weekOne() {
    final FakeWorld w = FakeWorld()..startWeek();
    w.plan(needs: 400, wants: 0, goal: 0);
    return w;
  }

  FakeWorld nextWeek(FakeWorld w, {int needs = 450}) {
    if (w.phase == WeekPhase.living) w.sleep();
    w.payBills();
    w.startWeek();
    w.plan(needs: needs.clamp(0, w.snapshot.unallocated), wants: 0, goal: 0);
    return w;
  }

  test('событие ждёт после плана, «!» на здании, уходит после выбора', () {
    final FakeWorld w = FakeWorld()..startWeek();
    expect(w.pendingEvent, isNull, reason: 'до плана событий нет');
    w.plan(needs: 400, wants: 0, goal: 0);
    final PendingEvent e = w.pendingEvent!;
    expect(e.id, 'slot_machine_sim');
    expect(w.eventBuildingId, e.buildingId);
    expect(e.choices.any((PendingEventChoice c) => c.preview.isEmpty), isTrue,
        reason: 'бесплатный вариант есть всегда');

    final WorldResult r = w.resolveEvent('simulate');
    expect(r.ok, isTrue, reason: r.reason);
    expect(r.reason, contains('потрачено бы 200'));
    expect(r.reason, isNot(contains('{')), reason: 'подстановки раскрыты');
    expect(w.pendingEvent, isNull);
    expect(w.eventBuildingId, isNull);
    expect(w.resolveEvent('simulate').reasonCode, 'event.none');
  });

  // Защищает: число на кнопке = то, что случилось. Уронит: превью и
  // применение считают по-разному.
  test('превью варианта = итог выбора; недоступный вариант подписан', () {
    final FakeWorld w = nextWeek(weekOne());
    final PendingEvent e = w.pendingEvent!;
    expect(e.id, 'grandma_gift');
    final PendingEventChoice half =
        e.choices.firstWhere((PendingEventChoice c) => c.id == 'half_half');
    final WorldResult r = w.resolveEvent('half_half');
    expect(r.coins, half.preview.coins);
    expect(r.goal, half.preview.goal);
    expect(r.happiness, half.preview.happiness);

    nextWeek(w); // неделя 3: кафе из копилки
    nextWeek(w); // неделя 4: рюкзак
    final PendingEvent backpack = w.pendingEvent!;
    expect(backpack.id, 'backpack_broke');
    final PendingEventChoice cheap = backpack.choices
        .firstWhere((PendingEventChoice c) => c.id == 'cheap_one');
    final int bill = w.snapshot.weeklyBill;
    expect(w.resolveEvent('cheap_one').ok, isTrue);
    expect(w.snapshot.weeklyBill, bill + cheap.preview.weeklyBill,
        reason: 'обязательная добавка входит в счёт недели');
  });

  test(
      'недоступный вариант: показан, погашен, выбор отказывает с той же '
      'причиной', () {
    final FakeWorld w = nextWeek(weekOne());
    expect(w.resolveEvent('treat').ok, isTrue); // бабушкины — в кошелёк
    nextWeek(w);
    nextWeek(w); // неделя 4: рюкзак, в копилке только подарок 200
    final PendingEvent e = w.pendingEvent!;
    expect(e.id, 'backpack_broke');
    final PendingEventChoice good = e.choices
        .firstWhere((PendingEventChoice c) => c.id == 'good_from_savings');
    expect(good.available, isFalse);
    expect(good.blockReason!.code, 'event.goal_short');
    final int goal = w.snapshot.goal;
    final WorldResult r = w.resolveEvent('good_from_savings');
    expect(r.reasonCode, good.blockReason!.code);
    expect(w.snapshot.goal, goal, reason: 'отказ ничего не меняет');
    expect(w.pendingEvent, isNotNull);
  });

  test('расписание детерминировано: одни действия — одни события', () {
    List<String?> run() {
      final FakeWorld w = weekOne();
      final List<String?> ids = <String?>[w.pendingEvent?.id];
      for (int i = 0; i < 5; i++) {
        nextWeek(w);
        ids.add(w.pendingEvent?.id);
      }
      return ids;
    }

    expect(run(), run());
    expect(run().toSet().length, greaterThan(3));
  });
}
