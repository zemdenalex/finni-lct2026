import '../models/envelope.dart';
import '../models/pet.dart';
import 'economy_config.dart';

/// Одно очко заботы и причина, по которой оно дано или не дано.
class CarePoint {
  const CarePoint({
    required this.id,
    required this.title,
    required this.earned,
    required this.explanation,
  });

  final String id;
  final String title;
  final bool earned;

  /// Объяснение — и когда очко дано, и когда нет. §2.5.8.3 и §2.2.
  /// 🔴 Формулировки без рода: «ты не забыл», «ты потратил» говорили
  /// с мальчиком, а играет любой ребёнок. Безличная форма ничего не теряет.
  ///
  /// Формулировки без «ты не справился»: см. таблицу тона в
  /// docs/karta-obrazovatelnogo-kontenta.md.
  final String explanation;
}

/// Расхождение факта с планом по одному конверту.
class EnvelopeDeviation {
  const EnvelopeDeviation({
    required this.envelope,
    required this.planned,
    required this.actual,
    required this.withinNorm,
  });

  final Envelope envelope;
  final int planned;
  final int actual;
  final bool withinNorm;

  int get delta => actual - planned;
}

/// Итог игровой недели.
class PeriodOutcome {
  const PeriodOutcome({
    required this.points,
    required this.carePoints,
    required this.deviations,
    required this.metersDelta,
  });

  final int points;
  final List<CarePoint> carePoints;
  final List<EnvelopeDeviation> deviations;

  /// Суммарное изменение показателей при закрытии недели: затухание плюс
  /// прибавки за задания и за взнос в копилку.
  final PetMeters metersDelta;
}

class PeriodRules {
  const PeriodRules._();

  /// 🔴 Отклонение считается **асимметрично**, и это не мелочь.
  ///
  /// Термины ТЗ про необязательные расходы: «Отказ от такой покупки или
  /// перенос её на следующий игровой период допустимы и **не считаются
  /// ошибкой пользователя**». Симметричный модуль отклонения наказывал бы
  /// ребёнка ровно за то поведение, которое ТЗ объявило не-ошибкой, —
  /// то есть механически побуждал бы тратить.
  ///
  /// Поэтому: по «Нужному» и «Хочу» нарушением считается только перерасход,
  /// по «Копилке» — только недовложение.
  static bool withinNorm({
    required Envelope envelope,
    required int planned,
    required int actual,
    required int tolerance,
  }) {
    final int delta = actual - planned;
    return switch (envelope) {
      Envelope.needs || Envelope.wants => delta <= tolerance,
      Envelope.savings => -delta <= tolerance,
    };
  }

  static PeriodOutcome close({
    required EconomyConfig config,
    required Allocation plan,
    required Allocation fact,
    required PetMeters metersAtClose,
    required int tasksCompleted,
    required int depositedThisPeriod,
    required bool boughtNeedsSoFar,
  }) {
    final List<EnvelopeDeviation> deviations = Envelope.values
        .map((Envelope e) => EnvelopeDeviation(
              envelope: e,
              planned: plan.byEnvelope(e),
              actual: fact.byEnvelope(e),
              withinNorm: withinNorm(
                envelope: e,
                planned: plan.byEnvelope(e),
                actual: fact.byEnvelope(e),
                tolerance: config.planTolerance,
              ),
            ))
        .toList();

    // 🔴 Очко — за решение ребёнка, а не за стартовый запас шкал. Финни
    // начинает сытым (startMeters 7 при пороге 4), и до 23.09 первая неделя
    // давала «Нужное закрыто» без единой покупки: итог хвалил «по плану 0,
    // вышло 0 — как задумано» ровно на той неделе, которую эксперт видит
    // первой.
    //
    // Условие — «хоть раз покупал нужное», а не «покупал на этой неделе»:
    // овощей хватает на две недели, купания — на три, и оптовая закупка
    // дешевле (economy_walkthrough_test). Недельное условие наказывало бы
    // ровно тот расчёт, которому игра учит.
    final bool metersOk = metersAtClose.needsCovered(config.needsThreshold);
    final bool needsCovered = metersOk && boughtNeedsSoFar;
    final bool planKept =
        deviations.every((EnvelopeDeviation d) => d.withinNorm);
    final bool saved = depositedThisPeriod > 0;

    final List<CarePoint> points = <CarePoint>[
      CarePoint(
        id: 'needs',
        title: 'Нужное закрыто',
        earned: needsCovered,
        explanation: needsCovered
            ? 'Финни сыт и в чистоте — главное не забыто.'
            : metersOk
                ? 'Финни пока сыт с самого начала, но из «Нужного» ещё '
                    'ничего не куплено. Скоро еда закончится — начни с неё.'
                : 'На этой неделе Финни не хватило еды или уборки. '
                    'На следующей положи в «Нужное» чуть больше.',
      ),
      CarePoint(
        id: 'plan',
        title: 'План сошёлся',
        earned: planKept,
        explanation: planKept
            ? 'Потрачено примерно столько, сколько было задумано.'
            : 'В одном конверте ушло больше, чем было в плане. '
                'Так бывает — посмотри, где именно, и учти это в новом плане.',
      ),
      CarePoint(
        id: 'saved',
        title: 'Отложено',
        earned: saved,
        explanation: saved
            ? 'В копилку отложено $depositedThisPeriod — цель стала ближе.'
            : 'На этой неделе в копилку ничего не ушло. '
                'Даже одна монетка приближает цель.',
      ),
    ];

    final int earned = points.where((CarePoint p) => p.earned).length;

    final int moodFromTasks =
        (tasksCompleted * config.moodPerTask).clamp(0, config.maxMoodFromTasks);
    final int moodFromSaving = saved ? config.moodPerDeposit : 0;

    return PeriodOutcome(
      points: earned,
      carePoints: points,
      deviations: deviations,
      metersDelta: PetMeters(
        fullness: config.decay.fullness,
        cleanliness: config.decay.cleanliness,
        mood: config.decay.mood + moodFromTasks + moodFromSaving,
      ),
    );
  }
}
