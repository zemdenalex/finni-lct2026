import 'package:flutter/material.dart';

import '../../../../core/feel.dart';
import '../../../../core/theme.dart';
import '../../world_layout.dart';
import '../job_games.dart';
import '../mini_games.dart';
import '../../../../core/world_theme.dart';

/// Курьер: сверить посылку с заказом, затем довезти её по городу
/// (`docs/game/job-courier.md`).
///
/// Заказы, посылки, карты и названия стен — `content/jobs.json →
/// jobs.courier` ([CourierContent]). Путь от старта до цели на каждой карте
/// проверяет тест (BFS).
///
/// Таймера нет. Тупик и «шаг назад» ничего не стоят. Оценка — только за
/// посылку с первого раза: она идёт в бонус, ставку не трогает.
@immutable
class CourierParcel {
  const CourierParcel(this.id, this.label, {this.why});

  /// Верная посылка — без `why`; неверная — с объяснением.
  factory CourierParcel.fromData(JobData d) => CourierParcel(
        dStr(d, 'id'),
        dStr(d, 'label'),
        why: dBool(d, 'correct') ? null : dStr(d, 'why'),
      );

  final String id;
  final String label;

  /// Почему не та; null — верная.
  final String? why;

  bool get correct => why == null;
}

@immutable
class CourierOrder {
  const CourierOrder({
    required this.id,
    required this.title,
    required this.to,
    required this.what,
    required this.special,
    required this.parcels,
    required this.map,
  });

  factory CourierOrder.fromData(JobData d) {
    final JobData card = dObj(d, 'order_card');
    return CourierOrder(
      id: dStr(d, 'id'),
      title: dStr(d, 'title'),
      to: dStr(card, 'to'),
      what: dStr(card, 'what'),
      special: dStr(card, 'special'),
      parcels: dObjs(d, 'parcels').map(CourierParcel.fromData).toList(),
      map: dStrs(d, 'map'),
    );
  }

  final String id;
  final String title;
  final String to;
  final String what;
  final String special;
  final List<CourierParcel> parcels;

  /// Карта: `S` старт, `G` дом клиента, `.` дорога; остальные буквы — стены
  /// ([CourierContent.walls]).
  final List<String> map;

  int get size => map.length;
}

/// `jobs.json → jobs.courier`.
@immutable
class CourierContent {
  const CourierContent({
    required this.orders,
    required this.walls,
    required this.wrongTurnRule,
  });

  factory CourierContent.fromData(JobData d) => CourierContent(
        orders: dObjs(d, 'orders').map(CourierOrder.fromData).toList(),
        walls: dObj(d, 'walls').cast<String, String>(),
        wrongTurnRule: dStr(d, 'wrong_turn_rule'),
      );

  final List<CourierOrder> orders;

  /// Буква стены на карте → как её назвать («дома», «парк»…).
  final Map<String, String> walls;

  /// Что сказать в тупике.
  final String wrongTurnRule;

  /// Заказ по уровню; неизвестный или null — первый (ближний).
  CourierOrder orderFor(String? variant) =>
      orders.firstWhere((CourierOrder o) => o.id == variant,
          orElse: () => orders.first);
}

const String courierHelp = 'Сначала сверь посылку с заказом: адрес, что '
    'внутри и особую пометку. Выбрал не ту — прочитай, что не так, и выбери '
    'другую. Потом довези посылку по городу: нажимай стрелки или соседнюю '
    'клетку. Через дома, парк, забор и дорожные работы не проехать. Попал в '
    'тупик — нажми «Шаг назад», это ничего не стоит. Таймера нет, оплата от '
    'ошибок не уменьшается.';

Widget buildCourierGame(BuildContext context, MiniGameArgs args) => CourierGame(
    content: args.games.courier, variant: args.variant, onDone: args.onDone);

class CourierGame extends StatefulWidget {
  const CourierGame({
    super.key,
    required this.content,
    this.variant,
    required this.onDone,
  });

  final CourierContent content;
  final String? variant;
  final MiniGameDone onDone;

  @override
  State<CourierGame> createState() => _CourierGameState();
}

enum _Stage { parcel, route, arrived }

typedef _Cell = ({int r, int c});

class _CourierGameState extends State<CourierGame> {
  late final CourierOrder _o = widget.content.orderFor(widget.variant);
  _Stage _stage = _Stage.parcel;
  final Set<String> _wrong = <String>{};
  String? _lastPick;
  final List<_Cell> _path = <_Cell>[];
  String? _note;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _path.add(_find('S'));
  }

  _Cell _find(String ch) {
    for (int r = 0; r < _o.size; r++) {
      final int c = _o.map[r].indexOf(ch);
      if (c >= 0) return (r: r, c: c);
    }
    throw StateError('На карте нет $ch');
  }

  _Cell get _at => _path.last;

  String? _tile(int r, int c) {
    if (r < 0 || c < 0 || r >= _o.size || c >= _o.size) return null;
    return _o.map[r][c];
  }

  bool _open(int r, int c) {
    final String? t = _tile(r, c);
    return t == '.' || t == 'S' || t == 'G';
  }

  void _pick(CourierParcel p) {
    setState(() {
      _lastPick = p.id;
      if (!p.correct) _wrong.add(p.id);
    });
    if (p.correct) context.cue(Cue.done);
  }

  void _move(int dr, int dc) {
    if (_stage != _Stage.route) return;
    final int r = _at.r + dr;
    final int c = _at.c + dc;
    final String? t = _tile(r, c);
    if (t == null) {
      setState(() => _note = 'Дальше край карты. Попробуй другую сторону.');
      return;
    }
    if (!_open(r, c)) {
      setState(
          () => _note = 'Там ${widget.content.walls[t] ?? 'стена'} — туда не '
              'проехать. Попробуй другую улицу.');
      return;
    }
    // Шаг обратно по своему следу — то же, что «Шаг назад».
    if (_path.length > 1 &&
        _path[_path.length - 2].r == r &&
        _path[_path.length - 2].c == c) {
      _back();
      return;
    }
    setState(() {
      _path.add((r: r, c: c));
      _note = null;
      if (t == 'G') {
        _stage = _Stage.arrived;
      } else if (_isDeadEnd(r, c)) {
        _note = '${widget.content.wrongTurnRule} Нажми «Шаг назад».';
      }
    });
    if (t == 'G') context.cue(Cue.done);
  }

  bool _isDeadEnd(int r, int c) {
    int exits = 0;
    for (final (int, int) d in const <(int, int)>[
      (1, 0),
      (-1, 0),
      (0, 1),
      (0, -1)
    ]) {
      if (_open(r + d.$1, c + d.$2)) exits++;
    }
    return exits <= 1;
  }

  void _back() => setState(() {
        if (_path.length > 1) _path.removeLast();
        _note = null;
      });

  void _tapCell(int r, int c) {
    final int dr = r - _at.r;
    final int dc = c - _at.c;
    if (dr.abs() + dc.abs() != 1) return;
    _move(dr, dc);
  }

  void _done() {
    if (_sent) return;
    _sent = true;
    widget.onDone(1 / (_wrong.length + 1));
  }

  @override
  Widget build(BuildContext context) => switch (_stage) {
        _Stage.parcel => _parcelStage(context),
        _ => _routeStage(context),
      };

  Widget _orderCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    Widget line(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: WorldColors.text),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(children: <InlineSpan>[
                    TextSpan(
                        text: '$label: ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: value),
                  ]),
                  style: WorldLayout.isLandscape(context)
                      ? gameText(context)
                      : text.bodyMedium,
                ),
              ),
            ],
          ),
        );
    return _Box(
      key: const ValueKey<String>('courier:order'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Заказ: ${_o.title}', style: text.titleMedium),
          const SizedBox(height: Gap.xs),
          line(Icons.place_rounded, 'Куда', _o.to),
          line(Icons.inventory_2_rounded, 'Что', _o.what),
          line(Icons.warning_amber_rounded, 'Особое', _o.special),
        ],
      ),
    );
  }

  Widget _parcelStage(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool land = WorldLayout.isLandscape(context);
    final CourierParcel? last = _lastPick == null
        ? null
        : _o.parcels.firstWhere((CourierParcel p) => p.id == _lastPick);
    final bool solved = last?.correct ?? false;
    final List<Widget> parcels = <Widget>[
      Text('Какая посылка подходит к заказу?', style: text.titleMedium),
      const SizedBox(height: Gap.xs),
      for (final CourierParcel p in _o.parcels)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: _ParcelButton(
            key: ValueKey<String>('courier:parcel:${p.id}'),
            parcel: p,
            mark: _wrong.contains(p.id)
                ? false
                : (solved && p.id == _lastPick ? true : null),
            onTap: solved || _wrong.contains(p.id) ? null : () => _pick(p),
          ),
        ),
    ];
    final List<Widget> outcome = <Widget>[
      if (last != null)
        _Box(
          key: const ValueKey<String>('courier:feedback'),
          color: solved ? WorldColors.needsBg : WorldColors.wantsBg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(solved ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: solved ? WorldColors.needs : WorldColors.wants),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  solved
                      ? 'Та самая посылка! Теперь отвези её.'
                      : '${last.why} Выбери другую.',
                  style: gameText(context),
                ),
              ),
            ],
          ),
        ),
      if (solved) ...<Widget>[
        SizedBox(height: land ? Gap.sm : Gap.md),
        FilledButton.icon(
          key: const ValueKey<String>('courier:toRoute'),
          style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(gameButtonHeight(context))),
          onPressed: () => setState(() => _stage = _Stage.route),
          icon: const Icon(Icons.pedal_bike_rounded),
          label: const Text('В путь'),
        ),
      ],
    ];
    if (land) {
      // Альбомная: заказ, подсказка и «В путь» слева, посылки справа.
      return GameSplit(panes: <GamePane>[
        GamePane(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _orderCard(context),
            if (outcome.isNotEmpty) const SizedBox(height: Gap.sm),
            ...outcome,
          ],
        )),
        GamePane(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: parcels,
        )),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _orderCard(context),
        const SizedBox(height: Gap.md),
        ...parcels,
        ...outcome,
      ],
    );
  }

  Widget _routeStage(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool arrived = _stage == _Stage.arrived;
    final bool land = WorldLayout.isLandscape(context);
    final Widget caption = Text(
      arrived
          ? 'Посылка у клиента!'
          : 'Довези посылку: ${_o.to}. Флажок — дом клиента.',
      style: land ? gameText(context) : text.bodyMedium,
    );
    final Widget? note = _note == null
        ? null
        : _Box(
            key: const ValueKey<String>('courier:note'),
            color: WorldColors.wantsBg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_rounded, color: WorldColors.wants),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text(_note!, style: gameText(context))),
              ],
            ),
          );
    final Widget control = arrived
        ? FilledButton.icon(
            key: const ValueKey<String>('courier:done'),
            style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(gameButtonHeight(context))),
            onPressed: _done,
            icon: const Icon(Icons.flag_rounded),
            label: const Text('Закончить смену'),
          )
        : _pad();
    if (land) {
      // Альбомная: карта слева во всю высоту, стрелки и подсказки справа.
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final bool bounded = box.hasBoundedHeight;
          final double side = bounded
              ? (box.maxWidth * 0.45 < box.maxHeight
                  ? box.maxWidth * 0.45
                  : box.maxHeight)
              : (box.maxWidth * 0.45).clamp(0, 320);
          final Widget right = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Стрелки — первыми: при крупном шрифте текст не сдвинет их
              // за край экрана. Подсказка про стену или тупик — сразу под
              // ними, постоянная подпись — ниже всех.
              control,
              if (note != null) ...<Widget>[
                const SizedBox(height: Gap.sm),
                note,
              ],
              const SizedBox(height: Gap.sm),
              caption,
            ],
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: side, child: _mapView(context)),
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
        caption,
        const SizedBox(height: Gap.sm),
        _mapView(context),
        const SizedBox(height: Gap.sm),
        if (note != null) note,
        const SizedBox(height: Gap.sm),
        control,
      ],
    );
  }

  Widget _arrow(String id, IconData icon, String label, int dr, int dc) =>
      SizedBox.square(
        dimension: TapSize.min + 8,
        child: IconButton.filledTonal(
          key: ValueKey<String>('courier:move:$id'),
          tooltip: label,
          iconSize: 32,
          onPressed: () => _move(dr, dc),
          icon: Icon(icon),
        ),
      );

  Widget _pad() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _arrow('up', Icons.arrow_upward_rounded, 'Вверх', -1, 0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _arrow('left', Icons.arrow_back_rounded, 'Влево', 0, -1),
                  const SizedBox.square(dimension: TapSize.min + 8),
                  _arrow('right', Icons.arrow_forward_rounded, 'Вправо', 0, 1),
                ],
              ),
              _arrow('down', Icons.arrow_downward_rounded, 'Вниз', 1, 0),
            ],
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey<String>('courier:back'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(TapSize.min),
                // Альбомная: рядом со стрелками узко — поля меньше.
                padding: WorldLayout.isLandscape(context)
                    ? const EdgeInsets.symmetric(horizontal: Gap.sm)
                    : null,
                textStyle:
                    WorldLayout.isLandscape(context) ? gameButtonText : null,
              ),
              onPressed: _path.length > 1 ? _back : null,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Шаг назад'),
            ),
          ),
        ],
      );

  Widget _mapView(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double side = box.maxWidth.clamp(0, 400);
          final double cell = side / _o.size;
          return Center(
            child: SizedBox.square(
              dimension: side,
              child: Column(
                children: <Widget>[
                  for (int r = 0; r < _o.size; r++)
                    Row(
                      children: <Widget>[
                        for (int c = 0; c < _o.size; c++) _cellView(r, c, cell),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      );

  Widget _cellView(int r, int c, double size) {
    final String t = _o.map[r][c];
    final bool here = _at.r == r && _at.c == c;
    final bool trail = _path.any((_Cell p) => p.r == r && p.c == c);
    final (IconData? icon, Color bg, Color fg) = here
        ? (Icons.pedal_bike_rounded, WorldColors.gold, WorldColors.text)
        : switch (t) {
            'H' => (
                Icons.house_rounded,
                SceneColors.wall,
                SceneColors.barkDark
              ),
            'P' => (
                Icons.park_rounded,
                WorldColors.needsBg,
                SceneColors.leafDark
              ),
            'F' => (Icons.fence_rounded, WorldColors.raised, SceneColors.bark),
            'R' => (
                Icons.construction_rounded,
                WorldColors.wantsBg,
                WorldColors.wants
              ),
            'G' => (Icons.flag_rounded, WorldColors.goalBg, WorldColors.goal),
            // Новая буква стены из файла без своей картинки — всё равно стена.
            _ when !_open(r, c) => (
                Icons.block_rounded,
                WorldColors.raised,
                SceneColors.barkDark
              ),
            _ => (
                trail ? Icons.circle : null,
                trail
                    ? WorldColors.gold.withValues(alpha: 0.35)
                    : WorldColors.panel,
                WorldColors.gold,
              ),
          };
    return GestureDetector(
      key: ValueKey<String>('courier:cell:$r:$c'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapCell(r, c),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: WorldColors.line, width: 0.5),
        ),
        child: icon == null
            ? null
            : Icon(icon,
                color: fg, size: t == '.' && !here ? size * 0.25 : size * 0.7),
      ),
    );
  }
}

class _ParcelButton extends StatelessWidget {
  const _ParcelButton(
      {super.key, required this.parcel, required this.mark, this.onTap});

  final CourierParcel parcel;

  /// true — верная, false — отмечена как не та, null — ещё не выбирали.
  final bool? mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color border) = switch (mark) {
      true => (Icons.check_circle_rounded, WorldColors.needs),
      false => (Icons.cancel_rounded, WorldColors.wants),
      null => (Icons.inventory_2_outlined, WorldColors.line),
    };
    return Material(
      color: WorldColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        side: BorderSide(color: border, width: mark == null ? 1.5 : 3),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TapSize.min),
          child: Padding(
            padding: const EdgeInsets.all(Gap.sm),
            child: Row(
              children: <Widget>[
                Icon(icon,
                    color:
                        border == WorldColors.line ? WorldColors.text : border),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    '${parcel.label}${mark == false ? ' — не та' : ''}',
                    style: WorldLayout.isLandscape(context)
                        ? gameText(context)
                        : Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
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
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: WorldColors.line, width: 1.5),
        ),
        child: Padding(padding: const EdgeInsets.all(Gap.sm), child: child),
      );
}
