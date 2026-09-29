/// Три направления, по которым ребёнок раскладывает монетки перед игровой неделей.
///
/// ТЗ §2.5.5.1 требует минимум три направления: обязательные расходы,
/// необязательные расходы, накопления. §2.5.5.4 разрешает свои названия,
/// если смысл понятен ребёнку — поэтому в интерфейсе это «Нужное», «Хочу»
/// и «Копилка», а не «обязательные расходы».
enum Envelope {
  needs('Нужное', 'Еда, вода и чистота — то, без чего не обойтись'),
  wants('Хочу', 'Игрушки и украшения. Приятно, но можно и подождать'),
  savings('Копилка', 'Монетки, которые ты откладываешь на цель');

  const Envelope(this.title, this.hint);

  /// Название, которое видит ребёнок.
  final String title;

  /// Одна строка, объясняющая смысл конверта. Показывается рядом, а не в справке:
  /// ТЗ §3.6 требует, чтобы ребёнок понимал раздел без чтения инструкции.
  final String hint;

  static Envelope byId(String id) =>
      Envelope.values.firstWhere((Envelope e) => e.name == id);
}

/// Распределение монеток по трём конвертам.
///
/// Называется Allocation, а не Split: Flutter экспортирует кривую анимации
/// с именем Split, и коллизия имён ломает строгий анализатор проекта.
///
/// Используется и как план (составляется до начала недели, §2.5.5.1),
/// и как факт (сколько реально ушло из каждого конверта, §2.5.5.3).
class Allocation {
  const Allocation({this.needs = 0, this.wants = 0, this.savings = 0});

  final int needs;
  final int wants;
  final int savings;

  int get total => needs + wants + savings;

  int byEnvelope(Envelope e) => switch (e) {
        Envelope.needs => needs,
        Envelope.wants => wants,
        Envelope.savings => savings,
      };

  Allocation withEnvelope(Envelope e, int value) => switch (e) {
        Envelope.needs => Allocation(needs: value, wants: wants, savings: savings),
        Envelope.wants => Allocation(needs: needs, wants: value, savings: savings),
        Envelope.savings => Allocation(needs: needs, wants: wants, savings: value),
      };

  Allocation plus(Envelope e, int delta) => withEnvelope(e, byEnvelope(e) + delta);

  Map<String, Object?> toJson() =>
      <String, Object?>{'needs': needs, 'wants': wants, 'savings': savings};

  static Allocation fromJson(Map<String, Object?> json) => Allocation(
        needs: json['needs']! as int,
        wants: json['wants']! as int,
        savings: json['savings']! as int,
      );

  @override
  String toString() => 'Allocation(нужное: $needs, хочу: $wants, копилка: $savings)';

  @override
  bool operator ==(Object other) =>
      other is Allocation &&
      other.needs == needs &&
      other.wants == wants &&
      other.savings == savings;

  @override
  int get hashCode => Object.hash(needs, wants, savings);
}
