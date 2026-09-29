import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/world_theme.dart';

/// Джойстик на экране: круг с ручкой. Ведёшь пальцем — [onChanged] с
/// направлением (длина 0…1, вправо — +x, вниз — +y), отпустил — ноль.
///
/// Дополнение к касаниям (Денис, 1001: «разработка хождения и джойстика,
/// простого 2.5d»): кнопки и касания предметов остаются для TalkBack, сам
/// джойстик от TalkBack скрыт. Экран не показывает его при выключенных
/// «Анимациях» (ТЗ 3.6.7: без хода).
class Joystick extends StatefulWidget {
  const Joystick({super.key, required this.onChanged, this.size = 104});

  final ValueChanged<Offset> onChanged;

  /// Диаметр круга, dp. Не меньше 96: палец семилетки.
  final double size;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero;

  double get _radius => widget.size / 2;

  /// Ход ручки: она целиком внутри круга.
  double get _travel => _radius - widget.size * 0.21;

  void _move(Offset local) {
    final Offset c = Offset(_radius, _radius);
    Offset d = local - c;
    if (d.distance > _travel) d = d / d.distance * _travel;
    setState(() => _knob = d);
    widget.onChanged(d / _travel);
  }

  void _end() {
    setState(() => _knob = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final double knob = widget.size * 0.42;
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (DragStartDetails d) => _move(d.localPosition),
        onPanUpdate: (DragUpdateDetails d) => _move(d.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: SizedBox.square(
          dimension: widget.size,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WorldColors.panel.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: WorldColors.line, width: 2),
                  ),
                ),
              ),
              Positioned(
                left: _radius + _knob.dx - knob / 2,
                top: _radius + _knob.dy - knob / 2,
                width: knob,
                height: knob,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WorldColors.raised,
                    shape: BoxShape.circle,
                    border: Border.all(color: WorldColors.gold, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Двигатель ходьбы от джойстика: пока ручка отведена, каждые кадр двигает
/// точку на `направление × скорость × время` и отдаёт её [onStep]. Ручка в
/// центре — тикер стоит, кадров не просит.
class JoystickDriver {
  JoystickDriver(TickerProvider vsync, {required this.onStep}) {
    _ticker = vsync.createTicker(_tick);
  }

  /// Шаг: сколько секунд прошло и куда смотрит ручка.
  final void Function(double seconds, Offset direction) onStep;

  late final Ticker _ticker;
  Offset _dir = Offset.zero;
  Duration _last = Duration.zero;

  /// Ручка отведена — Финни идёт.
  bool get moving => _dir != Offset.zero;

  void set(Offset dir) {
    _dir = dir.distance < 0.15 ? Offset.zero : dir;
    if (moving && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!moving && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.25) return;
    onStep(dt, _dir);
  }

  void dispose() {
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
  }
}
