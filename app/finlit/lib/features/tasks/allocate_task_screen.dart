import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/task.dart';
import '../savings/coin_stepper.dart';
import 'task_kit.dart';
import 'task_scoring.dart';

/// Проигрыватель заданий [TaskKind.allocate].
///
/// Внутри два сценария, и оба — «игровая ситуация с выбором и последствиями»
/// (§2.5.8.2), а не выбор ответа из вариантов:
/// * разложить сумму по конвертам (в том числе исправить Финни);
/// * решить, откуда взять деньги на неожиданную трату.
class AllocateTaskScreen extends StatelessWidget {
  const AllocateTaskScreen({super.key, required this.task});

  final GameTask task;

  @override
  Widget build(BuildContext context) {
    final TaskParams p = TaskParams(task.params);
    return p.has('sources')
        ? _SourceBody(task: task, params: p)
        : _SplitBody(task: task, params: p);
  }
}

// ───────────────────── разложить по конвертам ─────────────────────

class _SplitBody extends StatefulWidget {
  const _SplitBody({required this.task, required this.params});

  final GameTask task;
  final TaskParams params;

  @override
  State<_SplitBody> createState() => _SplitBodyState();
}

class _SplitBodyState extends State<_SplitBody> {
  late Allocation _a;
  bool _done = false;
  bool _best = false;

  bool get _isFinniMistake => widget.params.has('finniProposal');

  @override
  void initState() {
    super.initState();
    // 🔴 В задании «Финни ошибается» стартуем не с нуля, а с его раскладки:
    // ребёнок не раскладывает заново, а **исправляет**. Это и есть разница
    // между «ухаживать за питомцем» и «учить питомца».
    _a = _isFinniMistake
        ? widget.params.allocation('finniProposal')
        : const Allocation();
  }

  @override
  Widget build(BuildContext context) {
    final int amount = widget.params.number('amount');
    final int placed = _a.total;
    final int left = amount - placed;

    return TaskScaffold(
      task: widget.task,
      children: <Widget>[
        if (_isFinniMistake && !_done) ...<Widget>[
          FinniSays(text: widget.params.text('finniSays') ?? ''),
          const SizedBox(height: Gap.sm),
          const Text(
            'Финни не обидится. Поправь, как считаешь нужным.',
            style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
          const SizedBox(height: Gap.md),
        ],
        if (_done) ...<Widget>[
          if (_isFinniMistake) ...<Widget>[
            // Финни благодарит и говорит, что понял. Он не грустит и не
            // обижается: ребёнок здесь учитель, а не виноватый.
            const FinniSays(
                text: 'Понял! Сначала еда, потом всё остальное. '
                    'Спасибо за подсказку.',
                icon: Pic.smile),
            const SizedBox(height: Gap.md),
          ],
          TaskOutcomePanel(
            title: 'Вот как вышло',
            lines: <String>[
              for (final Envelope e in Envelope.values)
                '${e.title}: ${_a.byEnvelope(e)} ${Coins.word(_a.byEnvelope(e))}',
            ],
          ),
          const SizedBox(height: Gap.md),
          const TaskDoneButton(),
        ] else ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Разложено $placed из $amount',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: Gap.xs),
                  Text(
                    left > 0
                        ? 'Осталось разложить $left ${Coins.word(left)}'
                        : 'Все монетки разложены',
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          for (final Envelope e in Envelope.values) ...<Widget>[
            _EnvelopeStepper(
              envelope: e,
              value: _a.byEnvelope(e),
              max: _a.byEnvelope(e) + left,
              onChanged: (int v) => setState(() => _a = _a.withEnvelope(e, v)),
            ),
            const SizedBox(height: Gap.sm),
          ],
          const SizedBox(height: Gap.sm),
          FilledButton(
            onPressed: left == 0 ? _finish : null,
            child: Text(_isFinniMistake
                ? 'Объяснить Финни'
                : 'Готово, так и разложим'),
          ),
          if (left != 0)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Text(
                'Кнопка заработает, когда разложишь все $amount '
                '${Coins.word(amount)}.',
                style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _finish() async {
    final bool best =
        TaskScoring.covers(_a, widget.params.envelopeAmounts('mustCover'));
    setState(() {
      _done = true;
      _best = best;
    });
    await finishTask(context, widget.task, best: _best);
  }
}

class _EnvelopeStepper extends StatelessWidget {
  const _EnvelopeStepper({
    required this.envelope,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final Envelope envelope;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color c = AppColors.of(envelope);
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.bgOf(envelope),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.35), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Pictogram(AppColors.picOf(envelope), size: 24, color: c),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(envelope.title,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: c)),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          // §3.6: смысл конверта подписан рядом, а не спрятан в справку.
          Text(envelope.hint,
              style: const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
          const SizedBox(height: Gap.sm),
          CoinStepper(
            label: envelope.title,
            value: value,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ───────────────────── откуда взять монетки ─────────────────────

class _SourceBody extends StatefulWidget {
  const _SourceBody({required this.task, required this.params});

  final GameTask task;
  final TaskParams params;

  @override
  State<_SourceBody> createState() => _SourceBodyState();
}

class _SourceBodyState extends State<_SourceBody> {
  String? _outcome;

  @override
  Widget build(BuildContext context) {
    final int amount = widget.params.number('amount');
    final List<Envelope> sources = widget.params.envelopes('sources');
    final String? deferLabel = widget.params.text('deferLabel');

    return TaskScaffold(
      task: widget.task,
      children: <Widget>[
        if (_outcome != null) ...<Widget>[
          TaskOutcomePanel(
            title: 'Вот как вышло',
            lines: <String>[_outcome!],
          ),
          const SizedBox(height: Gap.md),
          const TaskDoneButton(),
        ] else ...<Widget>[
          Text('Откуда взять $amount ${Coins.word(amount)}?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: Gap.sm),
          const Text(
            'Все варианты нормальные. У каждого свои последствия.',
            style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
          const SizedBox(height: Gap.md),
          for (int i = 0; i < sources.length; i++) ...<Widget>[
            TaskChoiceButton(
              icon: AppColors.picOf(sources[i]),
              label: 'Взять из «${sources[i].title}»',
              // 🔴 Лучший исход — первый источник в списке: в контенте первым
              // стоит тот, который ребёнок готовил заранее (для «Дождливого
              // дня» это копилка). Правило живёт в данных, а не в коде экрана,
              // поэтому новое задание того же вида не требует правок здесь.
              onPressed: () => _finish(
                'Взято $amount ${Coins.word(amount)} '
                'из «${sources[i].title}».',
                best: i == 0,
              ),
            ),
            const SizedBox(height: Gap.sm),
          ],
          // 🔴 Четвёртый выход — не платить — подан такой же кнопкой, как
          // остальные. Без него это не выбор, а налог со способами оплаты.
          if (widget.params.flag('allowDefer') && deferLabel != null)
            TaskChoiceButton(
              icon: Pic.house,
              label: deferLabel,
              onPressed: () => _finish(
                'Обойтись тем, что есть дома, и перенести покупку '
                'на следующую неделю — тоже решение.',
                best: false,
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _finish(String outcome, {required bool best}) async {
    setState(() => _outcome = outcome);
    await finishTask(context, widget.task, best: best);
  }
}
