import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/world_theme.dart';

/// Значок «+2» / «−3» у числа HUD на несколько секунд после того, как число
/// изменилось (модель 7 дней, Денис 17.10: настроение «ходит» по типу работы —
/// ребёнок должен видеть, на сколько оно сдвинулось после смены).
///
/// Сравнивает с прошлым значением этого же виджета: при первом показе экрана
/// значка нет. TalkBack его не читает — причина изменения уже звучит в
/// ответе мира (строка Финни, итог смены).
class HudDelta extends StatefulWidget {
  const HudDelta({
    super.key,
    required this.value,
    required this.child,
    this.deltaKey = 'hud:delta',
    this.top = 0,
    this.right = -4,
  });

  /// Где значок относительно ячейки. В полосе комнаты — рядом с числом;
  /// в компактном HUD экранов число у правого края — значок над ним.
  final double top;
  final double right;

  final int value;
  final Widget child;

  /// Ключ значка — чтобы тесты отличали настроение от других чисел.
  final String deltaKey;

  /// Сколько значок виден.
  static const Duration shown = Duration(seconds: 3);

  @override
  State<HudDelta> createState() => _HudDeltaState();
}

class _HudDeltaState extends State<HudDelta> {
  int? _delta;
  Timer? _hide;

  @override
  void didUpdateWidget(HudDelta old) {
    super.didUpdateWidget(old);
    final int d = widget.value - old.value;
    if (d == 0) return;
    _hide?.cancel();
    _delta = d;
    _hide = Timer(HudDelta.shown, () {
      if (mounted) setState(() => _delta = null);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int? d = _delta;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        if (d != null)
          Positioned(
            // Внутри ячейки: над рамкой HUD значок обрезался краем экрана.
            top: widget.top,
            right: widget.right,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: Container(
                  key: ValueKey<String>(widget.deltaKey),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: WorldColors.night,
                    borderRadius: BorderRadius.circular(WorldRadii.tag),
                    border: Border.all(
                        color: d > 0 ? WorldColors.needs : WorldColors.danger,
                        width: 1.5),
                  ),
                  child: Text(
                    // Минус — типографский, как в остальных числах мира.
                    d > 0 ? '+$d' : '−${-d}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: d > 0 ? WorldColors.needs : WorldColors.danger,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
