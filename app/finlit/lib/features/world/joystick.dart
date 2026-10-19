import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/world_theme.dart';

/// Джойстик на экране: круг с ручкой. Ведёшь пальцем — [onChanged] с
/// направлением (длина 0…1, вправо — +x, вниз — +y), отпустил — ноль.
///
/// Дополнение к касаниям (Денис, 1001: «разработка хождения и джойстика,
/// простого 2.5d»): кнопки и касания предметов остаются для TalkBack, сам
/// джойстик от TalkBack скрыт. Джойстик — ввод, а не анимация: он виден и
/// при выключенных «Анимациях» / «Уменьшить движение»; тогда без анимации
/// только ход ([JoystickDriver.set] со `stepped`: шагами, без тикера).
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

  /// Шаг при выключенных анимациях: Финни переставляется раз в столько, без
  /// плавного хода (ТЗ 3.6.7), но идёт, куда ведут.
  static const Duration stepEvery = Duration(milliseconds: 250);

  Timer? _steps;

  /// Ручка отведена — Финни идёт.
  bool get moving => _dir != Offset.zero;

  /// [stepped] — анимации выключены: ход шагами по таймеру, без тикера.
  void set(Offset dir, {bool stepped = false}) {
    _dir = dir.distance < 0.15 ? Offset.zero : dir;
    if (stepped) {
      if (_ticker.isActive) _ticker.stop();
      if (moving) {
        _steps ??= Timer.periodic(stepEvery, (_) {
          if (moving) onStep(stepEvery.inMicroseconds / 1e6, _dir);
        });
      } else {
        _steps?.cancel();
        _steps = null;
      }
      return;
    }
    _steps?.cancel();
    _steps = null;
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
    _steps?.cancel();
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
  }
}

/// Круг джойстика с ручкой — рисунок без жестов: [knob] — сдвиг ручки от
/// центра (dp). Один на комнату и город ([FloatingJoystick]).
class JoystickPad extends StatelessWidget {
  const JoystickPad({super.key, required this.knob, this.size = 96});

  final Offset knob;
  final double size;

  /// Ход ручки при диаметре [size]: ручка целиком внутри круга.
  static double travelOf(double size) => size / 2 - size * 0.21;

  @override
  Widget build(BuildContext context) {
    final double k = size * 0.42;
    return SizedBox.square(
      dimension: size,
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
            left: size / 2 + knob.dx - k / 2,
            top: size / 2 + knob.dy - k / 2,
            width: k,
            height: k,
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
    );
  }
}

/// Плавающий джойстик — как в комнате (Настя, тема 11: «в городе джойстик
/// такой же, как в квартире»): палец лёг на [child] и повёл — под ним круг
/// с ручкой, [onChanged] с направлением (длина 0…1); отпустил — ноль. В
/// покое круг бледно лежит в левом нижнем углу (макет Алины) — место, куда
/// палец можно положить наверняка; ключ [restKey]. Касания [child] (здания)
/// работают как раньше: ход начинается только после движения пальца.
class FloatingJoystick extends StatefulWidget {
  const FloatingJoystick({
    super.key,
    required this.child,
    required this.onChanged,
    this.restKey,
    this.size = 96,
    this.margin = 8,
    this.bottomInset = 0,
  });

  final Widget child;
  final ValueChanged<Offset> onChanged;
  final Key? restKey;
  final double size;
  final double margin;

  /// Снизу занято (кнопки поверх) — джойстик в покое выше.
  final double bottomInset;

  @override
  State<FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<FloatingJoystick> {
  Offset? _center;
  Offset _knob = Offset.zero;

  double get _travel => JoystickPad.travelOf(widget.size);

  void _start(Offset at) => setState(() {
        _center = at;
        _knob = Offset.zero;
      });

  void _move(Offset at) {
    final Offset? c = _center;
    if (c == null) return;
    Offset d = at - c;
    if (d.distance > _travel) d = d / d.distance * _travel;
    setState(() => _knob = d);
    widget.onChanged(d / _travel);
  }

  void _end() {
    if (_center == null) return;
    widget.onChanged(Offset.zero);
    setState(() => _center = null);
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.size;
    final Offset? c = _center;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          // Круг — где палец лёг, а не где он прошёл порог сдвига.
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (DragStartDetails d) => _start(d.localPosition),
          onPanUpdate: (DragUpdateDetails d) => _move(d.localPosition),
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          child: widget.child,
        ),
        if (c == null)
          Positioned(
            left: widget.margin,
            bottom: widget.margin + widget.bottomInset,
            width: s,
            height: s,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0.55,
                  child: SizedBox.square(
                    key: widget.restKey,
                    dimension: s,
                    child: JoystickPad(knob: Offset.zero, size: s),
                  ),
                ),
              ),
            ),
          )
        else
          Positioned(
            left: c.dx - s / 2,
            top: c.dy - s / 2,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: JoystickPad(
                  key: const ValueKey<String>('joystick:pad'),
                  knob: _knob,
                  size: s,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
