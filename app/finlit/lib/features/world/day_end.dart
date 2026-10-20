import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/world_theme.dart';
import '../../domain/world/contract.dart';
import 'home/game_calendar.dart';
import 'home/world_hud.dart';

/// Дело (смена, отдых) закончило день: сил осталось меньше, чем на самое
/// дешёвое дело, — мир сам укладывает Финни спать, и сразу утро (D7,
/// контракт §2). Логика — в мире; здесь только подача итога (путь ребёнка
/// rc-7d, D2): короткая строка «Уже утро» видна без прокрутки, а в тексте
/// итога вместо «Силы кончились» при остатке — сколько сил осталось.

/// Начало хвоста про ночь в итоге мира (`_afterEnergySpent`): «Силы
/// кончились — наступил вечер, пора спать. Наступило утро — …».
const String _nightMark = 'Силы кончились — наступил вечер';

/// Итог мира на две части: про само дело и про утро. Хвоста нет — утро
/// пустое.
({String done, String morning}) splitDayEnd(String reason) {
  final int i = reason.indexOf(_nightMark);
  if (i < 0) return (done: reason, morning: '');
  final String tail = reason.substring(i);
  const String sleep = 'пора спать.';
  final int j = tail.indexOf(sleep);
  return (
    done: reason.substring(0, i).trimRight(),
    morning: j < 0 ? tail : tail.substring(j + sleep.length).trim(),
  );
}

/// Тексты конца дня или null, если день идёт: [short] — строка «Уже утро:
/// день N из M» (одна строка: на 360×640 при шрифте 1,3 она не закрывает
/// варианты), [full] — итог дела словами: что сделано, сколько сил
/// осталось, утро.
///
/// [dayBefore] и [energyBefore] — до действия; [result] — его итог; [now] —
/// снимок мира после. [gender] — род героя для реплики «Я устал, пойду
/// спать» ([finniSleepLine], Настя 20.10: каждая смена дня — с ней).
({String short, String full})? dayEndText({
  required WorldResult? result,
  required int? dayBefore,
  required double energyBefore,
  required ResourceSnapshot now,
  FinniGender? gender,
}) {
  final WorldResult? r = result;
  if (r == null || !r.ok || dayBefore == null) return null;
  if (now.dayInWeek == dayBefore) return null;
  final double left = energyBefore + r.energy;
  final ({String done, String morning}) parts = splitDayEnd(r.reason);
  return (
    // Игровой календарь (Настя 20.10): «Уже утро: Вт, 6 окт».
    short: 'Уже утро: '
        '${GameCalendar.short(week: now.weekNo, day: now.dayInWeek)}',
    full: '${parts.done} Сил осталось '
        '${WorldHud.energyText(left < 0 ? 0 : left)} — на дела не хватит, '
        'поэтому день закончился. «${finniSleepLine(gender)}» '
        '${parts.morning}',
  );
}

/// Строка «Уже утро»: в портрете — полосой у нижнего края, вне прокрутки;
/// в альбомной ([boxed]) — рамкой в панели итога.
class DayEndStrip extends StatelessWidget {
  const DayEndStrip(
      {super.key, required this.text, required this.style, this.boxed = false});

  final String text;

  /// Основной текст экрана: строка набирается им же, жирно и золотом.
  final TextStyle style;

  final bool boxed;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: boxed
            ? BoxDecoration(
                color: WorldColors.panel,
                borderRadius: BorderRadius.circular(WorldRadii.button),
                border: Border.all(color: WorldColors.line, width: 1.5),
              )
            : const BoxDecoration(
                color: WorldColors.panel,
                border: Border(
                    top: BorderSide(color: WorldColors.line, width: 1.5)),
              ),
        padding: boxed
            ? const EdgeInsets.all(Gap.sm)
            : const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.bedtime_rounded, color: WorldColors.gold),
            const SizedBox(width: Gap.sm),
            Expanded(
                child: Text(text,
                    style: style.copyWith(
                        fontWeight: FontWeight.w700, color: WorldColors.gold))),
          ],
        ),
      );
}
