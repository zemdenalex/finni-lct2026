import 'package:flutter/material.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import 'game_calendar.dart';

/// Варианты HUD для модели «день по энергии» (созвон 15.10: D1 сытость рядом
/// с энергией, D2/D7 день и вечер, D3 прогресс и ачивки) при правиле «в HUD не
/// больше трёх значений». Страница для Дениса: `docs/final/hud-day-energy/`.
///
/// 🟡 Только для рендера вариантов: в приложении — [HudLook.asIs]. Числа
/// сытости и время суток — моковые ([dayMock]), домена ещё нет (контракт
/// придёт от back). После выбора Дениса остаётся один вид, файл уходит.
enum HudLook {
  /// 0 — как сдано: монеты, энергия, настроение; сытости и времени нет.
  asIs,

  /// A — HUD прежний; сытость — полоской над Финни (и на холодильнике).
  fedOnFinni,

  /// B — «силы»: энергия и сытость одной двойной шкалой в одной ячейке.
  doubleBar,

  /// C — HUD: монеты, энергия, сытость; настроение — на самом Финни.
  moodOnFinni,

  /// D — как сдано, пока Финни сыт; сытость ниже трети встаёт на место
  /// настроения, настроение уходит на Финни.
  fedWhenLow,

  /// E — в первом ряду три значения как сдано; сытость — во втором ряду
  /// рядом с «День N из 7»: миска, «сытость N», полоска ([FedChip]).
  fedRow,
}

/// Вид HUD дня. По умолчанию — E: сытость во втором ряду HUD — миска, слово
/// и число (Денис, чат 1900 17.10: «где шкала голода/сытости?» — над Финни
/// её не замечали; вторая полоска под силами без слова и числа не читалась,
/// а слово в ячейку 48 dp не влезает). Остальные — для рендера
/// (`docs/final/hud-day-energy/`).
/// В прежней неделе (`daysPerWeek` = 1, сытости нет) HUD всегда как сдано.
HudLook hudLook = HudLook.fedRow;

/// Время суток игрового дня (D7: день и вечер; ночь — экран сна). В домене
/// отдельного вечера нет (контракт back §2): в игре всегда [DayTime.day],
/// вечер и ночь — только в рендере вариантов.
enum DayTime { day, evening, night }

/// Моковые значения — только для рендера вариантов; null — числа из мира.
class DayMock {
  const DayMock({this.fed = 0.6, this.day = 3, this.time = DayTime.day});

  /// Сытость 0..1.
  final double fed;

  /// Номер игрового дня.
  final int day;
  final DayTime time;
}

DayMock? dayMock;

/// Что показывает HUD дня: сытость, день, дней в неделе — из снимка мира
/// (`docs/final/day-energy-contract.md` §1), в рендере — из [dayMock].
class DayView {
  const DayView(
      {this.fed,
      this.day = 1,
      this.days = 1,
      this.week = 1,
      this.time = DayTime.day,
      this.hungry = false});

  factory DayView.of(ResourceSnapshot s) {
    final DayMock? m = dayMock;
    if (m != null) {
      return DayView(
          fed: m.fed,
          day: m.day,
          days: s.daysPerWeek > 1 ? s.daysPerWeek : 3,
          time: m.time,
          hungry: m.fed * 100 < s.satietyHungryAt);
    }
    final int? sat = s.satiety;
    return DayView(
        fed: sat == null ? null : sat / 100,
        day: s.dayInWeek,
        days: s.daysPerWeek,
        week: s.weekNo,
        hungry: s.hungry);
  }

  /// Сытость 0..1; null — дней нет (флаг `days_per_week: 1`).
  final double? fed;
  final int day;
  final int days;

  /// Номер недели — для игрового календаря ([GameCalendar]).
  final int week;
  final DayTime time;

  /// «Вт, 6 окт» — день игрового календаря на экране (Настя 20.10).
  String get dateShort => GameCalendar.short(week: week, day: day);

  /// Для TalkBack: «Вторник, 6 октября, день 2 из 7» — сколько до итогов
  /// недели, слышно и без экрана.
  String get dateSpoken =>
      '${GameCalendar.spoken(week: week, day: day)}, день $day из $days';

  /// Модель дней включена.
  bool get on => fed != null;

  /// Вид HUD для этого снимка: без дней — как сдано.
  HudLook get look => on ? hudLook : HudLook.asIs;

  /// Сытость в HUD вместо настроения (C всегда, D — только когда мало).
  bool get fedInHud =>
      look == HudLook.moodOnFinni ||
      (look == HudLook.fedWhenLow && (fed ?? 1) < 0.3);

  /// Голоден: сытость ниже порога мира (`snapshot.hungry`, контракт §1).
  final bool hungry;
}

/// 🟡 Цвет сытости — временный, из текущей палитры (`wants`): Денис палитру
/// ещё не выбрал.
const Color fedColor = WorldColors.wants;

String dayTimeWord(DayTime t) => switch (t) {
      DayTime.day => 'день',
      DayTime.evening => 'вечер',
      DayTime.night => 'ночь',
    };

/// Тонировка комнаты по времени суток. ⚠ Ассета нет: у каждой стадии одна
/// картинка с одним временем суток (Москва — день, город — ночь, деревня —
/// закат), поэтому вечер и ночь — цветом поверх, а не своей картинкой окна.
Color? roomTint() => dayMock == null || hudLook == HudLook.asIs
    ? null
    : switch (dayMock!.time) {
        DayTime.day => null,
        DayTime.evening => const Color(0x59FF7A2E),
        DayTime.night => const Color(0xB30A1030),
      };

/// Метка времени в HUD: «День 3 · вечер» со значком солнца или луны.
class DayTimeChip extends StatelessWidget {
  const DayTimeChip(this.view, {super.key});

  final DayView view;

  @override
  Widget build(BuildContext context) {
    final DayView m = view;
    return Semantics(
      label: m.time == DayTime.day
          ? m.dateSpoken
          : '${m.dateSpoken}, ${dayTimeWord(m.time)}',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey<String>('hud:daytime'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          switch (m.time) {
            DayTime.day => const Icon(
                Icons.wb_sunny_rounded,
                size: 18,
                color: WorldColors.gold,
              ),
            DayTime.evening => const Icon(
                Icons.wb_twilight_rounded,
                size: 18,
                color: WorldColors.gold,
              ),
            DayTime.night => const Pictogram(
                Pic.moon,
                size: 18,
                color: WorldColors.gold,
              ),
          },
          const SizedBox(width: 4),
          Text(
            m.dateShort,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              shadows: <Shadow>[
                Shadow(
                  color: Color(0x99000000),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Сытость во втором ряду HUD (вид E): миска · «сытость N» · полоска той же
/// толщины, что под силами. TalkBack: «Сытость: N из 100».
class FedChip extends StatelessWidget {
  const FedChip(this.fed, {super.key, this.bar = true});

  /// Сытость 0..1.
  final double fed;

  /// Полоска за числом. В верхней строке по макету Алины полосок нет —
  /// там без неё (и ряд с целью не тесный).
  final bool bar;

  @override
  Widget build(BuildContext context) {
    final int n = (fed * 100).round();
    return Semantics(
      label: 'Сытость: $n из 100',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey<String>('hud:fed'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Pictogram(Pic.bowl, size: 18, color: fedColor),
          const SizedBox(width: 4),
          Text(
            'сытость $n',
            key: const ValueKey<String>('hud:fed:text'),
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              shadows: <Shadow>[
                Shadow(
                  color: Color(0x99000000),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          if (bar) ...<Widget>[
            const SizedBox(width: 4),
            SizedBox(width: 28, child: ValueBar(fed, fedColor, height: 4)),
          ],
        ],
      ),
    );
  }
}

/// Тонкая полоска значения (как под числами HUD).
class ValueBar extends StatelessWidget {
  const ValueBar(this.value, this.color, {super.key, this.height = 5});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          color: color,
          backgroundColor: const Color(0x40FFFFFF),
        ),
      );
}

/// Сытость у Финни (вариант A): значок миски и полоска — слева от строки
/// состояния над ним.
class FedOnFinni extends StatelessWidget {
  const FedOnFinni(this.fed, {super.key});

  /// Сытость 0..1.
  final double fed;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Сытость ${(fed * 100).round()} из 100',
        excludeSemantics: true,
        child: SizedBox(
          key: const ValueKey<String>('finni:fed'),
          width: 44,
          child: Row(
            children: <Widget>[
              const Pictogram(Pic.bowl, size: 18, color: fedColor),
              const SizedBox(width: 4),
              Expanded(child: ValueBar(fed, fedColor, height: 6)),
            ],
          ),
        ),
      );
}

/// Настроение у Финни (вариант C): смайлик и число слева от строки.
class MoodOnFinni extends StatelessWidget {
  const MoodOnFinni(this.mood, {super.key});

  final int mood;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Настроение $mood из 100',
        excludeSemantics: true,
        child: Row(
          key: const ValueKey<String>('finni:mood'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Pictogram(Pic.smile, size: 18, color: WorldColors.mood),
            const SizedBox(width: 3),
            Text('$mood', style: AppType.number(15, color: WorldColors.text)),
          ],
        ),
      );
}

/// Значок «Прогресс» с числом новых наград (D3). В приложении — как есть.
/// Новых наград на кнопке «Прогресс» (рендер вариантов; домен наград — отдельно).
int progressNew = 0;

Widget progressIcon(Widget icon) => progressNew == 0
    ? icon
    : Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          icon,
          Positioned(
            right: -10,
            top: -4,
            child: Container(
              key: const ValueKey<String>('room:nav:progress:new'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: WorldColors.gold,
                borderRadius: BorderRadius.circular(WorldRadii.tag),
              ),
              child: Text(
                '$progressNew',
                style: AppType.number(11, color: WorldColors.onGold),
              ),
            ),
          ),
        ],
      );
