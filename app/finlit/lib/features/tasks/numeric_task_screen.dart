import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/models/task.dart';
import '../savings/coin_stepper.dart';
import 'task_kit.dart';
import 'task_scoring.dart';

/// Проигрыватель заданий [TaskKind.numericInput]: ребёнок называет число.
///
/// 🔴 Число набирается кнопками −1/+1, а не клавиатурой: §3.6.3 требует
/// крупных целей нажатия, а системная цифровая клавиатура их не даёт.
/// Заодно исчезает целый класс «ошибок», которые на самом деле промахи.
class NumericTaskScreen extends StatefulWidget {
  const NumericTaskScreen({super.key, required this.task});

  final GameTask task;

  @override
  State<NumericTaskScreen> createState() => _NumericTaskScreenState();
}

class _NumericTaskScreenState extends State<NumericTaskScreen> {
  int _value = 0;
  bool _done = false;
  bool _best = false;

  @override
  Widget build(BuildContext context) {
    final TaskParams p = TaskParams(widget.task.params);
    final int answer = p.number('answer');
    final String unit = p.text('unit') ?? 'монеток';

    return TaskScaffold(
      task: widget.task,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Твой ответ',
                    style: TextStyle(fontSize: 16, color: AppColors.inkSoft)),
                const SizedBox(height: Gap.sm),
                CoinStepper(
                  label: 'Ответ',
                  value: _value,
                  max: TaskScoring.numericMax(answer),
                  unit: unit,
                  onChanged:
                      _done ? (int _) {} : (int v) => setState(() => _value = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        if (_done) ...<Widget>[
          TaskOutcomePanel(
            title: 'Твой ответ: $_value $unit',
            lines: <String>[
              // 🔴 Ни «неправильно», ни «молодец». Только что получилось
              // и как это считают (§2.5.8.3).
              if (_best)
                'Столько и получается.'
              else
                'Получается другое число. Вот как это считают:',
            ],
            workings: p.text('workings'),
          ),
          const SizedBox(height: Gap.md),
          const TaskDoneButton(),
        ] else
          FilledButton(
            onPressed: () => _finish(answer),
            child: const Text('Ответить'),
          ),
      ],
    );
  }

  Future<void> _finish(int answer) async {
    setState(() {
      _done = true;
      _best = _value == answer;
    });
    await finishTask(context, widget.task, best: _best);
  }
}
