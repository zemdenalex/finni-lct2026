import 'contract.dart';

/// Причина настроения Финни (карточка A12, ТЗ 2.5.10.3) — общая для
/// `WorldGame` и `FakeWorld`.
///
/// Правило: последнее, что **изменило** 😊 или **закрыло неделю**, объясняет
/// настроение. [causeCode] — код причины, [causeDelta] — на сколько 😊
/// изменилось.
///
/// Причины, которые называются даже без изменения 😊 (в файле
/// `energy.exhausted.happiness` = 0, а нехватка без помощи семьи 😊 не
/// штрафует):
/// - `week.energy_out` — силы кончились → `mood.tired`;
/// - итоги недели по старшинству: `bills.family_help` → `bills.from_goal`
///   (нехватку закрыли из копилки) → `bills.downgraded` (на еду не хватило,
///   взяли простую) → `week.stagnation` (неделя без роста, P7) →
///   `week.tired` (неделя кончилась по ⚡) → `week.growth` (неделя роста, P7).
///
/// Обычные итоги недели (`week.closed`) без изменения 😊 причиной не
/// считаются: тогда фраза по уровню 😊, прошлая неделя не тянется.
///
/// `day.passed` (P7: игровой день тратит 😊) пишется перед самим действием,
/// поэтому причиной становится, только если действие 😊 не изменило —
/// например, обычная смена.
MoodReason moodReasonFor({
  required int happiness,
  required WeekPhase phase,
  String? causeCode,
  int causeDelta = 0,
}) {
  if (causeCode != null) {
    final bool up = causeDelta > 0;
    final bool changed = causeDelta != 0;
    final MoodReason? cause = switch (causeCode) {
      // Называются всегда.
      'week.energy_out' =>
        const MoodReason('mood.tired', 'Силы кончились — Финни устал.'),
      'bills.family_help' => const MoodReason('mood.family_help',
          'Семье пришлось помочь со счетами — Финни неловко.'),
      'bills.from_goal' => const MoodReason('mood.shortfall_goal',
          'На счета не хватило — пришлось взять из копилки. Финни переживает.'),
      'bills.downgraded' => const MoodReason(
          'mood.shortfall_food', 'На счета не хватило — Финни ел простую еду.'),
      'week.tired' => const MoodReason('mood.tired_week',
          'Силы кончились раньше сна — Финни не отдохнул как следует.'),
      // Рост и застой называются, только если не спорят с лицом Финни:
      // неделя роста, после которой 😊 всё же упало, — «остыла»; застой, после
      // которого 😊 выросло, — «удалась». Итог роста всё равно есть в
      // итогах недели (`payBills.reason`).
      'week.stagnation' => up
          ? _weekGood
          : const MoodReason(
              'mood.stagnation',
              'Неделя прошла так же, как прошлая, — Финни заскучал. Заработать '
                  'больше, отложить на цель или купить мечту — и станет '
                  'веселее.'),
      'week.growth' => causeDelta < 0
          ? _cooling
          : const MoodReason('mood.growth',
              'Финни растёт: эта неделя лучше прошлой — и это радует!'),
      // Остальные — только если 😊 изменилось.
      _ when !changed => null,
      // Последствия выбора в событии (`event.*`) — те же причины, что у
      // обычных досуга и покупок: последней 😊 меняет именно эта запись.
      'leisure.done' ||
      'event.leisure' =>
        const MoodReason('mood.leisure', 'Финни отдохнул — настроение лучше.'),
      'buy.goal' ||
      'event.goal_discount' =>
        const MoodReason('mood.goal', 'Цель достигнута — Финни очень рад!'),
      'buy.item' ||
      'event.buy' =>
        const MoodReason('mood.new_thing', 'Обновка радует Финни.'),
      'pet.tap' =>
        const MoodReason('mood.pet', 'Питомец рядом — Финни веселее.'),
      'meal.eaten' => up
          ? const MoodReason(
              'mood.meal', 'Финни вкусно поел — настроение лучше.')
          : null,
      'day.passed' => const MoodReason(
          'mood.days',
          'Дни идут — радость понемногу тратится, как силы. Отдых, питомец '
              'или обновка её вернут.'),
      'sleep.bonus' =>
        const MoodReason('mood.slept', 'Финни выспался — настроение лучше.'),
      'job.payout' => up
          ? null
          : const MoodReason(
              'mood.hard_shift', 'Финни постарался на смене и немного устал.'),
      'week.closed' => up ? _weekGood : _cooling,
      'event.choice' => up
          ? const MoodReason(
              'mood.event_good', 'Финни доволен тем, как всё вышло.')
          : const MoodReason('mood.event_bad',
              'Финни немного расстроен из-за того, что случилось.'),
      _ => null,
    };
    if (cause != null) return cause;
  }
  if (phase == WeekPhase.onboarding) {
    return const MoodReason(
        'mood.new_home', 'Финни только переехал — всё новое и интересно.');
  }
  if (happiness >= 70) {
    return const MoodReason('mood.high', 'Финни в отличном настроении.');
  }
  if (happiness <= 30) {
    return const MoodReason('mood.low',
        'Финни грустно. Отдых, питомец или обновка поднимут настроение.');
  }
  return MoodReason.neutral;
}

const MoodReason _weekGood = MoodReason(
    'mood.week_good', 'Неделя удалась: еда, дом и питомцы радуют Финни.');

const MoodReason _cooling = MoodReason(
    'mood.cooling',
    'Неделя прошла, и радость немного остыла. Отдых, питомец или обновка её '
        'вернут.');

/// Код причины настроения для итогов недели — одно правило старшинства для
/// свёртки журнала и `FakeWorld`.
///
/// [growth] — итог проверки роста (P7): `up`, `flat` или null (неделя 1 —
/// сравнивать не с чем).
String weekClosedMoodCause({
  required int fromFamily,
  required int fromGoal,
  required bool downgraded,
  required WeekEnd? endedBy,
  String? growth,
}) {
  if (fromFamily > 0) return 'bills.family_help';
  if (fromGoal > 0) return 'bills.from_goal';
  if (downgraded) return 'bills.downgraded';
  if (growth == weekGrowthFlat) return 'week.stagnation';
  if (endedBy == WeekEnd.energyOut) return 'week.tired';
  if (growth == weekGrowthUp) return 'week.growth';
  return 'week.closed';
}

/// Итог проверки роста в `periodClosed.args.growth` (P7).
const String weekGrowthUp = 'up';
const String weekGrowthFlat = 'flat';
