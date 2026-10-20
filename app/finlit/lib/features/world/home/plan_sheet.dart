import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../shop/shop_kit.dart' show billPartsText;
import '../world_state.dart';
import '../../../core/world_theme.dart';
import '../onboarding/onboarding_script.dart';
import '../pic_text.dart';
import 'plan_amount.dart';
import 'plan_pool.dart';

/// Быстрый план недели из комнаты: монеты недели по «Нужное» / «Хочу» /
/// «Копилка». Удержание «−»/«+», ввод числа и совет Финни — plan_amount.dart.
///
/// 🟡 Отдельного экрана плана в маршрутах нового мира нет — лист живёт
/// здесь, пока карточка плана его не заменит. Остаток уходит в кошелёк
/// заработка (контракт [World.plan]).
///
/// Возвращает итог действия или null, если ребёнок закрыл лист.
Future<WorldResult?> showPlanSheet(BuildContext context, WorldState state) =>
    showModalBottomSheet<WorldResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // ТЗ 3.6.7: с выключенными анимациями лист не выезжает, а появляется.
      sheetAnimationStyle: AnimationStyle(
        duration: context.motion(const Duration(milliseconds: 250)),
        reverseDuration: context.motion(const Duration(milliseconds: 200)),
      ),
      builder: (BuildContext c) => _PlanSheet(state: state),
    );

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.state});

  final WorldState state;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  /// Шаг «−»/«+» — тот же, что в плане знакомства (`plan_step`).
  late final OnboardingScript? script = context.read<OnboardingScript?>();
  late final int step = script?.planStep ?? 10;

  late final int total = widget.state.snapshot.unallocated;
  late final int bill = widget.state.snapshot.weeklyBill;
  late final WeekBillParts parts = widget.state.world.weeklyBillParts;

  /// Конверты с нуля: раскладывает ребёнок сам (Денис, 29.09: «может
  /// сделать изначально 0 и пускай сами распределяют»).
  int need = 0;
  int want = 0;
  int goal = 0;
  String? refusal;

  /// «+» без остатка: строка «На неделю» трясётся, под ней «Всё уже
  /// разложено» ([PlanPool]).
  int shake = 0;
  bool full = false;

  int get rest => total - need - want - goal;

  void _set(void Function() f) => setState(() {
        f();
        refusal = null;
        full = false;
      });

  @override
  Widget build(BuildContext context) {
    Widget row(String id, Pic icon, String name, Color color, int value,
            void Function(int) put) =>
        _EnvelopeRow(
          id: id,
          icon: icon,
          name: name,
          color: color,
          value: value,
          max: value + rest,
          step: step,
          onSet: (int v) => _set(() => put(v)),
          onFull: () => setState(() {
            shake++;
            full = true;
          }),
        );

    // «Готово» прижато к низу листа: строки плана прокручиваются над ним,
    // а кнопка всегда под пальцем (совет Финни добавил строку высоты).
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('План недели',
                      style: AppType.title(21, color: WorldColors.text)),
                  const SizedBox(height: Gap.xs),
                  Text('Счёт недели — $bill (${billPartsText(parts)}): '
                      'его оплатит «Нужно» в конце недели.'),
                  const SizedBox(height: Gap.xs),
                  PlanPool(
                    amount: total,
                    // Остаток считается на лету: ввели в часть — строка
                    // сразу показывает, сколько ещё можно разложить.
                    left: rest,
                    saved: widget.state.snapshot.saved,
                    shake: shake,
                    full: full,
                  ),
                  const SizedBox(height: Gap.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PlanAdviceButton(
                      name: widget.state.finniName,
                      onPressed: rest > 0
                          ? () => _set(() {
                                final ({int need, int want, int goal}) r =
                                    advisePlan(
                                  pool: total,
                                  bill: bill,
                                  step: step,
                                  advice:
                                      script?.planAdvice ?? const PlanAdvice(),
                                  need: need,
                                  want: want,
                                  goal: goal,
                                );
                                need = r.need;
                                want = r.want;
                                goal = r.goal;
                              })
                          : null,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  row('need', Pic.basket, 'Нужно', WorldColors.needs, need,
                      (int v) => need = v),
                  row('want', Pic.heart, 'Хочу', WorldColors.wants, want,
                      (int v) => want = v),
                  row('goal', Pic.jar, 'Копилка', WorldColors.goal, goal,
                      (int v) => goal = v),
                  const SizedBox(height: Gap.xs),
                  Text(
                    rest > 0
                        ? 'Не разложено: $rest — уйдёт в заработок.'
                        : planAllSpentLine,
                    key: const ValueKey<String>('plan:rest'),
                    style: const TextStyle(color: WorldColors.textSoft),
                  ),
                  if (need < bill)
                    PicText('⚠️ «Нужно» меньше счёта на ${bill - need}.',
                        style: const TextStyle(color: WorldColors.wants)),
                  if (refusal != null)
                    Text(refusal!,
                        style: const TextStyle(color: WorldColors.wants)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
            child: FilledButton(
              key: const ValueKey<String>('plan:confirm'),
              onPressed: () {
                final WorldResult r = widget.state.act(
                    (World w) => w.plan(needs: need, wants: want, goal: goal));
                if (r.ok) {
                  Navigator.of(context).pop(r);
                } else {
                  setState(() => refusal = r.reason);
                }
              },
              child: const Text('Готово'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка плана: «−», сумма (касание — ввод числа), «+».
class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow({
    required this.id,
    required this.icon,
    required this.name,
    required this.color,
    required this.value,
    required this.max,
    required this.step,
    required this.onSet,
    required this.onFull,
  });

  final String id;
  final Pic icon;
  final String name;
  final Color color;
  final int value;

  /// Больше нельзя: сколько в строке + остаток.
  final int max;
  final int step;
  final ValueChanged<int> onSet;

  /// «+» без остатка: «На неделю» трясётся.
  final VoidCallback onFull;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$name: $value',
        child: Row(
          children: <Widget>[
            Pictogram(icon, size: 24, color: color),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: color, fontSize: 16)),
            ),
            HoldStepButton(
              key: ValueKey<String>('sheet:minus:$id'),
              outlined: false,
              icon: Icons.remove_circle_outline,
              label: '$name: меньше',
              value: value,
              max: max,
              step: step,
              up: false,
              onChanged: onSet,
            ),
            AmountTap(
              key: ValueKey<String>('amount:$id'),
              title: name,
              value: value,
              max: max,
              onChanged: onSet,
              child: SizedBox(
                width: 64,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$value',
                      style: AppType.number(18, color: WorldColors.text)
                          .copyWith(
                              decoration: TextDecoration.underline,
                              decorationColor: WorldColors.textSoft)),
                ),
              ),
            ),
            HoldStepButton(
              key: ValueKey<String>('sheet:plus:$id'),
              outlined: false,
              icon: Icons.add_circle_outline,
              label: '$name: больше',
              value: value,
              max: max,
              step: step,
              up: true,
              onChanged: onSet,
              onBlocked: onFull,
            ),
          ],
        ),
      );
}
