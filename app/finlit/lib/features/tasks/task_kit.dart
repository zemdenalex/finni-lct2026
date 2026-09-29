import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/feel.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../domain/game.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/task.dart';

/// Типизированный доступ к `params` задания.
///
/// 🔴 Нужен из-за строгого анализатора: `params` — это `Map<String, Object?>`
/// из JSON, и без разбора в одном месте каждый проигрыватель заводил бы свои
/// приведения типов, а `avoid_dynamic_calls` включён как ошибка. Заодно это
/// единственное место, где видно, какие ключи понимает приложение, —
/// §2.5.14: новое задание добавляется одним JSON-файлом.
class TaskParams {
  const TaskParams(this._raw);

  final Map<String, Object?> _raw;

  bool has(String key) => _raw[key] != null;

  int number(String key, {int or = 0}) => (_raw[key] as int?) ?? or;

  String? text(String key) => _raw[key] as String?;

  bool flag(String key) => (_raw[key] as bool?) ?? false;

  List<String> ids(String key) =>
      ((_raw[key] as List<Object?>?) ?? const <Object?>[]).cast<String>();

  List<Envelope> envelopes(String key) => ids(key).map(Envelope.byId).toList();

  Map<Envelope, int> envelopeAmounts(String key) {
    final Map<Object?, Object?>? raw = _raw[key] as Map<Object?, Object?>?;
    if (raw == null) return const <Envelope, int>{};
    return raw.map((Object? k, Object? v) =>
        MapEntry<Envelope, int>(Envelope.byId(k! as String), v! as int));
  }

  Allocation allocation(String key) {
    Allocation a = const Allocation();
    envelopeAmounts(key).forEach((Envelope e, int v) {
      a = a.withEnvelope(e, v);
    });
    return a;
  }
}

/// Завершение задания — одинаковое для всех трёх проигрывателей.
///
/// 🔴 §2.5.8.3: объяснение показывается **при любом исходе**. Поэтому здесь
/// нет ни одной ветки «если правильно»: [Game.completeTask] сам решает, что
/// сказать, и всегда говорит хотя бы `explainAny`. Флаг [best] — не «верно
/// или неверно», а «нашёлся ли лучший вариант»; у большинства заданий
/// единственно правильного ответа нет.
Future<void> finishTask(
  BuildContext context,
  GameTask task, {
  required bool best,
}) async {
  final AppState app = context.read<AppState>();
  await app.act((Game g) => g.completeTask(task, best: best));
  if (context.mounted && app.lastFeedback != null) {
    // За задание приходят монетки — отклик тот же, что у карманных.
    await showFeedback(context, app.lastFeedback!, cue: Cue.earn, cheer: true);
  }
}

/// Общая рамка проигрывателя: условие задания сверху, содержимое ниже.
class TaskScaffold extends StatelessWidget {
  const TaskScaffold({
    super.key,
    required this.task,
    required this.children,
  });

  final GameTask task;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(task.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(task.topic.title,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.inkSoft)),
                    const SizedBox(height: Gap.xs),
                    // §2.5.8.4: условие — одной фразой, слова и числа
                    // по возрасту. Длина условия проверяется на контенте.
                    Text(task.prompt,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Панель исхода: что получилось. Показывается и при лучшем варианте,
/// и при любом другом — разными словами, но одинаково спокойно.
class TaskOutcomePanel extends StatelessWidget {
  const TaskOutcomePanel({
    super.key,
    required this.title,
    required this.lines,
    this.workings,
  });

  final String title;
  final List<String> lines;

  /// Разбор вычисления (§2.5.8.3 — «короткое объяснение независимо
  /// от правильности решения»).
  final String? workings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.savingsBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.savings, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final String line in lines) ...<Widget>[
            const SizedBox(height: Gap.xs),
            Text(line, style: const TextStyle(fontSize: 16)),
          ],
          if (workings != null) ...<Widget>[
            const SizedBox(height: Gap.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Pictogram(Pic.calc,
                    size: 22, color: AppColors.savings),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(workings!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Реплика Финни. Только его слова — и никогда о его страданиях:
/// это Parasocial relationship pressure из таксономии Radesky (2022).
class FinniSays extends StatelessWidget {
  const FinniSays({super.key, required this.text, this.icon = Pic.paw});

  final String text;
  final Pic icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.needsBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.needs, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Pictogram(icon, size: 26, color: AppColors.needs),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text('Финни: $text',
                style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }
}

/// Кнопка «Готово» внизу проигрывателя: возвращает к списку заданий.
class TaskDoneButton extends StatelessWidget {
  const TaskDoneButton({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Готово'),
      );
}

/// Широкая кнопка выбора с переносимой подписью.
///
/// `FilledButton.icon` кладёт подпись в Row без Flexible, и длинная строка
/// на 360 dp при системном увеличении шрифта уезжает за край.
class TaskChoiceButton extends StatelessWidget {
  const TaskChoiceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Pic icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: <Widget>[
          Pictogram(icon, size: 24, color: AppColors.primary),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(label, textAlign: TextAlign.left)),
        ],
      ),
    );
  }
}
