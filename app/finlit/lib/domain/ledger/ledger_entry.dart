import '../models/envelope.dart';
import '../models/pet.dart';

/// Что именно произошло. От вида зависит формулировка объяснения и иконка.
enum LedgerKind {
  /// Карманные в начале игровой недели (§2.5.4.2).
  pocketMoney,

  /// Награда за выполненное задание (§2.5.4.2).
  taskReward,

  /// Подтверждение плана: монетки разложены по конвертам (§2.5.5).
  planConfirmed,

  /// Покупка из каталога (§2.5.6).
  purchase,

  /// Перекладывание монеток между конвертами. Отдельное осознанное действие
  /// ребёнка — именно оно создаёт расхождение плана и факта.
  envelopeMove,

  /// Взнос в копилку сверх плана (§2.5.7.3).
  savingsDeposit,

  /// Снятие с копилки. Только после отдельного подтверждения (§2.5.7.5).
  savingsWithdraw,

  /// Непредвиденный расход — единственный запланированный кейс, который
  /// ТЗ §2 разрешает как исключение из запрета на негативные последствия.
  unexpectedCost,

  /// Непредвиденный расход перенесён на следующую неделю. Денег не меняет,
  /// но это решение ребёнка, и оно обязано быть в истории.
  unexpectedDeferred,

  /// Попытка покупки при нехватке монеток (§2.5.6.4). Денег не меняет.
  /// Запись нужна, чтобы шаг 7 Приложения А засчитывался автоматически,
  /// и чтобы ребёнок видел в истории, что он пробовал.
  purchaseDeclined,

  /// Затухание показателей при закрытии недели.
  weeklyDecay,

  /// Итог недели: очки заботы, план против факта.
  periodClosed,

  /// Вещь отложена в список ожидания. Денег не меняет: это решение
  /// ребёнка подождать при том, что монеток хватало.
  wishAdded,

  /// Дождавшись, ребёнок подтвердил желание.
  wishKept,

  /// Дождавшись, ребёнок передумал. Самая ценная запись в журнале:
  /// единственная, которая сообщает ребёнку что-то о нём самом.
  wishDropped,

  /// Мечта исполнена: из копилки ушла её цена, и она осталась в мире Финни.
  goalFulfilled,

  /// Взрослый открыл дополнительное задание (§2.5.12).
  /// 🔴 Не деньги. Взрослый даёт возможность заработать, а не монетки:
  /// иначе дыра в бюджете закрывается просьбой к родителю, а §2.1 требует
  /// ограниченности ресурсов.
  parentUnlockedTask,
}

/// Одна запись журнала: что изменилось и **почему**.
///
/// 🔴 Центральное архитектурное решение проекта. Баланс, накопления и
/// показатели питомца нигде не хранятся как числа — хранится этот журнал,
/// а значения получаются свёрткой (см. [LedgerFold]).
///
/// Зачем так: ТЗ §2.5.4.3 требует, чтобы баланс не менялся без объяснения,
/// а §2.2 — чтобы любое изменение отвечало на вопрос «что изменилось и почему».
/// При хранении чисел это пожелание, которое легко нарушить по невнимательности.
/// При хранении журнала другого способа изменить баланс просто нет:
/// [reasonCode] — обязательное поле.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.periodNo,
    required this.kind,
    required this.reasonCode,
    this.envelope,
    this.coins = 0,
    this.savings = 0,
    this.unallocated = 0,
    this.meters = PetMeters.zero,
    this.args = const <String, Object?>{},
  });

  final String id;
  final int periodNo;
  final LedgerKind kind;

  /// Ключ текста в assets/content/copy.json. Не сам текст: тексты — учебный
  /// контент, и §3.2 ТЗ требует отделять его от кода.
  final String reasonCode;

  /// Из какого конверта ушли или в какой пришли монетки.
  final Envelope? envelope;

  /// Изменение монеток в конверте [envelope].
  final int coins;

  /// Изменение суммы накоплений.
  final int savings;

  /// Изменение нераспределённых монеток — тех, что пришли, но ещё не
  /// разложены по конвертам.
  final int unallocated;

  /// Изменение показателей питомца.
  final PetMeters meters;

  /// Подстановки в текст объяснения: сумма, название товара, срок до цели.
  final Map<String, Object?> args;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'periodNo': periodNo,
        'kind': kind.name,
        'reasonCode': reasonCode,
        if (envelope != null) 'envelope': envelope!.name,
        'coins': coins,
        'savings': savings,
        'unallocated': unallocated,
        'meters': meters.toJson(),
        'args': args,
      };

  static LedgerEntry fromJson(Map<String, Object?> json) => LedgerEntry(
        id: json['id']! as String,
        periodNo: json['periodNo']! as int,
        kind: LedgerKind.values.byName(json['kind']! as String),
        reasonCode: json['reasonCode']! as String,
        envelope: json['envelope'] == null
            ? null
            : Envelope.byId(json['envelope']! as String),
        coins: json['coins']! as int,
        savings: json['savings']! as int,
        unallocated: json['unallocated']! as int,
        meters: PetMeters.fromJson(
            (json['meters']! as Map<Object?, Object?>).cast<String, Object?>()),
        args: (json['args']! as Map<Object?, Object?>).cast<String, Object?>(),
      );

  @override
  String toString() =>
      'LedgerEntry(#$periodNo ${kind.name} $reasonCode coins:$coins savings:$savings)';
}
