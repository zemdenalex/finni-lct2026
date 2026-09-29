/// Финансовая цель (§2.5.7.1).
///
/// ТЗ §2.6 требует не менее трёх. Среди них обязательно есть цель-впечатление,
/// а не только вещь: Common Sense Media снизила оценку Star Banks Adventure
/// до 2/5 именно за посыл «успех — это накопить на вещь».
/// См. docs/konkurenty.md §2.1.
class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.price,
    required this.isExperience,
    required this.icon,
  });

  final String id;
  final String title;
  final int price;

  /// true — это событие или впечатление, а не предмет.
  final bool isExperience;
  final String icon;

  static Goal fromJson(Map<String, Object?> json, {int scale = 1}) => Goal(
        id: json['id']! as String,
        title: json['title']! as String,
        price: (json['price']! as int) * scale,
        isExperience: (json['isExperience'] ?? false) as bool,
        icon: json['icon']! as String,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'price': price,
        'isExperience': isExperience,
        'icon': icon,
      };
}
