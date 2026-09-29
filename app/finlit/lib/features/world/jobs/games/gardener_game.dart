import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/feel.dart';
import '../../../../core/theme.dart';
import '../../world_layout.dart';
import '../job_games.dart';
import '../mini_games.dart';
import '../../../../core/world_theme.dart';

/// Садовник: поливать сохнущие грядки (`docs/game/job-gardener.md`).
///
/// Числа и тексты — `content/jobs.json → jobs.gardener` ([GardenerContent]).
///
/// Один темп — по ходам, без часов и обратного отсчёта (критерии ночи
/// §8.8: таймеров нет; ревью df2164a). Ребёнок сам решает, когда дальше
/// (`calm_turns`, `calm_wilt_turns`).
@immutable
class GardenerContent {
  const GardenerContent({
    required this.beds,
    required this.columns,
    required this.maxDryAtOnce,
    required this.greatShare,
    required this.okShare,
    required this.lineGreat,
    required this.lineOk,
    required this.lineLow,
    required this.calmTurns,
    required this.calmWiltTurns,
  });

  factory GardenerContent.fromData(JobData d) {
    final JobData lines = dObj(d, 'result_lines');
    return GardenerContent(
      beds: dInt(d, 'beds'),
      columns: dInts(d, 'grid').first,
      maxDryAtOnce: dInt(d, 'max_dry_at_once'),
      greatShare: dNum(d, 'great_share'),
      okShare: dNum(d, 'ok_share'),
      lineGreat: dStr(lines, 'great'),
      lineOk: dStr(lines, 'ok'),
      lineLow: dStr(lines, 'low'),
      calmTurns: dInt(d, 'calm_turns'),
      calmWiltTurns: dInt(d, 'calm_wilt_turns'),
    );
  }

  final int beds;

  /// Грядок в ряду (`grid[0]`).
  final int columns;

  final int maxDryAtOnce;
  final double greatShare;
  final double okShare;
  final String lineGreat;
  final String lineOk;
  final String lineLow;

  /// Ходов за смену и через сколько ходов сухая грядка никнет.
  final int calmTurns;
  final int calmWiltTurns;

  /// Что написать под итогом по доле политых.
  String resultLine(double share) => share >= greatShare
      ? lineGreat
      : share >= okShare
          ? lineOk
          : lineLow;
}

const String gardenerHelp = 'Грядки понемногу сохнут: на сухой появляется '
    'капля и надпись «Полей!». Нажми на такую грядку — она снова растёт. '
    'Полей сухие грядки и нажми «Дальше» — спешить некуда, часов нет. Не '
    'полил — грядка поникнет, но не пропадёт: полей её, и она оживёт. Оплата '
    'от результата не зависит.';

Widget buildGardenerGame(BuildContext context, MiniGameArgs args) =>
    GardenerGame(
        content: args.games.gardener, round: args.round, onDone: args.onDone);

enum GardenBed { growing, dry, wilted }

class GardenerGame extends StatefulWidget {
  const GardenerGame({
    super.key,
    required this.content,
    this.round = 0,
    required this.onDone,
  });

  final GardenerContent content;
  final int round;
  final MiniGameDone onDone;

  @override
  State<GardenerGame> createState() => _GardenerGameState();
}

class _GardenerGameState extends State<GardenerGame> {
  late final math.Random _rng = math.Random(widget.round);
  GardenerContent get _c => widget.content;

  late final List<GardenBed> _beds =
      List<GardenBed>.filled(_c.beds, GardenBed.growing);

  /// Ход, на котором грядка начала сохнуть.
  late final List<int> _dryAt = List<int>.filled(_c.beds, 0);

  int _turn = 0;
  int _dried = 0;
  int _watered = 0;
  bool _over = false;
  bool _sent = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _dryTurn();
  }

  int get _dryNow =>
      _beds.where((GardenBed b) => b != GardenBed.growing).length;

  /// Одна случайная растущая грядка начинает сохнуть (если есть место).
  void _dryOne() {
    if (_dryNow >= _c.maxDryAtOnce) return;
    final List<int> free = <int>[
      for (int i = 0; i < _c.beds; i++)
        if (_beds[i] == GardenBed.growing) i,
    ];
    if (free.isEmpty) return;
    final int i = free[_rng.nextInt(free.length)];
    _beds[i] = GardenBed.dry;
    _dryAt[i] = _turn;
    _dried++;
  }

  /// В начале хода сохнут одна-две грядки.
  void _dryTurn() {
    final int count = _turn.isEven ? 1 : 2;
    for (int k = 0; k < count; k++) {
      _dryOne();
    }
  }

  void _nextTurn() => setState(() {
        _note = null;
        for (int i = 0; i < _c.beds; i++) {
          if (_beds[i] == GardenBed.dry &&
              _turn + 1 - _dryAt[i] >= _c.calmWiltTurns) {
            _beds[i] = GardenBed.wilted;
          }
        }
        _turn++;
        if (_turn >= _c.calmTurns) {
          _finish();
        } else {
          _dryTurn();
        }
      });

  void _finish() {
    _over = true;
    _note = null;
  }

  void _water(int i) {
    if (_over) return;
    if (_beds[i] == GardenBed.growing) {
      setState(() => _note = 'Эта грядка ещё влажная — поливать не нужно.');
      return;
    }
    final bool wilted = _beds[i] == GardenBed.wilted;
    setState(() {
      _beds[i] = GardenBed.growing;
      _watered++;
      _note = wilted ? 'Грядка ${i + 1} ожила!' : null;
    });
    context.cue(Cue.done);
  }

  double get _share => _dried == 0 ? 1 : _watered / _dried;

  void _done() {
    if (_sent) return;
    _sent = true;
    widget.onDone(_share.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool land = WorldLayout.isLandscape(context);
    final List<Widget> turnInfo = <Widget>[
      if (!_over) ...<Widget>[
        Text(
          key: const ValueKey<String>('gardener:turn'),
          'Ход ${_turn + 1} из ${_c.calmTurns}. Полей сухие грядки '
          'и нажми «Дальше».',
          style: land ? gameText(context) : text.bodyMedium,
        ),
        const SizedBox(height: Gap.sm),
      ],
    ];
    final List<Widget> after = <Widget>[
      if (_note != null)
        Text(
          key: const ValueKey<String>('gardener:note'),
          _note!,
          style: land ? gameText(context) : text.bodyMedium,
        ),
      const SizedBox(height: Gap.sm),
      if (_over) ...<Widget>[
        _Box(
          key: const ValueKey<String>('gardener:summary'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.local_florist_rounded,
                  color: SceneColors.leafDark),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  'Ты полил $_watered ${_bedsWord(_watered)} из $_dried.\n'
                  '${_c.resultLine(_share)}',
                  style: gameText(context),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: land ? Gap.sm : Gap.md),
        FilledButton.icon(
          key: const ValueKey<String>('gardener:done'),
          style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(gameButtonHeight(context))),
          onPressed: _done,
          icon: const Icon(Icons.flag_rounded),
          label: const Text('Закончить смену'),
        ),
      ] else
        FilledButton.icon(
          key: const ValueKey<String>('gardener:next'),
          style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(gameButtonHeight(context))),
          onPressed: _nextTurn,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(_turn == _c.calmTurns - 1 ? 'Закончить' : 'Дальше'),
        ),
    ];

    if (land) {
      // Альбомная: огород 3 × 2 слева во всю высоту, ход и кнопки справа.
      return GameSplit(panes: <GamePane>[
        GamePane(
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) =>
                _bedsGrid(fill: box.hasBoundedHeight),
          ),
          flex: 3,
          scroll: false,
        ),
        GamePane(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[...turnInfo, ...after],
          ),
          flex: 2,
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...turnInfo,
        _bedsGrid(fill: false),
        ...after,
      ],
    );
  }

  /// Грядки рядами по [GardenerContent.columns]. [fill] — ряды делят всю высоту
  /// (альбомная), иначе каждый ряд своей высоты.
  Widget _bedsGrid({required bool fill}) {
    Widget row(int r) => Row(
          crossAxisAlignment:
              fill ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
          children: <Widget>[
            for (int c = 0; c < _c.columns; c++) ...<Widget>[
              if (c > 0) const SizedBox(width: Gap.sm),
              Expanded(
                child: _BedTile(
                  index: r * _c.columns + c,
                  state: _beds[r * _c.columns + c],
                  onTap: _over ? null : () => _water(r * _c.columns + c),
                ),
              ),
            ],
          ],
        );
    final int rows = (_c.beds / _c.columns).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int r = 0; r < rows; r++)
          if (fill) ...<Widget>[
            if (r > 0) const SizedBox(height: Gap.sm),
            Expanded(child: row(r)),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: row(r),
            ),
      ],
    );
  }
}

String _bedsWord(int n) {
  final int m10 = n % 10;
  final int m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'грядку';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'грядки';
  return 'грядок';
}

class _BedTile extends StatelessWidget {
  const _BedTile({required this.index, required this.state, this.onTap});

  final int index;
  final GardenBed state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, Color bg, Color fg) = switch (state) {
      GardenBed.growing => (
          Icons.grass_rounded,
          'Растёт',
          WorldColors.needsBg,
          SceneColors.leafDark,
        ),
      GardenBed.dry => (
          Icons.water_drop_rounded,
          'Полей!',
          const Color(0xFFF6E3B4),
          SceneColors.blueprint,
        ),
      GardenBed.wilted => (
          Icons.water_drop_rounded,
          'Поникла',
          const Color(0xFFE8D6C4),
          SceneColors.barkDark,
        ),
    };
    return Semantics(
      button: true,
      label: 'Грядка ${index + 1}: $label',
      excludeSemantics: true,
      onTap:
          onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
      child: Material(
        key: ValueKey<String>('gardener:bed:$index'),
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
          side: BorderSide(
            color: state == GardenBed.growing ? WorldColors.line : fg,
            width: state == GardenBed.growing ? 1.5 : 3,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TapSize.min + 24),
            child: Padding(
              padding: const EdgeInsets.all(Gap.xs),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, color: fg, size: 32),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      key: ValueKey<String>('gardener:bed:$index:$label'),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: WorldColors.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WorldColors.needsBg,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: WorldColors.line, width: 1.5),
        ),
        child: Padding(padding: const EdgeInsets.all(Gap.sm), child: child),
      );
}
