import '../models/envelope.dart';
import '../models/pet.dart';
import 'ledger_entry.dart';

/// Состояние игры, полученное свёрткой журнала. Не хранится — вычисляется.
class Wallet {
  const Wallet({
    required this.envelopes,
    required this.savings,
    required this.unallocated,
  });

  static const Wallet empty =
      Wallet(envelopes: Allocation(), savings: 0, unallocated: 0);

  /// Монетки, разложенные по конвертам. Накопления сюда не входят.
  final Allocation envelopes;

  /// Сумма накоплений. Термины ТЗ: «часть игровой валюты, отложенная
  /// пользователем и учитываемая **отдельно** от доступного баланса».
  final int savings;

  /// Пришло, но ещё не разложено. Появляется в начале недели и исчезает
  /// при подтверждении плана.
  final int unallocated;

  /// Доступный баланс (§2.5.3.1) — то, что можно потратить прямо сейчас.
  int get available => envelopes.needs + envelopes.wants + unallocated;

  /// Всё, чем ребёнок владеет, включая копилку. Показывается отдельной
  /// строкой, чтобы «деньги есть, а купить нельзя» не выглядело поломкой.
  int get everything => available + savings;
}

/// Результат свёртки журнала.
class GameSnapshot {
  const GameSnapshot({
    required this.wallet,
    required this.meters,
    required this.carePoints,
    required this.stage,
    required this.periodNo,
  });

  final Wallet wallet;
  final PetMeters meters;

  /// Накопленные очки заботы за все недели. Никогда не уменьшаются:
  /// ТЗ §2.2 «не обнулять ранее достигнутый прогресс».
  final int carePoints;

  final PetStage stage;
  final int periodNo;
}

/// Свёртка журнала в текущее состояние.
///
/// Единственный способ узнать баланс. Если где-то в приложении появится
/// число, полученное не отсюда, — это ошибка, и её ловит тест
/// `test/domain/ledger_is_the_only_source_test.dart`.
class LedgerFold {
  const LedgerFold._();

  static GameSnapshot fold(
    List<LedgerEntry> entries, {
    required PetMeters startMeters,
    int carePoints = 0,
  }) {
    Allocation envelopes = const Allocation();
    int savings = 0;
    int unallocated = 0;
    PetMeters meters = startMeters;
    int periodNo = 1;

    for (final LedgerEntry e in entries) {
      if (e.periodNo > periodNo) periodNo = e.periodNo;
      if (e.envelope != null && e.coins != 0) {
        envelopes = envelopes.plus(e.envelope!, e.coins);
      }
      savings += e.savings;
      unallocated += e.unallocated;
      if (e.meters != PetMeters.zero) meters = meters.plus(e.meters);
    }

    return GameSnapshot(
      wallet:
          Wallet(envelopes: envelopes, savings: savings, unallocated: unallocated),
      meters: meters,
      carePoints: carePoints,
      stage: PetStage.forPoints(carePoints),
      periodNo: periodNo,
    );
  }

  /// Записи одной недели — для экрана истории (§2.5.6.3, §2.5.11.1).
  static List<LedgerEntry> ofPeriod(List<LedgerEntry> entries, int periodNo) =>
      entries.where((LedgerEntry e) => e.periodNo == periodNo).toList();

  /// Фактические траты недели по конвертам (§2.5.5.3 — сравнение с планом).
  ///
  /// Учитываются только расходы: покупки и непредвиденный расход. Взносы
  /// в копилку идут в [Envelope.savings] со знаком плюс.
  static Allocation factOfPeriod(List<LedgerEntry> entries, int periodNo) {
    int needs = 0;
    int wants = 0;
    int savings = 0;
    for (final LedgerEntry e in ofPeriod(entries, periodNo)) {
      switch (e.kind) {
        case LedgerKind.purchase:
        case LedgerKind.unexpectedCost:
          if (e.envelope == Envelope.needs) needs += -e.coins;
          if (e.envelope == Envelope.wants) wants += -e.coins;
        case LedgerKind.savingsDeposit:
        case LedgerKind.savingsWithdraw:
          savings += e.savings;
        case LedgerKind.pocketMoney:
        case LedgerKind.taskReward:
        case LedgerKind.planConfirmed:
        case LedgerKind.envelopeMove:
        case LedgerKind.unexpectedDeferred:
        case LedgerKind.purchaseDeclined:
        case LedgerKind.weeklyDecay:
        case LedgerKind.periodClosed:
        case LedgerKind.parentUnlockedTask:
        // Список ожидания денег не двигает: отложить, дождаться и передумать
        // ничего не стоит. Записи нужны истории, а не арифметике.
        case LedgerKind.wishAdded:
        case LedgerKind.wishKept:
        case LedgerKind.wishDropped:
        // Исполнение мечты — то, ради чего копили, а не трата мимо плана.
        // Считать его в факт недели значило бы наказать за достигнутую цель
        // «отклонением от плана».
        case LedgerKind.goalFulfilled:
          break;
      }
    }
    return Allocation(needs: needs, wants: wants, savings: savings);
  }
}
