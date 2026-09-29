import 'envelope.dart';
import 'pet.dart';

/// Позиция каталога покупок (§2.5.6.1).
///
/// ТЗ §2.6 требует не менее 8 позиций двух типов. Тип задаётся конвертом:
/// [Envelope.needs] — обязательные расходы, [Envelope.wants] — необязательные.
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.envelope,
    required this.price,
    required this.effect,
    required this.hint,
    required this.icon,
    this.accessory,
    this.keeps = false,
  });

  final String id;
  final String title;
  final Envelope envelope;
  final int price;

  /// Как покупка меняет показатели питомца.
  final PetMeters effect;

  /// Предполагаемое влияние на питомца словами — ТЗ §2.5.6.2 требует
  /// показывать его **до** покупки. Словами, а не числом «+3»: семилетка
  /// читает «Финни поест», а не дельту.
  final String hint;

  /// Ключ иконки. Иконки рисуются кодом, без растровых ассетов —
  /// см. lib/core/finni_art.dart.
  final String icon;

  /// Если покупка меняет внешний вид питомца — идентификатор аксессуара.
  final String? accessory;

  /// Вещь остаётся после покупки — её видно в комнате Финни.
  ///
  /// 🔴 Главный ход из анализа игровых референсов команды: «ребёнок должен
  /// копить не ради денег, а ради изменения своего мира». Съеденная каша
  /// исчезает — так и должно быть, это расход. А купленный мячик, который
  /// исчезал так же, как каша, учил одному: деньги уходят в никуда. Теперь
  /// он лежит в комнате, и её можно показать.
  final bool keeps;

  bool get isNeed => envelope == Envelope.needs;

  static CatalogItem fromJson(Map<String, Object?> json, {int scale = 1}) {
    final Map<String, Object?> eff =
        (json['effect']! as Map<Object?, Object?>).cast<String, Object?>();
    return CatalogItem(
      id: json['id']! as String,
      title: json['title']! as String,
      envelope: Envelope.byId(json['envelope']! as String),
      price: (json['price']! as int) * scale,
      effect: PetMeters(
        fullness: (eff['fullness'] ?? 0) as int,
        cleanliness: (eff['cleanliness'] ?? 0) as int,
        mood: (eff['mood'] ?? 0) as int,
      ),
      hint: json['hint']! as String,
      icon: json['icon']! as String,
      accessory: json['accessory'] as String?,
      keeps: json['keeps'] as bool? ?? false,
    );
  }
}
