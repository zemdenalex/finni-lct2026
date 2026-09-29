import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/economy/purchase_rules.dart';
import 'package:finlit/domain/ledger/ledger_fold.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/phrases.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_content.dart';

/// 🔴 Класс дефектов, который виден только в собранной фразе.
///
/// Тексты склеиваются из шаблона и подставленного значения, и каждый кусок
/// по отдельности выглядит правильно. На экране при этом появлялось
/// «настроение почти полная» и «Мячик — 2 монеток»: числа и род согласуются
/// только в готовом предложении, а его до запуска на устройстве никто
/// не читал.
void main() {
  late GameContent content;

  setUpAll(() async {
    content = await loadRealContent();
  });

  test('число и «монетка» согласованы во всех текстах', () {
    // Показательные числа: 1 — «монетка», 2–4 — «монетки», 5+ и 11–14 —
    // «монеток». Именно на 2 и появлялось «2 монеток».
    const Map<int, String> expected = <int, String>{
      1: 'монетка',
      2: 'монетки',
      3: 'монетки',
      5: 'монеток',
      11: 'монеток',
      12: 'монеток',
      21: 'монетка',
      22: 'монетки',
      25: 'монеток',
      100: 'монеток',
      101: 'монетка',
    };
    expected.forEach((int n, String word) {
      expect(Phrases.coinWord(n), word, reason: 'число $n');
    });
  });

  test('ни один текст не приписывает число к слову вручную', () {
    // Вручную написанное «{price} монеток» не склоняется никогда.
    final RegExp handwritten = RegExp(r'\{\w+\}\s+монет\w*');
    final List<String> bad = <String>[];
    content.copy.forEach((String key, String template) {
      if (handwritten.hasMatch(template)) bad.add('$key: «$template»');
    });
    expect(bad, isEmpty,
        reason: 'число рядом со словом без согласования:\n${bad.join('\n')}');
  });

  test('готовые фразы о показателях согласованы по роду', () {
    // Собираем предупреждение для каждого показателя на максимуме и
    // проверяем, что прилагательное согласовано с существительным.
    const Map<Meter, String> agreement = <Meter, String>{
      Meter.fullness: 'сытость уже полная',
      Meter.cleanliness: 'чистота уже полная',
      Meter.mood: 'настроение уже отличное',
    };

    agreement.forEach((Meter m, String phrase) {
      final CatalogItem item = content.catalog.firstWhere(
        (CatalogItem i) => i.effect.byMeter(m) > 0,
        orElse: () => content.catalog.first,
      );
      if (item.effect.byMeter(m) <= 0) return;

      final PurchaseDecision d = PurchaseRules.check(
        item: item,
        wallet: Wallet(
          envelopes: const Allocation(needs: 99, wants: 99, savings: 99),
          savings: 0,
          unallocated: 0,
        ),
        meters: const PetMeters(fullness: 10, cleanliness: 10, mood: 10),
        hasAvailableTask: false,
      );
      expect(d.wastedWarning, isNotNull);
      expect(d.wastedWarning!.toLowerCase(), contains(phrase),
          reason: 'род не согласован: «${d.wastedWarning}»');
    });
  });

  test('в предупреждении нет местоимения, которое не согласуется', () {
    // «Эта покупка её не изменит» ломается на «настроении».
    for (final CatalogItem item in content.catalog) {
      final PurchaseDecision d = PurchaseRules.check(
        item: item,
        wallet: Wallet(
          envelopes: const Allocation(needs: 99, wants: 99, savings: 99),
          savings: 0,
          unallocated: 0,
        ),
        meters: const PetMeters(fullness: 10, cleanliness: 10, mood: 10),
        hasAvailableTask: false,
      );
      final String? w = d.wastedWarning;
      if (w == null) continue;
      expect(w.contains(' её '), isFalse, reason: w);
      expect(w.contains(' его '), isFalse, reason: w);
    }
  });
}
