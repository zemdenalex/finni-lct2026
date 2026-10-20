import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';

/// Куда смотрит хвостик облачка: к Финни под облачком, над ним или слева.
enum BubbleTail { down, up, left }

/// Облачко реплики Финни (Денис 20.10: «не сбоку, а облачко над Финни»):
/// тёмная панель с золотой кромкой, хвостик к голове Финни. Текст лежит на
/// панели, не на картинке (дизайн-система §1 п. 1).
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.child,
    this.tail = BubbleTail.down,
    this.tailAt,
    this.dense = false,
  });

  final Widget child;
  final BubbleTail tail;

  /// Плотнее: облачко в панели над планом, где каждая строка на счету.
  final bool dense;

  /// Где хвостик вдоль своей стороны, px от левого (верхнего) края; null —
  /// посередине.
  final double? tailAt;

  static const double tailSize = 12;

  @override
  Widget build(BuildContext context) {
    final double t = dense ? tailSize * 2 / 3 : tailSize;
    final double v = dense ? Gap.xs : Gap.sm;
    return CustomPaint(
      painter: _BubblePainter(tail: tail, tailAt: tailAt, tip: t),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          (dense ? Gap.sm : Gap.md) + (tail == BubbleTail.left ? t : 0),
          v + (tail == BubbleTail.up ? t : 0),
          dense ? Gap.sm : Gap.md,
          v + (tail == BubbleTail.down ? t : 0),
        ),
        child: child,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(
      {required this.tail, required this.tailAt, required this.tip});

  final BubbleTail tail;
  final double? tailAt;
  final double tip;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = tip;
    final Rect body = Rect.fromLTRB(
      tail == BubbleTail.left ? t : 0,
      tail == BubbleTail.up ? t : 0,
      size.width,
      size.height - (tail == BubbleTail.down ? t : 0),
    );
    const double r = WorldRadii.button;
    final Path box = Path()
      ..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(r)));
    final Path cue = Path();
    switch (tail) {
      case BubbleTail.down:
        final double x = (tailAt ?? body.center.dx)
            .clamp(body.left + r + t, math.max(body.left + r + t, body.right - r - t))
            .toDouble();
        cue
          ..moveTo(x - t, body.bottom - 1)
          ..lineTo(x, size.height)
          ..lineTo(x + t, body.bottom - 1)
          ..close();
      case BubbleTail.up:
        final double x = (tailAt ?? body.center.dx)
            .clamp(body.left + r + t, math.max(body.left + r + t, body.right - r - t))
            .toDouble();
        cue
          ..moveTo(x - t, body.top + 1)
          ..lineTo(x, 0)
          ..lineTo(x + t, body.top + 1)
          ..close();
      case BubbleTail.left:
        final double y = (tailAt ?? body.center.dy)
            .clamp(body.top + r + t, math.max(body.top + r + t, body.bottom - r - t))
            .toDouble();
        cue
          ..moveTo(body.left + 1, y - t)
          ..lineTo(0, y)
          ..lineTo(body.left + 1, y + t)
          ..close();
    }
    final Path all = Path.combine(PathOperation.union, box, cue);
    canvas
      ..drawShadow(all, const Color(0xFF000000), 4, false)
      ..drawPath(all, Paint()..color = WorldColors.panel)
      ..drawPath(
        all,
        Paint()
          ..color = WorldColors.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.tail != tail || old.tailAt != tailAt || old.tip != tip;
}

/// Где Финни на слое: прямоугольник спрайта в координатах [layer]; null —
/// Финни не на экране.
typedef FinniLocator = Rect? Function(RenderBox layer);

/// Финни по [key] спрайта: прямоугольник в координатах [layer].
Rect? finniRectByKey(GlobalKey key, RenderBox layer) {
  final RenderObject? f = key.currentContext?.findRenderObject();
  if (f is! RenderBox || !f.hasSize || !f.attached) return null;
  return layer.globalToLocal(f.localToGlobal(Offset.zero)) & f.size;
}

/// Слой над сценой: облачко [child] над головой Финни, хвостик — к ней.
/// Облачко не выходит за слой; не хватает места над головой — прижато к
/// верху слоя. Пока Финни идёт, облачко идёт за ним; с выключенными
/// «Анимациями» ставится один раз (ТЗ 3.6.7).
class FinniSpeechLayer extends StatefulWidget {
  const FinniSpeechLayer({
    super.key,
    required this.locate,
    required this.child,
    this.maxWidth = 380,
    this.bubbleKey = const ValueKey<String>('finni:bubble'),
    this.onTap,
    this.scroll = true,
  });

  /// Облачко выше места над головой — текст прокручивается внутри, а не
  /// вылезает за кромку (шрифт ×1,3 на 640 × 360). false — [child] сам
  /// решает (подсказки города: кнопки всегда видны).
  final bool scroll;

  final FinniLocator locate;
  final Widget child;
  final double maxWidth;
  final Key bubbleKey;

  /// Касание облачка (в сценках — «Дальше», как касание комнаты). null —
  /// облачко само касания не ловит, только его кнопки.
  final VoidCallback? onTap;

  /// Поле от краёв слоя.
  static const double margin = Gap.sm;

  /// Пустой верх кадра спрайта (листья над головой) — доля высоты: хвостик
  /// касается головы, а не воздуха над ней.
  static const double headInset = 0.04;

  @override
  State<FinniSpeechLayer> createState() => _FinniSpeechLayerState();
}

class _FinniSpeechLayerState extends State<FinniSpeechLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Rect? _finni;
  Duration _movedAt = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wake();
  }

  @override
  void didUpdateWidget(FinniSpeechLayer old) {
    super.didUpdateWidget(old);
    _wake();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _wake() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _place();
    });
    final bool motion =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
            context.motionOn;
    if (motion && !_ticker.isActive) {
      _movedAt = Duration.zero;
      _ticker.start();
    } else if (!motion && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    if (_place()) _movedAt = elapsed;
    if (elapsed - _movedAt > const Duration(milliseconds: 300)) _ticker.stop();
  }

  /// true — Финни сдвинулся.
  bool _place() {
    final RenderObject? me = context.findRenderObject();
    if (me is! RenderBox || !me.hasSize) return false;
    final Rect? was = _finni;
    Rect? r = widget.locate(me);
    // Кадр ещё не прочитан (заглушка без размера, пока грузится лист
    // ходьбы): ноги — те же, рост — прежний, облачко не прыгает на ноги.
    if (r != null && r.height < 1 && was != null && was.height >= 1) {
      r = Rect.fromLTWH(r.center.dx - was.width / 2, r.bottom - was.height,
          was.width, was.height);
    }
    if (r == was) return false;
    if (r != null &&
        was != null &&
        (r.topLeft - was.topLeft).distance <= 0.5 &&
        (r.bottomRight - was.bottomRight).distance <= 0.5) {
      return false;
    }
    setState(() => _finni = r);
    return true;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          const double m = FinniSpeechLayer.margin;
          final Rect? f = _finni;
          final double w =
              math.max(0, math.min(widget.maxWidth, box.maxWidth - 2 * m));
          final double cx = f?.center.dx ?? box.maxWidth / 2;
          final double x = (cx - w / 2)
              .clamp(m, math.max(m, box.maxWidth - w - m))
              .toDouble();
          final double head = f == null
              ? box.maxHeight / 2
              : f.top + f.height * FinniSpeechLayer.headInset;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _AboveHead(
                      left: x, width: w, head: head, fit: widget.scroll),
                  child: Opacity(
                    // До первого замера — невидимо: не мигает в углу.
                    opacity: f == null ? 0 : 1,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Для TalkBack «Дальше» — кнопка под репликой.
                      excludeFromSemantics: true,
                      onTap: widget.onTap,
                      child: SpeechBubble(
                        key: widget.bubbleKey,
                        tailAt: cx - x,
                        child: widget.scroll
                            ? SingleChildScrollView(child: widget.child)
                            : widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

/// Облачко шириной [width] от [left]; низ — у [head], но не выше поля слоя.
class _AboveHead extends SingleChildLayoutDelegate {
  _AboveHead(
      {required this.left,
      required this.width,
      required this.head,
      required this.fit});

  final double left;
  final double width;
  final double head;

  /// Текст прокручивается: облачко не выше места над головой (не ниже
  /// [minAbove]) — длинная реплика при шрифте ×1,3 не ложится на лицо
  /// Финни, а прокручивается (640 × 360, n6-welcome 20.10).
  final bool fit;

  /// Меньше этого над головой — облачко всё равно такой высоты: две строки
  /// с хвостиком.
  static const double minAbove = 72;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final double all =
        math.max(0, constraints.maxHeight - 2 * FinniSpeechLayer.margin);
    final double above = math.max(minAbove, head - FinniSpeechLayer.margin);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: fit ? math.min(all, above) : all,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
        left,
        math.max(FinniSpeechLayer.margin, head - childSize.height),
      );

  @override
  bool shouldRelayout(_AboveHead old) =>
      old.left != left ||
      old.width != width ||
      old.head != head ||
      old.fit != fit;
}
