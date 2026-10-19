import 'package:finlit/domain/phrases.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/xp_twins.dart';

/// Надбавка за опыт в монетах (решение Дениса 19.10: на детских экранах
/// «опыт» словами и монетами, без процентов).
///
/// Защищает: [JobOffer.experienceCoins] — ровно столько монет, на сколько
/// больше начисляют за смену из-за опыта (та же математика и округление,
/// что у начисления: дни — вверх до монеты, «неделя» — до десятка), на всех
/// доступных работах и нескольких уровнях опыта; слова доли и согласование
/// «монета / монеты / монет».
/// Уронит: надбавка считается своей формулой (`pay × (1 − 1/рост)`,
/// округление вниз или до десятка в режиме дней), граница слова сдвинута
/// («пятая часть» на 25 %), «монетки» вместо «монеты» (правило Насти).
/// Почему не ловят прежние: поля в монетах раньше не было;
/// `experience_pay_test` проверяет оплату, а не её долю за опыт.

/// Сверка надбавки с начислением: после каждой из [levels] хороших смен —
/// до [perLevel] доступных обычных смен, по кругу с разных работ (сил и
/// дней недели на все работы на каждом уровне не хватает).
int _checkAgainstCredit(double growth, int levels,
    {bool week = false, int perLevel = 2}) {
  final (WorldGame a, WorldGame b) = livingTwins(growth, week: week);
  int checked = 0;
  for (int xp = 0; xp <= levels; xp++) {
    if (xp > 0) goodShift(a, b);
    final List<JobOffer> board = a.jobBoard;
    int here = 0;
    for (int i = 0; i < board.length && here < perLevel; i++) {
      final JobOffer listed = board[(i + xp * perLevel) % board.length];
      if (!readyFor(a, b, listed.jobId, variant: listed.variant)) continue;
      // Карточка — заново перед сменой: прошлая смена потратила силы.
      final JobOffer o = a.offer(listed.jobId, variant: listed.variant)!;
      final JobOffer twin = b.offer(o.jobId, variant: o.variant)!;
      expect(twin.experienceCoins, 0, reason: 'без роста надбавки нет');
      final int credited =
          creditedXpCoins(a, b, o.jobId, variant: o.variant);
      expect(o.experienceCoins, credited,
          reason: '${o.jobId}/${o.variant} опыт $xp: pay ${o.pay}, '
              'близнец ${twin.pay}');
      checked++;
      here++;
    }
  }
  return checked;
}

void main() {
  test('надбавка = начислению: сборка (×1,01), режим дней', () {
    expect(_checkAgainstCredit(1.01, 4), greaterThan(4));
  });

  test('надбавка = начислению: рост ×1,2, режим дней', () {
    expect(_checkAgainstCredit(1.2, 4), greaterThan(4));
  });

  test('надбавка = начислению: режим «неделя» (до десятка)', () {
    expect(_checkAgainstCredit(1.2, 2, week: true, perLevel: 1), greaterThan(1));
  });

  test('слова доли и монеты', () {
    String t(int pay, int coins) =>
        experiencePayText(pay: pay, coins: coins);
    expect(t(140, 0), 'за опыт прибавки пока нет');
    expect(t(141, 1), 'за опыт оплата чуть больше (+1 монета)');
    expect(t(214, 14), 'за опыт оплата чуть больше (+14 монет)',
        reason: '7 % — ещё «чуть»');
    expect(t(215, 15), 'за опыт оплата больше примерно на десятую часть '
        '(+15 монет)', reason: '7,5 % — уже десятая');
    expect(t(110, 10), 'за опыт оплата больше на десятую часть (+10 монет)');
    expect(t(115, 15), 'за опыт оплата больше примерно на пятую часть '
        '(+15 монет)', reason: '15 % — уже пятая');
    expect(t(120, 20), 'за опыт оплата больше на пятую часть (+20 монет)');
    expect(t(125, 25), 'за опыт оплата больше на четверть (+25 монет)');
    expect(t(133, 33), 'за опыт оплата больше на треть (+33 монеты)');
    expect(t(140, 40), 'за опыт оплата больше примерно на треть (+40 монет)');
    expect(t(150, 50), 'за опыт оплата в полтора раза больше (+50 монет)');
    expect(t(160, 60),
        'за опыт оплата примерно в полтора раза больше (+60 монет)');
    expect(t(200, 100), 'за опыт оплата вдвое больше (+100 монет)');
    expect(t(300, 200), 'за опыт оплата больше чем вдвое (+200 монет)');
    // Границы слов: (оплата, монеты за опыт) → доля от оплаты без опыта.
    for (final (int, int, String) c in <(int, int, String)>[
      (122, 22, 'больше примерно на пятую часть'), // 22 %
      (245, 45, 'больше примерно на четверть'), // 22,5 %
      (128, 28, 'больше примерно на четверть'), // 28 %
      (129, 29, 'больше примерно на треть'), // 29 %
      (141, 41, 'больше примерно на треть'), // 41 %
      (283, 83, 'примерно в полтора раза больше'), // 41,5 %
      (174, 74, 'примерно в полтора раза больше'), // 74 %
      (175, 75, 'примерно вдвое больше'), // 75 %
      (249, 149, 'примерно вдвое больше'), // 149 %
      (250, 150, 'больше чем вдвое'), // 150 %
    ]) {
      expect(t(c.$1, c.$2), startsWith('за опыт оплата ${c.$3} ('),
          reason: '${c.$1}/${c.$2}');
    }
    for (final (int, int) c in <(int, int)>[
      (141, 1), (110, 10), (150, 50), (300, 200),
    ]) {
      expect(t(c.$1, c.$2), isNot(matches(RegExp('%|процент|—|монетк'))));
    }
  });

  test('«монета / монеты / монет»', () {
    expect(Phrases.coinsNom(1), 'монета');
    expect(Phrases.coinsNom(2), 'монеты');
    expect(Phrases.coinsNom(5), 'монет');
    expect(Phrases.coinsNom(11), 'монет');
    expect(Phrases.coinsNom(21), 'монета');
    expect(Phrases.coinsNom(22), 'монеты');
    expect(Phrases.coinsNom(112), 'монет');
  });
}
