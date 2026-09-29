import 'dart:math' as math;

import '../ledger/ledger_entry.dart' show LedgerKind;
import 'contract.dart';
import 'world_entry.dart';

/// Учёт одной недели для [WeekPlanFact]: общий у свёртки журнала
/// ([foldWeekHistory]) и у `FakeWorld`, чтобы оба мира считали план и факт
/// одинаково.
class WeekTally {
  WeekTally(this.weekNo);

  final int weekNo;
  bool planMade = false;
  bool billsPaid = false;
  int planNeed = 0;
  int planWant = 0;
  int planGoal = 0;

  /// Счета недели целиком (свои, из копилки и помощь семьи).
  int bills = 0;

  /// Еда недели: приёмы посреди недели и домашние в счёте (часть [bills]).
  int food = 0;

  /// Из [food] — на «вкусное без пользы» (`food.options[].treat`).
  int treats = 0;

  /// Потрачено на ХОЧУ: покупки, досуг, траты событий.
  int wantSpent = 0;

  /// Чистое отложенное: взносы в ЦЕЛЬ минус снятое.
  int saved = 0;

  final List<WeekItem> shifts = <WeekItem>[];
  final List<WeekItem> purchases = <WeekItem>[];
  final List<String> events = <String>[];
  final List<String> goalsReached = <String>[];
  String? goalTitle;
  int? goalPrice;
  int savedAtEnd = 0;

  /// Взрослый открыл дополнительную смену (запись `parentBonus`).
  bool parentBonus = false;

  WeekPlanFact build() => WeekPlanFact(
        weekNo: weekNo,
        planMade: planMade,
        billsPaid: billsPaid,
        need: EnvelopePlanFact(planned: planNeed, actual: bills),
        want: EnvelopePlanFact(planned: planWant, actual: wantSpent),
        goal: EnvelopePlanFact(planned: planGoal, actual: saved),
        shifts: List<WeekItem>.unmodifiable(shifts),
        purchases: List<WeekItem>.unmodifiable(purchases),
        events: List<String>.unmodifiable(events),
        goalsReached: List<String>.unmodifiable(goalsReached),
        goalTitle: goalTitle,
        goalPrice: goalPrice,
        savedAtEnd: savedAtEnd,
        parentBonus: parentBonus,
        food: food,
        treats: treats,
      );
}

/// Названия и цены для истории — у каждого мира свои справочники.
typedef WeekHistoryNames = ({
  String Function(String itemId) item,
  int Function(String itemId) price,
  String Function(String jobId, String? variant) job,
  String Function(String kind) leisure,
  String Function(String eventId) event,
  bool Function(String foodId) treat,
});

/// История недель, свёрнутая из журнала. Записи группируются по
/// [WorldEntry.weekNo]: итоги (`periodClosed`, `stageChanged`) пишутся после
/// счетов, но с номером своей недели.
///
/// Траты считаются **по виду записи**, а не по изменению конвертов: счета
/// списываются НУЖНО → заработок → ХОЧУ, и «ХОЧУ убыло» не значит «на ХОЧУ
/// потрачено».
List<WeekPlanFact> foldWeekHistory(
    Iterable<WorldEntry> journal, WeekHistoryNames names) {
  final List<WeekTally> weeks = <WeekTally>[];
  int goalBalance = 0;
  String? activeGoal;
  for (final WorldEntry e in journal) {
    goalBalance += e.goal;
    final Enum k = e.kind;
    final Map<String, Object?> a = e.args;
    final bool goalBuy = k == WorldLedgerKind.petBought ||
        k == WorldLedgerKind.transportBought ||
        k == WorldLedgerKind.homeBought;
    if (k == WorldChoiceKind.goalChosen) activeGoal = a['goalId']! as String;
    if (goalBuy && a['itemId'] == activeGoal) activeGoal = null;
    if (e.weekNo < 1) continue;
    if (weeks.isEmpty || weeks.last.weekNo != e.weekNo) {
      weeks.add(WeekTally(e.weekNo));
    }
    final WeekTally t = weeks.last;
    // Потрачено из карманов (ХОЧУ и заработок) этой записью.
    final int out = -(e.want + e.free);
    if (k == LedgerKind.planConfirmed) {
      t.planMade = true;
      t.planNeed = e.need;
      t.planWant = e.want;
      t.planGoal = e.goal;
      t.saved += e.goal;
    } else if (k == WorldLedgerKind.billPaid) {
      final int amount = a['amount'] as int? ?? 0;
      t.bills += amount;
      final Object? foodId = a['foodId'];
      if (a['bill'] == 'food') {
        t.food += amount;
        // Сохранения до приёмов пищи (без `meals`): «вкусная еда на неделю»
        // была уровнем, а не выбором вкусного без пользы — долю не считаем.
        if (foodId is String && a['meals'] != null && names.treat(foodId)) {
          t.treats += amount;
        }
      }
    } else if (k == WorldLedgerKind.lessonChoice) {
      // Урок виден в истории недели (критерии §4 п. 7).
      t.events.add('Урок: ${a['title'] ?? a['jobId']}');
      t.saved += e.goal;
      t.wantSpent += -(e.free < 0 ? e.free : 0) - (e.want < 0 ? e.want : 0);
    } else if (k == WorldLedgerKind.mealEaten) {
      // Еда посреди недели — обязательная трата: факт НУЖНО, как счёт.
      final int price = a['price'] as int? ?? 0;
      t.bills += price;
      t.food += price;
      final Object? foodId = a['foodId'];
      if (foodId is String && names.treat(foodId)) t.treats += price;
    } else if (k == LedgerKind.periodClosed) {
      t.billsPaid = true;
    } else if (k == LedgerKind.purchase || k == WorldLedgerKind.itemOwned) {
      t.wantSpent += out;
      final String id = a['itemId']! as String;
      t.purchases.add(WeekItem(
          id: id, title: names.item(id), amount: a['price'] as int? ?? out));
    } else if (k == WorldLedgerKind.leisure) {
      t.wantSpent += out;
      t.saved += e.goal; // досуг из копилки — снятое из ЦЕЛИ
      final String kind = a['kind']! as String;
      final int price = a['price'] as int? ?? 0;
      if (price > 0) {
        t.purchases
            .add(WeekItem(id: kind, title: names.leisure(kind), amount: price));
      }
    } else if (k == WorldLedgerKind.eventChoice) {
      // Траты из ХОЧУ и заработка = ушло из них + доход события − перенос
      // в копилку из них. В копилку идут подарок (доход), неразложенные
      // карманные (повтор «Копилки» в начале недели) и карманы. Неразложенные,
      // потраченные повтором до плана, — не из ХОЧУ: их нет ни в одной части.
      final int income = a['income'] as int? ?? 0;
      final int toGoal = math.max<int>(0, e.goal);
      final int fromUnallocToGoal =
          math.min(-e.unallocated, math.max<int>(0, toGoal - income));
      t.wantSpent +=
          math.max<int>(0, out + income - toGoal + fromUnallocToGoal);
      t.saved += e.goal;
      if (e.reasonCode != 'event.recurring') {
        t.events.add(names.event(a['eventId']! as String));
      }
    } else if (k == WorldLedgerKind.parentBonus) {
      t.parentBonus = true;
    } else if (k == WorldLedgerKind.goalSliderDeposit ||
        k == LedgerKind.savingsWithdraw) {
      t.saved += e.goal;
    } else if (k == WorldLedgerKind.jobPayout) {
      final String job = a['jobId']! as String;
      t.shifts.add(WeekItem(
          id: job,
          title: names.job(job, a['variant'] as String?),
          amount: e.free));
    } else if (goalBuy) {
      final String id = a['itemId']! as String;
      final String title = names.item(id);
      t.purchases.add(WeekItem(
          id: id, title: title, amount: a['price'] as int? ?? -e.goal));
      t.goalsReached.add(title);
    }
    t.goalTitle = activeGoal == null ? null : names.item(activeGoal);
    t.goalPrice = activeGoal == null ? null : names.price(activeGoal);
    t.savedAtEnd = goalBalance;
  }
  return <WeekPlanFact>[for (final WeekTally t in weeks) t.build()];
}
