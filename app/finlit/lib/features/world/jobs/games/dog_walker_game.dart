import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/feel.dart';
import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/world_theme.dart';
import '../../world_layout.dart';
import '../job_games.dart';
import '../mini_games.dart';

/// Выгульщик собак: провести собаку по тропинке, собрать всё, что на ней
/// лежит, и привести её домой.
///
/// Прогулки, предметы и препятствия — `content/jobs.json →
/// jobs.dog_walker` ([DogWalkContent]); самый короткий путь каждой прогулки
/// ([DogWalkLevel.bestSteps]) проверяет тест своим BFS.
///
/// Таймера нет. Нажатие на препятствие или на дом раньше времени — шаг не
/// считается. Оценка — `bestSteps / шаги`, не ниже 0,5: лишние шаги только
/// уменьшают бонус, ставку не трогают. Урок работы — «Про запас»: монета на
/// тропинке — заработок, лужа — неожиданная трата, её обходят.
@immutable
class DogWalkItem {
  const DogWalkItem({required this.name, required this.found});

  factory DogWalkItem.fromData(JobData d) =>
      DogWalkItem(name: dStr(d, 'name'), found: dStr(d, 'found'));

  /// Как назвать клетку вслух: «монета», «мячик».
  final String name;

  /// Что сказать, когда собака подобрала.
  final String found;
}

@immutable
class DogWalkBlock {
  const DogWalkBlock({required this.name, required this.note});

  factory DogWalkBlock.fromData(JobData d) =>
      DogWalkBlock(name: dStr(d, 'name'), note: dStr(d, 'note'));

  final String name;

  /// Что сказать, когда ребёнок нажал на препятствие.
  final String note;
}

@immutable
class DogWalkLevel {
  const DogWalkLevel({
    required this.id,
    required this.title,
    required this.map,
    required this.bestSteps,
  });

  factory DogWalkLevel.fromData(JobData d) => DogWalkLevel(
        id: dStr(d, 'id'),
        title: dStr(d, 'title'),
        map: dStrs(d, 'map'),
        bestSteps: dInt(d, 'best_steps'),
      );

  final String id;
  final String title;

  /// Карта: `S` старт, `G` дом, `.` тропинка; остальные буквы — предметы
  /// ([DogWalkContent.items]) и препятствия ([DogWalkContent.blocks]).
  final List<String> map;

  /// Шагов в самом коротком пути: собрать всё и дойти до дома.
  final int bestSteps;

  int get size => map.length;
}

/// `jobs.json → jobs.dog_walker`.
@immutable
class DogWalkContent {
  const DogWalkContent({
    required this.items,
    required this.blocks,
    required this.levels,
  });

  factory DogWalkContent.fromData(JobData d) => DogWalkContent(
        items: dObj(d, 'items').map((String k, Object? v) =>
            MapEntry<String, DogWalkItem>(
                k, DogWalkItem.fromData(v! as JobData))),
        blocks: dObj(d, 'blocks').map((String k, Object? v) =>
            MapEntry<String, DogWalkBlock>(
                k, DogWalkBlock.fromData(v! as JobData))),
        levels: dObjs(d, 'levels').map(DogWalkLevel.fromData).toList(),
      );

  /// Буква клетки → что собрать.
  final Map<String, DogWalkItem> items;

  /// Буква клетки → препятствие.
  final Map<String, DogWalkBlock> blocks;

  /// Прогулки от лёгкой к трудной.
  final List<DogWalkLevel> levels;

  /// Прогулка смены: по id ([variant]) или по кругу от числа смен.
  DogWalkLevel levelFor(String? variant, int round) {
    for (final DogWalkLevel l in levels) {
      if (l.id == variant) return l;
    }
    return levels[round % levels.length];
  }
}

const String dogWalkerHelp = 'Нажимай клетку рядом с собакой — она пойдёт '
    'туда. Собери всё на тропинке и приведи собаку домой. Лужи и заборы '
    'обходи.';

Widget buildDogWalkerGame(BuildContext context, MiniGameArgs args) =>
    DogWalkerGame(
        content: args.games.dogWalker,
        variant: args.variant,
        round: args.round,
        onDone: args.onDone);

class DogWalkerGame extends StatefulWidget {
  const DogWalkerGame({
    super.key,
    required this.content,
    this.variant,
    this.round = 0,
    required this.onDone,
  });

  final DogWalkContent content;
  final String? variant;
  final int round;
  final MiniGameDone onDone;

  @override
  State<DogWalkerGame> createState() => _DogWalkerGameState();
}

typedef _Cell = ({int r, int c});

class _DogWalkerGameState extends State<DogWalkerGame> {
  late final DogWalkLevel _l =
      widget.content.levelFor(widget.variant, widget.round);
  late _Cell _at = _find('S');
  late final int _total = _l.map
      .join()
      .split('')
      .where((String ch) => widget.content.items.containsKey(ch))
      .length;
  final Set<_Cell> _got = <_Cell>{};
  final Set<_Cell> _trail = <_Cell>{};
  int _steps = 0;

  /// Подсказка под полем; null — задание прогулки ([_goal]).
  String? _note;

  /// Подсказка — находка (зелёная), а не «туда нельзя».
  bool _noteGood = false;
  bool _arrived = false;
  bool _sent = false;

  /// Кнопка «Закончить смену»: в портрете она под полем — экран сам
  /// докручивает до неё, когда собака дома.
  final GlobalKey _doneKey = GlobalKey();

  _Cell _find(String ch) {
    for (int r = 0; r < _l.size; r++) {
      final int c = _l.map[r].indexOf(ch);
      if (c >= 0) return (r: r, c: c);
    }
    throw StateError('На карте нет $ch');
  }

  String _tile(_Cell p) => _l.map[p.r][p.c];

  bool _near(_Cell p) => (p.r - _at.r).abs() + (p.c - _at.c).abs() == 1;

  void _tap(_Cell p) {
    if (_arrived || p == _at) return;
    if (!_near(p)) {
      _say('Собака ходит на одну клетку. Нажми клетку рядом с ней.');
      return;
    }
    final String t = _tile(p);
    final DogWalkBlock? block = widget.content.blocks[t];
    if (block != null) {
      _say(block.note);
      return;
    }
    if (t == 'G' && _got.length < _total) {
      _say('Дом рядом, но на тропинке ещё что-то лежит. Сначала собери всё.');
      return;
    }
    final DogWalkItem? item = widget.content.items[t];
    setState(() {
      _trail.add(_at);
      _at = p;
      _steps++;
      _note = null;
      _noteGood = false;
      if (item != null && _got.add(p)) {
        _note = item.found;
        _noteGood = true;
      }
      if (t == 'G') _arrived = true;
    });
    if (t == 'G') {
      context.cue(Cue.done);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? c = _doneKey.currentContext;
        if (!mounted || c == null) return;
        Scrollable.ensureVisible(c,
            alignment: 1, duration: context.motion(Motion.state));
      });
    }
  }

  void _say(String note) => setState(() {
        _note = note;
        _noteGood = false;
      });

  /// Задание прогулки. Название ступени — только в альбомной: в портрете
  /// под полем место на три строки при шрифте 1,3.
  String _goal(bool land) => land
      ? '${_l.title}. Собери всё на тропинке и приведи собаку домой.'
      : 'Собери всё на тропинке и приведи собаку домой.';

  void _done() {
    if (_sent) return;
    _sent = true;
    widget.onDone((_l.bestSteps / _steps).clamp(0.5, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final bool land = WorldLayout.isLandscape(context);
    // Портрет: счёт и подсказка мельче (как подпись курьера) — под полем
    // подсказка помещается целиком без прокрутки.
    final TextStyle noteStyle =
        land ? gameText(context) : Theme.of(context).textTheme.bodyMedium!;
    final TextStyle strong = noteStyle.copyWith(fontWeight: FontWeight.w700);
    final Widget status = Row(
      key: const ValueKey<String>('dogwalk:status'),
      children: <Widget>[
        Expanded(
            child: Text('Собрано: ${_got.length} из $_total', style: strong)),
        const SizedBox(width: Gap.sm),
        Text('Шаги: $_steps', style: strong),
      ],
    );
    final (Color bg, IconData icon, Color fg) = _note == null
        ? (WorldColors.panel, Icons.flag_rounded, WorldColors.gold)
        : _noteGood
            ? (
                WorldColors.needsBg,
                Icons.check_circle_rounded,
                WorldColors.needs
              )
            : (WorldColors.wantsBg, Icons.info_rounded, WorldColors.wants);
    final Widget? note = _arrived
        ? null
        : _Box(
            key: const ValueKey<String>('dogwalk:note'),
            color: bg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: fg),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text(_note ?? _goal(land), style: noteStyle)),
              ],
            ),
          );
    final List<Widget> finish = !_arrived
        ? const <Widget>[]
        : <Widget>[
            _Box(
              key: const ValueKey<String>('dogwalk:result'),
              color: WorldColors.needsBg,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.check_circle_rounded,
                      color: WorldColors.needs),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      _steps <= _l.bestSteps
                          ? 'Собака дома! Это самый короткий путь.'
                          : 'Собака дома! В другой раз можно найти путь '
                              'короче.',
                      style: noteStyle,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: land ? Gap.sm : Gap.md),
            KeyedSubtree(
              key: _doneKey,
              child: FilledButton.icon(
                key: const ValueKey<String>('dogwalk:done'),
                style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(gameButtonHeight(context))),
                onPressed: _done,
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Закончить смену'),
              ),
            ),
          ];
    if (land) {
      // Альбомная: поле слева во всю высоту, счёт и подсказки справа.
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final bool bounded = box.hasBoundedHeight;
          final double half = box.maxWidth * 0.5;
          final double side = bounded
              ? (half < box.maxHeight ? half : box.maxHeight)
              : half.clamp(0, 320);
          final Widget right = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Кнопка и подсказка — первыми: крупный шрифт не сдвинет их
              // за край экрана.
              ...finish,
              if (finish.isNotEmpty) const SizedBox(height: Gap.sm),
              status,
              if (note != null) ...<Widget>[
                const SizedBox(height: Gap.sm),
                note,
              ],
            ],
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox.square(dimension: side, child: _field(side)),
              const SizedBox(width: Gap.md),
              Expanded(
                child: bounded
                    ? SizedBox(
                        height: box.maxHeight,
                        child: SingleChildScrollView(child: right),
                      )
                    : right,
              ),
            ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        status,
        const SizedBox(height: Gap.sm),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            // Поле 288 dp при любой ступени (6 × 6 — клетки по 48 dp): под
            // ним на 360 × 640 при шрифте 1,3 видна подсказка без прокрутки.
            final double side =
                box.maxWidth.clamp(0.0, math.max(_l.size * 48.0, 288.0));
            return Center(
              child: SizedBox.square(dimension: side, child: _field(side)),
            );
          },
        ),
        if (note != null) ...<Widget>[
          const SizedBox(height: Gap.sm),
          note,
        ],
        if (finish.isNotEmpty) const SizedBox(height: Gap.sm),
        ...finish,
      ],
    );
  }

  /// Поле: клетки и собака поверх. Собака переходит плавно, а при
  /// «уменьшить движение» — сразу (`context.motion`).
  Widget _field(double side) {
    final double cell = side / _l.size;
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            for (int r = 0; r < _l.size; r++)
              Row(
                children: <Widget>[
                  for (int c = 0; c < _l.size; c++)
                    _cellView((r: r, c: c), cell),
                ],
              ),
          ],
        ),
        AnimatedPositioned(
          key: const ValueKey<String>('dogwalk:dog'),
          duration: context.motion(Motion.state),
          curve: Curves.easeOut,
          left: _at.c * cell,
          top: _at.r * cell,
          width: cell,
          height: cell,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Padding(
                padding: EdgeInsets.all(cell * 0.1),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: WorldColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Pictogram(Pic.paw,
                        size: cell * 0.5, color: WorldColors.onGold),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Как назвать клетку вслух.
  String _spoken(_Cell p) {
    if (p == _at) return 'собака';
    final String t = _tile(p);
    if (t == 'G') return 'дом';
    final DogWalkItem? item = widget.content.items[t];
    if (item != null && !_got.contains(p)) return item.name;
    final DogWalkBlock? block = widget.content.blocks[t];
    if (block != null) return block.name;
    return 'тропинка';
  }

  Widget _cellView(_Cell p, double size) {
    final String t = _tile(p);
    final bool open = !widget.content.blocks.containsKey(t);
    final bool next = !_arrived && open && _near(p);
    final bool item = widget.content.items.containsKey(t) && !_got.contains(p);
    final double g = size * 0.6;
    // Свои пиктограммы приложения (`core/icons.dart`) — как монета в
    // полосе сверху; забору и мячику — значки Material.
    final (Widget? glyph, Color bg) = switch (t) {
      'G' => (
          Pictogram(Pic.house, size: g, color: WorldColors.goal),
          WorldColors.goalBg
        ),
      'C' when item => (
          Pictogram(Pic.coin, size: g, color: WorldColors.gold),
          WorldColors.panel
        ),
      // Мячик — футбольный: мяч из набора приложения на клетке похож на
      // знак «нельзя».
      'M' when item => (
          Icon(Icons.sports_soccer_rounded, size: g, color: WorldColors.text),
          WorldColors.panel
        ),
      'W' => (
          Pictogram(Pic.drop, size: g, color: WorldColors.energy),
          WorldColors.needsBg
        ),
      'F' => (
          Icon(Icons.fence_rounded, size: g, color: SceneColors.bark),
          WorldColors.raised
        ),
      'T' => (
          Pictogram(Pic.leaf, size: g, color: WorldColors.needs),
          WorldColors.needsBg
        ),
      // Новая буква из файла без своей картинки: предмет — звёздочка,
      // препятствие — знак «нельзя».
      _ when item => (
          Pictogram(Pic.star, size: g, color: WorldColors.gold),
          WorldColors.panel
        ),
      _ when !open => (
          Pictogram(Pic.cross, size: g, color: WorldColors.textMute),
          WorldColors.raised
        ),
      // Пройденная тропинка — след точкой.
      _ => (
          _trail.contains(p)
              ? Icon(Icons.circle, size: size * 0.2, color: WorldColors.gold)
              : null,
          WorldColors.panel
        ),
    };
    return Semantics(
      button: next,
      label: 'Клетка ${p.r + 1}, ${p.c + 1}: ${_spoken(p)}',
      excludeSemantics: true,
      onTap: next
          ? () => _tap(p)
          : null, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
      child: GestureDetector(
        key: ValueKey<String>('dogwalk:cell:${p.r}:${p.c}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _tap(p),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
              // Куда можно шагнуть — золотая рамка.
              color: next ? WorldColors.gold : WorldColors.line,
              width: next ? 2.5 : 0.5,
            ),
          ),
          alignment: Alignment.center,
          child: glyph,
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child, this.color = WorldColors.panel});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(WorldRadii.button),
          border: Border.all(color: WorldColors.line, width: 1.5),
        ),
        child: Padding(padding: const EdgeInsets.all(Gap.sm), child: child),
      );
}
