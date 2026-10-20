import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';

/// «Выбери вариант» на шаге-задании мини-игры (Настя 20.10, п. 13: второй
/// шаг помощника бухгалтера — «не ясно, что снова нужно что-то решать,
/// сделай подсказку, если будет тыкать не туда»). То же, что на итогах
/// смены (218f53c5): касание мимо вариантов — вспышка золотой рамки вокруг
/// них, подсказка жирнее и золотом, варианты прокручиваются в окно.
///
/// Один объект на шаг: [listen] — вокруг всего шага, [frame] — вокруг
/// вариантов, [hint] — строка «что сделать». Жив, пока жив [State] игры
/// ([dispose]).
class ChoiceNudge {
  /// Сколько раз коснулись мимо вариантов: 0 — ни разу.
  final ValueNotifier<int> count = ValueNotifier<int>(0);

  final GlobalKey _area = GlobalKey();
  Offset? _downAt;

  void dispose() => count.dispose();

  /// Прозрачный слой над шагом: кнопки, прокрутка и TalkBack работают как
  /// раньше. Пока [active] (выбор ещё не сделан), касание (не прокрутка)
  /// мимо [frame] — подсказка.
  Widget listen({required bool active, required Widget child}) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: active ? (PointerDownEvent e) => _downAt = e.position : null,
    onPointerUp: active ? _up : null,
    child: child,
  );

  void _up(PointerUpEvent e) {
    final Offset? down = _downAt;
    _downAt = null;
    if (down == null || (e.position - down).distance > kTouchSlop) return;
    final BuildContext? c = _area.currentContext;
    final RenderObject? box = c?.findRenderObject();
    if (box is RenderBox && box.attached) {
      final Rect r = box.localToGlobal(Offset.zero) & box.size;
      if (r.contains(e.position)) return;
    }
    count.value++;
    if (c != null && c.mounted) {
      Scrollable.ensureVisible(
        c,
        duration: c.motion(Motion.state),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }

  /// Варианты в рамке, которая вспыхивает на каждое касание мимо.
  Widget frame(BuildContext context, Widget choices, {Key? key}) =>
      KeyedSubtree(
        key: _area,
        child: ValueListenableBuilder<int>(
          valueListenable: count,
          builder: (BuildContext context, int n, Widget? child) =>
              TweenAnimationBuilder<double>(
                key: ValueKey<int>(n),
                tween: Tween<double>(begin: n == 0 ? 0 : 1, end: 0),
                duration: context.motion(const Duration(milliseconds: 1400)),
                builder: (BuildContext context, double v, Widget? child) =>
                    DecoratedBox(
                      key: key,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(WorldRadii.button),
                        border: Border.all(
                          color: WorldColors.gold.withValues(alpha: v),
                          width: 3,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: child,
                      ),
                    ),
                child: child,
              ),
          child: choices,
        ),
      );

  /// Строка «что сделать»: после касания мимо — жирно и золотом;
  /// liveRegion — TalkBack зачитывает её, когда она меняется.
  Widget hint(String text, TextStyle style, {Key? key}) =>
      ValueListenableBuilder<int>(
        valueListenable: count,
        builder: (BuildContext context, int n, _) => Semantics(
          liveRegion: true,
          child: Text(
            text,
            key: key,
            style: n > 0
                ? style.copyWith(
                    fontWeight: FontWeight.w800,
                    color: WorldColors.gold,
                  )
                : style,
          ),
        ),
      );
}
