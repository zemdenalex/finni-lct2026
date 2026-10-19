import 'contract.dart';
import 'world_config.dart';

/// Правило урока после смены — одно для `WorldGame` и `FakeWorld`
/// (критерии ночи 29.09, §4).
///
/// Доли ([WorldLessonChoice.goalShare], [WorldLessonChoice.needShare]) — от
/// оплаты этой смены [pay], округляются до десятков (числа для 7–11 лет) и
/// берутся только из кошелька заработка: больше, чем в нём есть, не уходит.
/// Трата [WorldLessonChoice.spend] — из кошелька, потом из ХОЧУ; не хватает —
/// вариант недоступен, ничего не списано (ТЗ 2.5.6.4).
typedef LessonMove = ({
  int toGoal,
  int toNeed,
  int fromFree,
  int fromWant,
  BlockReason? block,
});

int _tens(double v) => ((v / 10).round() * 10);

LessonMove lessonMove(WorldLessonChoice c,
    {required int pay, required int free, required int want}) {
  int left = free;
  final int toGoal = _tens(pay * c.goalShare).clamp(0, left);
  left -= toGoal;
  final int toNeed = _tens(pay * c.needShare).clamp(0, left);
  left -= toNeed;
  if (c.spend > left + want) {
    return (
      toGoal: 0,
      toNeed: 0,
      fromFree: 0,
      fromWant: 0,
      block: BlockReason('lesson.short', 'Не хватает ${c.spend - left - want}.',
          nextStep: 'Можно выбрать другой вариант'),
    );
  }
  final int fromFree = c.spend < left ? c.spend : left;
  return (
    toGoal: toGoal,
    toNeed: toNeed,
    fromFree: fromFree,
    fromWant: c.spend - fromFree,
    block: null,
  );
}

/// Доли в уроке — монетами, а не словами (NAS-5 A, Настя 19.10: «отложи 50
/// из 180»): `{goal}` и `{need}` — сколько на самом деле уйдёт в копилку и
/// в «Нужное» ([lessonMove]: до десятков и не больше заработка), `{pay}` —
/// оплата этой смены. Число в тексте всегда то, что спишет мир.
String lessonText(String s, LessonMove m, {required int pay}) => s
    .replaceAll('{goal}', '${m.toGoal}')
    .replaceAll('{need}', '${m.toNeed}')
    .replaceAll('{pay}', '$pay');

/// Итог урока: «Что мы поняли: …» и реплика Финни.
String lessonReason(WorldLesson l, WorldLessonChoice c, LessonMove m,
        {required int pay}) =>
    'Что мы поняли: ${l.understood} ${lessonText(c.finni, m, pay: pay)}';

/// Что будет — до выбора (монеты, копилка, 😊).
EffectPreview lessonPreview(LessonMove m, WorldLessonChoice c) => EffectPreview(
      coins: -(m.toGoal + m.fromFree + m.fromWant),
      goal: m.toGoal,
      happiness: c.happiness,
    );

/// Урок для экрана.
///
/// [name] — имя героя: `{name}` в ситуации урока (BG-01, [heroText]).
LessonOffer lessonOffer(WorldLesson l,
        {required int pay,
        required int free,
        required int want,
        String name = OnboardingProgress.defaultFinniName}) =>
    LessonOffer(
      jobId: l.jobId,
      topic: l.topic,
      title: l.title,
      situation: heroText(l.situation, name),
      wordTerm: l.wordTerm,
      choices: <LessonChoiceView>[
        for (final WorldLessonChoice c in l.choices)
          () {
            final LessonMove m =
                lessonMove(c, pay: pay, free: free, want: want);
            return LessonChoiceView(
              id: c.id,
              label: lessonText(c.label, m, pay: pay),
              preview: lessonPreview(m, c),
              blockReason: m.block,
            );
          }(),
      ],
    );
