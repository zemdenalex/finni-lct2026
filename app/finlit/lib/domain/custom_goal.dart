import 'content.dart';
import 'models/goal.dart';

/// Своя цель — §2.5.7.1: «возможность создать простую цель из установленного
/// набора параметров».
///
/// 🔴 Цель целиком помещается в идентификатор: `custom:<номер названия>:<номер
/// цены>`. И название, и цена — это **номера** позиций из
/// `content.customGoalTitles` и `content.customGoalPrices`, то есть придумать
/// произвольную строку или произвольное число ребёнок не может, и в профиле
/// не появляется ни одного свободно введённого текста (§3.5.1 — без сбора
/// персональных данных). Побочная выгода: цель переживает перезапуск, не
/// требуя нового поля в профиле, — достаточно [restore] при открытии экрана.
///
/// 🔴 В идентификаторе именно номер цены, а не сама цена. Цена, записанная
/// числом, застывала в тех монетках, которые были на экране в момент выбора:
/// при включении «чисел покрупнее» дорожало всё вокруг — карманные, каталог,
/// готовые цели, — а своя цель оставалась в старых единицах и становилась
/// достижимой за одну неделю. Номер же читается из контента, который уже
/// загружен в нужном масштабе, поэтому своя цель дорожает вместе со всем
/// остальным. Цена того, что выбрал ребёнок («второй вариант, средний»),
/// сохраняется по смыслу, а не по числу.
abstract final class CustomGoals {
  static const String prefix = 'custom:';
  static const String icon = 'custom';

  static bool isCustom(String? id) => id != null && id.startsWith(prefix);

  static String idFor(int titleIndex, int priceIndex) =>
      '$prefix$titleIndex:$priceIndex';

  /// Разбор идентификатора обратно в цель. null — если идентификатор
  /// не наш или ссылается на позицию, которой в контенте больше нет
  /// (например, контент обновили между версиями).
  static Goal? decode(GameContent content, String id) {
    if (!isCustom(id)) return null;
    final List<String> parts = id.substring(prefix.length).split(':');
    if (parts.length != 2) return null;
    final int? title = int.tryParse(parts[0]);
    final int? price = int.tryParse(parts[1]);
    if (title == null || price == null) return null;
    if (title < 0 || title >= content.customGoalTitles.length) return null;
    if (price < 0 || price >= content.customGoalPrices.length) return null;
    return Goal(
      id: id,
      title: content.customGoalTitles[title],
      price: content.customGoalPrices[price],
      // Своя цель может оказаться и впечатлением, и вещью — набор названий
      // в goals.json содержит и то и другое, поэтому отдельной пометки нет.
      isExperience: false,
      icon: icon,
    );
  }

  /// Кладёт свою цель в список целей контента, чтобы `game.goal` её нашёл.
  ///
  /// Вызывается при загрузке профиля и при смене масштаба: в профиле остаётся
  /// только идентификатор, а список целей собирается из goals.json заново —
  /// и уже в нужных монетках. Если не восстановить, главный экран покажет
  /// «цель не выбрана» у ребёнка, который цель выбрал, — то есть §2.5.13
  /// нарушается молча.
  static void restore(GameContent content, String? goalId) {
    if (!isCustom(goalId)) return;
    if (content.goal(goalId) != null) return;
    final Goal? g = decode(content, goalId!);
    if (g != null) content.goals.add(g);
  }
}
