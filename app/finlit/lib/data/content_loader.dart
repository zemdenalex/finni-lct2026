import 'dart:convert';

import '../domain/content.dart';
import '../domain/models/catalog_item.dart';
import '../domain/models/goal.dart';
import '../domain/models/task.dart';

/// Читает один файл контента и отдаёт его текст.
///
/// Абстракция нужна ровно за тем, чтобы тесты читали те же самые файлы
/// с диска, что и приложение из assets. Иначе тест валидности контента
/// проверяет не тот контент, который поедет в сборку.
typedef ReadAsset = Future<String> Function(String path);

class ContentLoader {
  const ContentLoader(this.read);

  final ReadAsset read;

  static const String base = 'assets/content';

  /// Имена файлов заданий. Добавление задания — это строка здесь и один
  /// JSON-файл рядом; §2.5.14 «новое задание добавляется без переработки
  /// основной логики приложения».
  static const List<String> taskFiles = <String>[
    'a1_week',
    'a2_finni_mistake',
    'a3_what_first',
    'a4_gift_money',
    'a5_friend_gift',
    'b1_how_many_weeks',
    'b2_rainy_day',
    'b3_by_the_holiday',
    'c1_change',
    'c2_which_cheaper',
    'c3_basket',
    'c4_short_change',
    'c5_where_cheaper',
  ];

  Future<GameContent> load({int scale = 1}) async {
    Future<Map<String, Object?>> obj(String name) async =>
        (jsonDecode(await read('$base/$name.json')) as Map<Object?, Object?>)
            .cast<String, Object?>();

    final List<Map<String, Object?>> tasks = <Map<String, Object?>>[];
    for (final String f in taskFiles) {
      tasks.add(await obj('tasks/$f'));
    }

    return GameContent.parse(
      economy: await obj('economy'),
      catalog: await obj('catalog'),
      goals: await obj('goals'),
      tasks: tasks,
      glossary: await obj('glossary'),
      copy: await obj('copy'),
      scale: scale,
    );
  }
}

/// Проверка целостности контента. Падает на неполной записи — до сборки,
/// а не на демонстрации.
class ContentValidation {
  const ContentValidation._();

  static List<String> problems(GameContent c) {
    final List<String> issues = <String>[];

    // ТЗ §2.6: не менее 8 позиций каталога двух типов.
    if (c.catalog.length < 8) {
      issues.add('Каталог: ${c.catalog.length} позиций, ТЗ §2.6 требует ≥ 8');
    }
    if (!c.catalog.any((CatalogItem i) => i.isNeed)) {
      issues.add('Каталог: нет обязательных позиций');
    }
    if (!c.catalog.any((CatalogItem i) => !i.isNeed)) {
      issues.add('Каталог: нет необязательных позиций');
    }

    // ТЗ §2.6: не менее 3 целей, и хотя бы одна — впечатление, а не вещь.
    if (c.goals.length < 3) {
      issues.add('Цели: ${c.goals.length}, ТЗ §2.6 требует ≥ 3');
    }
    if (!c.goals.any((Goal g) => g.isExperience)) {
      issues
          .add('Цели: ни одна не является впечатлением — посыл «успех = вещь»');
    }

    // ТЗ §2.6 и §2.5.8.1: не менее 6 заданий по 3 темам.
    if (c.tasks.length < 6) {
      issues.add('Задания: ${c.tasks.length}, ТЗ §2.6 требует ≥ 6');
    }
    final Set<String> topics =
        c.tasks.map((GameTask t) => t.topic.name).toSet();
    if (topics.length < 3) {
      issues.add('Задания: тем ${topics.length}, ТЗ §2.5.8.1 требует ≥ 3');
    }

    // §2.5.8.3: объяснение выдаётся при любом исходе.
    for (final GameTask t in c.tasks.expand((GameTask t) => t.allVariants)) {
      if (t.explainAny.trim().isEmpty) {
        issues.add('Задание ${t.id}: пустое объяснение explainAny');
      }
    }

    // §2.5.8.4, «числа покрупнее»: каждое число задания должно быть объявлено
    // либо монетками (умножается), либо не монетками (не умножается).
    //
    // 🔴 Молчаливого умолчания здесь нет намеренно. Пока классификации не
    // было, множитель применялся только к награде: при масштабе 5 задание
    // «Что сначала?» давало бюджет 6 на каталог, где каша стоит 10, — и
    // становилось непроходимым. Забыть классифицировать новый параметр
    // теперь нельзя: сборка упадёт здесь.
    for (final GameTask t in c.tasks.expand((GameTask t) => t.allVariants)) {
      final Set<String> declared = <String>{...t.moneyParams, ...t.plainParams};
      t.params.forEach((String key, Object? value) {
        final bool numeric = value is int ||
            (value is Map<Object?, Object?> &&
                value.values.every((Object? v) => v is int));
        if (numeric && !declared.contains(key)) {
          issues.add('Задание ${t.id}: число «$key» не отнесено ни к money, '
              'ни к plain — в режиме «числа покрупнее» оно разойдётся с ценами');
        }
      });
      for (final String key in declared) {
        if (!t.params.containsKey(key)) {
          issues.add('Задание ${t.id}: объявлен параметр «$key», '
              'которого нет в params');
        }
      }
    }

    // Тексты заданий собираются подстановкой чисел из params. Оставшаяся
    // фигурная скобка — это либо опечатка в ключе, либо число, которого
    // в параметрах нет; и то и другое ребёнок увидит на экране.
    for (final GameTask t in c.tasks.expand((GameTask t) => t.allVariants)) {
      final List<String> texts = <String>[
        t.prompt,
        t.explainAny,
        t.explainBest,
        ...t.params.values.whereType<String>(),
      ];
      for (final String text in texts) {
        if (text.contains('{') || text.contains('}')) {
          issues.add('Задание ${t.id}: незаполненная подстановка в «$text»');
        }
      }
    }

    // §2.5.6.2: перед покупкой видно предполагаемое влияние на питомца.
    for (final CatalogItem i in c.catalog) {
      if (i.hint.trim().isEmpty) {
        issues.add('Позиция ${i.id}: нет описания влияния на питомца');
      }
      if (i.price <= 0) {
        issues.add('Позиция ${i.id}: цена должна быть больше нуля');
      }
    }

    // Все ключи объяснений, которыми пользуется движок, должны существовать.
    const List<String> required = <String>[
      'income.pocket',
      'income.task',
      'earn.partial',
      'earn.capReached',
      'trust.grew',
      'goal.fulfilled',
      'plan.confirmed',
      'plan.envelope',
      'purchase.done',
      'purchase.declined',
      'envelope.move',
      'savings.deposit',
      'savings.withdraw',
      'unexpected.paid',
      'unexpected.deferred',
      'period.decay',
      'period.closed',
      'parent.unlockedTask',
      'wish.added',
      'wish.kept',
      'wish.dropped',
    ];
    for (final String key in required) {
      if (!c.copy.containsKey(key)) {
        issues.add('copy.json: нет текста для ключа $key');
      }
    }

    return issues;
  }
}
