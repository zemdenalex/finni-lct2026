import 'dart:math';

import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart';
import 'package:finlit/domain/ledger/ledger_fold.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Тест, который назван в `lib/domain/ledger/ledger_fold.dart` как сторож
/// центрального архитектурного решения проекта: баланс, накопления и
/// показатели питомца нигде не хранятся числом — они получаются свёрткой
/// журнала. До сих пор этот файл существовал только в комментарии.
///
/// Требование ТЗ §2.5.4.3: баланс не меняется без объяснения. Оно выполнимо
/// ровно потому, что изменить баланс иначе, чем добавив запись с причиной,
/// технически невозможно.

/// Случайная, местами заведомо некорректная партия.
Game _fuzz(GameContent content, int seed) {
  final Random rnd = Random(seed);
  final Game g = Game(
    content: content,
    profile: GameProfile.fresh(isDemo: true),
  );
  g.chooseGoal(content.goals.first.id);

  for (int step = 0; step < 120; step++) {
    final int amount = rnd.nextInt(30) - 5; // в том числе отрицательные
    final Envelope from = Envelope.values[rnd.nextInt(Envelope.values.length)];
    final Envelope to = Envelope.values[rnd.nextInt(Envelope.values.length)];
    switch (rnd.nextInt(9)) {
      case 0:
        g.startPeriod();
      case 1:
        g.confirmPlan(Allocation(
          needs: rnd.nextInt(20) - 3,
          wants: rnd.nextInt(20) - 3,
          savings: rnd.nextInt(20) - 3,
        ));
      case 2:
        g.allocate(to, amount);
      case 3:
        final CatalogItem item = content.catalog[rnd.nextInt(content.catalog.length)];
        if (rnd.nextBool()) {
          g.buy(item);
        } else {
          g.declinePurchase(item);
        }
      case 4:
        g.move(from: from, to: to, amount: amount);
      case 5:
        g.payUnexpected(from);
      case 6:
        g.deferUnexpected();
      case 7:
        g.completeTask(content.tasks[rnd.nextInt(content.tasks.length)],
            best: rnd.nextBool());
      case 8:
        g.closePeriod();
    }

    // §2.5.6.4: отрицательного баланса не бывает ни при каком вводе.
    final Wallet w = g.snapshot.wallet;
    expect(w.unallocated, greaterThanOrEqualTo(0), reason: 'шаг $step');
    expect(w.savings, greaterThanOrEqualTo(0), reason: 'шаг $step');
    for (final Envelope e in <Envelope>[
      Envelope.needs,
      Envelope.wants,
      Envelope.savings,
    ]) {
      expect(w.envelopes.byEnvelope(e), greaterThanOrEqualTo(0),
          reason: 'конверт ${e.title}, шаг $step');
    }
  }
  return g;
}

void main() {
  late GameContent content;

  setUpAll(() async {
    content = await loadRealContent();
  });

  test('профиль не хранит ни одного числа о деньгах', () {
    final Map<String, Object?> json = GameProfile.fresh(isDemo: false).toJson();
    const List<String> forbidden = <String>[
      'balance',
      'coins',
      'savings',
      'wallet',
      'unallocated',
      'needs',
      'wants',
    ];
    for (final String key in json.keys) {
      final String lower = key.toLowerCase();
      for (final String bad in forbidden) {
        expect(lower.contains(bad), isFalse,
            reason: 'поле «$key» кеширует деньги мимо журнала — '
                'после этого баланс сможет измениться без причины');
      }
    }
  });

  test('состояние — функция журнала: пересборка даёт то же самое', () {
    for (int seed = 0; seed < 40; seed++) {
      final Game g = _fuzz(content, seed);
      final GameSnapshot live = g.snapshot;

      // Свёртка тех же записей с нуля обязана совпасть до монетки.
      final GameSnapshot rebuilt = LedgerFold.fold(
        g.ledger,
        startMeters: content.economy.startMeters,
        carePoints: g.profile.carePoints,
      );
      expect(rebuilt.wallet.unallocated, live.wallet.unallocated);
      expect(rebuilt.wallet.savings, live.wallet.savings);
      expect(rebuilt.periodNo, live.periodNo);
      expect(rebuilt.stage, live.stage);
      expect(rebuilt.meters.fullness, live.meters.fullness);
    }
  });

  test('сохранение и загрузка не теряют ни одной причины', () {
    final Game g = _fuzz(content, 777);
    final Game restored = Game.fromJson(g.toJson(), content);

    expect(restored.ledger.length, g.ledger.length);
    for (int i = 0; i < g.ledger.length; i++) {
      expect(restored.ledger[i].reasonCode, g.ledger[i].reasonCode);
      expect(restored.ledger[i].kind, g.ledger[i].kind);
    }
    expect(restored.snapshot.wallet.savings, g.snapshot.wallet.savings);
  });

  test('§2.5.4.3 у каждой записи журнала есть причина', () {
    final Game g = _fuzz(content, 13);
    expect(g.ledger, isNotEmpty);
    for (final LedgerEntry e in g.ledger) {
      expect(e.reasonCode.trim(), isNotEmpty);
      expect(content.copy.containsKey(e.reasonCode), isTrue,
          reason: 'причина «${e.reasonCode}» не имеет текста в copy.json');
    }
  });
}
