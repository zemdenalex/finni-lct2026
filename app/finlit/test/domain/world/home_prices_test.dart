import 'dart:convert';
import 'dart:io';

import 'package:finlit/domain/world/world_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Цены переездов (слово Насти, тема 11; finni 18.10): залог и первая неделя
/// — город 5000, Москва 12000; аренда в неделю прежняя 400 и 1000. Защищает
/// числа в файле, в разобранном мире и в значениях по умолчанию (без файла
/// — те же цены), и порядок «собака 3200 дешевле переезда». Уронит: цена
/// осталась старой в одной из двух копий или в коде, аренда поменялась
/// вместе с ценой. Почему не ловят прежние: `rent_stage_test` проверяет
/// стадию и аренду, а не цену переезда.
void main() {
  test('файл, мир и значения по умолчанию: 5000 / 12000, аренда 400 / 1000',
      () {
    for (final String f in <String>[
      'assets/content/world/economy.json',
      '../../content/economy.json',
    ]) {
      final Map<String, Object?> e =
          jsonDecode(File(f).readAsStringSync()) as Map<String, Object?>;
      final Map<String, Map<String, Object?>> h =
          <String, Map<String, Object?>>{
        for (final Object? o in ((e['homes']!
            as Map<String, Object?>)['options']! as List<Object?>))
          (o! as Map<String, Object?>)['id']! as String:
              o as Map<String, Object?>,
      };
      expect(h['home_flat']!['price'], 5000, reason: f);
      expect(h['home_house']!['price'], 12000, reason: f);
      expect(h['home_flat']!['weekly_cost'], 400, reason: f);
      expect(h['home_house']!['weekly_cost'], 1000, reason: f);
    }
    for (final WorldConfig c in <WorldConfig>[
      contentDayConfig,
      contentConfig,
      const WorldConfig(),
    ]) {
      expect(c.home('home_flat')!.price, 5000);
      expect(c.home('home_house')!.price, 12000);
      expect(c.home('home_flat')!.weeklyCost, 400);
      expect(c.home('home_house')!.weeklyCost, 1000);
    }
  });

  test('собака дешевле переезда в город', () {
    final int dog = contentDayConfig.pets
        .singleWhere((WorldPet p) => p.id == 'pet_dog')
        .price;
    expect(dog, lessThan(contentDayConfig.home('home_flat')!.price));
  });
}
