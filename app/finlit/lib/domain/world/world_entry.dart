import '../ledger/ledger_entry.dart' show LedgerKind;
import 'contract.dart';

/// Выборы ребёнка, которые меняют будущие числа, но не деньги.
///
/// 🔴 Не в контракте: [WorldLedgerKind] их не содержит, а без записи в
/// журнале выбор еды и цели терялся бы при перезапуске (ТЗ 2.5.13.1).
/// Контракт оставляет форму записи реализации журнала (A2).
enum WorldChoiceKind {
  /// Выбрана активная цель накопления. `args.goalId`.
  goalChosen,

  /// Выбран уровень еды недели. `args.foodId`.
  foodChosen,
}

/// Действия панели «Проверка» для эксперта (ТЗ 2.5.8.5, 2.5.13.2): в
/// журнале — `demo.*`.
///
/// Не деньги и не выбор ребёнка: запись не меняет ни монет, ни ⚡, ни 😊, ни
/// владения — только то, что открыто или показано. Сброс игры начинает журнал заново и
/// стирает её вместе со всем остальным.
enum WorldDemoKind {
  /// «Открыть все профессии»: закрытые работы (курьер, выгульщик) открыты
  /// без покупки транспорта и собаки. Скидки транспорта и перков нет.
  unlockAllJobs,

  /// «Показать событие»: событие `args.eventId` ждёт выбора на этой неделе,
  /// как показанное по расписанию. Расписание (повтор, лимит в неделю) не
  /// сдвигается; выбор закрывает его обычной записью `eventChoice`.
  showEvent,
}

/// Одна запись журнала нового мира: что изменилось и **почему**.
///
/// Все поля-числа — **изменения**, а не значения: деньги, ⚡ и 😊 получаются
/// только свёрткой журнала (`WorldFold`). 😊 пишется уже с учётом границ
/// 0–100 — то изменение, которое реально случилось.
///
/// [kind] — одно из четырёх перечислений: [WorldLedgerKind] (новый мир),
/// [LedgerKind] (старые виды, которые новый мир использует как есть:
/// `pocketMoney`, `planConfirmed`, `savingsWithdraw`, `periodClosed`),
/// [WorldChoiceKind] или [WorldDemoKind].
class WorldEntry {
  const WorldEntry({
    required this.seq,
    required this.weekNo,
    required this.kind,
    required this.reasonCode,
    this.need = 0,
    this.want = 0,
    this.goal = 0,
    this.free = 0,
    this.unallocated = 0,
    this.energy = 0,
    this.happiness = 0,
    this.args = const <String, Object?>{},
  });

  /// Порядковый номер в журнале, с 0.
  final int seq;
  final int weekNo;
  final Enum kind;

  /// Ключ текста в `copy.json`.
  final String reasonCode;

  final int need;
  final int want;
  final int goal;
  final int free;
  final int unallocated;
  final double energy;
  final int happiness;

  /// Подстановки: id работы, товара, сумма, итог недели.
  final Map<String, Object?> args;

  /// Суммарное изменение доступных монет (💰 в HUD).
  int get coins => need + want + free + unallocated;

  bool isKind(Enum k) => kind == k;

  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'weekNo': weekNo,
        'kind': kindToString(kind),
        'reasonCode': reasonCode,
        if (need != 0) 'need': need,
        if (want != 0) 'want': want,
        if (goal != 0) 'goal': goal,
        if (free != 0) 'free': free,
        if (unallocated != 0) 'unallocated': unallocated,
        if (energy != 0) 'energy': energy,
        if (happiness != 0) 'happiness': happiness,
        if (args.isNotEmpty) 'args': args,
      };

  /// null — вид записи неизвестен (старая или будущая версия): такая запись
  /// пропускается и считается «нечитаемой», приложение не падает.
  static WorldEntry? fromJson(Map<String, Object?> json) {
    final Enum? kind = kindFromString(json['kind'] as String? ?? '');
    if (kind == null) return null;
    return WorldEntry(
      seq: json['seq']! as int,
      weekNo: json['weekNo']! as int,
      kind: kind,
      reasonCode: json['reasonCode']! as String,
      need: json['need'] as int? ?? 0,
      want: json['want'] as int? ?? 0,
      goal: json['goal'] as int? ?? 0,
      free: json['free'] as int? ?? 0,
      unallocated: json['unallocated'] as int? ?? 0,
      energy: (json['energy'] as num? ?? 0).toDouble(),
      happiness: json['happiness'] as int? ?? 0,
      args:
          (json['args'] as Map<Object?, Object?>? ?? const <String, Object?>{})
              .cast<String, Object?>(),
    );
  }

  static String kindToString(Enum kind) => switch (kind) {
        WorldLedgerKind() => 'world.${kind.name}',
        LedgerKind() => 'ledger.${kind.name}',
        WorldChoiceKind() => 'choice.${kind.name}',
        WorldDemoKind() => 'demo.${kind.name}',
        _ => throw ArgumentError('Чужой вид записи: $kind'),
      };

  static Enum? kindFromString(String s) {
    final int dot = s.indexOf('.');
    if (dot < 0) return null;
    final String name = s.substring(dot + 1);
    final List<Enum> values = switch (s.substring(0, dot)) {
      'world' => WorldLedgerKind.values,
      'ledger' => LedgerKind.values,
      'choice' => WorldChoiceKind.values,
      'demo' => WorldDemoKind.values,
      _ => const <Enum>[],
    };
    for (final Enum v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  @override
  String toString() => 'WorldEntry#$seq w$weekNo ${kindToString(kind)} '
      '$reasonCode need $need want $want goal $goal free $free '
      'unalloc $unallocated ⚡ $energy 😊 $happiness $args';
}
