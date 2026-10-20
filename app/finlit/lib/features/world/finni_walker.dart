import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Финни, который ходит: от прежней точки к [at] за [duration], лицом по
/// ходу, чуть покачиваясь ([bob] px). Нулевая длительность («Анимации»
/// выкл., ТЗ 3.6.7) — сразу на месте. [at] — ноги, низ по центру.
///
/// Прямой ребёнок [Stack]: строит [Positioned]. Общий для комнаты S1,
/// сценок знакомства и карты города S2 (Денис, 938: «механика хождения
/// Финни по квартире и по городу»). [builder] получает, идёт ли Финни
/// сейчас, — чтобы включить кадры ходьбы, где они нарисованы.
///
/// [via] — точки поворота по пути к [at] (город, флаг `city.smooth_walk`:
/// в обход домов). Пусто — прямо, как в комнате.
class FinniWalker extends StatefulWidget {
  const FinniWalker({
    super.key,
    required this.at,
    required this.duration,
    required this.bob,
    required this.builder,
    this.via = const <Offset>[],
    this.onMove,
  });

  final Offset at;
  final Duration duration;
  final double bob;
  final Widget Function(bool walking) builder;
  final List<Offset> via;

  /// Где Финни сейчас (ноги, в координатах [at]) — на каждом кадре пути.
  /// Город по нему держит глубину: идёт за домом — нарисован за домом,
  /// а не по глубине двери, куда идёт (Настя 20.10, тема 11).
  final ValueChanged<Offset>? onMove;

  @override
  State<FinniWalker> createState() => _FinniWalkerState();
}

class _FinniWalkerState extends State<FinniWalker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, value: 1)
        ..addListener(() => widget.onMove?.call(_now));
  late Offset _from = widget.at;
  late Offset _to = widget.at;
  bool _faceLeft = false;

  /// Путь с поворотами: от [_from] через [FinniWalker.via] к [_to]; пусто —
  /// прямо.
  List<Offset> _path = const <Offset>[];
  double _pathLen = 0;

  Offset get _now {
    final double t = Curves.easeInOut.transform(_c.value);
    if (_path.length < 3 || _pathLen <= 0) return Offset.lerp(_from, _to, t)!;
    double left = t * _pathLen;
    for (int i = 0; i + 1 < _path.length; i++) {
      final double seg = (_path[i + 1] - _path[i]).distance;
      if (left <= seg || i + 2 == _path.length) {
        // Лицом по ходу этого отрезка.
        final double dx = _path[i + 1].dx - _path[i].dx;
        if (dx.abs() > 0.5) _faceLeft = dx < 0;
        return seg == 0
            ? _path[i + 1]
            : Offset.lerp(
                _path[i], _path[i + 1], (left / seg).clamp(0.0, 1.0))!;
      }
      left -= seg;
    }
    return _to;
  }

  @override
  void didUpdateWidget(FinniWalker old) {
    super.didUpdateWidget(old);
    if (widget.at == _to) return;
    final Offset now = _now;
    if ((widget.at.dx - now.dx).abs() > 0.5) {
      _faceLeft = widget.at.dx < now.dx;
    }
    _from = now;
    _to = widget.at;
    _path = widget.via.isEmpty || widget.duration == Duration.zero
        ? const <Offset>[]
        : <Offset>[now, ...widget.via, widget.at];
    _pathLen = 0;
    for (int i = 0; i + 1 < _path.length; i++) {
      _pathLen += (_path[i + 1] - _path[i]).distance;
    }
    if (_path.length >= 3) {
      final double dx = _path[1].dx - now.dx;
      if (dx.abs() > 0.5) _faceLeft = dx < 0;
    }
    if (widget.duration == Duration.zero) {
      _c.value = 1;
    } else {
      _c.duration = widget.duration;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          final bool walking = _c.isAnimating;
          // Два шага за проход: подъём и спуск на каждом.
          final double lift = walking
              ? -widget.bob * math.sin(_c.value * math.pi * 4).abs()
              : 0;
          final Offset p = _now;
          return Positioned(
            left: p.dx,
            top: p.dy + lift,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -1),
              child: Transform.flip(
                flipX: _faceLeft,
                child: widget.builder(walking),
              ),
            ),
          );
        },
      );
}
