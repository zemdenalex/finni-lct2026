import 'contract.dart';
import 'world_entry.dart';
import 'world_game.dart';

/// Какое действие мира делает шаг автопилота.
enum AutopilotAction {
  startWeek,
  plan,
  chooseGoal,
  resolveEvent,
  eat,
  shift,
  depositToGoal,
  buy,
  leisure,
  sleep,
  payBills,
}

/// Следующее действие автопилота — до того, как оно сделано.
class AutopilotMove {
  const AutopilotMove(this.action, {this.id, this.variant});

  final AutopilotAction action;

  /// Аргумент: цель, вариант события, работа, товар, вид досуга.
  final String? id;

  /// Уровень работы (курьер, программист), иначе null.
  final String? variant;

  @override
  String toString() => 'AutopilotMove(${action.name}'
      '${id == null ? '' : ' $id'}${variant == null ? '' : '/$variant'})';
}

/// Одно действие автопилота: что сделано, что ответил мир и каким мир
/// стал после него.
class AutopilotStep {
  const AutopilotStep(this.move, this.result, this.after);

  final AutopilotMove move;
  final WorldResult result;

  /// Снимок мира сразу после действия — для журнала демо по неделям и
  /// проверки, что баланс ни на одном шаге не ушёл в минус.
  final ResourceSnapshot after;

  AutopilotAction get action => move.action;

  @override
  String toString() => 'AutopilotStep($move: $result)';
}

/// Автопилот демо-режима на настоящем мире (карточка A8,
/// `docs/game/demo-mode.md`).
///
/// 🔴 Только действия [World] — те же, что делает ребёнок на экранах: план,
/// смены, счета, цель, досуг, «Спать». Журнал пишет сам [WorldGame], поэтому
/// у каждой записи есть причина, а очки роста и стадия получаются свёрткой
/// журнала по настоящим правилам. Формул очков здесь нет: правило поведения
/// простое — закрыть счёт недели своими деньгами, остальное отложить в ЦЕЛЬ.
///
/// Детерминирован: следующее действие выбирается только по состоянию мира
/// ([nextMove]), без случайности и времени. Один и тот же мир → один и тот же
/// журнал, пошагово ([step]) или неделями ([playWeeks]).
///
/// Неделя автопилота:
/// 1. план: НУЖНО = счёт недели (сколько хватает карманных), остаток — в ЦЕЛЬ;
/// 2. цель: самая дешёвая из тех, что ещё нет (сначала рыбка);
/// 3. событие недели — вариант, который не берёт из копилки, не добавляет к
///    счёту, не тратит монеты и не съедает ⚡, нужные на отдых и сон;
/// 3а. поесть: домашнее меню, пока приёмы недели не кончились. Стоит столько
///    же, сколько в счёте недели, но ⚡ приходит сейчас, а не на следующую
///    неделю;
/// 4. до [maxShifts] **хороших** смен (оценка = порог «хорошо» работы) там,
///    где больше монет за ⚡, — пока после них остаются силы на досуг и сон;
/// 5. свободный заработок сверх счёта — в ЦЕЛЬ, цель по карману — купить;
/// 6. досуг (с питомцем, если есть, иначе парк), «Спать», счета, новая неделя.
///
/// Если ⚡ кончилась раньше, неделя закрывается сама — автопилот откладывает
/// остаток и платит счета уже в итогах.
///
/// Старый `DemoAutopilot` (мир `Game`) не тронут: живёт до переключения
/// экранов.
class WorldAutopilot {
  WorldAutopilot(this.world, {this.maxShifts = 2});

  final WorldGame world;

  /// Сколько смен за неделю берёт автопилот сам. Смена из события
  /// засчитывается туда же: мир считает все смены недели вместе.
  final int maxShifts;

  /// Сколько действий за неделю максимум: зависший цикл в демонстрации
  /// выглядит хуже недоигранной недели.
  static const int stepsPerWeekGuard = 60;

  static const double _eps = 1e-9;

  /// Что автопилот сделает следующим шагом, не делая этого. У каждой фазы
  /// недели есть выход, поэтому ход есть всегда.
  AutopilotMove nextMove() {
    final ResourceSnapshot s = world.snapshot;
    switch (world.phase) {
      case WeekPhase.onboarding:
        return const AutopilotMove(AutopilotAction.startWeek);
      case WeekPhase.weekStart:
      case WeekPhase.planning:
        return const AutopilotMove(AutopilotAction.plan);
      case WeekPhase.review:
        if (world.canDo(WorldAction.payBills) != null) {
          return const AutopilotMove(AutopilotAction.startWeek);
        }
        // Неделя кончилась по ⚡ раньше взноса: отложить ещё можно — взнос
        // до счетов засчитывается этой неделе.
        if (_spare(s) > 0) {
          return const AutopilotMove(AutopilotAction.depositToGoal);
        }
        return const AutopilotMove(AutopilotAction.payBills);
      case WeekPhase.living:
        return _livingMove(s);
    }
  }

  AutopilotMove _livingMove(ResourceSnapshot s) {
    final PendingEvent? event = world.pendingEvent;
    // Все варианты погашены (так быть не должно: бесплатный есть всегда) —
    // событие ждёт, неделя идёт дальше, а не упирается в отказ.
    if (event != null &&
        event.choices.any((PendingEventChoice c) => c.available)) {
      return AutopilotMove(
        AutopilotAction.resolveEvent,
        id: _pickChoice(event),
      );
    }
    // Копим на переезд (стадия = аренда, Денис 941 п. 3): накопленное
    // остаётся в копилке, если цель сменилась.
    final String? move = _openMove();
    if (move != null && s.activeGoalId != move) {
      return AutopilotMove(AutopilotAction.chooseGoal, id: move);
    }
    if (s.activeGoalId == null) {
      final String? goal = _nextGoal();
      if (goal != null) {
        return AutopilotMove(AutopilotAction.chooseGoal, id: goal);
      }
    }
    final String? meal = s.foodId;
    if (meal != null &&
        s.mealsLeft > 0 &&
        world.canDo(WorldAction.eat, id: meal) == null) {
      return AutopilotMove(AutopilotAction.eat, id: meal);
    }
    if (s.shiftsThisWeek < maxShifts) {
      final JobOffer? job = _pickJob(s);
      if (job != null) {
        return AutopilotMove(
          AutopilotAction.shift,
          id: job.jobId,
          variant: job.variant,
        );
      }
    }
    if (_spare(s) > 0) {
      return const AutopilotMove(AutopilotAction.depositToGoal);
    }
    final String? goal = s.activeGoalId;
    if (goal != null && world.canDo(WorldAction.buy, id: goal) == null) {
      return AutopilotMove(AutopilotAction.buy, id: goal);
    }
    final String? kind = _pickLeisure(s);
    if (kind != null) return AutopilotMove(AutopilotAction.leisure, id: kind);
    return const AutopilotMove(AutopilotAction.sleep);
  }

  /// Сделать ровно одно действие мира.
  AutopilotStep step() {
    final AutopilotMove move = nextMove();
    final String? id = move.id;
    final WorldResult result = switch (move.action) {
      AutopilotAction.startWeek => world.startWeek(),
      AutopilotAction.plan => _plan(),
      AutopilotAction.chooseGoal => world.chooseGoal(id!),
      AutopilotAction.resolveEvent => world.resolveEvent(id!),
      AutopilotAction.eat => world.eat(id!),
      AutopilotAction.shift => _shift(id!, move.variant),
      AutopilotAction.depositToGoal => world.depositToGoal(
          _spare(world.snapshot),
        ),
      AutopilotAction.buy => world.buy(id!),
      AutopilotAction.leisure => world.leisure(id!),
      AutopilotAction.sleep => world.sleep(),
      AutopilotAction.payBills => world.payBills(),
    };
    return AutopilotStep(move, result, world.snapshot);
  }

  /// Проиграть [weeks] недель: до [weeks] закрытых счетов, затем открыть
  /// следующую неделю — с карманными, но без плана, как её увидит ребёнок.
  /// Возвращает все шаги по порядку.
  List<AutopilotStep> playWeeks(int weeks) {
    final List<AutopilotStep> steps = <AutopilotStep>[];
    int closed = 0;
    int guard = stepsPerWeekGuard * weeks;
    while (closed < weeks && guard-- > 0) {
      final AutopilotStep st = step();
      steps.add(st);
      if (st.action == AutopilotAction.payBills && st.result.ok) closed++;
    }
    if (world.canDo(WorldAction.startWeek) == null) {
      final WorldResult r = world.startWeek();
      steps.add(
        AutopilotStep(
          const AutopilotMove(AutopilotAction.startWeek),
          r,
          world.snapshot,
        ),
      );
    }
    return steps;
  }

  /// Играть неделями, пока Финни не дойдёт до [target], но не больше
  /// [maxWeeks] недель («Дойти до 3-й стадии» на панели демо).
  List<AutopilotStep> playToStage(WorldStage target, {int maxWeeks = 12}) {
    final List<AutopilotStep> steps = <AutopilotStep>[];
    int weeks = 0;
    while (world.snapshot.stage.index < target.index && weeks < maxWeeks) {
      steps.addAll(playWeeks(1));
      weeks++;
    }
    return steps;
  }

  // ─────────────────────────────── действия ───────────────────────────────

  /// План: НУЖНО — счёт недели (сколько хватает), остальное — в ЦЕЛЬ.
  WorldResult _plan() {
    final ResourceSnapshot s = world.snapshot;
    final int have = s.unallocated;
    final int needs = have < s.weeklyBill ? have : s.weeklyBill;
    return world.plan(needs: needs, wants: 0, goal: have - needs);
  }

  /// Хорошая смена: оценка ровно на пороге «хорошо» этой работы.
  WorldResult _shift(String jobId, String? variant) {
    final JobOffer o = world.offer(jobId, variant: variant)!;
    return world.completeJob(jobId, variant: variant, score: o.goodScoreMin);
  }

  // ─────────────────────────────── выбор ───────────────────────────────

  /// Свободный заработок сверх счёта недели: столько можно отложить, не
  /// оставив счета без денег. Откладывается только из кошелька заработка.
  int _spare(ResourceSnapshot s) {
    final int overBill = s.need + s.want + s.free - s.weeklyBill;
    final int spare = s.free < overBill ? s.free : overBill;
    return spare > 0 ? spare : 0;
  }

  /// Следующее жильё (переезд — главная цель демо: стадия = аренда): самое
  /// дешёвое из тех, что ещё впереди. Копим на него сразу, даже пока очков
  /// роста не хватает, — к нужным очкам залог уже накоплен. null — дальше
  /// переезжать некуда.
  String? _openMove() {
    WorldCatalogItem? best;
    for (final WorldCatalogItem i in world.catalog) {
      if (i.category != WorldCatalogCategory.home) continue;
      if (world.canDo(WorldAction.chooseGoal, id: i.id) != null) continue;
      if (best == null || i.price < best.price) best = i;
    }
    return best?.id;
  }

  /// Самая дешёвая цель, которой у Финни ещё нет (при равной цене — первая
  /// в каталоге).
  String? _nextGoal() {
    WorldCatalogItem? best;
    for (final WorldCatalogItem i in world.catalog) {
      if (!i.isGoal) continue;
      if (world.canDo(WorldAction.chooseGoal, id: i.id) != null) continue;
      if (best == null || i.price < best.price) best = i;
    }
    return best?.id;
  }

  /// Досуг недели: один раз, и только если после него хватит сил ещё на
  /// одно действие — иначе неделя кончится сама и «Спать» не будет.
  String? _pickLeisure(ResourceSnapshot s) {
    if (_leisureDoneThisWeek(s.weekNo)) return null;
    for (final String kind in const <String>['pet_play', 'park']) {
      if (world.canDo(WorldAction.leisure, id: kind) != null) continue;
      final double cost = _leisureCost(kind);
      if (s.energy - cost + _eps >= world.cheapestActionEnergy) return kind;
    }
    return null;
  }

  bool _leisureDoneThisWeek(int weekNo) => world.journal.any(
        (WorldEntry e) =>
            e.weekNo == weekNo &&
            e.kind == WorldLedgerKind.leisure &&
            e.reasonCode == 'leisure.done',
      );

  double _leisureCost(String kind) => -(world.catalogItem(kind)?.energy ?? 0);

  /// Сколько ⚡ оставить после смены: на досуг (если его ещё не было) и
  /// на одно действие сверх — чтобы неделю закрыл «Спать», а не усталость.
  double _reserve(ResourceSnapshot s) {
    double r = world.cheapestActionEnergy;
    if (!_leisureDoneThisWeek(s.weekNo)) {
      double leisure = double.infinity;
      for (final String kind in const <String>['pet_play', 'park']) {
        final WorldCatalogItem? item = world.catalogItem(kind);
        if (item == null) continue;
        if (item.requires != null && !_petOwned(s)) continue;
        final double c = -item.energy;
        if (c < leisure) leisure = c;
      }
      if (leisure.isFinite) r += leisure;
    }
    return r;
  }

  bool _petOwned(ResourceSnapshot s) => world.catalog.any(
        (WorldCatalogItem i) =>
            i.category == WorldCatalogCategory.pet && s.owned.contains(i.id),
      );

  /// Смена, где больше монет за ⚡, из тех, что можно взять сейчас и после
  /// которых остаётся запас [_reserve]. При равенстве — первая на доске.
  JobOffer? _pickJob(ResourceSnapshot s) {
    final double budget = s.energy - _reserve(s);
    JobOffer? best;
    double bestRate = 0;
    for (final JobOffer o in world.jobBoard) {
      if (o.blocked) continue;
      final double cost = o.energyCost + o.goodEnergyExtra;
      if (cost > budget + _eps) continue;
      final double rate = o.pay / cost;
      if (best == null || rate > bestRate + _eps) {
        best = o;
        bestRate = rate;
      }
    }
    return best;
  }

  /// Вариант события: не берёт из копилки, не добавляет к счёту, не тратит
  /// монеты мимо копилки и оставляет ⚡ на досуг и сон. Из подходящих —
  /// сначала те, что откладывают в ЦЕЛЬ, затем по порядку в файле. Ничего
  /// не подходит — первый доступный. Зовётся, только если доступный есть.
  String _pickChoice(PendingEvent e) {
    final double reserve = _reserve(world.snapshot);
    final double energy = world.snapshot.energy;
    String? saving;
    String? calm;
    String? any;
    for (final PendingEventChoice c in e.choices) {
      if (!c.available) continue;
      any ??= c.id;
      final EffectPreview p = c.preview;
      final bool harmless = p.goal >= 0 &&
          p.weeklyBill <= 0 &&
          p.coins + p.goal >= 0 &&
          (p.energy >= -_eps || energy + p.energy + _eps >= reserve);
      if (!harmless) continue;
      if (p.goal > 0) saving ??= c.id;
      calm ??= c.id;
    }
    return saving ?? calm ?? any!;
  }
}
