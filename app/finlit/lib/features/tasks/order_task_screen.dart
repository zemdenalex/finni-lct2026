import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../domain/models/catalog_item.dart';
import '../../domain/models/task.dart';
import 'task_kit.dart';
import 'task_scoring.dart';

/// Проигрыватель заданий [TaskKind.orderAndBuy]: ребёнок сам составляет
/// очерёдность покупок и смотрит, на чём закончились монетки.
///
/// §2.5.8.2: это не выбор ответа из вариантов — порядок ребёнок строит сам,
/// а последствие (что куплено, а что осталось) считается из этого порядка.
class OrderTaskScreen extends StatefulWidget {
  const OrderTaskScreen({super.key, required this.task});

  final GameTask task;

  @override
  State<OrderTaskScreen> createState() => _OrderTaskScreenState();
}

class _OrderTaskScreenState extends State<OrderTaskScreen> {
  late List<CatalogItem> _items;
  OrderRun? _run;

  @override
  void initState() {
    super.initState();
    final AppState app = context.read<AppState>();
    _items = TaskParams(widget.task.params)
        .ids('items')
        .map(app.content.item)
        .toList();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _items.length) return;
    setState(() {
      final CatalogItem item = _items.removeAt(from);
      _items.insert(to, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final int budget = TaskParams(widget.task.params).number('budget');
    final OrderRun? run = _run;

    return TaskScaffold(
      task: widget.task,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('Бюджет',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(width: Gap.sm),
            Coins(budget, size: 24),
          ],
        ),
        const SizedBox(height: Gap.sm),
        if (run == null) ...<Widget>[
          const Text(
            'Перетащи карточки или двигай их стрелками. Сверху — то, '
            'что купим первым.',
            style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
          const SizedBox(height: Gap.md),
          ReorderableListView.builder(
            shrinkWrap: true,
            // Внутренний список не прокручивается сам и не забирает
            // PrimaryScrollController у ListView экрана.
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            itemCount: _items.length,
            // ⚠ `onReorder` объявлен устаревшим после 3.41.0-0.0.pre в пользу
            // `onReorderItem`. Замену использовать нельзя: её нет в 3.41.7,
            // на которой работает часть команды, а CI собирает 3.47.4.
            // Переключимся, когда у всех будет одна версия SDK.
            //
            // 🔴 Директива должна стоять строкой ровно над кодом — комментарии
            // между ней и строкой её отклеивают, и `flutter analyze` (в отличие
            // от `dart analyze`) валит сборку даже на info.
            // ignore: deprecated_member_use
            onReorder: (int oldIndex, int newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              _move(oldIndex, newIndex);
            },
            itemBuilder: (BuildContext context, int i) => Padding(
              key: ValueKey<String>(_items[i].id),
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: _OrderRow(
                position: i + 1,
                item: _items[i],
                onUp: i == 0 ? null : () => _move(i, i - 1),
                onDown:
                    i == _items.length - 1 ? null : () => _move(i, i + 1),
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          FilledButton(
            onPressed: _buy,
            child: const Text('Купить по моему порядку'),
          ),
        ] else ...<Widget>[
          TaskOutcomePanel(
            title: 'Вот что получилось',
            lines: <String>[
              if (run.bought.isEmpty)
                'Купить не получилось ничего: первая покупка дороже бюджета.'
              else
                'Купили: ${run.bought.map((CatalogItem i) => i.title).join(', ')}.',
              if (run.stoppedAt != null)
                'Монетки закончились на позиции «${run.stoppedAt!.title}» — '
                'она стоит ${run.stoppedAt!.price}, а осталось ${run.left}.'
              else
                'Хватило на всё.',
              'Осталось ${run.left} ${Coins.word(run.left)}.',
            ],
          ),
          const SizedBox(height: Gap.md),
          const TaskDoneButton(),
        ],
      ],
    );
  }

  Future<void> _buy() async {
    final int budget = TaskParams(widget.task.params).number('budget');
    final OrderRun run = TaskScoring.run(_items, budget);
    setState(() => _run = run);
    await finishTask(context, widget.task,
        best: TaskScoring.needsFirst(_items));
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.position,
    required this.item,
    required this.onUp,
    required this.onDown,
  });

  final int position;
  final CatalogItem item;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final Color c = AppColors.of(item.envelope);
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.xs, Gap.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: Row(
        children: <Widget>[
          Semantics(
            label: 'Место $position',
            excludeSemantics: true,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: AppColors.paper, shape: BoxShape.circle),
              child: Text('$position',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Coins(item.price, size: 18),
                    const SizedBox(width: Gap.sm),
                    // Обязательная покупка отличается не только цветом:
                    // рядом иконка и слово (§3.6.5).
                    Pictogram(AppColors.picOf(item.envelope), size: 16, color: c),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(item.envelope.title,
                          style: TextStyle(fontSize: 16, color: c)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 🔴 Стрелки обязательны рядом с перетаскиванием: удержать и
          // протащить карточку пальцем семилетка надёжно не может, а
          // порядок — единственное действие в этом задании.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ArrowButton(
                icon: Pic.caretUp,
                tooltip: 'Поднять выше: ${item.title}',
                onPressed: onUp,
              ),
              _ArrowButton(
                icon: Pic.caretDown,
                tooltip: 'Опустить ниже: ${item.title}',
                onPressed: onDown,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Pic icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        // 56×56 на каждую стрелку: §3.6.3 рекомендует 48 dp, проект держит
        // 56, и экономить здесь нельзя — это основной орган управления
        // задания, по нему бьют десятки раз подряд.
        width: TapSize.min,
        height: TapSize.min,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          iconSize: 30,
          // 🔴 Выключенное состояние красится вручную: вектор рисуется
          // своим пером и подсветку IconButton не наследует. Верхняя
          // карточка не поднимается выше — и стрелка должна это показать.
          icon: Pictogram(
            icon,
            size: 30,
            color: onPressed == null
                ? AppColors.inkSoft.withValues(alpha: 0.38)
                : AppColors.primary,
          ),
        ),
      );
}
