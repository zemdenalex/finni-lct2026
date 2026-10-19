import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../world_state.dart';
import 'tutorial_steps.dart';

/// Обучалка первого захода поверх экрана [child] (комната).
///
/// Шаги — [tutorialSteps], вид — флаг [tutorialLook]. Цель шага ищется в
/// поддереве [child] по `ValueKey<String>`: экран комнаты об обучалке не
/// знает, и правки комнаты не ломают её, пока ключи на месте.
class TutorialGate extends StatefulWidget {
  const TutorialGate({super.key, required this.child, this.look, this.steps});

  final Widget child;

  /// Вид; null — из флага [tutorialLook].
  final TutorialLook? look;

  /// Шаги; null — [tutorialSteps].
  final List<TutorialStep>? steps;

  @override
  State<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends State<TutorialGate>
    with SingleTickerProviderStateMixin {
  /// Следит за целью каждый кадр — только пока обучалка идёт.
  Ticker? _ticker;
  final GlobalKey _childKey = GlobalKey();
  late final Future<AssetRegistry> _registry = AssetRegistry.load();

  /// Обучалка идёт. Решается один раз, при первом показе экрана.
  bool _on = false;
  int _index = 0;
  Element? _targetElement;
  Rect? _target;

  /// Кадр, на котором цель последний раз искали по дереву: цели нет на
  /// экране — ищем раз в 15 кадров, а не обходим дерево каждый кадр.
  int _frame = 0, _lookedAt = -1000;

  TutorialLook get _look => widget.look ?? tutorialLook;
  List<TutorialStep> get _steps => widget.steps ?? tutorialSteps;

  /// Где обучалка остановилась — на сам мир, а не на экран: комната
  /// пересоздаётся при каждом возвращении из города, и без этого шаги
  /// пошли бы сначала, а пропущенная обучалка вернулась бы. Новый мир
  /// (сброс) — новая обучалка. −1 — пройдена или пропущена.
  static final Expando<int> _progress = Expando<int>('tutorial');

  late final World _world = context.read<WorldState>().world;

  @override
  void initState() {
    super.initState();
    final int at = _progress[_world] ?? 0;
    _on = _look != TutorialLook.off && at >= 0 && isFirstVisit(_world);
    _index = at < 0 ? 0 : at;
    if (_on) _ticker = createTicker(_track)..start();
    _focus();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    tutorialRoomFocus.value = null;
    super.dispose();
  }

  /// Камера комнаты — на предмет текущего шага (после кадра: слушатели
  /// строятся заново, а сейчас идёт сборка).
  void _focus() {
    final String? id = _on && _index < _steps.length
        ? _steps[_index]
            .targets
            .map(roomObjectOfTarget)
            .firstWhere((String? o) => o != null, orElse: () => null)
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tutorialRoomFocus.value = id;
    });
  }

  /// Каждый кадр — где сейчас цель (Финни ходит, камера едет).
  void _track(Duration _) {
    if (!mounted || !_on) return;
    final TutorialStep step = _steps[_index];
    _frame++;
    Element? e = _targetElement;
    if (e != null && !e.mounted) e = _targetElement = null;
    if (e == null && _frame - _lookedAt >= 15) {
      _lookedAt = _frame;
      for (final String k in step.targets) {
        e = _find(k);
        if (e != null) break;
      }
      _targetElement = e;
    }
    final Rect? r = _rectOf(e);
    if (r != _target) setState(() => _target = r);
  }

  Element? _find(String key) {
    final BuildContext? root = _childKey.currentContext;
    if (root == null) return null;
    final ValueKey<String> want = ValueKey<String>(key);
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget.key == want) {
        found = e;
        return;
      }
      e.visitChildElements(visit);
    }

    (root as Element).visitChildElements(visit);
    return found;
  }

  Rect? _rectOf(Element? e) {
    final RenderObject? ro = e?.renderObject;
    final RenderObject? me = context.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    if (me is! RenderBox || !me.hasSize) return null;
    final Offset tl = ro.localToGlobal(Offset.zero, ancestor: me);
    final Rect r = tl & ro.size;
    // Цель за краем экрана (дверь за камерой) — карточка без подсветки.
    final Rect view = Offset.zero & me.size;
    if (!view.overlaps(r)) return null;
    return r.intersect(view);
  }

  void _next() {
    if (_index + 1 >= _steps.length) return _finish();
    _progress[_world] = _index + 1;
    setState(() {
      _index++;
      _targetElement = null;
      _target = null;
      _lookedAt = -1000;
    });
    _focus();
  }

  void _finish() {
    _progress[_world] = -1;
    _ticker?.stop();
    setState(() => _on = false);
    _focus();
  }

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    // T3 не держит игру: ребёнок сам сходил на смену или поел — подсказки
    // первого захода больше не к месту.
    final bool show =
        _on && (_look != TutorialLook.hints || isFirstVisit(ws.world));
    final Widget child = KeyedSubtree(key: _childKey, child: widget.child);
    if (!show) return child;
    final TutorialStep step = _steps[_index];
    final _Beat beat = _Beat(
      step: step,
      index: _index,
      count: _steps.length,
      say: step.say(ws.world),
      short: step.short(ws.world),
      target: _target,
      onNext: _next,
      onSkip: _finish,
      finni: _FinniFace(registry: _registry, profile: ws.profile),
    );
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: switch (_look) {
            TutorialLook.spotlight => _Spotlight(beat),
            TutorialLook.dialog => _Dialog(beat),
            TutorialLook.hints => _Hints(beat),
            TutorialLook.off => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

/// Что показывает шаг — общее для трёх видов.
class _Beat {
  const _Beat({
    required this.step,
    required this.index,
    required this.count,
    required this.say,
    required this.short,
    required this.target,
    required this.onNext,
    required this.onSkip,
    required this.finni,
  });

  final TutorialStep step;
  final int index;
  final int count;
  final String say;
  final String short;
  final Rect? target;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final Widget finni;

  bool get last => index == count - 1;
  Rect? get hole => target?.inflate(6);
}

const TextStyle _sayStyle = TextStyle(
    fontSize: 16, height: 1.3, color: WorldColors.text, fontFamily: 'Onest');

/// Самая широкая карточка — на планшете не тянется через весь экран.
const double _cardMaxWidth = 440;

class _FinniFace extends StatelessWidget {
  const _FinniFace({required this.registry, required this.profile});

  final Future<AssetRegistry> registry;
  final WorldProfile profile;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: 48,
          height: 60,
          child: FutureBuilder<AssetRegistry>(
            future: registry,
            builder: (BuildContext c, AsyncSnapshot<AssetRegistry> s) {
              final SpriteRef? f = s.data?.finni(profile.species);
              if (f == null) return const SizedBox.shrink();
              return FittedBox(
                child: SpriteAnim(sprite: f, tag: profile.idleTag, scale: 0.45),
              );
            },
          ),
        ),
      );
}

class _Buttons extends StatelessWidget {
  const _Buttons(this.beat);
  final _Beat beat;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.sm),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                key: const ValueKey<String>('tutorial:skip'),
                onPressed: beat.onSkip,
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, TapSize.min),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xs)),
                // На 360 dp при шрифте ×1,3 «Пропустить» резалось до
                // «Пропустит» — ужимается целиком, а не режется.
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Пропустить',
                      maxLines: 1,
                      style: TextStyle(color: WorldColors.textSoft)),
                ),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: FilledButton(
                key: const ValueKey<String>('tutorial:next'),
                onPressed: beat.onNext,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, TapSize.min),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.sm)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(beat.last ? 'Играть' : 'Дальше', maxLines: 1),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Dots extends StatelessWidget {
  const _Dots(this.beat);
  final _Beat beat;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Шаг ${beat.index + 1} из ${beat.count}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 0; i < beat.count; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        i == beat.index ? WorldColors.gold : WorldColors.line,
                  ),
                ),
            ],
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding, super.key});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Material(
        color: WorldColors.panel,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorldRadii.button),
          side: const BorderSide(color: WorldColors.gold, width: 2),
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(Gap.md),
          child: child,
        ),
      );
}

/// T1: затемнение с окном вокруг цели, карточка над или под ним.
class _Spotlight extends StatelessWidget {
  const _Spotlight(this.beat);
  final _Beat beat;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext c, BoxConstraints box) {
          final Size size = box.biggest;
          final Rect? hole = beat.hole;
          final Widget card = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
            child: _Card(
              key: ValueKey<String>('tutorial:step:${beat.step.id}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      beat.finni,
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(beat.say, style: _sayStyle),
                        ),
                      ),
                    ],
                  ),
                  _Dots(beat),
                  _Buttons(beat),
                ],
              ),
            ),
          );
          final (Rect area, Alignment align) = _cardArea(size, hole);
          return BlockSemantics(
            child: Stack(
              children: <Widget>[
                // Игра стоит, пока идёт шаг: касания мимо карточки гасятся.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: CustomPaint(painter: _Dim(hole)),
                  ),
                ),
                Positioned.fromRect(
                  rect: area,
                  child: Align(
                    alignment: align,
                    child: SingleChildScrollView(child: card),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Где карточке T1 место: самая просторная полоса рядом с целью (под,
/// над, справа, слева), в которую карточка влезает шириной. Карточка
/// прижата к цели. На 640×360 под дверью места нет — карточка встаёт
/// сбоку; под настроением наверху — снизу, а не узкой полосой сбоку.
(Rect, Alignment) _cardArea(Size size, Rect? hole) {
  const double m = Gap.md;
  const double minW = 300, minH = 150;
  final Rect all = Rect.fromLTRB(m, m, size.width - m, size.height - m);
  if (hole == null) return (all, Alignment.bottomCenter);
  final List<(Rect, Alignment)> sides = <(Rect, Alignment)>[
    (
      Rect.fromLTRB(m, hole.bottom + m, size.width - m, size.height - m),
      Alignment.topCenter
    ),
    (Rect.fromLTRB(m, m, size.width - m, hole.top - m), Alignment.bottomCenter),
    (
      Rect.fromLTRB(hole.right + m, m, size.width - m, size.height - m),
      Alignment.centerLeft
    ),
    (
      Rect.fromLTRB(m, m, hole.left - m, size.height - m),
      Alignment.centerRight
    ),
  ];
  double area((Rect, Alignment) s) =>
      s.$1.width <= 0 || s.$1.height <= 0 ? 0 : s.$1.width * s.$1.height;
  final List<(Rect, Alignment)> fit = sides
      .where(((Rect, Alignment) s) => s.$1.width >= minW && s.$1.height >= minH)
      .toList();
  final List<(Rect, Alignment)> pool = fit.isEmpty ? sides : fit;
  pool.sort(
      ((Rect, Alignment) a, (Rect, Alignment) b) => area(b).compareTo(area(a)));
  return pool.first;
}

class _Dim extends CustomPainter {
  _Dim(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final Path all = Path()..addRect(Offset.zero & size);
    final Rect? h = hole;
    if (h == null) {
      canvas.drawPath(all, Paint()..color = const Color(0xA6000000));
      return;
    }
    final RRect r =
        RRect.fromRectAndRadius(h, const Radius.circular(WorldRadii.button));
    canvas.drawPath(
      Path.combine(PathOperation.difference, all, Path()..addRRect(r)),
      Paint()..color = const Color(0xA6000000),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = WorldColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole;
}

/// T2: панель-диалог снизу, цель обведена рамкой, экран не темнеет.
class _Dialog extends StatelessWidget {
  const _Dialog(this.beat);
  final _Beat beat;

  @override
  Widget build(BuildContext context) {
    final Rect? hole = beat.hole;
    return BlockSemantics(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
            ),
          ),
          if (hole != null)
            Positioned.fromRect(
              rect: hole,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(WorldRadii.button),
                    border: Border.all(color: WorldColors.gold, width: 3),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _cardMaxWidth * 1.4),
                child: Material(
                  key: ValueKey<String>('tutorial:step:${beat.step.id}'),
                  color: WorldColors.panel,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(WorldRadii.panel)),
                    side: BorderSide(color: WorldColors.line, width: 1.5),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Gap.md, Gap.md, Gap.md, Gap.sm),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              beat.finni,
                              const SizedBox(width: Gap.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                        '${context.read<WorldState>().finniName}'
                                        ' · ${beat.index + 1} из ${beat.count}',
                                        style: AppType.title(15,
                                            color: WorldColors.gold)),
                                    const SizedBox(height: Gap.xs),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(beat.say, style: _sayStyle),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          _Buttons(beat),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// T3: короткая подсказка у цели; игра идёт. «×» — к следующей,
/// «Без подсказок» — выключить все.
class _Hints extends StatelessWidget {
  const _Hints(this.beat);
  final _Beat beat;

  static const double _width = 220;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext c, BoxConstraints box) {
          final Size size = box.biggest;
          final Rect? hole = beat.hole;
          final bool below = hole == null || hole.center.dy < size.height / 2;
          final double left = hole == null
              ? (size.width - _width) / 2
              : (hole.center.dx - _width / 2)
                  .clamp(Gap.sm, size.width - _width - Gap.sm)
                  .toDouble();
          return Stack(
            children: <Widget>[
              Positioned(
                left: left,
                width: _width,
                top: hole == null
                    ? size.height / 3
                    : below
                        ? hole.bottom + Gap.xs
                        : null,
                bottom: hole != null && !below
                    ? size.height - hole.top + Gap.xs
                    : null,
                child: _Card(
                  key: ValueKey<String>('tutorial:step:${beat.step.id}'),
                  padding: const EdgeInsets.only(left: Gap.sm),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(beat.short,
                            style: _sayStyle.copyWith(fontSize: 14)),
                      ),
                      IconButton(
                        key: const ValueKey<String>('tutorial:next'),
                        tooltip: beat.last
                            ? 'Закрыть подсказку'
                            : 'Следующая подсказка',
                        onPressed: beat.onNext,
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: WorldColors.textSoft),
                      ),
                    ],
                  ),
                ),
              ),
              if (beat.index == 0)
                Positioned(
                  right: Gap.sm,
                  top: size.height * 0.62,
                  child: _Card(
                    padding: EdgeInsets.zero,
                    child: TextButton(
                      key: const ValueKey<String>('tutorial:skip'),
                      onPressed: beat.onSkip,
                      style: TextButton.styleFrom(
                          minimumSize: const Size(TapSize.min, TapSize.min)),
                      child: Text('Без подсказок',
                          style: _sayStyle.copyWith(
                              fontSize: 14, color: WorldColors.textSoft)),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
