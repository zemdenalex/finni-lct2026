import '../../../domain/world/contract.dart';

/// Что Финни говорит игроку по касанию (Денис 20.10: «Финни друг, и при
/// нажатии на него он должен говорить как друг с игроком» — не питомец,
/// которого гладят). Реплики по ситуации, без рода в словах Финни о себе
/// и в обращении к ребёнку; `{nick}` — ник ребёнка, `{goal}` — цель,
/// `{left}` — сколько монет до неё (числом, без слова «монет»: не склонять).
enum TalkSituation { tired, hungry, sad, joy, goal, noJob, morning, lastDay, any }

/// Реплики по ситуациям. Ситуационные идут в выборке первыми, нейтральные
/// ([TalkSituation.any]) — всегда.
const Map<TalkSituation, List<String>> finniTalkLines =
    <TalkSituation, List<String>>{
  TalkSituation.tired: <String>[
    'Сил почти нет, {nick}. Отдохнём — и снова за дела.',
    '{nick}, на сегодня хватит. Выспимся — сил станет больше.',
  ],
  TalkSituation.hungry: <String>[
    '{nick}, в животе урчит. Заглянем в холодильник?',
  ],
  TalkSituation.sad: <String>[
    '{nick}, мне грустновато. Может, сходим в парк?',
    'Поговорить с тобой — уже лучше, {nick}.',
  ],
  TalkSituation.joy: <String>[
    'Настроение отличное! Здорово, что ты рядом, {nick}.',
    '{nick}, сегодня всё получается. Так держать!',
  ],
  TalkSituation.goal: <String>[
    'До цели «{goal}» осталось собрать {left}. Вместе дойдём, {nick}!',
    '{nick}, каждая монета в копилке — шаг к цели «{goal}».',
  ],
  TalkSituation.noJob: <String>[
    '{nick}, сегодня ещё не было смены. Глянем доску работ в городе?',
  ],
  TalkSituation.morning: <String>[
    'Доброе утро, {nick}! Что сегодня: работа или прогулка?',
  ],
  TalkSituation.lastDay: <String>[
    'Последний день недели, {nick}. Скоро посмотрим, как сработал план.',
  ],
  TalkSituation.any: <String>[
    'Привет, {nick}! Как твои дела?',
    'С тобой веселее, {nick}. Что делаем дальше?',
    '{nick}, монеты любят план: сначала нужное, потом остальное.',
    'Хорошо, что ты заглядываешь, {nick}!',
  ],
};

/// Подходящие сейчас ситуации, самая важная первой.
List<TalkSituation> talkSituations(
  ResourceSnapshot s, {
  required double tiredBelow,
  required bool hasGoal,
}) {
  final bool days = s.daysPerWeek > 1;
  const Set<String> deeds = <String>{'job', 'meal', 'rest', 'fridge'};
  return <TalkSituation>[
    if (s.energy + 1e-9 < tiredBelow) TalkSituation.tired,
    if (s.hungry) TalkSituation.hungry,
    if (s.happiness <= 30) TalkSituation.sad,
    if (s.happiness >= 70) TalkSituation.joy,
    if (hasGoal) TalkSituation.goal,
    if (days && s.dayInWeek >= s.daysPerWeek) TalkSituation.lastDay,
    if (days && !s.doneToday.any(deeds.contains)) TalkSituation.morning,
    if (!s.doneToday.contains('job') && s.energy + 1e-9 >= tiredBelow)
      TalkSituation.noJob,
    TalkSituation.any,
  ];
}

/// Реплика номер [n] (счётчик касаний) из подходящих сейчас; не совпадает
/// с [last] — два касания подряд не дают одну и ту же фразу.
String finniTalkLine({
  required List<TalkSituation> situations,
  required int n,
  required String nick,
  String? goalTitle,
  int goalLeft = 0,
  String? last,
}) {
  final List<String> pool = <String>[
    for (final TalkSituation t in situations)
      if (t != TalkSituation.goal || goalTitle != null)
        ...finniTalkLines[t] ?? const <String>[],
  ];
  String fill(String line) => line
      .replaceAll('{nick}', nick.isEmpty ? 'друг' : nick)
      .replaceAll('{goal}', goalTitle ?? '')
      .replaceAll('{left}', '$goalLeft');
  final int start = n % pool.length;
  for (int i = 0; i < pool.length; i++) {
    final String line = fill(pool[(start + i) % pool.length]);
    if (line != last) return line;
  }
  return fill(pool[start]);
}
