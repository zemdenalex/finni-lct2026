import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/phrases.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/world_game.dart';
import '../review/plan_fact_view.dart';

/// Варианты кнопки «Отправить родителю» на «Прогрессе» (консультация
/// экспертов 16.10, п. 4): страница `docs/final/otpravit-roditelyu`.
/// Переключает только инструмент рендера; в приложении — [ShareLook.none],
/// пока Денис не выбрал. Без аккаунта и личных данных: в итогах только
/// игровые числа и имя питомца, ник ребёнка не уходит.
enum ShareLook { none, picture, text }

ShareLook shareLook = ShareLook.none;

/// Флаг `progress.share_parent` настоящего мира (EXP-9); у FakeWorld — нет.
bool parentShareOn(World w) => w is WorldGame && w.config.shareParent;

/// Неделя для родителя: последняя с оплаченными счетами, иначе текущая.
WeekPlanFact? shareWeek(List<WeekPlanFact> history) {
  for (final WeekPlanFact w in history.reversed) {
    if (w.billsPaid) return w;
  }
  return history.isEmpty ? null : history.last;
}

int _earned(WeekPlanFact w) =>
    w.shifts.fold<int>(0, (int s, WeekItem i) => s + i.amount);

/// Короткий текст для системного «поделиться» (вариант B).
String parentShareText(WeekPlanFact w, {required String petName}) {
  final int earned = _earned(w);
  final int shifts = w.shifts.length;
  final String need = w.billsPaid ? '${w.need.actual}' : 'ещё не оплачены';
  final String goal = w.goalTitle == null
      ? 'В копилке: ${w.savedAtEnd}.'
      : (w.goalPrice ?? 0) > 0
          ? 'Копим на «${w.goalTitle}»: ${w.savedAtEnd} из ${w.goalPrice}.'
          : 'Копим на «${w.goalTitle}»: ${w.savedAtEnd}.';
  return '$petName · неделя ${w.weekNo} (игра «Питомец Финни»)\n'
      'Заработали: $earned ${_coins(earned)} '
      '(${shifts == 0 ? 'смен не было' : '$shifts ${Phrases.shiftWord(shifts) == 'смену' ? 'смена' : Phrases.shiftWord(shifts)}'}).\n'
      'План → на деле: «Нужно» ${w.need.planned} → счета $need, '
      '«Хочу» ${w.want.planned} → ${w.want.actual}, '
      '«Копилка» ${w.goal.planned} → ${w.goal.actual}.\n'
      '$goal\n'
      'Что поняли: ${_lower(planFactTakeaway(w))}';
}

/// «монета / монеты / монет»: текст читает взрослый, не «монеток».
String _coins(int n) {
  final int m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'монета';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'монеты';
  return 'монет';
}

String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Кнопка на «Прогрессе»; null — кнопки нет. [enabled] — флаг
/// `progress.share_parent` (EXP-9, Денис 18.10 — false): выключен — кнопки
/// нет при любом [shareLook]; включён — вид [shareLook], а без выбранного вида
/// — картинка (A, рекомендация front3).
Widget? parentShareButton(
  BuildContext context, {
  required WeekPlanFact? week,
  required String petName,
  bool enabled = false,
}) {
  if (!enabled || week == null) return null;
  final ShareLook look =
      shareLook == ShareLook.none ? ShareLook.picture : shareLook;
  return OutlinedButton.icon(
    key: const ValueKey<String>('history:share'),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(TapSize.min),
    ),
    onPressed: () =>
        showParentSharePreview(context, week, petName: petName, look: look),
    icon: const Icon(Icons.share_rounded),
    label: const Text('Отправить родителю'),
  );
}

/// Что увидит родитель — до системного «поделиться».
Future<void> showParentSharePreview(
  BuildContext context,
  WeekPlanFact week, {
  required String petName,
  ShareLook? look,
}) {
  final bool picture = (look ?? shareLook) == ShareLook.picture;
  return showDialog<void>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      key: const ValueKey<String>('share:preview'),
      insetPadding: const EdgeInsets.all(Gap.md),
      title: Text(picture ? 'Картинка родителю' : 'Текст родителю'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Картинка целиком, как уйдёт файлом: на малом экране —
            // уменьшенной, без прокрутки.
            if (picture)
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(c).height * 0.5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 300,
                    child: ParentShareCard(week: week, petName: petName),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: WorldColors.raised,
                  borderRadius: BorderRadius.circular(WorldRadii.tag),
                ),
                child: Text(
                  parentShareText(week, petName: petName),
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              ),
            const SizedBox(height: Gap.sm),
            const Text(
              'Только числа игры, без имени. Куда — выберешь сам.',
              style: TextStyle(fontSize: 14, color: WorldColors.textSoft),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('share:send'),
          onPressed: () => Navigator.of(c).pop(),
          icon: const Icon(Icons.share_rounded),
          label: const Text('Отправить'),
        ),
      ],
    ),
  );
}

/// Итоги недели картинкой (вариант A): то, что уйдёт PNG-файлом.
class ParentShareCard extends StatelessWidget {
  const ParentShareCard({super.key, required this.week, required this.petName});

  final WeekPlanFact week;
  final String petName;

  @override
  Widget build(BuildContext context) {
    final WeekPlanFact w = week;
    final int earned = _earned(w);
    final int? price = w.goalPrice;
    return Container(
      key: const ValueKey<String>('share:card'),
      padding: const EdgeInsets.all(Gap.sm),
      decoration: BoxDecoration(
        color: WorldColors.panel,
        borderRadius: BorderRadius.circular(WorldRadii.tile),
        border: Border.all(color: WorldColors.goal, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$petName · неделя ${w.weekNo}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            'Заработали $earned ${_coins(earned)}',
            style: const TextStyle(fontSize: 15, color: WorldColors.textSoft),
          ),
          const SizedBox(height: Gap.xs),
          PlanFactRows(week: w, keyPrefix: 'share:planfact'),
          if (w.goalTitle != null) ...<Widget>[
            const SizedBox(height: Gap.xs),
            Text(
              (price ?? 0) > 0
                  ? 'Копим на «${w.goalTitle}»: ${w.savedAtEnd} из $price'
                  : 'Копим на «${w.goalTitle}»: ${w.savedAtEnd}',
              style: const TextStyle(fontSize: 15),
            ),
            if ((price ?? 0) > 0) ...<Widget>[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (w.savedAtEnd / price!).clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  color: WorldColors.goal,
                  backgroundColor: WorldColors.raised,
                ),
              ),
            ],
          ],
          const SizedBox(height: Gap.xs),
          Text(
            'Что поняли: ${_lower(planFactTakeaway(w))}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Gap.xs),
          const Text(
            'Питомец Финни · игра о деньгах для 7–11 лет',
            style: TextStyle(fontSize: 12, color: WorldColors.textSoft),
          ),
        ],
      ),
    );
  }
}
