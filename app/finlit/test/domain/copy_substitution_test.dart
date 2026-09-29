import 'package:finlit/domain/content.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_content.dart';

/// Проигрывает партию так, чтобы в журнале встретился каждый вид записи.
///
/// 🔴 Этот тест существует из-за настоящего дефекта: поконвертные записи
/// плана переиспользовали ключ `plan.confirmed`, но передавали пустые
/// подстановки — и на экране «Итоги недели» ребёнок видел сырой шаблон
/// «Нужное {needs}, Хочу {wants}, Копилка {savings}». Сто три теста этого
/// не заметили, потому что проверяли наличие ключа, а не то, что текст
/// после подстановки стал текстом.
Game _playEverything(GameContent content, {required bool deferUnexpected}) {
  final Game g = Game(
    content: content,
    profile: GameProfile.fresh(isDemo: true),
  );
  g.chooseGoal('scooter');

  for (int week = 1; week <= 3; week++) {
    g.startPeriod();

    final CatalogItem need =
        content.catalog.firstWhere((CatalogItem i) => i.isNeed);
    final int income = g.snapshot.wallet.unallocated;
    g.confirmPlan(Allocation(
      needs: need.price,
      wants: 1,
      savings: income - need.price - 1,
    ));

    // Задание: и награда, и разблокировка взрослым.
    final GameTask task = content.tasks[week % content.tasks.length];
    g.completeTask(task, best: week.isOdd);
    g.allocate(Envelope.savings, g.snapshot.wallet.unallocated);
    g.parentUnlockTask();

    g.buy(need);

    // Список ожидания: отложить, а на следующей неделе — оба ответа.
    final List<CatalogItem> waitable = content.catalog
        .where((CatalogItem i) => g.canWait(i))
        .toList();
    for (final CatalogItem i in waitable.take(2)) {
      g.addToWishList(i);
    }
    // Отвечаем на всё созревшее, чередуя оба ответа. Считать через
    // ripeWishes.length нельзя: список укорачивается на каждом ответе.
    int answered = 0;
    while (g.ripeWishes.isNotEmpty) {
      final CatalogItem i = g.ripeWishes.first;
      if (answered.isEven) {
        g.keepWish(i);
      } else {
        g.dropWish(i);
      }
      answered++;
    }

    // Отказ от покупки и покупка, на которую не хватает.
    final CatalogItem want = content.catalog
        .where((CatalogItem i) => !i.isNeed)
        .reduce((CatalogItem a, CatalogItem b) => a.price > b.price ? a : b);
    g.declinePurchase(want);
    g.buy(want);

    // Перекладывание между конвертами и оба направления копилки.
    g.move(from: Envelope.needs, to: Envelope.wants, amount: 1);
    g.move(from: Envelope.wants, to: Envelope.savings, amount: 1);
    g.move(from: Envelope.savings, to: Envelope.needs, amount: 1);

    // Непредвиденный расход случается ровно на третьей неделе, и у него два
    // исхода. Один прогон покрывает только один — поэтому прогонов два.
    if (g.unexpectedPending) {
      if (deferUnexpected) {
        g.deferUnexpected();
      } else {
        g.payUnexpected(Envelope.savings);
      }
    }
    g.closePeriod();
  }

  // Исполнить мечту: копилку дотягиваем до цены прямо переводом, чтобы
  // прогон не зависел от того, сколько успели отложить за три недели.
  g.startPeriod();
  final int need = g.goal!.price - g.snapshot.wallet.savings;
  if (need > 0) {
    for (final GameTask t in content.tasks) {
      g.completeTask(t, best: true);
    }
    final int free = g.snapshot.wallet.unallocated;
    g.allocate(Envelope.savings, free < need ? free : need);
  }
  if (g.goalReached) g.fulfillGoal();
  return g;
}

/// Журналы обоих исходов непредвиденного расхода, слитые в один список.
List<LedgerEntry> _bothOutcomes(GameContent content) => <LedgerEntry>[
      ..._playEverything(content, deferUnexpected: false).ledger,
      ..._playEverything(content, deferUnexpected: true).ledger,
    ];

void main() {
  late GameContent content;

  setUpAll(() async {
    content = await loadRealContent();
  });

  test('ни одна запись журнала не показывает ребёнку сырой шаблон', () {
    final List<LedgerEntry> ledger = _bothOutcomes(content);
    expect(ledger, isNotEmpty);

    final List<String> raw = <String>[];
    for (final LedgerEntry e in ledger) {
      final String text = content.say(e.reasonCode, e.args);
      if (text.contains('{') || text.contains('}')) {
        raw.add('${e.reasonCode} → «$text» (подстановки: ${e.args})');
      }
      if (text == e.reasonCode) {
        raw.add('${e.reasonCode} → текста нет, показан сам ключ');
      }
    }
    expect(raw, isEmpty,
        reason: 'нерасставленные подстановки:\n${raw.join('\n')}');
  });

  test('проверка покрывает все виды записей журнала', () {
    final Set<LedgerKind> seen =
        _bothOutcomes(content).map((LedgerEntry e) => e.kind).toSet();
    final Set<LedgerKind> missing =
        LedgerKind.values.toSet().difference(seen);
    expect(missing, isEmpty,
        reason: 'партия не порождает записи вида $missing — '
            'проверка подстановок молча перестала их проверять');
  });

  test('каждая подстановка в copy.json кем-то заполняется', () {
    final Map<String, Set<String>> supplied = <String, Set<String>>{};
    for (final LedgerEntry e in _bothOutcomes(content)) {
      supplied
          .putIfAbsent(e.reasonCode, () => <String>{})
          .addAll(e.args.keys);
    }

    final RegExp placeholder = RegExp(r'\{(\w+)\}');
    final List<String> gaps = <String>[];
    supplied.forEach((String code, Set<String> args) {
      final String template = content.copy[code] ?? '';
      for (final RegExpMatch m in placeholder.allMatches(template)) {
        final String name = m.group(1)!;
        if (!args.contains(name)) {
          gaps.add('$code: шаблон ждёт {$name}, движок его не передаёт');
        }
      }
    });
    expect(gaps, isEmpty, reason: gaps.join('\n'));
  });
}
