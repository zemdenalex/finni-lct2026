import 'content.dart';
import 'custom_goal.dart';
import 'economy/economy_config.dart';
import 'economy/period_rules.dart';
import 'economy/purchase_rules.dart';
import 'economy/savings_rules.dart';
import 'ledger/ledger_entry.dart';
import 'ledger/ledger_fold.dart';
import 'models/catalog_item.dart';
import 'models/envelope.dart';
import 'models/goal.dart';
import 'models/pet.dart';
import 'models/profile.dart';
import 'models/task.dart';

/// Короткая обратная связь после действия (§2.5.9).
///
/// Называется ActionResult, а не Feedback, потому что Flutter экспортирует
/// свой класс Feedback из material — коллизия имён молча превращает наш тип
/// в dynamic, и строгий анализатор проекта падает на первом же обращении.
///
/// Три поля ровно потому, что ТЗ требует трёх вещей: что изменилось,
/// почему, и что делать дальше.
class ActionResult {
  const ActionResult({required this.title, required this.text, this.nextStep});

  final String title;
  final String text;
  final String? nextStep;
}

/// Этап игровой недели — определяет, что предлагает главный экран.
enum PeriodPhase { planning, living, closing }

/// Игровое ядро. Чистый Dart: ни одного import 'package:flutter/…'.
///
/// Проверяется тестом test/domain/layering_test.dart — без него слои
/// расползаются к пятому дню, это происходит на каждом хакатоне.
class Game {
  Game({
    required this.content,
    required GameProfile profile,
    List<LedgerEntry>? ledger,
  })  : _profile = profile,
        _ledger = ledger ?? <LedgerEntry>[],
        _seq = (ledger?.length ?? 0);

  final GameContent content;
  GameProfile _profile;
  final List<LedgerEntry> _ledger;
  int _seq;

  GameProfile get profile => _profile;
  List<LedgerEntry> get ledger => List<LedgerEntry>.unmodifiable(_ledger);

  /// Та же игра, но на другом наборе контента — режим «числа покрупнее»
  /// меняет весь контент целиком (§2.5.8.4).
  ///
  /// 🔴 Журнал переносится полностью и намеренно. Баланс — это свёртка
  /// журнала (`LedgerFold`), а не отдельное поле: потерять журнал значит
  /// обнулить кошелёк, копилку и показатели питомца, то есть нарушить
  /// §3.4.6 «без потери прогресса». Записи остаются в тех монетках, в
  /// которых были сделаны, — накопленное не пропадает и не умножается,
  /// ровно как обещает диалог подтверждения в настройках.
  ///
  /// Список копируется: [ledger] отдаёт неизменяемое представление, а новой
  /// игре нужен список, в который она сможет дописывать.
  Game withContent(GameContent next) => Game(
        content: next,
        profile: _profile,
        ledger: List<LedgerEntry>.of(_ledger),
      );

  GameSnapshot get snapshot => LedgerFold.fold(
        _ledger,
        startMeters: content.economy.startMeters,
        carePoints: _profile.carePoints,
      );

  int get periodNo => snapshot.periodNo;

  Goal? get goal => content.goal(_profile.goalId);

  // ───────────────────── доверие и подработка ─────────────────────
  //
  // 🔴 Решение команды 19.09 («вариант 4»). До него задание платило при
  // каждом прохождении, то есть любое задание можно было фармить бесконечно,
  // и §2.1 «за один игровой период нельзя купить всё сразу» держался только
  // на том, что ребёнку лень. Теперь у недели есть потолок: бюджет от
  // родителей плюс ограниченная подработка.

  /// Уровень доверия на текущей стадии Финни.
  TrustLevel get trust => content.economy.trustFor(snapshot.stage);

  /// Сколько на этой неделе дают родители.
  int get trustBudget => trust.fromParents;

  /// Сколько взрослый открыл дополнительных подработок на этой неделе.
  int get _parentUnlocksThisPeriod => _ledger
      .where((LedgerEntry e) =>
          e.periodNo == periodNo && e.kind == LedgerKind.parentUnlockedTask)
      .length;

  /// Лимит подработки на этой неделе: по стадии плюс то, что открыл взрослый.
  int get earnCap =>
      trust.earnCap +
      _parentUnlocksThisPeriod * content.economy.parentBonusCap;

  /// Сколько уже заработано заданиями на этой неделе.
  int get earnedThisPeriod => _ledger
      .where((LedgerEntry e) =>
          e.periodNo == periodNo && e.kind == LedgerKind.taskReward)
      .fold<int>(0, (int a, LedgerEntry e) => a + e.unallocated);

  /// Сколько ещё можно заработать на этой неделе.
  int get earnLeft => (earnCap - earnedThisPeriod).clamp(0, earnCap);

  bool get earnCapReached => earnLeft == 0;

  /// Пришли ли карманные за текущую игровую неделю.
  bool get pocketMoneyReceived => _ledger.any((LedgerEntry e) =>
      e.periodNo == periodNo && e.kind == LedgerKind.pocketMoney);

  /// Что сейчас делать: планировать неделю, жить внутри неё или закрывать.
  ///
  /// 🔴 Фаза выводится из факта начисления карманных, а не из остатка в
  /// кошельке. Раньше условием было `unallocated > 0`, и монетки за задание,
  /// выполненное до начала недели, сами переводили игру в планирование:
  /// ребёнок раскладывал их по конвертам, фаза становилась `living`, и
  /// `startPeriod()` за эту неделю не вызывался уже никогда — карманные
  /// пропадали навсегда (§2.5.4.2, §3.4.6 «без потери прогресса»).
  PeriodPhase get phase {
    if (_profile.plans.containsKey(periodNo)) {
      return PeriodPhase.living;
    }
    return pocketMoneyReceived ? PeriodPhase.planning : PeriodPhase.closing;
  }

  Allocation? get currentPlan => _profile.plans[periodNo];

  /// История взносов по неделям — для расчёта срока до цели (§2.5.7.4).
  List<int> get depositHistory {
    final Map<int, int> byPeriod = <int, int>{};
    for (final LedgerEntry e in _ledger) {
      if (e.savings != 0) {
        byPeriod[e.periodNo] = (byPeriod[e.periodNo] ?? 0) + e.savings;
      }
    }
    final List<int> periods = byPeriod.keys.toList()..sort();
    return periods.map((int p) => byPeriod[p]!).toList();
  }

  GoalForecast? get forecast {
    final Goal? g = goal;
    if (g == null) return null;
    return SavingsRules.forecast(
      goal: g,
      savings: snapshot.wallet.savings,
      depositHistory: depositHistory,
    );
  }

  // ───────────────────────────── действия ─────────────────────────────

  void _add(LedgerEntry Function(String id) build) {
    _seq++;
    _ledger.add(build('e$_seq'));
  }

  /// Начало игровой недели: приходят карманные (§2.5.4.2).
  ///
  /// 🔴 Никакой привязки к календарю. Термины ТЗ разрешают: «продолжительность,
  /// способ завершения и возможную привязку к реальному времени команда
  /// определяет самостоятельно». Пока ребёнка нет, не происходит ничего —
  /// это же снимает главный этический риск питомцевых игр.
  ActionResult startPeriod() {
    // 🔴 Карманные за неделю приходят ровно один раз. Без этой защиты
    // повторное касание кнопки удваивает доход.
    if (pocketMoneyReceived) {
      return const ActionResult(
        title: 'Неделя уже началась',
        text: 'Карманные за эту неделю уже пришли.',
        nextStep: 'Разложи монетки по трём конвертам',
      );
    }
    final int amount = trustBudget;
    final int cap = earnCap;
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.pocketMoney,
          reasonCode: 'income.pocket',
          unallocated: amount,
          args: <String, Object?>{'amount': amount, 'cap': cap},
        ));
    return ActionResult(
      title: 'Бюджет на неделю',
      text: content.say(
          'income.pocket', <String, Object?>{'amount': amount, 'cap': cap}),
      nextStep: 'Разложи монетки по трём конвертам',
    );
  }

  /// Подтверждение плана (§2.5.5.3). После него план сравнивается с фактом.
  ActionResult confirmPlan(Allocation plan) {
    final int available = snapshot.wallet.unallocated;
    // 🔴 Проверять одну лишь сумму недостаточно. План «нужное 10, хочу −3,
    // копилка 5» даёт total = 12 и проходил проверку, уводя конверт «Хочу»
    // в минус — §2.5.6.4 запрещает отрицательный баланс при любом вводе.
    // Со степперов такой план не приходит, но инвариант держит домен,
    // а не экран.
    if (plan.needs < 0 || plan.wants < 0 || plan.savings < 0) {
      return const ActionResult(
        title: 'В конверте не может быть меньше нуля',
        text: 'Монеток в конверте не бывает меньше, чем нисколько.',
        nextStep: 'Разложи заново',
      );
    }
    if (plan.total > available) {
      return ActionResult(
        title: 'Монеток столько нет',
        text: 'В плане ${plan.total}, а есть только $available.',
        nextStep: 'Убери лишнее из любого конверта',
      );
    }
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.planConfirmed,
          reasonCode: 'plan.confirmed',
          unallocated: -plan.total,
          args: <String, Object?>{
            'needs': plan.needs,
            'wants': plan.wants,
            'savings': plan.savings,
          },
        ));
    for (final Envelope e in <Envelope>[Envelope.needs, Envelope.wants]) {
      final int v = plan.byEnvelope(e);
      if (v == 0) continue;
      _add((String id) => LedgerEntry(
            id: id,
            periodNo: periodNo,
            kind: LedgerKind.planConfirmed,
            // 🔴 Свой ключ, а не чужой. Раньше здесь переиспользовался
            // 'plan.confirmed' с пустыми подстановками, и в истории недели
            // ребёнок видел сырой шаблон «{needs} {wants} {savings}».
            reasonCode: 'plan.envelope',
            envelope: e,
            coins: v,
            args: <String, Object?>{'envelope': e.title, 'amount': v},
          ));
    }
    if (plan.savings > 0) {
      _add((String id) => LedgerEntry(
            id: id,
            periodNo: periodNo,
            kind: LedgerKind.savingsDeposit,
            reasonCode: 'savings.deposit',
            savings: plan.savings,
            args: <String, Object?>{
              'amount': plan.savings,
              'remaining': (goal?.price ?? 0) -
                  (snapshot.wallet.savings + plan.savings),
            },
          ));
    }
    _profile = _profile.copyWith(
      plans: <int, Allocation>{..._profile.plans, periodNo: plan},
      unlockedTerms: <String>{..._profile.unlockedTerms, 'budget'},
    );
    return ActionResult(
      title: 'План на неделю готов',
      text: content.say('plan.confirmed', <String, Object?>{
        'needs': plan.needs,
        'wants': plan.wants,
        'savings': plan.savings,
      }),
      nextStep: 'Теперь можно покупать',
    );
  }

  /// Положить нераспределённые монетки в конверт.
  ///
  /// Через это проходит каждая монетка, пришедшая после подтверждения плана:
  /// заработанное за задание тоже требует решения, куда его деть. Иначе
  /// «заработал» незаметно превращается в «потратил на себя».
  ActionResult allocate(Envelope to, int amount) {
    final int free = snapshot.wallet.unallocated;
    if (amount <= 0 || amount > free) {
      return ActionResult(
        title: 'Столько положить нельзя',
        text: 'Нераспределённых монеток: $free.',
      );
    }
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: to == Envelope.savings
              ? LedgerKind.savingsDeposit
              : LedgerKind.envelopeMove,
          reasonCode:
              to == Envelope.savings ? 'savings.deposit' : 'envelope.move',
          envelope: to == Envelope.savings ? null : to,
          coins: to == Envelope.savings ? 0 : amount,
          savings: to == Envelope.savings ? amount : 0,
          unallocated: -amount,
          args: <String, Object?>{
            'amount': amount,
            'from': 'Новые монетки',
            'to': to.title,
            'remaining': (goal?.price ?? 0) - (snapshot.wallet.savings + amount),
          },
        ));
    return ActionResult(
      title: 'Разложено',
      text: '$amount монеток отправились в «${to.title}».',
    );
  }

  PurchaseDecision canBuy(CatalogItem item) => PurchaseRules.check(
        item: item,
        wallet: snapshot.wallet,
        meters: snapshot.meters,
        hasAvailableTask: availableTasks.isNotEmpty,
      );

  /// Покупка (§2.5.6.3): требует подтверждения, уменьшает баланс,
  /// сохраняется в истории недели.
  ActionResult buy(CatalogItem item) {
    final PurchaseDecision d = canBuy(item);
    if (!d.allowed) return declinePurchase(item, d);

    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.purchase,
          reasonCode: 'purchase.done',
          envelope: item.envelope,
          coins: -item.price,
          meters: item.effect,
          args: <String, Object?>{
            'item': item.title,
            'itemId': item.id,
            'price': item.price,
            'envelope': item.envelope.title,
          },
        ));
    if (item.accessory != null) {
      _profile = _profile.copyWith(
        accessories: <String>{..._profile.accessories, item.accessory!},
      );
    }
    if (item.id == 'book') {
      _profile = _profile.copyWith(
        unlockedTerms: <String>{..._profile.unlockedTerms, 'change'},
      );
    }
    return ActionResult(
      title: 'Куплено: ${item.title}',
      text: content.say('purchase.done', <String, Object?>{
        'item': item.title,
        'price': item.price,
        'envelope': item.envelope.title,
      }),
      nextStep: item.hint,
    );
  }

  /// Отказ по нехватке монеток (§2.5.6.4). Запись в журнал нужна, чтобы шаг 7
  /// Приложения А засчитывался сам, и чтобы ребёнок видел в истории попытку.
  ActionResult declinePurchase(CatalogItem item, [PurchaseDecision? known]) {
    final PurchaseDecision d = known ?? canBuy(item);
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.purchaseDeclined,
          reasonCode: 'purchase.declined',
          envelope: item.envelope,
          args: <String, Object?>{
            'item': item.title,
            'shortfall': d.shortfall,
            'envelope': item.envelope.title,
          },
        ));
    return ActionResult(
      title: 'Не хватает ${d.shortfall}',
      text: content.say('purchase.declined', <String, Object?>{
        'item': item.title,
        'shortfall': d.shortfall,
        'envelope': item.envelope.title,
      }),
      nextStep: 'Можно переложить монетки, заработать или подождать неделю',
    );
  }

  /// Перекладывание между конвертами — то самое действие, которое создаёт
  /// расхождение плана и факта, и единственное, кроме непредвиденного расхода.
  ActionResult move({
    required Envelope from,
    required Envelope to,
    required int amount,
  }) {
    final Wallet w = snapshot.wallet;
    final int source =
        from == Envelope.savings ? w.savings : w.envelopes.byEnvelope(from);
    if (amount <= 0 || source < amount) {
      return const ActionResult(
        title: 'Столько переложить нельзя',
        text: 'В этом конверте меньше монеток.',
      );
    }
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: from == Envelope.savings
              ? LedgerKind.savingsWithdraw
              : LedgerKind.envelopeMove,
          reasonCode: from == Envelope.savings
              ? 'savings.withdraw'
              : 'envelope.move',
          envelope: from == Envelope.savings ? null : from,
          coins: from == Envelope.savings ? 0 : -amount,
          savings: from == Envelope.savings ? -amount : 0,
          args: <String, Object?>{
            'amount': amount,
            'from': from.title,
            'to': to.title,
            'remaining': w.savings - amount,
          },
        ));
    if (to != Envelope.savings) {
      _add((String id) => LedgerEntry(
            id: id,
            periodNo: periodNo,
            kind: LedgerKind.envelopeMove,
            reasonCode: 'envelope.move',
            envelope: to,
            coins: amount,
            args: <String, Object?>{
              'amount': amount,
              'from': from.title,
              'to': to.title,
            },
          ));
    } else {
      _add((String id) => LedgerEntry(
            id: id,
            periodNo: periodNo,
            kind: LedgerKind.savingsDeposit,
            reasonCode: 'savings.deposit',
            savings: amount,
            args: <String, Object?>{
              'amount': amount,
              'remaining': (goal?.price ?? 0) - (w.savings + amount),
            },
          ));
    }
    return ActionResult(
      title: 'Переложено',
      text: content.say('envelope.move', <String, Object?>{
        'amount': amount,
        'from': from.title,
        'to': to.title,
      }),
    );
  }

  // ───────────────────────── список ожидания ─────────────────────────
  //
  // 🔴 Главная педагогическая ставка продукта и единственная механика,
  // которой нет в ТЗ. Причина: «подождать» у нас предлагалось только когда
  // монеток НЕ ХВАТИЛО, то есть ожидание было следствием нехватки. Вся
  // практика семейного финансового воспитания — про обратное: про паузу
  // тогда, когда денег хватает. Именно в этой паузе выясняется, чего
  // ребёнок хотел на самом деле.
  //
  // Ожидание здесь — предложение, а не запрет: купить сейчас можно всегда.
  // Принудительная пауза превратила бы приём в наказание, а данные о
  // принуждённом «правильном» поведении говорят, что оно даёт обратный
  // эффект (Warneken & Tomasello, 2008; Weinstein & Ryan).

  /// Можно ли предложить подождать: вещь необязательная, дорогая по меркам
  /// недельного дохода и ещё не в списке.
  bool canWait(CatalogItem item) =>
      !item.isNeed &&
      item.price >= content.economy.wishThreshold &&
      !_profile.wishList.containsKey(item.id);

  /// Вещи из списка, отложенные на прошлых неделях, — про них пора спросить.
  /// Отложенное на этой же неделе не «созрело»: пауза должна быть паузой.
  List<CatalogItem> get ripeWishes => _profile.wishList.entries
      .where((MapEntry<String, int> e) => e.value < periodNo)
      .map((MapEntry<String, int> e) => content.item(e.key))
      .toList();

  /// Вещи, отложенные прямо сейчас, — их ещё рано спрашивать.
  List<CatalogItem> get freshWishes => _profile.wishList.entries
      .where((MapEntry<String, int> e) => e.value >= periodNo)
      .map((MapEntry<String, int> e) => content.item(e.key))
      .toList();

  ActionResult addToWishList(CatalogItem item) {
    _profile = _profile.copyWith(
      wishList: <String, int>{..._profile.wishList, item.id: periodNo},
      // Термин открывается ровно в тот момент, когда ребёнок впервые им
      // воспользовался (§2.5.11.2): словарь идёт за игрой, а не впереди неё.
      unlockedTerms: <String>{..._profile.unlockedTerms, 'wishlist'},
    );
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.wishAdded,
          reasonCode: 'wish.added',
          args: <String, Object?>{'item': item.title},
        ));
    return ActionResult(
      title: 'Подождём до следующей недели',
      text: content.say('wish.added', <String, Object?>{'item': item.title}),
      nextStep: 'На следующей неделе спрошу, хочешь ли ты это до сих пор',
    );
  }

  /// Ребёнок дождался и подтвердил желание. Монетки не тратятся: вещь просто
  /// уходит из списка, и купить её можно как обычно.
  ActionResult keepWish(CatalogItem item) {
    final Map<String, int> next = Map<String, int>.of(_profile.wishList)
      ..remove(item.id);
    _profile = _profile.copyWith(
      wishList: next,
      wishKept: _profile.wishKept + 1,
    );
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.wishKept,
          reasonCode: 'wish.kept',
          args: <String, Object?>{'item': item.title},
        ));
    return ActionResult(
      title: 'Значит, правда хочется',
      text: content.say('wish.kept', <String, Object?>{'item': item.title}),
      nextStep: 'Теперь можно купить',
    );
  }

  /// Ребёнок дождался и передумал. 🔴 Это не проигрыш и нигде не должно
  /// выглядеть проигрышем: передумать — тоже решение, и притом бесплатное.
  ActionResult dropWish(CatalogItem item) {
    final Map<String, int> next = Map<String, int>.of(_profile.wishList)
      ..remove(item.id);
    _profile = _profile.copyWith(
      wishList: next,
      wishDropped: _profile.wishDropped + 1,
    );
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.wishDropped,
          reasonCode: 'wish.dropped',
          args: <String, Object?>{'item': item.title},
        ));
    return ActionResult(
      title: 'Расхотелось — и хорошо',
      text: content.say('wish.dropped', <String, Object?>{'item': item.title}),
      nextStep: 'Монетки остались у тебя',
    );
  }

  /// Сколько раз ребёнок дождался и сколько раз передумал.
  (int kept, int dropped) get wishTally =>
      (_profile.wishKept, _profile.wishDropped);

  static const ActionResult _noUnexpected = ActionResult(
    title: 'Решать нечего',
    text: 'Непредвиденной траты сейчас нет или она уже решена.',
    nextStep: 'Можно заниматься своими делами',
  );

  /// Непредвиденное событие этой недели — решённое или нет.
  UnexpectedEvent? get unexpectedThisWeek =>
      content.economy.unexpectedFor(periodNo);

  /// Непредвиденный расход этой недели, если он ещё не решён (§2, исключение).
  bool get unexpectedPending =>
      unexpectedThisWeek != null &&
      !_profile.unexpectedResolvedPeriods.contains(periodNo) &&
      _profile.plans.containsKey(periodNo);

  ActionResult payUnexpected(Envelope from) {
    // Оплатить или перенести можно только событие, которое ждёт решения:
    // иначе второе нажатие списало бы трату дважды, а на неделе без события
    // — списало бы трату, которой не было.
    if (!unexpectedPending) return _noUnexpected;
    final UnexpectedEvent event = unexpectedThisWeek!;
    final int cost = event.cost;
    final Wallet w = snapshot.wallet;
    final int source =
        from == Envelope.savings ? w.savings : w.envelopes.byEnvelope(from);
    if (source < cost) {
      return ActionResult(
        title: 'Здесь не хватит',
        text: 'В «${from.title}» только $source из $cost монеток.',
        nextStep: 'Возьми из другого конверта или перенеси на следующую неделю',
      );
    }
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.unexpectedCost,
          reasonCode: 'unexpected.paid',
          envelope: from == Envelope.savings ? null : from,
          coins: from == Envelope.savings ? 0 : -cost,
          savings: from == Envelope.savings ? -cost : 0,
          args: <String, Object?>{'amount': cost, 'eventId': event.id},
        ));
    _profile = _profile.copyWith(
      unexpectedResolvedPeriods: <int>{
        ..._profile.unexpectedResolvedPeriods,
        periodNo
      },
      unlockedTerms: <String>{
        ..._profile.unlockedTerms,
        'unexpected',
        'cushion'
      },
    );
    return ActionResult(
      title: event.paidTitle,
      text: '${event.paid}. '
          '${content.say('unexpected.paid', <String, Object?>{'amount': cost})}',
      nextStep: 'Такие траты случаются у всех — поэтому монетки держат про запас',
    );
  }

  /// Четвёртый выход: не платить. Без него это не выбор, а налог
  /// с тремя способами инкассации.
  ActionResult deferUnexpected() {
    // Оплатить или перенести можно только событие, которое ждёт решения:
    // иначе второе нажатие списало бы трату дважды, а на неделе без события
    // — списало бы трату, которой не было.
    if (!unexpectedPending) return _noUnexpected;
    final UnexpectedEvent event = unexpectedThisWeek!;
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.unexpectedDeferred,
          reasonCode: 'unexpected.deferred',
          meters: const PetMeters(fullness: 0, cleanliness: 0, mood: -1),
          args: <String, Object?>{'eventId': event.id},
        ));
    _profile = _profile.copyWith(
      unexpectedResolvedPeriods: <int>{
        ..._profile.unexpectedResolvedPeriods,
        periodNo
      },
      unlockedTerms: <String>{
        ..._profile.unlockedTerms,
        'unexpected',
        'cushion'
      },
    );
    return ActionResult(
      title: 'Перенесли на следующую неделю',
      text: '${event.deferred} ${content.say('unexpected.deferred')}',
      nextStep: 'Финни немного поскучает, но ничего страшного не случится',
    );
  }

  /// Доступные сейчас задания (§2.5.8.5 — в демо-режиме доступны все сразу).
  List<GameTask> get availableTasks {
    if (_profile.isDemo) {
      return <GameTask>[
        for (final GameTask t in content.tasks) t.forWeek(periodNo)
      ];
    }
    final Set<String> doneThisPeriod = _ledger
        .where((LedgerEntry e) =>
            e.periodNo == periodNo && e.kind == LedgerKind.taskReward)
        .map((LedgerEntry e) => e.args['taskId']! as String)
        .toSet();
    return content.tasks
        .where((GameTask t) => !doneThisPeriod.contains(t.id))
        .map((GameTask t) => t.forWeek(periodNo))
        .toList();
  }

  ActionResult completeTask(GameTask task, {required bool best}) {
    // 🔴 Платится не больше остатка недельного лимита. Задание при этом
    // засчитывается всегда: запись о нём попадает в журнал даже с нулём
    // монеток. Учёба не должна зависеть от того, осталась ли подработка, —
    // иначе ребёнок, у которого лимит кончился, перестал бы заниматься.
    final int cap = earnCap;
    final int pay = task.reward < earnLeft ? task.reward : earnLeft;
    final String reason = pay == task.reward
        ? 'income.task'
        : (pay > 0 ? 'earn.partial' : 'earn.capReached');
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.taskReward,
          reasonCode: reason,
          unallocated: pay,
          args: <String, Object?>{
            'task': task.title,
            'taskId': task.id,
            'amount': pay,
            'cap': cap,
          },
        ));
    _profile = _profile.copyWith(
      completedTaskIds: <String>[..._profile.completedTaskIds, task.id],
      unlockedTerms: <String>{
        ..._profile.unlockedTerms,
        if (task.id == 'c1_change') 'change',
        if (task.topic == TaskTopic.savings) 'goal',
      },
    );
    final String explain =
        best ? '${task.explainAny} ${task.explainBest}' : task.explainAny;
    return ActionResult(
      title: pay > 0 ? 'Задание выполнено: +$pay' : 'Задание выполнено',
      // §2.5.8.3: объяснение выдаётся при любом исходе, а не только при верном.
      text: pay == task.reward
          ? explain
          : '$explain ${content.say(reason, <String, Object?>{'task': task.title, 'amount': pay, 'cap': cap})}',
      nextStep: pay > 0
          ? 'Положи монетки в один из конвертов'
          : 'Монетки за задания снова пойдут со следующей недели',
    );
  }

  /// Взрослый открывает дополнительное задание (§2.5.12).
  ActionResult parentUnlockTask() {
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.parentUnlockedTask,
          reasonCode: 'parent.unlockedTask',
          args: <String, Object?>{'bonus': content.economy.parentBonusCap},
        ));
    _profile = _profile.copyWith(
        parentUnlockedTasks: _profile.parentUnlockedTasks + 1);
    return ActionResult(
      title: 'Открыта дополнительная подработка',
      text: content.say('parent.unlockedTask',
          <String, Object?>{'bonus': content.economy.parentBonusCap}),
    );
  }

  void chooseGoal(String goalId) {
    _profile = _profile.copyWith(
      goalId: goalId,
      unlockedTerms: <String>{..._profile.unlockedTerms, 'goal'},
    );
  }

  /// Что стоит в комнате Финни: вещи, которые остаются после покупки,
  /// с числом экземпляров. В порядке первой покупки.
  ///
  /// 🔴 Комната нигде не хранится — она выводится из журнала покупок, как
  /// баланс. Хранить её отдельно значило бы завести второй источник правды:
  /// рано или поздно в комнате оказалась бы вещь, за которую ни разу не
  /// платили, или купленная вещь не оказалась бы.
  List<(CatalogItem item, int count)> get keepsakes {
    final Map<String, int> counts = <String, int>{};
    for (final LedgerEntry e in _ledger) {
      if (e.kind != LedgerKind.purchase) continue;
      final String? id = e.args['itemId'] as String?;
      if (id == null) continue;
      final CatalogItem? item = content.itemOrNull(id);
      if (item == null || !item.keeps) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return <(CatalogItem, int)>[
      for (final MapEntry<String, int> e in counts.entries)
        (content.item(e.key), e.value),
    ];
  }

  /// Набрана ли выбранная мечта целиком.
  bool get goalReached {
    final Goal? g = goal;
    return g != null && snapshot.wallet.savings >= g.price;
  }

  /// Исполнить мечту: из копилки уходит её цена, мечта остаётся в мире
  /// Финни, и можно выбрать следующую.
  ///
  /// 🔴 Центральная петля из анализа игровых референсов команды: накопил →
  /// вещь появляется в мире → новое желание. До 23.09 при 100 % не
  /// происходило ничего: копилка просто продолжала расти, а если выбрать
  /// следующую цель, набранная мечта исчезала бесследно. Ребёнок копил
  /// на число, а не на изменение своего мира.
  ActionResult fulfillGoal() {
    final Goal? g = goal;
    if (g == null) {
      return const ActionResult(
        title: 'Мечта не выбрана',
        text: 'Сначала выбери, на что копить.',
        nextStep: 'Открой копилку и выбери мечту',
      );
    }
    final int have = snapshot.wallet.savings;
    if (have < g.price) {
      return ActionResult(
        title: 'Ещё не хватает',
        text: 'Для «${g.title}» нужно ${g.price}, в копилке $have.',
        nextStep: 'Продолжай откладывать',
      );
    }
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: periodNo,
          kind: LedgerKind.goalFulfilled,
          reasonCode: 'goal.fulfilled',
          savings: -g.price,
          args: <String, Object?>{
            'goal': g.title,
            'goalId': g.id,
            'price': g.price,
            'left': have - g.price,
          },
        ));
    _profile = _profile.copyWith(goalId: null);
    return ActionResult(
      title: 'Мечта исполнена!',
      text: content.say('goal.fulfilled', <String, Object?>{
        'goal': g.title,
        'price': g.price,
        'left': have - g.price,
      }),
      nextStep: 'Выбери следующую мечту',
    );
  }

  /// Исполненные мечты — в порядке исполнения. Выводятся из журнала:
  /// в мире Финни не может оказаться мечта, за которую не заплатили.
  List<Goal> get fulfilledGoals => <Goal>[
        for (final LedgerEntry e in _ledger)
          if (e.kind == LedgerKind.goalFulfilled)
            if (_goalById(e.args['goalId'] as String?) case final Goal g) g,
      ];

  Goal? _goalById(String? id) {
    if (id == null) return null;
    if (CustomGoals.isCustom(id)) return CustomGoals.decode(content, id);
    return content.goal(id);
  }

  /// Покупал ли ребёнок что-нибудь из «Нужного» до конца недели [n].
  bool _boughtNeedsUpTo(int n) => _ledger.any((LedgerEntry e) =>
      e.periodNo <= n &&
      e.kind == LedgerKind.purchase &&
      e.envelope == Envelope.needs);

  /// Итоги уже закрытой недели, пересчитанные из журнала.
  ///
  /// 🔴 Итог недели нигде не хранится — он вычисляется. Раньше он жил полем
  /// в памяти приложения, и после перезапуска блок «Итоги недели» с очками
  /// заботы и разбором плана исчезал, хотя §2.5.11.1 требует показывать
  /// итоги последнего периода. Хранить его было бы вторым источником правды
  /// рядом с журналом — ровно тем, против чего построена вся архитектура.
  PeriodOutcome? outcomeOfPeriod(int n) {
    final bool closed = _ledger.any((LedgerEntry e) =>
        e.periodNo == n && e.kind == LedgerKind.periodClosed);
    if (!closed) return null;

    // Показатели берутся такими, какими были в момент закрытия: затухание
    // записано уже следующей неделей, поэтому достаточно отсечь её.
    final List<LedgerEntry> upToClose =
        _ledger.where((LedgerEntry e) => e.periodNo <= n).toList();

    return PeriodRules.close(
      config: content.economy,
      plan: _profile.plans[n] ?? const Allocation(),
      fact: LedgerFold.factOfPeriod(_ledger, n),
      metersAtClose: LedgerFold.fold(
        upToClose,
        startMeters: content.economy.startMeters,
      ).meters,
      tasksCompleted: _ledger
          .where((LedgerEntry e) =>
              e.periodNo == n && e.kind == LedgerKind.taskReward)
          .length,
      depositedThisPeriod: _ledger
          .where((LedgerEntry e) => e.periodNo == n)
          .fold<int>(
              0, (int a, LedgerEntry e) => a + (e.savings > 0 ? e.savings : 0)),
      boughtNeedsSoFar: _boughtNeedsUpTo(n),
    );
  }

  /// Закрытие игровой недели (§2.5.5.3, §2.5.10).
  PeriodOutcome closePeriod() {
    final Allocation plan = _profile.plans[periodNo] ?? const Allocation();
    final Allocation fact = LedgerFold.factOfPeriod(_ledger, periodNo);
    final int tasksDone = _ledger
        .where((LedgerEntry e) =>
            e.periodNo == periodNo && e.kind == LedgerKind.taskReward)
        .length;
    final int deposited = _ledger
        .where((LedgerEntry e) => e.periodNo == periodNo)
        .fold<int>(0, (int a, LedgerEntry e) => a + (e.savings > 0 ? e.savings : 0));

    final PeriodOutcome outcome = PeriodRules.close(
      config: content.economy,
      plan: plan,
      fact: fact,
      metersAtClose: snapshot.meters,
      tasksCompleted: tasksDone,
      depositedThisPeriod: deposited,
      boughtNeedsSoFar: _boughtNeedsUpTo(periodNo),
    );

    final int closing = periodNo;
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: closing,
          kind: LedgerKind.periodClosed,
          reasonCode: 'period.closed',
          args: <String, Object?>{
            'periodNo': closing,
            'points': outcome.points,
          },
        ));
    _add((String id) => LedgerEntry(
          id: id,
          periodNo: closing + 1,
          kind: LedgerKind.weeklyDecay,
          reasonCode: 'period.decay',
          meters: outcome.metersDelta,
          args: const <String, Object?>{},
        ));

    _profile = _profile.copyWith(
      carePoints: _profile.carePoints + outcome.points,
      unlockedTerms: <String>{..._profile.unlockedTerms, 'planfact'},
    );
    return outcome;
  }

  /// Сброс тестового профиля к исходному состоянию (§2.5.13).
  void resetDemo() {
    _ledger.clear();
    _seq = 0;
    _profile = GameProfile.fresh(isDemo: true);
  }

  void updateProfile(GameProfile p) => _profile = p;

  Map<String, Object?> toJson() => <String, Object?>{
        'profile': _profile.toJson(),
        'ledger': _ledger.map((LedgerEntry e) => e.toJson()).toList(),
      };

  static Game fromJson(Map<String, Object?> json, GameContent content) => Game(
        content: content,
        profile: GameProfile.fromJson(
            (json['profile']! as Map<Object?, Object?>).cast<String, Object?>()),
        ledger: (json['ledger']! as List<Object?>)
            .map((Object? e) => LedgerEntry.fromJson(
                (e! as Map<Object?, Object?>).cast<String, Object?>()))
            .toList(),
      );
}
