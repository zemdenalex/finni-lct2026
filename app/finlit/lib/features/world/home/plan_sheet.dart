import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../shop/shop_kit.dart' show billPartsText;
import '../world_state.dart';
import '../../../core/world_theme.dart';
import '../pic_text.dart';

/// Быстрый план недели из комнаты: карманные по НУЖНО / ХОЧУ / ЦЕЛЬ.
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
  static const int step = 10;

  late final int total = widget.state.snapshot.unallocated;
  late final int bill = widget.state.snapshot.weeklyBill;
  late final WeekBillParts parts = widget.state.world.weeklyBillParts;

  /// Подсказка по умолчанию: сначала счета недели, остальное — в ХОЧУ.
  /// Ребёнок двигает сам.
  late int need = math.min(bill, total);
  late int want = total - need;
  int goal = 0;
  String? refusal;

  int get rest => total - need - want - goal;

  void _set(void Function() f) => setState(() {
        f();
        refusal = null;
      });

  @override
  Widget build(BuildContext context) {
    Widget row(Pic icon, String name, Color color, int value,
            void Function(int) put) =>
        _EnvelopeRow(
          icon: icon,
          name: name,
          color: color,
          value: value,
          onMinus: value >= step ? () => _set(() => put(value - step)) : null,
          onPlus: rest >= step
              ? () => _set(() => put(value + step))
              : () => setState(() => refusal = planAllSpentHint),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('План недели',
                style: AppType.title(21, color: WorldColors.text)),
            const SizedBox(height: Gap.xs),
            Text('Разложи $total монет. Счёт недели — $bill '
                '(${billPartsText(parts)}): он спишется из НУЖНО в конце '
                'недели.'),
            const SizedBox(height: Gap.sm),
            row(Pic.basket, 'НУЖНО', WorldColors.needs, need,
                (int v) => need = v),
            row(Pic.heart, 'ХОЧУ', WorldColors.wants, want,
                (int v) => want = v),
            row(Pic.jar, 'ЦЕЛЬ', WorldColors.goal, goal, (int v) => goal = v),
            const SizedBox(height: Gap.xs),
            Text(
              rest > 0
                  ? 'Не разложено: $rest — уйдёт в кошелёк.'
                  : planAllSpentLine,
              key: const ValueKey<String>('plan:rest'),
              style: const TextStyle(color: WorldColors.textSoft),
            ),
            if (need < bill)
              PicText('⚠️ В НУЖНО меньше счёта на ${bill - need}.',
                  style: const TextStyle(color: WorldColors.wants)),
            if (refusal != null)
              Text(refusal!, style: const TextStyle(color: WorldColors.wants)),
            const SizedBox(height: Gap.sm),
            FilledButton(
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
          ],
        ),
      ),
    );
  }
}

class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow({
    required this.icon,
    required this.name,
    required this.color,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final Pic icon;
  final String name;
  final Color color;
  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

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
            IconButton(
              tooltip: '$name меньше',
              onPressed: onMinus,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$value',
                    style: AppType.number(18, color: WorldColors.text)),
              ),
            ),
            IconButton(
              tooltip: '$name больше',
              onPressed: onPlus,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      );
}
