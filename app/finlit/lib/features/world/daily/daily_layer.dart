import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../world_state.dart';
import 'daily_card.dart';
import 'daily_rules.dart';

/// Карточка «Сегодня» над экраном [child] (комнатой), у кнопки «Сейчас»
/// (`room:now`): над ней в портрете, под ней в альбомной (там «Сейчас» —
/// вверху боковой панели). Комната о карточке не знает.
///
/// Дел нет (флаг `day_cycle.daily_activities` выключен) — ничего не рисует.
class DailyLayer extends StatefulWidget {
  const DailyLayer({super.key, required this.child});

  final Widget child;

  /// Ключ кнопки, к которой прижата карточка.
  static const String anchor = 'room:now';

  /// Строка цели: если она прямо под «Сейчас» (альбомная), карточка — под ней.
  static const String below = 'room:goal';

  /// Нижние разделы: в альбомной карточка не заходит на них (при шрифте 1,3
  /// и строке «Сегодня сделано» она закрывала «Неделя · Город · Прогресс»).
  static const String floor = 'room:nav:progress';

  @override
  State<DailyLayer> createState() => _DailyLayerState();
}

class _DailyLayerState extends State<DailyLayer> {
  final GlobalKey _childKey = GlobalKey();
  Rect? _anchor;
  Rect? _floor;

  /// После каждого кадра — где «Сейчас» (раскладка меняется с размером
  /// экрана и фазой недели). Сходится за кадр: перерисовка только при сдвиге.
  void _measure(Duration _) {
    if (!mounted) return;
    Rect? r = _rectOf(DailyLayer.anchor);
    // В альбомной под «Сейчас» стоит строка цели (`room:goal`) — карточка
    // её закрывала. Тогда прижимаем карточку под цель: та же ширина столбца.
    final Rect? goal = _rectOf(DailyLayer.below);
    if (r != null &&
        goal != null &&
        goal.top >= r.bottom &&
        (goal.left - r.left).abs() < 1) {
      r = Rect.fromLTRB(r.left, r.top, r.right, goal.bottom);
    }
    final Rect? f = _rectOf(DailyLayer.floor);
    if (r != _anchor || f != _floor) {
      setState(() {
        _anchor = r;
        _floor = f;
      });
    }
  }

  Rect? _rectOf(String key) {
    final BuildContext? root = _childKey.currentContext;
    final RenderObject? me = context.findRenderObject();
    if (root == null || me is! RenderBox || !me.hasSize) return null;
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
    final RenderObject? ro = found?.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    return ro.localToGlobal(Offset.zero, ancestor: me) & ro.size;
  }

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    final DailyRules? rules = DailyRules.of(ws.world);
    final Widget child = KeyedSubtree(key: _childKey, child: widget.child);
    if (rules == null || ws.phase != WeekPhase.living) return child;
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    final Rect? a = _anchor;
    final Rect? f = _floor;
    return LayoutBuilder(
      builder: (BuildContext c, BoxConstraints box) {
        final double h = box.maxHeight;
        final bool above = a != null && a.center.dy > h / 2;
        // Под «Сейчас» (альбомная) и разделы ниже — высота ограничена ими,
        // лишнее прокручивается внутри карточки.
        final bool capped =
            a != null && !above && f != null && f.top > a.bottom;
        return Stack(
          children: <Widget>[
            child,
            if (a != null)
              Positioned(
                left: a.left,
                width: a.width,
                top: above ? null : a.bottom + Gap.xs,
                bottom: above
                    ? h - a.top + Gap.xs
                    : (capped ? h - f.top + Gap.xs : null),
                child: capped
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: SingleChildScrollView(
                          key: const ValueKey<String>('daily:scroll'),
                          child: DailyCard(rules: rules),
                        ),
                      )
                    : DailyCard(rules: rules),
              ),
          ],
        );
      },
    );
  }
}
