import 'package:finlit/data/content_loader.dart';
import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_content.dart';

void main() {
  test('контент проходит проверку целостности', () async {
    final GameContent c = await loadRealContent();
    final List<String> problems = ContentValidation.problems(c);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('минимальный объём контента по §2.6 ТЗ', () async {
    final GameContent c = await loadRealContent();
    expect(c.catalog.length, greaterThanOrEqualTo(8),
        reason: 'покупки: не менее 8 позиций двух типов');
    expect(c.goals.length, greaterThanOrEqualTo(3),
        reason: 'цели накопления: не менее 3');
    expect(c.tasks.length, greaterThanOrEqualTo(6),
        reason: 'задания: не менее 6 по 3 темам');
    expect(c.tasks.map((GameTask t) => t.topic).toSet().length,
        greaterThanOrEqualTo(3));
  });

  test('в каталоге есть и обязательные, и необязательные позиции', () async {
    final GameContent c = await loadRealContent();
    expect(c.catalog.where((CatalogItem i) => i.isNeed).length,
        greaterThanOrEqualTo(2));
    expect(c.catalog.where((CatalogItem i) => !i.isNeed).length,
        greaterThanOrEqualTo(2));
  });

  test('задание добавляется одним файлом: все файлы из списка читаются',
      () async {
    final GameContent c = await loadRealContent();
    expect(c.tasks.length, ContentLoader.taskFiles.length);
  });

  test('режим «числа покрупнее» умножает экономику, не ломая её', () async {
    final GameContent base = await loadRealContent();
    final GameContent big = await loadRealContent(scale: 5);
    expect(big.economy.pocketMoney, base.economy.pocketMoney * 5);
    expect(big.catalog.first.price, base.catalog.first.price * 5);
    expect(big.goals.first.price, base.goals.first.price * 5);
    // Затухание показателей от множителя не зависит: шкалы всегда 0..10.
    expect(big.economy.decay, base.economy.decay);
  });
}
