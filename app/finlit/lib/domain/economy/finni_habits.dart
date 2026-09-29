import '../models/envelope.dart';

/// Раскладка, которую Финни предлагает сам, и его слова о ней.
class FinniProposal {
  const FinniProposal({required this.plan, required this.says});

  final Allocation plan;
  final String says;
}

/// «Финни сам раскладывает монетки по конвертам» — обещание стадии
/// «Хранитель копилки» (`PetStage.planner`).
///
/// Финни не знает правильного ответа: он **повторяет привычку ребёнка** —
/// доли последних планов, перенесённые на сегодняшнюю сумму. Хорошую
/// привычку он повторит, и не очень хорошую тоже. Это эффект протеже
/// из docs/etika-i-motivaciya.md, развёрнутый в зеркало: ребёнок видит свой
/// способ раскладывать со стороны, в чужих лапах.
///
/// 🔴 Раскладка ничего не подтверждает. Она заполняет черновик, ребёнок
/// правит его и подтверждает сам: решение остаётся за ним (§2.5.5.3).
class FinniHabits {
  const FinniHabits._();

  /// Сколько последних недель Финни помнит. Три — чтобы одна неудачная
  /// неделя не стала «привычкой».
  static const int memory = 3;

  static FinniProposal? propose({
    required Map<int, Allocation> plans,
    required int periodNo,
    required int available,
  }) {
    if (available <= 0) return null;
    final List<Allocation> recent = (plans.entries
            .where((MapEntry<int, Allocation> e) =>
                e.key < periodNo && e.value.total > 0)
            .toList()
          ..sort((MapEntry<int, Allocation> a, MapEntry<int, Allocation> b) =>
              b.key.compareTo(a.key)))
        .take(memory)
        .map((MapEntry<int, Allocation> e) => e.value)
        .toList();
    if (recent.isEmpty) return null;

    int sum(Envelope e) =>
        recent.fold<int>(0, (int a, Allocation p) => a + p.byEnvelope(e));
    final int total = sum(Envelope.needs) + sum(Envelope.wants) +
        sum(Envelope.savings);

    // Метод наибольших остатков: сумма всегда сходится с тем, что есть,
    // а доли расходятся с привычкой не больше чем на одну монетку.
    final Map<Envelope, int> whole = <Envelope, int>{};
    final Map<Envelope, double> rest = <Envelope, double>{};
    for (final Envelope e in Envelope.values) {
      final double exact = available * sum(e) / total;
      whole[e] = exact.floor();
      rest[e] = exact - exact.floor();
    }
    int left = available - whole.values.fold<int>(0, (int a, int b) => a + b);
    // При равных остатках первым идёт «Нужное», потом «Копилка». Порядок
    // задан явно: сортировка в Dart не обязана быть устойчивой.
    const List<Envelope> priority = <Envelope>[
      Envelope.needs,
      Envelope.savings,
      Envelope.wants,
    ];
    final List<Envelope> order = List<Envelope>.of(priority)
      ..sort((Envelope a, Envelope b) {
        final int byRest = rest[b]!.compareTo(rest[a]!);
        return byRest != 0
            ? byRest
            : priority.indexOf(a).compareTo(priority.indexOf(b));
      });
    for (final Envelope e in order) {
      if (left == 0) break;
      whole[e] = whole[e]! + 1;
      left--;
    }

    final Allocation plan = Allocation(
      needs: whole[Envelope.needs]!,
      wants: whole[Envelope.wants]!,
      savings: whole[Envelope.savings]!,
    );
    return FinniProposal(plan: plan, says: _says(plan, sum, total));
  }

  /// Финни называет привычку, а не оценивает её: ни «молодец», ни «зря».
  static String _says(
      Allocation plan, int Function(Envelope) sum, int total) {
    const String lead = 'Я разложил, как обычно делаешь ты.';
    if (sum(Envelope.needs) == 0) {
      return '$lead В «Нужное» ты обычно ничего не кладёшь — и я не положил. '
          'Посмотри, хватит ли мне еды на неделю.';
    }
    if (sum(Envelope.savings) * 10 >= total * 3) {
      return '$lead Ты обычно откладываешь — и я отложил ${plan.savings}.';
    }
    if (sum(Envelope.wants) * 2 > total) {
      return '$lead Больше всего — в «Хочу», как у тебя. '
          'А мечта при этом ждёт.';
    }
    return '$lead Сначала «Нужное», остальное — как у тебя.';
  }
}
