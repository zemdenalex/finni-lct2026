import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/models/envelope.dart';
import '../../../domain/world/contract.dart';

/// План против факта по конвертам НУЖНО / ХОЧУ / ЦЕЛЬ (ТЗ 2.5.5.3): итоги
/// S11 и каждая неделя истории S12.
///
/// Цвет конверта — только полоска: рядом всегда слово и числа (ТЗ 3.6.5).
/// Числа — только из [WeekPlanFact], экран ничего не пересчитывает.
class PlanFactRows extends StatelessWidget {
  const PlanFactRows({
    super.key,
    required this.week,
    required this.keyPrefix,
    this.pendingBill,
  });

  final WeekPlanFact week;

  /// Префикс ключей строк: `$keyPrefix:need` / `:want` / `:goal`.
  final String keyPrefix;

  /// Счёт недели, пока он не оплачен (текущая неделя), — показать «счёт N,
  /// ещё не оплачен» вместо нуля.
  final int? pendingBill;

  @override
  Widget build(BuildContext context) {
    String actual(int v, String verb) => '$verb $v';
    final String needFact = week.billsPaid
        ? actual(week.need.actual, 'счета')
        : pendingBill == null
            ? 'счета ещё не оплачены'
            : 'счёт $pendingBill — ещё не оплачен';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Row(
          key: ValueKey<String>('$keyPrefix:need'),
          envelope: Envelope.needs,
          label: 'НУЖНО',
          planned: week.need.planned,
          planMade: week.planMade,
          fact: needFact,
          diff: week.billsPaid ? week.need.diff : null,
        ),
        const SizedBox(height: Gap.xs),
        _Row(
          key: ValueKey<String>('$keyPrefix:want'),
          envelope: Envelope.wants,
          label: 'ХОЧУ',
          planned: week.want.planned,
          planMade: week.planMade,
          fact: actual(week.want.actual, 'потратили'),
          diff: week.want.diff,
        ),
        const SizedBox(height: Gap.xs),
        _Row(
          key: ValueKey<String>('$keyPrefix:goal'),
          envelope: Envelope.savings,
          label: 'ЦЕЛЬ',
          planned: week.goal.planned,
          planMade: week.planMade,
          // Взяли из копилки больше, чем положили: не «отложили −50» —
          // минус в слове «отложили» семилетке непонятен.
          fact: week.goal.actual < 0
              ? 'взяли из копилки ${-week.goal.actual}'
              : actual(week.goal.actual, 'отложили'),
          diff: week.goal.diff,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.envelope,
    required this.label,
    required this.planned,
    required this.planMade,
    required this.fact,
    required this.diff,
  });

  final Envelope envelope;
  final String label;
  final int planned;
  final bool planMade;
  final String fact;

  /// Факт минус план; null — сравнивать пока не с чем.
  final int? diff;

  @override
  Widget build(BuildContext context) {
    final int? d = planMade ? diff : null;
    final String mark = d == null
        ? ''
        : d == 0
            ? 'ровно'
            : d > 0
                ? 'на\u00A0$d\u00A0больше'
                : 'на\u00A0${-d}\u00A0меньше';
    // Знак «чека» (критерии ночи §8 п. 2): ▲ больше плана, ▼ меньше, = ровно
    // — значком (в шрифте игры нет ▲▼), вместе со словами, не только цветом.
    final IconData? sign = d == null
        ? null
        : d == 0
            ? Icons.drag_handle_rounded
            : d > 0
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded;
    return Container(
      decoration: BoxDecoration(
        color: WorldColors.raised,
        borderRadius: BorderRadius.circular(WorldRadii.tag),
        border:
            Border(left: BorderSide(color: WorldColors.of(envelope), width: 6)),
      ),
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
      child: Text.rich(
        TextSpan(children: <InlineSpan>[
          // Строка 1 — вывод «чека»: конверт, ▲/▼ и «на N больше»; строка 2 —
          // числа. Строка не рвётся посреди фразы и при шрифте 1,3 занимает
          // две строки, а не три (review_fits_test). Конверт — словом и
          // цветной полосой слева.
          TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (sign != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(sign,
                  key: ValueKey<String>('planfact:sign:${envelope.name}'),
                  size: 20,
                  color: WorldColors.text),
            ),
          if (mark.isNotEmpty)
            TextSpan(
                text: ' $mark',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(
              text: planMade
                  ? '\nплан\u00A0$planned → $fact'
                  : '\nбез плана · $fact'),
        ]),
        style: const TextStyle(fontSize: 16, color: WorldColors.text),
      ),
    );
  }
}

/// Одна строка вывода недели голосом Финни — «мы», без морали: что
/// разошлось с планом сильнее всего, или что всё сошлось.
/// Еда недели против плана НУЖНО одной фразой (критерии ночи 29.09, §2 п. 8):
/// сколько ушло на еду и какую долю съело «вкусное без пользы». null — еды на
/// неделе ещё не было.
String? foodTakeaway(WeekPlanFact w) {
  if (w.food <= 0) return null;
  final String head = w.planMade
      ? 'Еда: ${w.food} из плана НУЖНО ${w.need.planned}'
      : 'Еда: ${w.food}';
  if (w.treats <= 0) return '$head — без лишнего на вкусное.';
  final int pct = (w.treats * 100 / w.food).round();
  return '$head. Вкусное без пользы (пицца, бургер) съело $pct % еды — '
      'на полезное и простое ушло бы меньше.';
}

String planFactTakeaway(WeekPlanFact w) {
  if (!w.planMade) return 'План на эту неделю мы не составляли.';
  final int need = w.need.diff;
  final int want = w.want.diff;
  final int goal = w.goal.diff;
  if (w.billsPaid && need > 0) {
    // Переложить в НУЖНО можно, только если что-то лежало в ХОЧУ или ЦЕЛИ;
    // иначе карманных просто меньше счёта — разницу закрывают смены.
    return w.want.planned + w.goal.planned > 0
        ? 'Счета вышли на $need больше плана НУЖНО — в следующий раз '
            'положим туда больше.'
        : 'Счета вышли на $need больше карманных — такую разницу мы '
            'закрываем сменами.';
  }
  if (want > 0) {
    return 'На ХОЧУ ушло на $want больше плана — добрали из заработка.';
  }
  if (goal > 0) return 'Отложили на $goal больше, чем собирались!';
  if (goal < 0 && w.goal.planned > 0) {
    return 'Отложили на ${-goal} меньше, чем собирались. Бывает — '
        'в копилке всё равно ${w.savedAtEnd}.';
  }
  if (!w.billsPaid) return 'Неделя ещё идёт — сверим в итогах.';
  return 'Всё сошлось с планом — так и держим!';
}
