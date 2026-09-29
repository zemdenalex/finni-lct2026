import 'economy/economy_config.dart';
import 'models/catalog_item.dart';
import 'models/goal.dart';
import 'models/task.dart';
import 'phrases.dart';

class GlossaryTerm {
  const GlossaryTerm({
    required this.id,
    required this.term,
    required this.text,
    required this.unlockedBy,
  });

  final String id;
  final String term;
  final String text;
  final String unlockedBy;

  static GlossaryTerm fromJson(Map<String, Object?> json) => GlossaryTerm(
        id: json['id']! as String,
        term: json['term']! as String,
        text: json['text']! as String,
        unlockedBy: json['unlockedBy']! as String,
      );
}

/// Весь учебный контент приложения, разобранный из JSON.
///
/// §3.2 ТЗ: «Учебный контент должен быть отделён от интерфейсного кода».
/// §2.5.14: «Новое задание добавляется без переработки основной логики».
/// Проверяется тестом test/content_valid_test.dart: он читает файлы из assets
/// ровно так же, как приложение, и падает на любой неполной записи.
class GameContent {
  const GameContent({
    required this.economy,
    required this.catalog,
    required this.goals,
    required this.customGoalTitles,
    required this.customGoalPrices,
    required this.tasks,
    required this.glossary,
    required this.copy,
  });

  final EconomyConfig economy;
  final List<CatalogItem> catalog;
  final List<Goal> goals;
  final List<String> customGoalTitles;
  final List<int> customGoalPrices;
  final List<GameTask> tasks;
  final List<GlossaryTerm> glossary;
  final Map<String, String> copy;

  /// Позиция каталога или null, если её больше нет — например, контент
  /// обновили, а в журнале осталась покупка старой позиции.
  CatalogItem? itemOrNull(String id) {
    for (final CatalogItem i in catalog) {
      if (i.id == id) return i;
    }
    return null;
  }

  CatalogItem item(String id) =>
      catalog.firstWhere((CatalogItem i) => i.id == id);

  Goal? goal(String? id) {
    if (id == null) return null;
    for (final Goal g in goals) {
      if (g.id == id) return g;
    }
    return null;
  }

  GameTask task(String id) => tasks.firstWhere((GameTask t) => t.id == id);

  /// Текст объяснения с подстановками. Отсутствующий ключ — это дефект
  /// контента, а не повод молча показать пустоту: возвращаем ключ,
  /// и тест валидности контента ловит такие случаи до сборки.
  String say(String reasonCode,
          [Map<String, Object?> args = const <String, Object?>{}]) =>
      Phrases.fill(copy[reasonCode] ?? reasonCode, args);

  /// Разбор из уже прочитанных JSON-карт. Чтение файлов — в data/,
  /// чтобы домен оставался чистым Dart без Flutter.
  static GameContent parse({
    required Map<String, Object?> economy,
    required Map<String, Object?> catalog,
    required Map<String, Object?> goals,
    required List<Map<String, Object?>> tasks,
    required Map<String, Object?> glossary,
    required Map<String, Object?> copy,
    int scale = 1,
  }) {
    final Map<String, Object?> custom =
        (goals['customOptions']! as Map<Object?, Object?>).cast<String, Object?>();
    return GameContent(
      economy: EconomyConfig.fromJson(economy, scale: scale),
      catalog: (catalog['items']! as List<Object?>)
          .map((Object? e) => CatalogItem.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
              scale: scale))
          .toList(),
      goals: (goals['goals']! as List<Object?>)
          .map((Object? e) => Goal.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
              scale: scale))
          .toList(),
      customGoalTitles: (custom['titles']! as List<Object?>).cast<String>(),
      customGoalPrices: (custom['prices']! as List<Object?>)
          .cast<int>()
          .map((int p) => p * scale)
          .toList(),
      tasks: tasks
          .map((Map<String, Object?> e) => GameTask.fromJson(e, scale: scale))
          .toList(),
      glossary: (glossary['terms']! as List<Object?>)
          .map((Object? e) => GlossaryTerm.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>()))
          .toList(),
      copy: copy.map((String k, Object? v) =>
          MapEntry<String, String>(k, v.toString())),
    );
  }
}
