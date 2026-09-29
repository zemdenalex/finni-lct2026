import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../domain/demo_autopilot.dart';
import '../../domain/economy/economy_config.dart';
import '../../domain/game.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/envelope.dart';
import 'expert_checklist.dart';

/// Демонстрационный режим и экран «Проверка» (§2.5.13, Приложение А ТЗ).
///
/// §2.5.13.2 дословно: «для экспертной проверки предусмотрен демонстрационный
/// режим с тестовым профилем: обязательные этапы игрового цикла
/// воспроизводятся подряд без ожидания календарных сроков, а тестовый профиль
/// сбрасывается к исходному состоянию».
///
/// Экран из двух частей: панель управления (промотать цикл) и чеклист из
/// 12 шагов Приложения А, где статус каждого шага выводится из журнала.
/// 🔴 Вторая часть — главная: мы делаем работу эксперта за него, а не
/// оставляем ему таблицу для ручных галочек.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  /// Сброс тестового профиля в этом сеансе. В журнале не остаётся следа
  /// по определению — журнал очищается, — поэтому факт живёт здесь.
  bool _demoResetWasDone = false;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Проверка')));
    }

    final List<ExpertStep> steps =
        ExpertChecklist.of(app.game, demoResetWasDone: _demoResetWasDone);

    return Scaffold(
      appBar: AppBar(title: const Text('Проверка')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
          children: <Widget>[
            _Panel(app: app, onDemoReset: _markDemoReset),
            const SizedBox(height: Gap.lg),
            _ChecklistHeader(steps: steps),
            const SizedBox(height: Gap.md),
            for (final ExpertStep s in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: _StepTile(step: s),
              ),
          ],
        ),
      ),
    );
  }

  void _markDemoReset() => setState(() => _demoResetWasDone = true);
}

// ───────────────────────── А. Панель управления ─────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({required this.app, required this.onDemoReset});

  final AppState app;
  final VoidCallback onDemoReset;

  @override
  Widget build(BuildContext context) {
    final bool demo = app.demoMode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: const Text('Панель управления',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: Gap.sm),
            SwitchListTile.adaptive(
              value: demo,
              onChanged: (bool v) => app.setDemoMode(v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Демонстрационный режим',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Отдельный тестовый профиль. Игра ребёнка остаётся нетронутой '
                'и ждёт на своём месте.',
                style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
              ),
            ),
            const Divider(height: Gap.lg),
            if (!demo)
              const Padding(
                padding: EdgeInsets.only(bottom: Gap.sm),
                child: Text(
                  'Кнопки ниже работают только в демонстрационном режиме: '
                  'иначе они промотали бы недели в игре ребёнка.',
                  style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
                ),
              ),
            _ActionRow(
              icon: Pic.check,
              title: 'Завершить неделю',
              subtitle: 'Считает очки заботы, сравнивает план с фактом и '
                  'переводит игру на следующую неделю.',
              onPressed: demo ? () => _closePeriod(context) : null,
            ),
            _ActionRow(
              icon: Pic.coin,
              title: 'Начислить карманные',
              subtitle: 'Выдаёт карманные новой недели сразу, без ожидания '
                  'календарных сроков.',
              onPressed: demo ? () => _startPeriod(context) : null,
            ),
            _ActionRow(
              icon: Pic.umbrella,
              title: 'Вызвать непредвиденный расход',
              subtitle: 'Проматывает игру до первой недели с непредвиденной '
                  'тратой и оставляет решение эксперту.',
              onPressed: demo ? () => _toUnexpected(context) : null,
            ),
            _ActionRow(
              icon: Pic.star,
              title: 'Дойти до стадии «Хранитель копилки»',
              subtitle: 'Проигрывает недели обычными действиями: самая '
                  'дешёвая еда и вода, остальное — в копилку. Это не '
                  'подсказка ребёнку, а быстрый путь к третьей стадии, '
                  'где растёт доверие и Финни раскладывает монетки сам.',
              onPressed: demo ? () => _toPlanner(context) : null,
            ),
            _ActionRow(
              icon: Pic.undo,
              title: 'Сбросить тестовый профиль',
              subtitle: 'Возвращает тестовый профиль к исходному состоянию. '
                  'Профиля ребёнка не касается.',
              onPressed: () => _resetDemo(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _closePeriod(BuildContext context) async {
    await app.closePeriod();
    if (!context.mounted) return;
    _say(context, 'Неделя закрыта. Идёт неделя № ${app.game.periodNo}.');
  }

  Future<void> _startPeriod(BuildContext context) async {
    await app.act((Game g) => g.startPeriod());
    if (!context.mounted || app.lastFeedback == null) return;
    await showFeedback(context, app.lastFeedback!);
  }

  /// Промотка до недели с непредвиденным расходом.
  ///
  /// Здесь нет ни одной формулы: цикл только вызывает те же действия домена,
  /// что и ребёнок на экранах. Это и есть «обязательные этапы игрового цикла
  /// воспроизводятся подряд» из §2.5.13.2.
  Future<void> _toUnexpected(BuildContext context) async {
    final int target = app.game.content.economy.unexpectedPeriod;
    if (app.game.periodNo > target) {
      _say(
        context,
        'Неделя № $target уже позади. Сбросьте тестовый профиль, чтобы '
        'повторить этот эпизод.',
      );
      return;
    }

    await app.act((Game g) {
      // Ограничитель на случай, если экономика когда-нибудь изменится так,
      // что неделя перестанет закрываться: зависший цикл в демонстрации
      // выглядит хуже, чем недомотанная игра.
      int guard = 0;
      while (g.periodNo < target && guard < 20) {
        guard++;
        _autoWeek(g);
        g.closePeriod();
      }
      _autoWeek(g);
      final UnexpectedEvent event = g.unexpectedThisWeek!;
      return ActionResult(
        title: event.title,
        text: 'Игра промотана до недели с непредвиденной тратой: '
            '${event.need.toLowerCase()} — ${event.cost}. Заплатить можно '
            'из копилки или из «Хочу», заработать на задании — или обойтись '
            'и перенести на следующую неделю. Дальше такие траты приходят '
            'каждые ${g.content.economy.unexpectedEvery} недели, каждый раз '
            'другие.',
        nextStep: 'Откройте копилку или главный экран и примите решение',
      );
    });
    if (!context.mounted || app.lastFeedback == null) return;
    await showFeedback(context, app.lastFeedback!);
  }

  Future<void> _toPlanner(BuildContext context) async {
    if (app.game.snapshot.stage == PetStage.planner) {
      _say(context, 'Финни уже «Хранитель копилки». Откройте план недели.');
      return;
    }
    await app.act((Game g) {
      final int weeks = DemoAutopilot.playTo(g, PetStage.planner);
      return ActionResult(
        title: 'Финни — «Хранитель копилки»',
        text: 'Проиграно недель: $weeks. Родители теперь дают меньшую часть, '
            'а заработать можно больше. Откройте план недели: Финни '
            'предложит раскладку по привычке последних недель.',
        nextStep: 'Главный экран → план недели',
      );
    });
    if (!context.mounted || app.lastFeedback == null) return;
    await showFeedback(context, app.lastFeedback!);
  }

  /// Автопилот одной недели: начислить карманные и подтвердить план.
  ///
  /// 🔴 Весь остаток уходит в «Нужное». Автопилот намеренно не изобретает
  /// распределение: раскладывать монетки — это решение ребёнка (§2.5.5),
  /// и придуманные здесь доли выглядели бы как «правильный» ответ игры.
  static void _autoWeek(Game g) {
    if (g.phase == PeriodPhase.closing) g.startPeriod();
    if (g.phase == PeriodPhase.planning) {
      g.confirmPlan(Allocation(needs: g.snapshot.wallet.unallocated));
    }
  }

  Future<void> _resetDemo(BuildContext context) async {
    // §3.6: действия, заметно меняющие прогресс, требуют подтверждения —
    // даже в тестовом профиле, иначе эксперт теряет свой же сценарий.
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Сбросить тестовый профиль?',
                style: TextStyle(fontSize: 22)),
            content: const Text(
              'Тестовый профиль вернётся к исходному состоянию: недели, '
              'монетки, покупки и копилка будут очищены. Профиль ребёнка '
              'останется нетронутым.',
              style: TextStyle(fontSize: 16),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(120, TapSize.min)),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Сбросить'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await app.resetDemoProfile();
    onDemoReset();
    if (!context.mounted) return;
    _say(context, 'Тестовый профиль сброшен к исходному состоянию.');
  }

  void _say(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, style: const TextStyle(fontSize: 16))),
    );
  }
}

/// Кнопка панели с одной строкой о том, что она делает.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final Pic icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: onPressed,
            // 🔴 Вектор про «выключено» от кнопки не узнаёт: цвет задаётся
            // вручную, иначе неактивная строка панели выглядит рабочей.
            icon: Pictogram(icon,
                color: onPressed == null
                    ? AppColors.inkSoft.withValues(alpha: 0.38)
                    : AppColors.primary),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(title),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(TapSize.min),
              alignment: Alignment.centerLeft,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: Gap.xs),
            child: Text(subtitle,
                style:
                    const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Б. Экран «Проверка» ─────────────────────────

class _ChecklistHeader extends StatelessWidget {
  const _ChecklistHeader({required this.steps});

  final List<ExpertStep> steps;

  @override
  Widget build(BuildContext context) {
    final int done = ExpertChecklist.doneCount(steps);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text('Проверка по Приложению А',
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: Gap.xs),
        Text('Выполнено $done из ${steps.length} шагов',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: Gap.sm),
        const Text(
          'Шаги с пометкой «по журналу» приложение отмечает само: отметка '
          'выводится из записей журнала и профиля, вручную её поставить '
          'нельзя. Шаги с пометкой «подтверждает эксперт» приложение '
          'доказать о себе не может — рядом написано, на что смотреть.',
          style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final ExpertStep step;

  @override
  Widget build(BuildContext context) {
    final bool done = step.done;
    final Color accent = done ? AppColors.needs : AppColors.inkSoft;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // §3.6.5: смысл несут три канала — иконка, форма и подпись
                // словами. Цвет только четвёртый.
                Pictogram(
                  done ? Pic.check : Pic.circleEmpty,
                  size: 28,
                  color: accent,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Шаг ${step.no}',
                          style: const TextStyle(
                              fontSize: 16, color: AppColors.inkSoft)),
                      Text(step.title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              children: <Widget>[
                _Tag(text: step.statusLabel, strong: done),
                _Tag(
                  text: step.source == CheckSource.ledger
                      ? 'по журналу'
                      : 'подтверждает эксперт',
                ),
              ],
            ),
            if (step.parts.isNotEmpty) ...<Widget>[
              const SizedBox(height: Gap.sm),
              for (final CheckPart p in step.parts)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Pictogram(p.done ? Pic.check : Pic.minus,
                          size: 20,
                          color: p.done ? AppColors.needs : AppColors.inkSoft),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          '${p.title} — ${p.done ? 'есть' : 'пока нет'}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: Gap.sm),
            Text(step.evidence,
                style:
                    const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            if (step.route != null) ...<Widget>[
              const SizedBox(height: Gap.sm),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, step.route!),
                icon: const Pictogram(Pic.external, color: AppColors.primary),
                label: const Text('Открыть экран'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(TapSize.min)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: strong ? AppColors.needsBg : AppColors.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: strong ? AppColors.needs : AppColors.line, width: 1.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: strong ? AppColors.needs : AppColors.inkSoft,
        ),
      ),
    );
  }
}
