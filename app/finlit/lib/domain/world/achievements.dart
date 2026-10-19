/// Награды и прогресс (решение Дениса D3, 15.10).
///
/// Награда — правило из контента (`economy.json → achievements`): что
/// считается ([metric]) и сколько нужно ([target]). Прогресс считается из
/// журнала (свёртка), получение — запись `achievementEarned`: один раз на
/// награду, переживает перезапуск, повторно не засчитывается.
library;

/// Что считает награда. Строки — те же, что в `economy.json`.
enum AchievementMetric {
  /// Отработано смен всего.
  shifts('shifts'),

  /// Смен на «хорошо» (опыт).
  goodShifts('good_shifts'),

  /// Куплено целей из копилки (питомцы, транспорт, техника, жильё).
  goalsBought('goals_bought'),

  /// Недель, закрытых без помощи семьи.
  weeksNoFamilyHelp('weeks_no_family_help'),

  /// Недель подряд без помощи семьи (сейчас).
  noFamilyStreak('no_family_streak'),

  /// Больше всего монет в копилке за игру.
  goalSavedMax('goal_saved_max'),

  /// Уроков после смен пройдено.
  lessonsDone('lessons_done'),

  /// Питомцев заведено.
  petsOwned('pets_owned'),

  /// Стадия: 1 — город, 2 — Москва.
  stage('stage'),

  // ── Режим дней (C7, флаг `achievements_days`) ──

  /// Разных работ, на которых была хоть одна смена.
  distinctJobs('distinct_jobs'),

  /// Смен с удачей (сценарий везения `good`).
  luckyShifts('lucky_shifts'),

  /// Ответов на вопрос в смене (мини-решение).
  shiftChoices('shift_choices'),

  /// Прожитых игровых дней (утр: начало недели и каждое новое утро).
  daysPlayed('days_played'),

  /// Дней, в которые была хоть одна смена.
  workDays('work_days');

  const AchievementMetric(this.key);
  final String key;

  static AchievementMetric? byKey(String key) {
    for (final AchievementMetric m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// Правило награды из контента.
/// Что даёт награда сверх самой награды (DEN-32, Денис 18.10): баффы.
sealed class AchievementEffect {
  const AchievementEffect();
}

/// Временный: +[happiness] 😊 сразу и ещё столько же каждое утро, всего
/// [days] игровых дней подряд (день получения — первый).
final class MoodBuff extends AchievementEffect {
  const MoodBuff({required this.happiness, required this.days});
  final int happiness;
  final int days;
}

/// Постоянный: предел ⚡ больше на [value] навсегда (и сон добирает до него).
final class EnergyMaxBuff extends AchievementEffect {
  const EnergyMaxBuff({required this.value});
  final double value;
}

class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.topic,
    required this.hint,
    required this.metric,
    required this.target,
    this.effect,
  });

  /// Бафф награды (`effect` в контенте) или null — награда без баффа.
  final AchievementEffect? effect;

  final String id;
  final String title;

  /// Тема для экрана: `work`, `money`, `knowledge`, `finni`.
  final String topic;

  /// Что сделать — одной фразой («Отработай одну смену»).
  final String hint;
  final AchievementMetric metric;
  final int target;
}

/// Состояние награды на экране.
enum AchievementStatus {
  /// Получена.
  earned,

  /// Прогресс есть, цель не достигнута.
  inProgress,

  /// Прогресса ещё нет.
  locked,
}

/// Награда в снимке: правило + прогресс + статус.
class AchievementView {
  const AchievementView({
    required this.def,
    required this.progress,
    required this.status,
    this.earnedWeek,
    this.earnedDay,
  });

  final AchievementDef def;

  /// Сколько набрано, не больше [AchievementDef.target].
  final int progress;
  final AchievementStatus status;

  /// Неделя получения; `null` — ещё не получена. Для ярлыка «новое» экран
  /// сравнивает с тем, что ребёнок уже видел.
  final int? earnedWeek;

  /// День недели получения (1…дней в неделе); `null` — режим «неделя», ещё не
  /// получена или старое сохранение без поля `day`.
  final int? earnedDay;

  int get target => def.target;
}
