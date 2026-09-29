import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../domain/game.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../../domain/ledger/ledger_fold.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/task.dart';
import '../../routes.dart';
import 'parent_questions.dart';

/// Раздел для взрослого (§2.5.12).
///
/// Три требования пункта задают весь экран:
/// §2.5.12.1 — раздел отделён от детского интерфейса простым барьером;
/// §2.5.12.2 — видны цели приложения, пройденные темы и общий прогресс,
///             🔴 **без негативных оценок ребёнка**;
/// §2.5.12.3 — правила начисления родителем дополнительных баллов команда
///             определяет самостоятельно.
/// Плюс §3.5: сброс и удаление локальных данных доступны взрослому без
/// обращения к разработчику.
///
/// 🔴 Чего здесь нет намеренно: процентов правильности, «слабых мест»,
/// сравнения с другими детьми, любых слов вида «отстаёт» и «не справился».
/// Раздел отвечает не на вопрос «как учится ребёнок», а на вопрос
/// «о чём с ним поговорить».
class AdultScreen extends StatefulWidget {
  const AdultScreen({super.key});

  /// Ключ поля с примером — по нему тест читает пример, чтобы ответить верно.
  static const Key barrierQuestionKey = Key('adult-barrier-question');
  static const Key barrierFieldKey = Key('adult-barrier-field');

  /// Одна и та же кнопка входа и выхода — см. комментарий в [_GateButton].
  static const Key gateButtonKey = Key('adult-gate-button');

  @override
  State<AdultScreen> createState() => _AdultScreenState();
}

class _AdultScreenState extends State<AdultScreen> {
  final TextEditingController _answer = TextEditingController();
  final Random _random = Random();

  late int _left;
  late int _right;
  bool _unlocked = false;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _newChallenge();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  /// Двузначное число на однозначное: 14 × 3.
  ///
  /// 🔴 Барьер «простой» по §2.5.12.1 — он и не должен быть защитой.
  /// Умножение двузначного на однозначное проходят в третьем классе, то есть
  /// нижняя половина нашей аудитории (7–8 лет) его не решит, а взрослый
  /// решает в уме за секунду. Пароль здесь был бы хуже: его забывают,
  /// а восстанавливать нечем — приложение работает без сети и без аккаунта.
  void _newChallenge() {
    _left = 11 + _random.nextInt(29); // 11…39
    _right = 3 + _random.nextInt(7); // 3…9
  }

  void _tryUnlock() {
    final int? given = int.tryParse(_answer.text.trim());
    if (given == _left * _right) {
      setState(() {
        _unlocked = true;
        _wrong = false;
        _answer.clear();
      });
      return;
    }
    setState(() {
      _wrong = true;
      _newChallenge();
      _answer.clear();
    });
  }

  Future<void> _lockAndLeave() async {
    setState(() {
      _unlocked = false;
      _wrong = false;
      _newChallenge();
      _answer.clear();
    });
    // Возврат в детскую часть, если экран открыт из навигации.
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Взрослым')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Взрослым')),
      body: SafeArea(
        child: _unlocked ? _Content(app: app) : _Barrier(state: this),
      ),
      // 🔴 Вход и выход — одна кнопка в одном и том же месте.
      // Common Sense Media отдельно ругала конкурента за то, что переключение
      // «родитель ↔ ребёнок» находится в разных местах в разные стороны:
      // взрослый выходит не туда и оставляет раздел открытым ребёнку.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
          child: _GateButton(
            unlocked: _unlocked,
            onPressed: _unlocked ? _lockAndLeave : _tryUnlock,
          ),
        ),
      ),
    );
  }
}

class _GateButton extends StatelessWidget {
  const _GateButton({required this.unlocked, required this.onPressed});

  final bool unlocked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: AdultScreen.gateButtonKey,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(TapSize.primary),
      ),
      icon: Pictogram(unlocked ? Pic.lock : Pic.lockOpen,
          color: AppColors.onAction),
      label: Text(unlocked ? 'Выйти в детский режим' : 'Войти в раздел'),
      onPressed: onPressed,
    );
  }
}

class _Barrier extends StatelessWidget {
  const _Barrier({required this.state});

  final _AdultScreenState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
      children: <Widget>[
        Semantics(
          header: true,
          child: Text('Этот раздел — для взрослого',
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: Gap.sm),
        const Text(
          'Здесь нет игры: только то, что помогает поговорить с ребёнком, '
          'и управление данными. Решите пример, чтобы войти.',
          style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
        ),
        const SizedBox(height: Gap.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${state._left} × ${state._right}',
                  key: AdultScreen.barrierQuestionKey,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: Gap.sm),
                TextField(
                  key: AdultScreen.barrierFieldKey,
                  controller: state._answer,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: const TextStyle(fontSize: 22),
                  onSubmitted: (String _) => state._tryUnlock(),
                  decoration: InputDecoration(
                    labelText: 'Ответ',
                    labelStyle: const TextStyle(fontSize: 16),
                    // §3.6.5: ошибка передаётся не только цветом рамки,
                    // но и текстом.
                    errorText:
                        state._wrong ? 'Не сходится. Вот другой пример.' : null,
                    errorStyle: const TextStyle(fontSize: 16),
                    border: const OutlineInputBorder(),
                    constraints:
                        const BoxConstraints(minHeight: TapSize.min),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
      children: <Widget>[
        const _TeachingBlock(),
        const SizedBox(height: Gap.md),
        _TopicsBlock(app: app),
        const SizedBox(height: Gap.md),
        _QuestionsBlock(app: app),
        const SizedBox(height: Gap.md),
        _DataBlock(app: app),
      ],
    );
  }
}

/// Карточка раздела: заголовок, пояснение одной строкой, содержимое.
class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final Pic icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Pictogram(icon, size: 26, color: AppColors.primary),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: Gap.xs),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 16, color: AppColors.inkSoft)),
            ],
            const SizedBox(height: Gap.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Блок 1 — чему учит приложение (§2.5.12.2, «цели приложения»).
class _TeachingBlock extends StatelessWidget {
  const _TeachingBlock();

  @override
  Widget build(BuildContext context) {
    return const _Block(
      icon: Pic.school,
      title: 'Чему учит приложение',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Каждую игровую неделю ребёнок принимает три решения: сколько '
            'оставить на нужное, сколько на желаемое и сколько отложить. '
            'Монеток всегда меньше, чем хочется, — и это не поломка, а суть '
            'задачи.',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: Gap.sm),
          Text(
            'Решения принимает ребёнок. Приложение не подсказывает «правильный» '
            'ответ и не наказывает за отказ от покупки: отложить или '
            'перенести — такой же нормальный исход, как купить.',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: Gap.md),
          // Прямая цитата из Единой рамки компетенций финансовой грамотности,
          // возрастная группа 7–11 лет. Цитата, а не пересказ: взрослому важно
          // видеть, что игра привязана к рамке, а не к фантазии команды.
          _Quote(
            'Делать выбор в пользу необходимого, а не желаемого при '
            'ограниченном бюджете',
            source: 'Единая рамка компетенций, 7–11 лет',
          ),
          SizedBox(height: Gap.md),
          Text(
            'Рамка отдельно оговаривает, что в этом возрасте ребёнок осваивает '
            'такие решения при участии значимого взрослого. Поэтому ниже — не '
            'оценки, а то, о чём с ним стоит поговорить.',
            style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote(this.text, {required this.source});

  final String text;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.needsBg,
        borderRadius: BorderRadius.circular(14),
        border: const Border(
            left: BorderSide(color: AppColors.needs, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('«$text»',
              style: const TextStyle(
                  fontSize: 16, fontStyle: FontStyle.italic)),
          const SizedBox(height: Gap.xs),
          Text(source,
              style:
                  const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

/// Блок 2 — пройденные темы (§2.5.12.2).
///
/// 🔴 Ни процентов, ни «правильно/неправильно», ни списка ошибок. Только
/// перечень тем, которых ребёнок уже касался: пункт ТЗ требует показать
/// пройденные темы, и он же запрещает негативные оценки.
class _TopicsBlock extends StatelessWidget {
  const _TopicsBlock({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final Game g = app.game;
    final Set<String> knownIds =
        g.content.tasks.map((GameTask t) => t.id).toSet();

    // Порядок — по темам, а не по времени: взрослому нужен охват,
    // а не хронология.
    final Map<TaskTopic, Set<String>> byTopic = <TaskTopic, Set<String>>{};
    for (final String id in g.profile.completedTaskIds) {
      if (!knownIds.contains(id)) continue; // задание убрали из контента
      final GameTask t = g.content.task(id);
      byTopic.putIfAbsent(t.topic, () => <String>{}).add(t.title);
    }

    final int points = g.snapshot.carePoints;

    return _Block(
      icon: Pic.list,
      title: 'Пройденные темы',
      subtitle: 'Темы, которых ребёнок уже касался. Это не оценка и не '
          'проверка знаний.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (byTopic.isEmpty)
            const Text(
              'Заданий пока не было. Они появляются на главном экране каждую '
              'игровую неделю.',
              style: TextStyle(fontSize: 16),
            )
          else
            for (final TaskTopic topic in TaskTopic.values)
              if (byTopic.containsKey(topic))
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(topic.title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: Gap.xs),
                      for (final String title in byTopic[topic]!)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Pictogram(Pic.check,
                                  size: 20, color: AppColors.needs),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: Text(title,
                                    style: const TextStyle(fontSize: 16)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
          const Divider(height: Gap.lg),
          // «Общий прогресс» из §2.5.12.2 — в тех же единицах, что видит
          // ребёнок: очки заботы и стадия Финни. Очки не уменьшаются,
          // поэтому эта строка не может прозвучать как упрёк.
          Text('Игровых недель пройдено: ${g.periodNo}',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: Gap.xs),
          Text('Очков заботы накоплено: $points',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: Gap.xs),
          Text('Финни сейчас: ${g.snapshot.stage.title}',
              style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

/// Блок 3 — «О чём спросить».
class _QuestionsBlock extends StatelessWidget {
  const _QuestionsBlock({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final Game g = app.game;

    // Разговор идёт про **завершённую** неделю: её итог ребёнок уже видел
    // на экране прогресса. Если завершённой недели ещё нет — берём текущую,
    // иначе первый же заход взрослого показывает пустой экран.
    final List<LedgerEntry> lastWeek =
        LedgerFold.ofPeriod(g.ledger, g.periodNo - 1);
    final List<LedgerEntry> week = lastWeek.isNotEmpty
        ? lastWeek
        : LedgerFold.ofPeriod(g.ledger, g.periodNo);
    final List<ParentQuestion> questions = ParentQuestions.from(week);

    final String when = lastWeek.isNotEmpty
        ? 'По прошлой игровой неделе (№ ${g.periodNo - 1})'
        : 'По текущей игровой неделе (№ ${g.periodNo})';

    return _Block(
      icon: Pic.speech,
      title: 'О чём спросить',
      subtitle: '$when. Вопросы открытые: у них нет правильного ответа, '
          'который нужно угадать.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final ParentQuestion q in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: Container(
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: AppColors.savingsBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(q.about,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.inkSoft)),
                    const SizedBox(height: Gap.xs),
                    Text(q.ask,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          const Divider(height: Gap.xl),
          _ChildAsksYou(question: ChildQuestions.ofPeriod(g.periodNo)),
        ],
      ),
    );
  }
}

/// 🔴 Обратное направление разговора. Всё остальное в этом разделе
/// подсказывает взрослому, о чём спросить ребёнка, — то есть оставляет
/// взрослого проверяющим. Здесь наоборот: ребёнок спрашивает взрослого,
/// и отвечать придётся про себя.
///
/// Это не украшение: самое надёжное, что даёт финансовое образование по
/// данным испытаний, — не знания и не самоконтроль, а разговоры о деньгах
/// дома. А передаётся отношение к деньгам не тем, что взрослый делает,
/// а тем, что он об этом рассказывает.
class _ChildAsksYou extends StatelessWidget {
  const _ChildAsksYou({required this.question});

  final ChildQuestion question;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.needsBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.needs, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Pictogram(Pic.family, size: 22, color: AppColors.needs),
              const SizedBox(width: Gap.sm),
              // Expanded обязателен: на 360 dp при увеличенном системном
              // шрифте строка не помещается, и Row переполняется.
              const Expanded(
                child: Text('А это ребёнок спросит у вас',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.needs)),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(question.ask,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: Gap.xs),
          Text(question.why,
              style: const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
          const SizedBox(height: Gap.sm),
          const Text(
            'Отвечать про суммы не нужно и не стоит: разговор про выбор '
            'работает, разговор про нехватку — пугает.',
            style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// Блок 4 — управление данными (§2.5.12.3, §3.5, §3.6).
class _DataBlock extends StatelessWidget {
  const _DataBlock({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return _Block(
      icon: Pic.sliders,
      title: 'Управление',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // §2.5.12.3 оставляет правила начисления родителем на усмотрение
          // команды. 🔴 Мы даём взрослому открыть **задание**, а не монетки.
          // Монетки от родителя обнуляют ограниченность ресурсов (§2.1) и
          // учат «попроси у мамы» вместо «спланируй и заработай».
          const Text(
            'Взрослый может открыть ребёнку дополнительное задание. Монетки '
            'за него ребёнок получит сам, выполнив задание: денег «просто '
            'так» в игре нет — иначе исчезает главное ограничение.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: Gap.sm),
          Text('Дополнительных заданий открыто: '
              '${app.game.profile.parentUnlockedTasks}',
              style: const TextStyle(
                  fontSize: 16, color: AppColors.inkSoft)),
          const SizedBox(height: Gap.sm),
          FilledButton.icon(
            icon: const Pictogram(Pic.task, color: AppColors.onAction),
            label: const Text('Открыть дополнительное задание'),
            onPressed: () async {
              await app.act((Game g) => g.parentUnlockTask());
              if (!context.mounted) return;
              if (app.lastFeedback != null) {
                await showFeedback(context, app.lastFeedback!);
              }
            },
          ),
          const Divider(height: Gap.xl),

          // §3.5: «сброс и удаление локальных данных доступны взрослому без
          // обращения к разработчику». §3.6: действия, заметно меняющие
          // прогресс, требуют подтверждения — поэтому оба через диалог.
          const Text(
            'Сброс и удаление данных доступны здесь и не требуют обращения '
            'к разработчику.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            icon: const Pictogram(Pic.undo, color: AppColors.primary),
            label: const Text('Сбросить прогресс'),
            onPressed: () => _resetProgress(context),
          ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                  color: Theme.of(context).colorScheme.error, width: 2),
            ),
            icon: Pictogram(Pic.trash,
                color: Theme.of(context).colorScheme.error),
            label: const Text('Удалить профиль'),
            onPressed: () => _deleteProfile(context),
          ),
          const Divider(height: Gap.xl),

          // §2.5.13: демонстрационный режим предусмотрен «для экспертной
          // проверки», а эксперт здесь — взрослый. Это его естественное
          // место: ребёнку тестовый профиль не нужен, а с главного экрана
          // ссылка на демо показывалась только когда режим уже включён.
          const Text(
            'Демонстрационный режим переключает игру на отдельный тестовый '
            'профиль и открывает экран «Проверка» — список шагов приёмки. '
            'Игра ребёнка при этом не меняется и ждёт на своём месте.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            icon: const Pictogram(Pic.flask, color: AppColors.primary),
            label: const Text('Демонстрационный режим и проверка'),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.demo),
          ),
          const Divider(height: Gap.xl),
          const _StorageNote(),
        ],
      ),
    );
  }

  Future<void> _resetProgress(BuildContext context) async {
    final bool ok = await _confirm(
      context,
      title: 'Сбросить прогресс?',
      body: 'Игровые недели, монетки, покупки, копилка и выполненные задания '
          'будут удалены. Финни останется тем же — имя, вид и цвет '
          'сохранятся, как и настройки. Отменить это действие нельзя.',
      action: 'Сбросить',
    );
    if (!ok || !context.mounted) return;

    final GameProfile before = app.game.profile;
    final bool demo = app.demoMode;
    await app.deleteActiveProfile();
    // Сброс прогресса — не то же самое, что удаление профиля: питомца,
    // которого ребёнок выбирал и называл, терять незачем. Настройки
    // доступности тем более: они не прогресс.
    await app.updateProfile(
      GameProfile.fresh(isDemo: demo).copyWith(
        petName: before.petName,
        species: before.species,
        palette: before.palette,
        settings: before.settings,
      ),
    );
    if (!context.mounted) return;
    _say(
      context,
      demo
          ? 'Прогресс тестового профиля сброшен. Игра ребёнка не тронута.'
          : 'Прогресс сброшен. Финни остался на месте.',
    );
  }

  Future<void> _deleteProfile(BuildContext context) async {
    final bool demo = app.demoMode;
    final bool ok = await _confirm(
      context,
      title: demo ? 'Удалить тестовый профиль?' : 'Удалить профиль?',
      body: demo
          ? 'Будет удалён тестовый профиль демонстрационного режима. Игра '
              'ребёнка останется на своём месте: она хранится отдельно.'
          : 'Будет удалено всё: питомец, его имя и внешний вид, монетки, '
              'копилка, цель и история недель. Данные хранятся только на этом '
              'устройстве, восстановить их будет неоткуда.',
      action: 'Удалить',
    );
    if (!ok || !context.mounted) return;
    await app.deleteActiveProfile();
    if (!context.mounted) return;
    _say(
      context,
      demo
          ? 'Тестовый профиль удалён. Игра ребёнка не тронута.'
          : 'Профиль удалён. Игра начнётся заново.',
    );
  }

  void _say(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, style: const TextStyle(fontSize: 16))),
    );
  }
}

/// Подтверждение разрушительного действия (§3.6: «удаление данных и другие
/// действия, заметно меняющие прогресс, требуют подтверждения»).
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 22)),
      content: Text(body, style: const TextStyle(fontSize: 16)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            minimumSize: const Size(120, TapSize.min),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Какие данные хранит приложение (§3.5).
class _StorageNote extends StatelessWidget {
  const _StorageNote();

  @override
  Widget build(BuildContext context) {
    const List<String> facts = <String>[
      'Всё хранится только на этом устройстве, в файле приложения.',
      'Ничего не передаётся: приложение работает без сети.',
      'Аккаунта и регистрации нет.',
      'Имя, возраст, телефон и e-mail не спрашиваются и нигде не хранятся.',
      'Особых разрешений Android приложение не запрашивает.',
      'Рекламы и покупок внутри приложения нет.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Какие данные хранит приложение',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: Gap.sm),
        // Замок перед каждой из шести строк не добавлял ни одного смысла —
        // он повторял заголовок блока шесть раз подряд. Строки читаются
        // списком; значок стоял тут только для красоты.
        for (final String f in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: Text(f, style: const TextStyle(fontSize: 16)),
          ),
      ],
    );
  }
}
