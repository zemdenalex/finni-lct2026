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
class FinniWalker extends StatefulWidget {
  const FinniWalker({
    super.key,
    required this.at,
    required this.duration,
    required this.bob,
    required this.builder,
  });

  final Offset at;
  final Duration duration;
  final double bob;
  final Widget Function(bool walking) builder;

  @override
  State<FinniWalker> createState() => _FinniWalkerState();
}

class _FinniWalkerState extends State<FinniWalker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, value: 1);
  late Offset _from = widget.at;
  late Offset _to = widget.at;
  bool _faceLeft = false;

  Offset get _now =>
      Offset.lerp(_from, _to, Curves.easeInOut.transform(_c.value))!;

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
