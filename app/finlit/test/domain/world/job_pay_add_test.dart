import 'package:finlit/domain/world/world_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Настя 20.10 (Денис: «Слушайся Настю»): «к прошлым зарплатам за
/// мини-игры добавь те суммы» — кассир +100, консультант +200, бухгалтер
/// +300, программист +300 / +500 / +700 по уровням, садовник без изменений.
/// Прибавка ложится на оплату смены режима 7 дней после `pay_scale`; запасной
/// режим «неделя» — как сдано. Уронит: прибавка потерялась при загрузке,
/// умножилась на `pay_scale` или попала в режим «неделя».
void main() {
  int pay(WorldConfig c, String id, [String? tier]) => c.job(id, tier)!.pay;

  test('прибавки к оплате смены — ровно названные суммы', () {
    const Map<(String, String?), int> add = <(String, String?), int>{
      ('gardener', null): 0,
      ('cashier', null): 100,
      ('consultant', null): 200,
      ('accountant', null): 300,
      ('programmer', 'easy'): 300,
      ('programmer', 'medium'): 500,
      ('programmer', 'hard'): 700,
    };
    final double scale = contentDayConfig.dayCycle.payScale;
    add.forEach(((String, String?) k, int plus) {
      final int base = pay(contentConfig, k.$1, k.$2);
      final int scaled = scale == 1 ? base : (base * scale / 10).ceil() * 10;
      expect(pay(contentDayConfig, k.$1, k.$2), scaled + plus,
          reason: '${k.$1} ${k.$2 ?? ''}');
    });
  });

  test('режим «неделя» — оплата как сдано', () {
    expect(pay(contentConfig, 'cashier'), 260);
    expect(pay(contentConfig, 'programmer', 'hard'), 480);
  });
}
