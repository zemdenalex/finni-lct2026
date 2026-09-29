import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/world/contract.dart';
import '../../adult/parent_questions.dart' show ChildQuestion, ChildQuestions;
import '../demo/world_checklist.dart';
import '../jobs/job_games.dart';
import '../review/learned_view.dart';
import '../pic_text.dart';
import '../shop/shop_kit.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import '../../../core/world_theme.dart';

/// S14 — раздел взрослого на новом мире (`docs/game/adult-section.md`).
///
/// Барьер (пример на умножение; неверно — раздел просто закрывается), чему
/// учит игра, общий прогресс из снимка, вопросы для разговора дома, правило
/// бонуса, «Начать игру заново» с подтверждением → онбординг, настройки
/// звука и анимаций, вход в «Проверку».
///
/// 🔴 Без оценок ребёнка: ни процентов, ни «ошибок», ни рейтингов.
///
/// Бонус взрослого (ТЗ 2.5.12.3, К4 решён 28.09) — [World.parentExtraShift]:
/// раз в неделю одна дополнительная смена, не монеты.
///
/// 🟡 Чего нет в контракте: журнал (темы по событиям и сменам «платежи»,
/// «дождался / передумал»), крупные числа (числа мира — из контента).
/// Показано то, что есть.
class WorldAdultScreen extends StatefulWidget {
  const WorldAdultScreen({super.key, this.random});

  /// Для тестов — предсказуемый пример.
  final Random? random;

  static const Key questionKey = ValueKey<String>('adult:question');
  static const Key answerKey = ValueKey<String>('adult:answer');

  /// Множители барьера: 12–29 без 20 (×20 считается в уме как ×2 и ноль).
  static const Map<int, String> factorWords = <int, String>{
    12: 'двенадцать',
    13: 'тринадцать',
    14: 'четырнадцать',
    15: 'пятнадцать',
    16: 'шестнадцать',
    17: 'семнадцать',
    18: 'восемнадцать',
    19: 'девятнадцать',
    21: 'двадцать один',
    22: 'двадцать два',
    23: 'двадцать три',
    24: 'двадцать четыре',
    25: 'двадцать пять',
    26: 'двадцать шесть',
    27: 'двадцать семь',
    28: 'двадцать восемь',
    29: 'двадцать девять',
  };

  /// Пример словами: «двадцать три × четырнадцать».
  static String questionText(int left, int right) =>
      '${factorWords[left]} × ${factorWords[right]}';

  /// Ответ на пример [question] ([questionText]) — для тестов и проверки.
  static int answerOf(String question) {
    final Map<String, int> back = <String, int>{
      for (final MapEntry<int, String> e in factorWords.entries) e.value: e.key,
    };
    final List<String> parts = question.split(' × ');
    return back[parts[0]]! * back[parts[1]]!;
  }

  @override
  State<WorldAdultScreen> createState() => _WorldAdultScreenState();
}

class _WorldAdultScreenState extends State<WorldAdultScreen> {
  final TextEditingController _answer = TextEditingController();
  late final Random _random = widget.random ?? Random();
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

  /// Двузначное на двузначное словами (Денис 29.09: «надо что-то
  /// посильнее»): ребёнку 7–11 лет в уме не решить, взрослый решит на
  /// бумаге или в калькуляторе; ответ — цифрами.
  void _newChallenge() {
    final List<int> f = WorldAdultScreen.factorWords.keys.toList();
    _left = f[_random.nextInt(f.length)];
    _right = f[_random.nextInt(f.length)];
  }

  Future<void> _tryUnlock() async {
    if (int.tryParse(_answer.text.trim()) == _left * _right) {
      WorldDemoSession.adultOpened = true;
      setState(() {
        _unlocked = true;
        _wrong = false;
        _answer.clear();
      });
      return;
    }
    // Неверно — новый пример и подсказка «для взрослых».
    setState(() {
      _wrong = true;
      _newChallenge();
      _answer.clear();
    });
  }

  void _back() {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.room);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WorldColors.night,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          // Альбомная — основная: низкая шапка.
          toolbarHeight: WorldLayout.isLandscape(context) ? 48 : null,
          leading: IconButton(
            key: const ValueKey<String>('adult:back'),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Назад',
            onPressed: _back,
          ),
          title: const Text('Взрослым'),
          actions: <Widget>[
            HelpButton(
              key: const ValueKey<String>('adult:help'),
              onPressed: () => showHelp(
                  context,
                  'Раздел для взрослого',
                  'Здесь нет игры: чему учит приложение, общий прогресс без '
                      'оценок, вопросы для разговора дома, бонус — '
                      'дополнительная смена раз в неделю — и управление '
                      'данными.\n\nВход — через пример на умножение, чтобы '
                      'ребёнок случайно не сбросил игру.'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _unlocked ? const _Content() : _barrier(context),
        ),
      );

  /// Цифра с экранной клавиатуры; «⌫» — стереть последнюю.
  void _key(String k) {
    final String t = _answer.text;
    final String next = k == _erase
        ? (t.isEmpty ? t : t.substring(0, t.length - 1))
        : (t.length >= 4 ? t : '$t$k');
    _answer.value = TextEditingValue(
        text: next, selection: TextSelection.collapsed(offset: next.length));
  }

  static const String _erase = '⌫';

  /// Барьер. Ввод — экранные цифры, системная клавиатура не выезжает
  /// (`TextInputType.none`): иначе на 640 × 360 она закрыла бы пример.
  /// Физическая клавиатура и вставка по-прежнему работают.
  Widget _barrier(BuildContext context) {
    final bool land = WorldLayout.isLandscape(context);
    final List<Widget> head = <Widget>[
      Semantics(
        header: true,
        child: const Text('Этот раздел — для взрослого', style: kitTitle),
      ),
      // Альбомная: пояснение — в подписи поля, иначе «Войти» уходит за
      // край на шрифте 1,3.
      if (!land) ...<Widget>[
        const SizedBox(height: Gap.xs),
        const Text('Решите пример и введите ответ цифрами, чтобы войти.',
            style: kitSoft),
      ],
    ];
    final Widget question = Text(WorldAdultScreen.questionText(_left, _right),
        key: WorldAdultScreen.questionKey,
        style:
            TextStyle(fontSize: land ? 20 : 24, fontWeight: FontWeight.w800));
    final Widget field = TextField(
      key: WorldAdultScreen.answerKey,
      controller: _answer,
      keyboardType: TextInputType.none,
      showCursor: true,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      style: const TextStyle(fontSize: 22),
      onSubmitted: (String _) => _tryUnlock(),
      decoration: InputDecoration(
        labelText: land ? 'Ответ цифрами' : 'Ответ',
        isDense: land,
        errorText: _wrong
            ? 'Не сходится. Этот раздел для взрослых — вот другой пример.'
            : null,
        errorMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );
    final Widget enter = FilledButton.icon(
      key: const ValueKey<String>('adult:enter'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: _tryUnlock,
      icon: const Icon(Icons.lock_open_rounded),
      label: const Text('Войти', style: TextStyle(fontSize: 16)),
    );
    final Widget pad = _DigitPad(onKey: _key, erase: _erase);

    if (land) {
      // Альбомная: пример, ответ и «Войти» слева, цифры справа.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              key: const ValueKey<String>('adult:barrier'),
              padding:
                  const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.sm),
              children: <Widget>[
                ...head,
                const SizedBox(height: Gap.sm),
                // Пример словами — слева (в две строки, если длинный),
                // поле ответа — справа: всё видно без прокрутки.
                Row(
                  children: <Widget>[
                    Expanded(child: question),
                    const SizedBox(width: Gap.sm),
                    SizedBox(width: 120, child: field),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                enter,
              ],
            ),
          ),
          SizedBox(
            width: 264,
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.md, Gap.sm),
              child: pad,
            ),
          ),
        ],
      );
    }
    return ListView(
      key: const ValueKey<String>('adult:barrier'),
      padding: const EdgeInsets.all(Gap.md),
      children: <Widget>[
        ...head,
        const SizedBox(height: Gap.md),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              question,
              const SizedBox(height: Gap.sm),
              field,
              const SizedBox(height: Gap.sm),
              pad,
              const SizedBox(height: Gap.sm),
              enter,
            ],
          ),
        ),
      ],
    );
  }
}

/// Экранные цифры барьера: 1–9, «⌫», 0. Клавиши ≥ 48 dp.
class _DigitPad extends StatelessWidget {
  const _DigitPad({required this.onKey, required this.erase});

  final void Function(String key) onKey;
  final String erase;

  static const List<List<String>> _rows = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
    <String>['7', '8', '9'],
    <String>['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey<String>('adult:pad'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int r = 0; r < _rows.length; r++)
            Padding(
              padding: EdgeInsets.only(top: r == 0 ? 0 : Gap.sm),
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < 3; c++) ...<Widget>[
                    if (c > 0) const SizedBox(width: Gap.sm),
                    Expanded(child: _key(_rows[r][c])),
                  ],
                ],
              ),
            ),
        ],
      );

  Widget _key(String k) {
    if (k.isEmpty) return const SizedBox(height: 48);
    final bool isErase = k == '⌫';
    return OutlinedButton(
      key: ValueKey<String>('adult:key:${isErase ? 'erase' : k}'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
      ),
      onPressed: () => onKey(isErase ? erase : k),
      child: isErase
          ? const Icon(Icons.backspace_outlined, semanticLabel: 'Стереть')
          : Text(k,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final WorldState st = context.watch<WorldState>();
    final ResourceSnapshot s = st.snapshot;
    // Названия — из каталога мира; неизвестный id — как есть.
    String title(String id) => st.world.catalogItem(id)?.title ?? id;
    // Откуда советы «вуза» Финни и адреса источников — только здесь, у
    // взрослого (jobs.json → university.adult_note, ТЗ §3.1.5).
    String sources = '';
    try {
      sources = context.read<JobGames>().university.adultNote;
    } on ProviderNotFoundException {
      // Раздел без содержания мини-игр (отдельный тест) — без строки.
    }
    // Порядок блоков: 0 чему учит, 1 прогресс, 2 разговор, 3 бонус,
    // 4 управление.
    final List<Widget> blocks = <Widget>[
      const _Block(
        icon: Icons.school_rounded,
        title: 'Чему учит игра',
        children: <Widget>[
          Text(
              'Каждую неделю ребёнок раскладывает карманные: НУЖНО на счета, '
              'ХОЧУ на радости, ЦЕЛЬ на мечту. Денег меньше, чем хочется, — '
              'в этом и задача.',
              style: kitText),
          SizedBox(height: Gap.xs),
          Text(
              'Заработать можно сменами на работе: сколько заплатят, видно '
              'заранее. Откладывать и ждать — такой же нормальный выбор, '
              'как купить.',
              style: kitText),
        ],
      ),
      _Block(
        icon: Icons.insights_rounded,
        title: 'Общий прогресс',
        children: <Widget>[
          // Темы ТЗ без оценок ребёнка (критерии ночи §8 п. 7).
          LearnedPanel(learning: st.world.learning, forAdult: true),
          const SizedBox(height: Gap.sm),
          const Text('Это не оценка, а то, где сейчас Финни.', style: kitSoft),
          const SizedBox(height: Gap.xs),
          _Line('Игровых недель: ${s.weekNo}', id: 'adult:weeks'),
          _Line('Финни живёт ${_lowerFirst(stageTitle(s.stage))}'),
          _Line('Очков роста: ${s.growthPoints}'),
          _Line('Смен на работе: ${s.experience}'),
          _Line(s.activeGoalId == null
              ? 'Цель сейчас не выбрана'
              : 'Цель: ${title(s.activeGoalId!)}, накоплено ${s.saved}'),
          _Line(s.owned.isEmpty
              ? 'Покупок-целей пока нет'
              : 'У Финни есть: '
                  '${s.owned.map(title).join(', ')}'),
        ],
      ),
      _Block(
        icon: Icons.forum_rounded,
        title: 'О чём поговорить дома',
        children: <Widget>[
          for (final String q in _questions(st.world))
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              child: Text('• $q', style: kitText),
            ),
          const SizedBox(height: Gap.xs),
          _ChildAsks(ChildQuestions.ofPeriod(s.weekNo < 1 ? 1 : s.weekNo)),
        ],
      ),
      const _Block(
        icon: Icons.volunteer_activism_rounded,
        title: 'Бонус от взрослого',
        children: <Widget>[_ParentBonus()],
      ),
      _Block(
        icon: Icons.tune_rounded,
        title: 'Управление',
        children: <Widget>[
          // Те же настройки, что у ребёнка по ⚙ в комнате, — без барьера
          // там, здесь просто второй путь для взрослого.
          OutlinedButton.icon(
            key: const ValueKey<String>('adult:settings'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: () =>
                Navigator.of(context).pushNamed(WorldRoutes.settings),
            icon: const Icon(Icons.settings_rounded),
            label:
                const Text('Звук и анимации', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            key: const ValueKey<String>('adult:demo'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).pushNamed(WorldRoutes.demo),
            icon: const Icon(Icons.science_rounded),
            label: const Text('Режим проверки', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: Gap.sm),
          // Шрифты (OFL) и библиотеки: тексты лицензий регистрирует main.dart.
          OutlinedButton.icon(
            key: const ValueKey<String>('adult:licenses'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: () =>
                showLicensePage(context: context, applicationName: 'Финни'),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Лицензии', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            key: const ValueKey<String>('adult:reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => _reset(context),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Начать игру заново',
                style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: Gap.sm),
          const Text(
              'Всё хранится только на этом устройстве. Аккаунта нет, '
              'имя, телефон и e-mail не спрашиваются.',
              style: kitSoft),
          if (sources.isNotEmpty) ...<Widget>[
            const SizedBox(height: Gap.sm),
            Text(sources,
                key: const ValueKey<String>('adult:sources'), style: kitSoft),
          ],
        ],
      ),
    ];
    if (!WorldLayout.isLandscape(context)) {
      return ListView(
        key: const ValueKey<String>('adult:list'),
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
        children: blocks,
      );
    }
    // Альбомная: слева прогресс и управление (сброс, проверка), справа —
    // чему учит игра, разговор дома и бонус.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            key: const ValueKey<String>('adult:list'),
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.md),
            children: <Widget>[blocks[1], blocks[4]],
          ),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey<String>('adult:list:more'),
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.md, Gap.md),
            children: <Widget>[blocks[0], blocks[2], blocks[3]],
          ),
        ),
      ],
    );
  }

  /// 2–3 открытых вопроса по тому, что видно в снимке.
  static List<String> _questions(World w) {
    final ResourceSnapshot s = w.snapshot;
    String title(String id) => w.catalogItem(id)?.title ?? id;
    return <String>[
      if (s.weekNo == 0)
        'Спросите, на что ребёнок хотел бы копить в игре и почему.',
      if (s.activeGoalId != null)
        'Спросите, почему выбрана цель «${title(s.activeGoalId!)}» '
            'и сколько ещё осталось отложить.',
      if (s.experience > 0)
        'Спросите, какая работа понравилась и почему за одну платят '
            'больше, чем за другую.',
      if (s.owned.any((String id) =>
          w.catalogItem(id)?.category == WorldCatalogCategory.pet))
        'Спросите, почему корм питомцу — обязательный счёт каждую неделю.',
      'Спросите, какое решение на этой неделе было самым трудным.',
    ].take(3).toList();
  }

  Future<void> _reset(BuildContext context) async {
    final bool yes = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Начать игру заново?'),
            content: const SingleChildScrollView(
              child: Text(
                'Весь прогресс будет стёрт: недели, монеты, копилка, цель, '
                'покупки, питомцы, очки роста, имя и облик Финни. Игра '
                'начнётся со знакомства. Отменить нельзя.',
                style: kitText,
              ),
            ),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>('adult:confirm:no'),
                style: TextButton.styleFrom(minimumSize: kitButton),
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const ValueKey<String>('adult:confirm:yes'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(c).colorScheme.error,
                  minimumSize: kitButton,
                ),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Стереть и начать'),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes || !context.mounted) return;
    await context.read<WorldState>().reset();
    if (!context.mounted) return;
    WorldDemoSession.resetDone = true;
    await Navigator.of(context)
        .pushNamedAndRemoveUntil(WorldRoutes.onboarding, (_) => false);
  }
}

/// Бонус взрослого (ТЗ 2.5.12.3): правило и кнопка «Открыть дополнительную
/// смену». Раз в неделю, только пока неделя идёт; иначе кнопка выключена и
/// под ней — почему (тот же отказ, что вернёт мир).
class _ParentBonus extends StatelessWidget {
  const _ParentBonus();

  @override
  Widget build(BuildContext context) {
    final WorldState st = context.watch<WorldState>();
    final World w = st.world;
    final bool used = w.parentBonusThisWeek;
    final int limit = w.shiftsLimitThisWeek;
    final int base = used ? limit - 1 : limit;
    final BlockReason? block = w.canDo(WorldAction.parentBonus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PicText(
            'Раз в неделю вы можете открыть Финни одну дополнительную '
            'смену — например, за дела дома. Смен на этой неделе станет '
            '${base + 1} вместо $base, взять её можно на любой работе. '
            'Монет, ⚡ и 😊 бонус не даёт: их ребёнок зарабатывает сам. '
            'Со следующей недели снова $base ${_shiftWord(base)}.',
            key: const ValueKey<String>('adult:bonus:rule'),
            style: kitText),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          key: const ValueKey<String>('adult:bonus'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: block == null ? () => _open(context, st) : null,
          icon: Icon(used ? Icons.check_rounded : Icons.work_history_rounded),
          label: Text(
              used
                  ? 'Дополнительная смена открыта'
                  : 'Открыть дополнительную смену',
              style: const TextStyle(fontSize: 16)),
        ),
        if (block != null) ...<Widget>[
          const SizedBox(height: Gap.xs),
          Text(block.text,
              key: const ValueKey<String>('adult:bonus:why'), style: kitSoft),
        ],
      ],
    );
  }

  void _open(BuildContext context, WorldState st) {
    final WorldResult r = st.act((World w) => w.parentExtraShift());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          key: const ValueKey<String>('adult:bonus:result'),
          content: Text(r.reason)));
  }
}

class _Block extends StatelessWidget {
  const _Block(
      {required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: WorldColors.text),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Semantics(
                        header: true, child: Text(title, style: kitTitle)),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              ...children,
            ],
          ),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.id});

  final String? id;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(text,
            key: id == null ? null : ValueKey<String>(id!), style: kitText),
      );
}

class _ChildAsks extends StatelessWidget {
  const _ChildAsks(this.question);

  final ChildQuestion question;

  @override
  Widget build(BuildContext context) => Panel(
        color: WorldColors.needsBg,
        padding: const EdgeInsets.all(Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.family_restroom_rounded, color: WorldColors.needs),
                SizedBox(width: Gap.sm),
                Expanded(
                  child: Text('А это ребёнок спросит у вас',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: WorldColors.needs)),
                ),
              ],
            ),
            Text(question.ask, style: kitText),
            Text(question.why, style: kitSoft),
          ],
        ),
      );
}

/// 1 смена, 3 смены, 5 смен.
String _shiftWord(int n) {
  final int m10 = n % 10;
  final int m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'смена';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'смены';
  return 'смен';
}

/// «В Москве» → «в Москве»: только первая буква, имя города остаётся.
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
