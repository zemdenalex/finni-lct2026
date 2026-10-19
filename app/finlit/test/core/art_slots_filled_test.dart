import 'dart:io';

import 'package:finlit/core/art/asset_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ловит: здание на стадии деревни, города или Москвы снова показывает один
/// и тот же рисунок по умолчанию (в реестре пропал вариант стадии), или
/// видимый игроку слот вернулся к ночной заглушке 29.09 (SDXL, сетка 4 px,
/// `hires/night/`) — после перезаливки арта Дениса 19.10 эти места закрыты.
void main() {
  final AssetRegistry reg =
      AssetRegistry.parse(File('assets/art/registry.json').readAsStringSync());

  // Только то, что прошло отбор Дениса 19.10 (угол 2:1 ≈ 26,6° ± 3°,
  // ≤ 256 цветов): остальные стадии ждут новых генераций.
  const Map<String, List<String>> stages = <String, List<String>>{
    'cinema': <String>['moscow'],
  };

  test('у каждого здания свой рисунок на каждой стадии', () {
    final List<String> same = <String>[
      for (final MapEntry<String, List<String>> b in stages.entries)
        for (final String stage in b.value)
          if (reg.building(b.key, variant: stage) == reg.building(b.key))
            '${b.key}/$stage',
    ];
    expect(same, isEmpty, reason: 'стадия берёт рисунок по умолчанию');
  });

  // Слоты, которые игрок видит: декор на карте, блюда и вещи в магазине,
  // картинки работ на доске смен.
  const List<String> visible = <String>[
    'city_tree',
    'city_bench',
    'city_fountain',
    'city_busstop',
    'city_kiosk',
    'city_flowerbed',
    'food_soup',
    'food_syrniki',
    'food_burger',
    'food_fish',
    'food_bread_tea',
    'food_oatmeal',
    'food_pasta',
    'work_cash_register',
    'work_price_tags',
    'work_dog_leash',
    'transport_skateboard',
  ];

  test('видимые слоты не на ночной заглушке', () {
    final List<String> placeholders = <String>[
      for (final String id in visible)
        if (reg.item(id) == null || reg.item(id)!.contains('/night/')) id,
    ];
    expect(placeholders, isEmpty);
  });
}
