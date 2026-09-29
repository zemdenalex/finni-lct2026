import '../ledger/ledger_fold.dart';
import '../models/catalog_item.dart';
import '../models/envelope.dart';
import '../models/pet.dart';

/// Почему покупка невозможна и что можно сделать вместо запрета.
enum ShortfallOption {
  /// Переложить недостающее из другого конверта. Показывается вместе с ценой:
  /// на сколько недель отодвинется цель.
  moveFromSavings,
  moveFromNeeds,
  moveFromWants,

  /// Заработать: выполнить задание.
  doTask,

  /// Отложить покупку до следующей недели. Термины ТЗ: перенос покупки
  /// «допустим и не считается ошибкой пользователя» — поэтому этот вариант
  /// стоит в списке наравне с остальными, а не последним «сдаться».
  waitForNextWeek,
}

/// Решение о покупке (§2.5.6).
class PurchaseDecision {
  const PurchaseDecision._({
    required this.allowed,
    required this.shortfall,
    required this.options,
    required this.wastedWarning,
  });

  final bool allowed;

  /// Сколько монеток не хватает в нужном конверте.
  final int shortfall;

  /// Что предлагается вместо запрета (§2.5.6.4: «приложение объясняет,
  /// чего не хватает и какие есть варианты»).
  final List<ShortfallOption> options;

  /// Показатель уже на максимуме, и покупка почти ничего не даст.
  ///
  /// Не запрет — сообщение о последствии. §2.5.6.2 требует показать до
  /// покупки предполагаемое влияние на питомца, и это ровно оно.
  ///
  /// 🔴 Здесь описывается ПОСЛЕДСТВИЕ, но не оценивается РЕШЕНИЕ. Раньше
  /// стояло «монетки уйдут зря» — то есть приговор трате до того, как
  /// ребёнок её совершил. Это лишает его единственного настоящего урока:
  /// вся практика семейного финансового воспитания сходится на том, что
  /// роль взрослого — не чинить ошибку, а дать её пережить, пока цена
  /// вопроса измеряется монетками. Слово «зря» выносит ребёнку оценку
  /// вместо факта — см. docs/chemu-uchit-i-pochemu.md §3.3.
  final String? wastedWarning;

  static const PurchaseDecision ok = PurchaseDecision._(
    allowed: true,
    shortfall: 0,
    options: <ShortfallOption>[],
    wastedWarning: null,
  );
}

class PurchaseRules {
  const PurchaseRules._();

  /// 🔴 Отрицательный баланс невозможен по построению: покупка разрешается
  /// только если в конверте хватает монеток (§2.5.6.4).
  static PurchaseDecision check({
    required CatalogItem item,
    required Wallet wallet,
    required PetMeters meters,
    required bool hasAvailableTask,
  }) {
    final int inEnvelope = wallet.envelopes.byEnvelope(item.envelope);
    final int shortfall = item.price - inEnvelope;

    final String? wasted = _wastedWarning(item, meters);

    if (shortfall <= 0) {
      return PurchaseDecision._(
        allowed: true,
        shortfall: 0,
        options: const <ShortfallOption>[],
        wastedWarning: wasted,
      );
    }

    final List<ShortfallOption> options = <ShortfallOption>[];
    if (wallet.savings >= shortfall) options.add(ShortfallOption.moveFromSavings);
    for (final Envelope other in Envelope.values) {
      if (other == item.envelope || other == Envelope.savings) continue;
      if (wallet.envelopes.byEnvelope(other) >= shortfall) {
        options.add(other == Envelope.needs
            ? ShortfallOption.moveFromNeeds
            : ShortfallOption.moveFromWants);
      }
    }
    if (hasAvailableTask) options.add(ShortfallOption.doTask);
    options.add(ShortfallOption.waitForNextWeek);

    return PurchaseDecision._(
      allowed: false,
      shortfall: shortfall,
      options: options,
      wastedWarning: wasted,
    );
  }

  static String? _wastedWarning(CatalogItem item, PetMeters meters) {
    for (final Meter m in Meter.values) {
      final int effect = item.effect.byMeter(m);
      if (effect <= 0) continue;
      final int current = meters.byMeter(m);
      final int usable = PetMeters.max - current;
      if (usable == 0) {
        // Без местоимения: «её» не согласуется с «настроением».
        return 'У Финни ${m.title.toLowerCase()} уже ${m.atMax}. '
            'Эта покупка ничего не добавит.';
      }
      if (usable < effect) {
        return 'У Финни ${m.title.toLowerCase()} почти ${m.atMax}. '
            'Пригодится только часть покупки.';
      }
    }
    return null;
  }
}
